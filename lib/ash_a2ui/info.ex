defmodule AshA2ui.Info do
  @moduledoc """
  Introspection for the `AshA2ui` extension, plus the public payload-building
  API.

  FROZEN CONTRACT — the signatures of `build_surface/2`, `build_data_model/2`,
  `resource!/1`, `components/1` and `fields/1` are the interface every parallel
  track codes against; do not change outside an integration commit.
  """

  use Spark.InfoGenerator, extension: AshA2ui, sections: [:a2ui]

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.Encoder.V0_9_1
  alias AshA2ui.ResolvedView
  alias Spark.Dsl.Extension

  @doc """
  The `component` entities declared in the `a2ui` section.
  """
  @spec components(module) :: [AshA2ui.Component.t()]
  def components(resource_or_ui_module) do
    resource_or_ui_module
    |> Extension.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Component))
  end

  @doc """
  The `field` entities declared in the `a2ui` section.
  """
  @spec fields(module) :: [AshA2ui.Field.t()]
  def fields(resource_or_ui_module) do
    resource_or_ui_module
    |> Extension.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Field))
  end

  @doc """
  The `query` entities declared in the `a2ui` section.
  """
  @spec queries(module) :: [AshA2ui.Query.t()]
  def queries(resource_or_ui_module) do
    resource_or_ui_module
    |> Extension.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Query))
  end

  @doc """
  The `action` entities (per-action refresh metadata) declared in the `a2ui`
  section.
  """
  @spec action_settings(module) :: [AshA2ui.Action.t()]
  def action_settings(resource_or_ui_module) do
    resource_or_ui_module
    |> Extension.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Action))
  end

  @doc """
  Resolves the Ash resource behind `resource_or_ui_module`: the module's
  `for_resource` option if set (standalone UI modules), otherwise the module
  itself (which must be an `Ash.Resource`).
  """
  @spec resource!(module) :: module
  def resource!(resource_or_ui_module) do
    case a2ui_for_resource(resource_or_ui_module) do
      {:ok, resource} ->
        resource

      :error ->
        if ResourceInfo.resource?(resource_or_ui_module) do
          resource_or_ui_module
        else
          raise ArgumentError,
                "#{inspect(resource_or_ui_module)} is not an Ash resource and has no " <>
                  "`for_resource` configured in its `a2ui` section"
        end
    end
  end

  @doc """
  Builds the ordered A2UI v0.9.1 server->client message list for the surface:
  `createSurface` -> `updateComponents` -> `updateDataModel`.

  ## Options

    * `:actor` — the actor used to load records.
    * `:tenant` — the tenant used to load records.
    * `:authorize?` — whether to authorize the read. Defaults to `true`.
    * `:domain` — the Ash domain used for the read. Defaults to the
      resource's configured domain.
    * `:query_state` — a client `/query` state map to run the read with
      (validated against the query allowlist; invalid or missing state falls
      back to the query's declared defaults). Lets refreshes preserve the
      user's current search/filters/sort/page instead of resetting them.
  """
  @spec build_surface(module, keyword) :: [map]
  def build_surface(resource_or_ui_module, opts \\ []) do
    resolved_view = ResolvedView.resolve(resource_or_ui_module, opts)
    {records, opts} = load_records!(resolved_view, opts)
    opts = Keyword.put(opts, :options, load_options!(resolved_view, opts))

    V0_9_1.encode_surface(resolved_view, records, opts)
  end

  @doc """
  Builds a data-only refresh: the `updateDataModel` message for the surface,
  used for PubSub-driven live refreshes.

  Takes the same options as `build_surface/2`.
  """
  @spec build_data_model(module, keyword) :: map
  def build_data_model(resource_or_ui_module, opts \\ []) do
    resolved_view = ResolvedView.resolve(resource_or_ui_module, opts)
    {records, opts} = load_records!(resolved_view, opts)
    opts = Keyword.put(opts, :options, load_options!(resolved_view, opts))

    V0_9_1.encode_data_model(resolved_view, records, opts)
  end

  # Loads the surface's records through normal `Ash.read`s (policies apply).
  # Surfaces without a table component render no records; single-table
  # surfaces load a plain record list; multi-table surfaces load one list
  # per table (`%{table_name => [record]}`). Tables with a `query` read
  # through `AshA2ui.QueryRunner` — with the caller-carried `:query_state`
  # when given (validated like any client input, falling back to the
  # declared defaults; on multi-table surfaces an object keyed by table
  # component name), otherwise with the query's declared defaults (default
  # sort, page 1) — and the resulting `/query` state (per table on
  # multi-table surfaces) is handed to the encoder via the `:query_state`
  # option.
  defp load_records!(resolved_view, opts) do
    case resolved_view.tables do
      [] ->
        {[], opts}

      [single] ->
        {records, query_state} = load_table!(resolved_view, single, opts)
        {records, (query_state && Keyword.put(opts, :query_state, query_state)) || opts}

      tables ->
        loaded = Enum.map(tables, &{&1.name, load_table!(resolved_view, &1, opts)})

        records = Map.new(loaded, fn {name, {records, _state}} -> {name, records} end)

        states =
          for {name, {_records, state}} <- loaded, not is_nil(state), into: %{}, do: {name, state}

        {records, (states != %{} && Keyword.put(opts, :query_state, states)) || opts}
    end
  end

  defp load_table!(resolved_view, table, opts) do
    cond do
      is_nil(table.read_action) ->
        raise ArgumentError,
              "cannot load records for #{inspect(resolved_view.resource)}: the resource has " <>
                "no read action (declare one, or set `read_action` on the table component)"

      table.query ->
        params = query_params(resolved_view, table, opts)

        case AshA2ui.QueryRunner.run(table, params, read_opts(resolved_view, opts)) do
          {:ok, records, query_state} -> {records, query_state}
          {:error, error} -> raise Ash.Error.to_error_class(error)
        end

      true ->
        records =
          table.resource
          |> Ash.Query.for_read(table.read_action)
          |> Ash.Query.load(table.loads)
          |> Ash.read!(read_opts(resolved_view, opts))

        {records, nil}
    end
  end

  # The caller-carried :query_state is the single table's state map, or (on
  # multi-table surfaces) an object keyed by table component name.
  defp query_params(resolved_view, table, opts) do
    carried = Keyword.get(opts, :query_state)

    state =
      if ResolvedView.multi_table?(resolved_view) do
        is_map(carried) && Map.get(carried, to_string(table.name))
      else
        carried
      end

    case is_map(state) && AshA2ui.QueryRunner.parse(table, %{"query" => state}) do
      {:ok, params} -> params
      _invalid_or_missing -> AshA2ui.QueryRunner.default_params(table.query)
    end
  end

  # Loads the option lists for the view's relationship selects and
  # pick_existing nested forms: the destination's primary read action with
  # the same actor/tenant/authorize? opts (policies apply to option reads),
  # sorted by `option_sort` and capped at `option_limit`. Returns
  # `%{name => [%{"label" => _, "value" => _}]}` — the shape written to the
  # reserved `/options/<name>` paths. Searchable sources load the same
  # initial page; the `"option_search"` action refreshes them.
  defp load_options!(resolved_view, opts) do
    resolved_view
    |> ResolvedView.option_sources()
    |> Map.new(fn {name, source} ->
      records =
        source.destination
        |> Ash.Query.for_read(ResourceInfo.primary_action!(source.destination, :read).name)
        |> Ash.Query.sort([{source.option_sort, :asc}])
        |> Ash.Query.limit(source.option_limit)
        |> Ash.read!(option_read_opts(source.destination, opts))

      {name, Enum.map(records, &option_entry(&1, source))}
    end)
  end

  @doc false
  # One `%{"label" => _, "value" => _}` option entry for a destination record
  # of the given option source. Shared with `AshA2ui.ActionHandler` (the
  # `option_search` refresh emits the same shape).
  @spec option_entry(Ash.Resource.record(), map) :: map
  def option_entry(record, source) do
    value = option_string(Map.get(record, source.option_value))
    label = Map.get(record, source.option_label)

    %{"label" => (label && option_string(label)) || value, "value" => value}
  end

  defp option_read_opts(destination, opts) do
    domain =
      ResourceInfo.domain(destination) || opts[:domain] ||
        raise(ArgumentError, "no domain configured for #{inspect(destination)}")

    [
      domain: domain,
      actor: opts[:actor],
      tenant: opts[:tenant],
      authorize?: Keyword.get(opts, :authorize?, true)
    ]
  end

  defp option_string(%Date{} = date), do: Date.to_iso8601(date)
  defp option_string(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp option_string(%Decimal{} = decimal), do: Decimal.to_string(decimal)
  defp option_string(value), do: to_string(value)

  defp read_opts(resolved_view, opts) do
    domain =
      opts[:domain] || ResourceInfo.domain(resolved_view.resource) ||
        raise(ArgumentError, "no domain configured for #{inspect(resolved_view.resource)}")

    [
      domain: domain,
      actor: opts[:actor],
      tenant: opts[:tenant],
      authorize?: Keyword.get(opts, :authorize?, true)
    ]
  end
end
