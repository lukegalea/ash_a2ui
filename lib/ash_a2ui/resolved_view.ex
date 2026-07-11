defmodule AshA2ui.ResolvedView do
  @moduledoc """
  The normalization seam between the DSL and the encoder: `resolve/2` turns a
  resource (or standalone UI module) plus request options into a plain struct
  that the encoder consumes. The encoder never reads compiled DSL state
  directly.

  Normalization semantics:

    * each component's `fields` list becomes the *effective rendering list*:
      `hidden` fields are dropped and the rest are ordered by the field's
      `order` (stable by declaration order within the component otherwise)
    * `fields` maps every field referenced by a component or declared as a
      `field` entity to fully-defaulted metadata: `label` defaults to the
      humanized field name, `widget` defaults via `AshA2ui.TypeMapper` on the
      attribute's Ash type/constraints, `format` is carried through
    * `read_action`/`create_action`/`update_action` fall back to the
      resource's primary action of the matching type when a component omits
      them
    * `selects` maps every form field backed by a `belongs_to` relationship
      (inferred by matching the field name against a relationship's
      `source_attribute`, or declared explicitly via the field's
      `relationship` option) to its resolved option-loading config; those
      fields default to the `:choice_picker` widget
    * `loads` is the `Ash.Query.load/2` statement covering every relationship
      path needed by `source` table columns

  FROZEN CONTRACT — the struct fields and `resolve/2` signature are the
  interface every parallel track codes against; do not change outside an
  integration commit.
  """

  alias Ash.Resource.Info, as: ResourceInfo

  defstruct [
    :resource,
    :surface_id,
    :read_action,
    :create_action,
    :update_action,
    :query,
    components: [],
    fields: %{},
    row_actions: [],
    selects: %{},
    loads: []
  ]

  @typedoc """
  Resolved option-loading config for one relationship-backed form select.
  """
  @type select :: %{
          relationship: atom,
          destination: module,
          option_label: atom,
          option_value: atom,
          option_sort: atom,
          option_limit: pos_integer
        }

  @type t :: %__MODULE__{
          resource: module,
          surface_id: String.t(),
          components: [AshA2ui.Component.t()],
          fields: %{atom => AshA2ui.Field.t()},
          read_action: atom | nil,
          create_action: atom | nil,
          update_action: atom | nil,
          query: AshA2ui.Query.t() | nil,
          row_actions: [atom],
          selects: %{atom => select},
          loads: list
        }

  @option_label_fallbacks [:name, :title, :label, :username, :email]

  @resolve_opts [:actor, :tenant, :domain, :authorize?, :query_state]

  @doc """
  Resolves the `a2ui` DSL of `resource_or_ui_module` (an `Ash.Resource` using
  the `AshA2ui` extension, or an `AshA2ui.Standalone` UI module with
  `for_resource`) into a `#{inspect(__MODULE__)}` struct.

  ## Options

    * `:actor` / `:tenant` / `:authorize?` / `:domain` / `:query_state` —
      reserved for data loading (see `AshA2ui.Info.build_surface/2`);
      validated and passed through, not consumed by normalization itself.
  """
  @spec resolve(module, keyword) :: t()
  def resolve(resource_or_ui_module, opts \\ []) do
    Keyword.validate!(opts, @resolve_opts)

    resource = AshA2ui.Info.resource!(resource_or_ui_module)
    components = AshA2ui.Info.components(resource_or_ui_module)
    declared_fields = AshA2ui.Info.fields(resource_or_ui_module)

    form = Enum.find(components, &(&1.name == :form))
    selects = resolve_selects(resource, form, Map.new(declared_fields, &{&1.name, &1}))

    fields = normalize_fields(resource, components, declared_fields, Map.keys(selects))
    components = Enum.map(components, &normalize_component(&1, fields))

    table = Enum.find(components, &(&1.name == :table))
    form = Enum.find(components, &(&1.name == :form))

    %__MODULE__{
      resource: resource,
      surface_id: surface_id(resource_or_ui_module, resource),
      components: components,
      fields: fields,
      read_action: component_action(table, :read_action, resource, :read),
      create_action: component_action(form, :create_action, resource, :create),
      update_action: component_action(form, :update_action, resource, :update),
      query: resolve_query(resource_or_ui_module, table),
      row_actions: (table && table.row_actions) || [],
      selects: selects,
      loads: loads(table, fields)
    }
  end

  # --- relationship selects ---------------------------------------------------

  # A form field is a relationship select when it declares an explicit
  # `relationship`, or when its name matches a `belongs_to` relationship's
  # `source_attribute` (the AshSDUI-derived inference).
  defp resolve_selects(_resource, nil, _declared), do: %{}

  defp resolve_selects(resource, form, declared) do
    (form.fields || [])
    |> Enum.flat_map(fn name ->
      field = declared[name] || %AshA2ui.Field{name: name}

      case select_relationship(resource, field) do
        nil -> []
        relationship -> [{name, resolve_select(field, relationship)}]
      end
    end)
    |> Map.new()
  end

  defp select_relationship(resource, %{relationship: relationship})
       when not is_nil(relationship) do
    ResourceInfo.relationship(resource, relationship)
  end

  defp select_relationship(resource, field) do
    resource
    |> ResourceInfo.relationships()
    |> Enum.find(&(&1.type == :belongs_to and &1.source_attribute == field.name))
  end

  defp resolve_select(field, relationship) do
    destination = relationship.destination
    option_value = field.option_value || single_primary_key!(field, destination)
    option_label = field.option_label || default_option_label(destination, option_value)

    %{
      relationship: relationship.name,
      destination: destination,
      option_label: option_label,
      option_value: option_value,
      option_sort: field.option_sort || option_label,
      option_limit: field.option_limit
    }
  end

  # The option-label fallback chain: the first existing public attribute of
  # [:name, :title, :label, :username, :email], else the option value itself.
  defp default_option_label(destination, option_value) do
    Enum.find(@option_label_fallbacks, option_value, fn name ->
      match?(%{public?: true}, ResourceInfo.attribute(destination, name))
    end)
  end

  defp single_primary_key!(field, destination) do
    case ResourceInfo.primary_key(destination) do
      [key] ->
        key

      composite ->
        raise ArgumentError,
              "cannot infer option_value for field #{inspect(field.name)}: " <>
                "#{inspect(destination)} has a composite primary key " <>
                "#{inspect(composite)} — set option_value explicitly"
    end
  end

  # --- source-column loads -----------------------------------------------------

  # One Ash.Query.load statement per relationship prefix of a rendered
  # `source` column ([:user, :email] -> :user; [:a, :b, :attr] -> {:a, [:b]}).
  defp loads(nil, _fields), do: []

  defp loads(table, fields) do
    table.fields
    |> Enum.map(&(fields[&1] && fields[&1].source))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Enum.drop(&1, -1))
    |> Enum.reject(&(&1 == []))
    |> Enum.uniq()
    |> Enum.map(&path_to_load/1)
  end

  defp path_to_load([relationship]), do: relationship
  defp path_to_load([relationship | rest]), do: {relationship, [path_to_load(rest)]}

  # The query config referenced by the table component; the reference is
  # verified at compile time (VerifyQueries), so a miss here only happens for
  # surfaces without a table or without a query option.
  defp resolve_query(resource_or_ui_module, %{query: query_name}) when not is_nil(query_name) do
    resource_or_ui_module
    |> AshA2ui.Info.queries()
    |> Enum.find(&(&1.name == query_name))
  end

  defp resolve_query(_resource_or_ui_module, _table), do: nil

  defp surface_id(resource_or_ui_module, resource) do
    case AshA2ui.Info.a2ui_surface_id(resource_or_ui_module) do
      {:ok, surface_id} -> surface_id
      :error -> default_surface_id(resource)
    end
  end

  # A declared action wins; otherwise fall back to the resource's primary
  # action of the matching type. No component of that kind -> no action.
  defp component_action(nil, _key, _resource, _type), do: nil

  defp component_action(component, key, resource, type) do
    Map.fetch!(component, key) || primary_action_name(resource, type)
  end

  # Effective field metadata for every field referenced by a component or
  # declared as a `field` entity, with label/widget defaults applied
  # (relationship-select fields default to `:choice_picker`).
  defp normalize_fields(resource, components, declared_fields, select_names) do
    declared = Map.new(declared_fields, &{&1.name, &1})

    components
    |> Enum.flat_map(&(&1.fields || []))
    |> Enum.concat(Map.keys(declared))
    |> Enum.uniq()
    |> Map.new(fn name ->
      field = declared[name] || %AshA2ui.Field{name: name}

      default_widget =
        if name in select_names do
          :choice_picker
        else
          default_widget(resource, name)
        end

      {name,
       %{
         field
         | label: field.label || humanize(name),
           widget: field.widget || default_widget
       }}
    end)
  end

  # Effective rendering list: hidden fields dropped, ordered by field order
  # (Enum.sort_by is stable, preserving declaration order on ties).
  defp normalize_component(component, fields) do
    effective =
      (component.fields || [])
      |> Enum.reject(&fields[&1].hidden)
      |> Enum.sort_by(&fields[&1].order)

    %{component | fields: effective}
  end

  defp default_widget(resource, name) do
    case Ash.Resource.Info.attribute(resource, name) do
      %{type: type, constraints: constraints} -> AshA2ui.TypeMapper.widget_for(type, constraints)
      nil -> AshA2ui.TypeMapper.widget_for(nil)
    end
  end

  defp primary_action_name(resource, type) do
    case Ash.Resource.Info.primary_action(resource, type) do
      %{name: name} -> name
      nil -> nil
    end
  end

  defp humanize(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp default_surface_id(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end
end
