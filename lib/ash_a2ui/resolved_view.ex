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

  FROZEN CONTRACT — the struct fields and `resolve/2` signature are the
  interface every parallel track codes against; do not change outside an
  integration commit.
  """

  defstruct [
    :resource,
    :surface_id,
    :read_action,
    :create_action,
    :update_action,
    :query,
    components: [],
    fields: %{},
    row_actions: []
  ]

  @type t :: %__MODULE__{
          resource: module,
          surface_id: String.t(),
          components: [AshA2ui.Component.t()],
          fields: %{atom => AshA2ui.Field.t()},
          read_action: atom | nil,
          create_action: atom | nil,
          update_action: atom | nil,
          query: AshA2ui.Query.t() | nil,
          row_actions: [atom]
        }

  @resolve_opts [:actor, :tenant, :domain, :authorize?]

  @doc """
  Resolves the `a2ui` DSL of `resource_or_ui_module` (an `Ash.Resource` using
  the `AshA2ui` extension, or an `AshA2ui.Standalone` UI module with
  `for_resource`) into a `#{inspect(__MODULE__)}` struct.

  ## Options

    * `:actor` / `:tenant` / `:authorize?` / `:domain` — reserved for data
      loading (see `AshA2ui.Info.build_surface/2`); validated and passed
      through, not consumed by normalization itself.
  """
  @spec resolve(module, keyword) :: t()
  def resolve(resource_or_ui_module, opts \\ []) do
    Keyword.validate!(opts, @resolve_opts)

    resource = AshA2ui.Info.resource!(resource_or_ui_module)
    components = AshA2ui.Info.components(resource_or_ui_module)
    declared_fields = AshA2ui.Info.fields(resource_or_ui_module)

    fields = normalize_fields(resource, components, declared_fields)
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
      row_actions: (table && table.row_actions) || []
    }
  end

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
  # declared as a `field` entity, with label/widget defaults applied.
  defp normalize_fields(resource, components, declared_fields) do
    declared = Map.new(declared_fields, &{&1.name, &1})

    components
    |> Enum.flat_map(&(&1.fields || []))
    |> Enum.concat(Map.keys(declared))
    |> Enum.uniq()
    |> Map.new(fn name ->
      field = declared[name] || %AshA2ui.Field{name: name}

      {name,
       %{
         field
         | label: field.label || humanize(name),
           widget: field.widget || default_widget(resource, name)
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
