defmodule AshA2ui.Verifiers.VerifyQueries do
  @moduledoc """
  Verifies at compile time that every `query` entity is a sound allowlist:

    * `search_fields`, `sortable`, `filters`, and `default_sort` keys must be
      public attributes of the resolved resource (relationship-sourced
      `source` columns get a dedicated "not sortable" error),
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
    attributes = public_attributes(target)

    Enum.reduce_while(queries, :ok, fn query, :ok ->
      case verify_query(query, attributes, source_fields, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_query(query, attributes, source_fields, module) do
    with :ok <- verify_allowlists(query, attributes, source_fields, module),
         :ok <- verify_search_types(query, attributes, module) do
      verify_page_sizes(query, module)
    end
  end

  defp verify_allowlists(query, attributes, source_fields, module) do
    [
      search_fields: query.search_fields,
      sortable: query.sortable,
      filters: query.filters,
      default_sort: Keyword.keys(query.default_sort)
    ]
    |> Enum.reduce_while(:ok, fn {option, names}, :ok ->
      case verify_fields(query, option, names, attributes, source_fields, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_fields(query, option, names, attributes, source_fields, module) do
    case Enum.find(names, &(not Map.has_key?(attributes, &1))) do
      nil ->
        :ok

      unknown ->
        if MapSet.member?(source_fields, unknown) do
          {:error,
           DslError.exception(
             module: module,
             path: [:a2ui, :query, query.name, option],
             message:
               "query #{inspect(query.name)} lists #{inspect(unknown)} in #{option}, but " <>
                 "#{inspect(unknown)} is a relationship-sourced column and is not sortable " <>
                 "or filterable — only plain public attributes may appear in query allowlists"
           )}
        else
          {:error,
           DslError.exception(
             module: module,
             path: [:a2ui, :query, query.name, option],
             message: """
             query #{inspect(query.name)} references unknown field #{inspect(unknown)} in #{option}.

             Every field in a query allowlist must be a public attribute of the resource. \
             Available fields: #{inspect(Map.keys(attributes))}
             """
           )}
        end
    end
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
