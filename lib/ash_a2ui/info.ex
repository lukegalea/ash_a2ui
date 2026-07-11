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

  # Loads the surface's records through a normal `Ash.read` (policies apply).
  # Surfaces without a table component render no records. With a `query`
  # configured, the read runs through `AshA2ui.QueryRunner` — with the
  # caller-carried `:query_state` when given (validated like any client
  # input, falling back to the declared defaults), otherwise with the
  # query's declared defaults (default sort, page 1) — and the resulting
  # `/query` state is handed to the encoder via the `:query_state` option.
  defp load_records!(resolved_view, opts) do
    cond do
      not Enum.any?(resolved_view.components, &(&1.name == :table)) ->
        {[], opts}

      is_nil(resolved_view.read_action) ->
        raise ArgumentError,
              "cannot load records for #{inspect(resolved_view.resource)}: the resource has " <>
                "no read action (declare one, or set `read_action` on the table component)"

      resolved_view.query ->
        params = query_params(resolved_view, opts)

        case AshA2ui.QueryRunner.run(resolved_view, params, read_opts(resolved_view, opts)) do
          {:ok, records, query_state} ->
            {records, Keyword.put(opts, :query_state, query_state)}

          {:error, error} ->
            raise Ash.Error.to_error_class(error)
        end

      true ->
        records =
          resolved_view.resource
          |> Ash.Query.for_read(resolved_view.read_action)
          |> Ash.Query.load(resolved_view.loads)
          |> Ash.read!(read_opts(resolved_view, opts))

        {records, opts}
    end
  end

  defp query_params(resolved_view, opts) do
    case Keyword.get(opts, :query_state) do
      state when is_map(state) ->
        case AshA2ui.QueryRunner.parse(resolved_view, %{"query" => state}) do
          {:ok, params} -> params
          {:error, _reason} -> AshA2ui.QueryRunner.default_params(resolved_view.query)
        end

      _missing ->
        AshA2ui.QueryRunner.default_params(resolved_view.query)
    end
  end

  # Loads the option lists for the view's relationship selects: the
  # destination's primary read action with the same actor/tenant/authorize?
  # opts (policies apply to option reads), sorted by `option_sort` and capped
  # at `option_limit`. Returns `%{field_name => [%{"label" => _, "value" => _}]}`
  # — the shape written to the reserved `/options/<field>` paths.
  defp load_options!(resolved_view, opts) do
    Map.new(resolved_view.selects, fn {field_name, select} ->
      records =
        select.destination
        |> Ash.Query.for_read(ResourceInfo.primary_action!(select.destination, :read).name)
        |> Ash.Query.sort([{select.option_sort, :asc}])
        |> Ash.Query.limit(select.option_limit)
        |> Ash.read!(option_read_opts(select.destination, opts))

      options =
        Enum.map(records, fn record ->
          value = option_string(Map.get(record, select.option_value))
          label = Map.get(record, select.option_label)

          %{"label" => (label && option_string(label)) || value, "value" => value}
        end)

      {field_name, options}
    end)
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
