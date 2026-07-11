defmodule AshA2ui.Verifiers.VerifyQueries do
  @moduledoc """
  Verifies at compile time that every `query` entity is a sound allowlist:

    * `search_fields` and `filters` entries must be public attributes of the
      resolved resource (relationship-sourced `source` columns get a
      dedicated "not sortable" error, calculations/aggregates a dedicated
      "sortable-only" error),
    * `sortable` and `default_sort` entries must be public attributes, or
      public calculations/aggregates that Ash can sort generically
      (`Ash.Resource.Info.sortable?/3`: expression-backed calculations and
      non-`:first`-over-unsortable aggregates) — non-sortable
      calculations/aggregates get a tailored error,
    * `search_fields` entries must be string-typed (they are matched with a
      case-insensitive contains),
    * `page_size` must not exceed `max_page_size`,
    * query names must be unique, and
    * a component's `query` option must reference a declared query.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Skipped when no resource can be resolved (standalone
  UI module without `for_resource`) — `AshA2ui.Info.resource!/1` reports that
  at runtime.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @string_types [Ash.Type.String, Ash.Type.CiString]

  @impl true
  def verify(dsl_state) do
    case target_resource(dsl_state) do
      nil ->
        :ok

      target ->
        module = Verifier.get_persisted(dsl_state, :module)
        queries = queries(dsl_state)
        source_fields = source_field_names(dsl_state)

        with :ok <- verify_unique_names(queries, module),
             :ok <- verify_queries(queries, target, source_fields, module) do
          verify_references(dsl_state, queries, module)
        end
    end
  end

  defp source_field_names(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&(is_struct(&1, AshA2ui.Field) and not is_nil(&1.source)))
    |> MapSet.new(& &1.name)
  end

  defp verify_unique_names(queries, module) do
    queries
    |> Enum.frequencies_by(& &1.name)
    |> Enum.find(fn {_name, count} -> count > 1 end)
    |> case do
      nil ->
        :ok

      {name, _count} ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :query, name],
           message: "duplicate query name #{inspect(name)}: query names must be unique"
         )}
    end
  end

  defp verify_queries(queries, target, source_fields, module) do
    ctx = %{
      target: target,
      attributes: public_attributes(target),
      source_fields: source_fields,
      module: module
    }

    Enum.reduce_while(queries, :ok, fn query, :ok ->
      case verify_query(query, ctx) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_query(query, ctx) do
    with :ok <- verify_allowlists(query, ctx),
         :ok <- verify_search_types(query, ctx.attributes, ctx.module) do
      verify_page_sizes(query, ctx.module)
    end
  end

  defp verify_allowlists(query, ctx) do
    [
      search_fields: query.search_fields,
      sortable: query.sortable,
      filters: query.filters,
      default_sort: Keyword.keys(query.default_sort)
    ]
    |> Enum.reduce_while(:ok, fn {option, names}, :ok ->
      case verify_fields(query, option, names, ctx) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_fields(query, option, names, ctx) do
    Enum.reduce_while(names, :ok, fn name, :ok ->
      case verify_field(query, option, name, ctx) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # Sort options accept attributes and generically-sortable public
  # calculations/aggregates; search/filter options accept plain attributes
  # only. Everything else gets a tailored rejection.
  defp verify_field(query, option, name, ctx) do
    kind = field_kind(name, ctx)
    sort_option? = option in [:sortable, :default_sort]

    case kind do
      :attribute ->
        :ok

      kind when kind in [:calculation, :aggregate] and sort_option? ->
        verify_sortable(query, option, name, kind, ctx)

      kind when kind in [:calculation, :aggregate] ->
        {:error,
         allowlist_error(
           query,
           option,
           ctx.module,
           "query #{inspect(query.name)} lists #{inspect(name)} in #{option}, but " <>
             "#{inspect(name)} is #{with_article(kind)} — calculations and aggregates may " <>
             "only appear in `sortable`/`default_sort`, never in `#{option}`"
         )}

      :source ->
        {:error,
         allowlist_error(
           query,
           option,
           ctx.module,
           "query #{inspect(query.name)} lists #{inspect(name)} in #{option}, but " <>
             "#{inspect(name)} is a relationship-sourced column and is not sortable " <>
             "or filterable — only plain public attributes may appear in query allowlists"
         )}

      :unknown ->
        {:error,
         allowlist_error(query, option, ctx.module, """
         query #{inspect(query.name)} references unknown field #{inspect(name)} in #{option}.

         Every field in a query allowlist must be a public attribute (or, for sortable/\
         default_sort, a sortable public calculation or aggregate) of the resource. \
         Available attributes: #{inspect(Map.keys(ctx.attributes))}
         """)}
    end
  end

  defp verify_sortable(query, option, name, kind, ctx) do
    if Info.sortable?(ctx.target, name, include_private?: false) do
      :ok
    else
      detail =
        case kind do
          :calculation ->
            "only expression-backed calculations (`calculate ..., expr(...)`) can be " <>
              "sorted generically — module-based calculations have no data-layer expression"

          :aggregate ->
            "this aggregate kind/field cannot be sorted generically " <>
              "(e.g. a `:first` aggregate over an unsortable field)"
        end

      {:error,
       allowlist_error(
         query,
         option,
         ctx.module,
         "query #{inspect(query.name)} lists #{inspect(name)} in #{option}, but the " <>
           "#{kind} #{inspect(name)} is not sortable: #{detail}"
       )}
    end
  end

  defp with_article(:aggregate), do: "an aggregate"
  defp with_article(kind), do: "a #{kind}"

  defp field_kind(name, ctx) do
    cond do
      Map.has_key?(ctx.attributes, name) -> :attribute
      not is_nil(Info.public_calculation(ctx.target, name)) -> :calculation
      not is_nil(Info.public_aggregate(ctx.target, name)) -> :aggregate
      MapSet.member?(ctx.source_fields, name) -> :source
      true -> :unknown
    end
  end

  defp allowlist_error(query, option, module, message) do
    DslError.exception(
      module: module,
      path: [:a2ui, :query, query.name, option],
      message: message
    )
  end

  defp verify_search_types(query, attributes, module) do
    query.search_fields
    |> Enum.find(fn name ->
      case attributes[name] do
        %{type: type} -> Ash.Type.get_type(type) not in @string_types
        nil -> false
      end
    end)
    |> case do
      nil ->
        :ok

      non_string ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :query, query.name, :search_fields],
           message:
             "query #{inspect(query.name)} search_fields entry #{inspect(non_string)} must " <>
               "be a string-typed attribute (search uses a case-insensitive contains)"
         )}
    end
  end

  defp verify_page_sizes(%{page_size: page_size, max_page_size: max} = query, module)
       when page_size > max do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :query, query.name, :page_size],
       message: "query #{inspect(query.name)} page_size #{page_size} exceeds max_page_size #{max}"
     )}
  end

  defp verify_page_sizes(_query, _module), do: :ok

  defp verify_references(dsl_state, queries, module) do
    declared = MapSet.new(queries, & &1.name)

    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&(is_struct(&1, AshA2ui.Component) and not is_nil(&1.query)))
    |> Enum.reduce_while(:ok, fn component, :ok ->
      if MapSet.member?(declared, component.query) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          DslError.exception(
            module: module,
            path: [:a2ui, :component, component.name, :query],
            message: """
            component #{inspect(component.name)} references undeclared query #{inspect(component.query)}.

            Declare it with a `query #{inspect(component.query)} do ... end` entity in the a2ui section. \
            Declared queries: #{inspect(MapSet.to_list(declared))}
            """
          )}}
      end
    end)
  end

  defp queries(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Query))
  end

  defp public_attributes(target) do
    target |> Info.public_attributes() |> Map.new(&{&1.name, &1})
  end

  defp target_resource(dsl_state) do
    case Verifier.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if Ash.Resource.Dsl in Verifier.get_persisted(dsl_state, :extensions, []),
          do: dsl_state

      resource ->
        if Code.ensure_loaded?(resource) and Info.resource?(resource), do: resource
    end
  end
end
