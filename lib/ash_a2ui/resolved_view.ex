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
      path needed by `source` table columns plus every calculation/aggregate
      field rendered by the tables
    * `tables` is one resolved read scope per `:table` component (in
      declaration order): its component key, effective read action, resolved
      query, per-table loads/row_actions, and the frozen data-model paths
      its records/query state live at (see `t:table/0`)
    * `actions` maps Ash action names to their `AshA2ui.Action` metadata
      entities (refresh targets, prompt fields, visibility conditions);
      actions without an entity have no entry
    * `refreshes` maps Ash action names to the table components their
      success refreshes (from `action` entities); actions without an entry —
      or whose entity omits `refreshes` (`nil`) — refresh every table
    * each table's `loads` additionally covers the expression calculations
      referenced by `visible_when` conditions of the table's row actions, so
      per-row visibility can be evaluated on the loaded records
    * on single-table surfaces the legacy top-level `read_action` / `query` /
      `row_actions` / `loads` fields mirror the single table exactly as
      before; on multi-table surfaces `read_action`/`query` are `nil` and
      `row_actions`/`loads` are the union across tables

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
    loads: [],
    tables: [],
    actions: %{},
    refreshes: %{}
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

  @typedoc """
  A fully resolved table scope — one per `:table` component, in declaration
  order. `name` is the component key (`:table` for the unnamed table);
  `records_path`/`query_path` are the frozen data-model paths this table's
  records and query state live at (`/records` + `/query` on single-table
  surfaces, `/records/<name>` + `/query/<name>` on multi-table surfaces;
  `query_path` is `nil` when the table declares no `query`).

  The `resource`/`read_action`/`query`/`loads` keys make a table scope a
  drop-in read scope for `AshA2ui.QueryRunner`.
  """
  @type table :: %{
          name: atom,
          component: AshA2ui.Component.t(),
          resource: module,
          read_action: atom | nil,
          query: AshA2ui.Query.t() | nil,
          loads: list,
          row_actions: [atom],
          records_path: String.t(),
          query_path: String.t() | nil
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
          loads: list,
          tables: [table],
          actions: %{atom => AshA2ui.Action.t()},
          refreshes: %{atom => [atom] | nil}
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

    form = Enum.find(components, &(&1.name == :form))

    actions =
      Map.new(AshA2ui.Info.action_settings(resource_or_ui_module), &{&1.name, &1})

    tables = resolve_tables(resource_or_ui_module, resource, components, fields, actions)
    single = if match?([_only], tables), do: hd(tables)

    %__MODULE__{
      resource: resource,
      surface_id: surface_id(resource_or_ui_module, resource),
      components: components,
      fields: fields,
      read_action: single && single.read_action,
      create_action: component_action(form, :create_action, resource, :create),
      update_action: component_action(form, :update_action, resource, :update),
      query: single && single.query,
      row_actions: tables |> Enum.flat_map(& &1.row_actions) |> Enum.uniq(),
      selects: selects,
      loads: tables |> Enum.flat_map(& &1.loads) |> Enum.uniq(),
      tables: tables,
      actions: actions,
      refreshes: Map.new(actions, fn {name, action} -> {name, action.refreshes} end)
    }
  end

  @doc """
  Whether the view is a multi-table surface (two or more `:table`
  components), switching the data model to the scoped
  `/records/<component_name>` / `/query/<component_name>` paths.
  """
  @spec multi_table?(t()) :: boolean
  def multi_table?(%__MODULE__{tables: tables}), do: match?([_, _ | _], tables)

  # --- table scopes -------------------------------------------------------------

  defp resolve_tables(resource_or_ui_module, resource, components, fields, actions) do
    table_components = Enum.filter(components, &(&1.name == :table))
    multi? = match?([_, _ | _], table_components)

    Enum.map(table_components, fn component ->
      name = AshA2ui.Component.key(component)
      query = resolve_query(resource_or_ui_module, component)

      %{
        name: name,
        component: component,
        resource: resource,
        read_action: component_action(component, :read_action, resource, :read),
        query: query,
        loads:
          Enum.uniq(
            loads(resource, component, fields) ++ condition_loads(resource, component, actions)
          ),
        row_actions: component.row_actions,
        records_path: (multi? && "/records/#{name}") || "/records",
        query_path: query && ((multi? && "/query/#{name}") || "/query")
      }
    end)
  end

  # Calculations referenced by visible_when conditions of this table's row
  # actions must be loaded with the records so per-row visibility can be
  # evaluated (deduplicated against the rendered-field loads).
  defp condition_loads(resource, component, actions) do
    component.row_actions
    |> Enum.flat_map(fn row_action ->
      case actions[row_action] do
        %{visible_when: [_ | _] = conditions} ->
          AshA2ui.Conditions.condition_loads(resource, conditions)

        _no_conditions ->
          []
      end
    end)
    |> Enum.uniq()
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

  # --- record loads --------------------------------------------------------------

  # The Ash.Query.load statement covering a table's rendered fields: one
  # entry per relationship prefix of a `source` column ([:user, :email] ->
  # :user; [:a, :b, :attr] -> {:a, [:b]}) plus the name of every field that
  # is a public calculation or aggregate of the resource.
  defp loads(resource, table, fields) do
    source_loads =
      table.fields
      |> Enum.map(&(fields[&1] && fields[&1].source))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Enum.drop(&1, -1))
      |> Enum.reject(&(&1 == []))
      |> Enum.uniq()
      |> Enum.map(&path_to_load/1)

    calc_loads = Enum.filter(table.fields, &calculation_or_aggregate?(resource, &1))

    source_loads ++ calc_loads
  end

  defp calculation_or_aggregate?(resource, name) do
    not is_nil(ResourceInfo.calculation(resource, name)) or
      not is_nil(ResourceInfo.aggregate(resource, name))
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

  # Calculations carry a type/constraints just like attributes; aggregates
  # (and unknown fields) fall back to the TypeMapper default (:text_field —
  # the widget is irrelevant for table display anyway).
  defp default_widget(resource, name) do
    case ResourceInfo.attribute(resource, name) || ResourceInfo.calculation(resource, name) do
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
