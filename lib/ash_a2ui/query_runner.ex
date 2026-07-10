defmodule AshA2ui.QueryRunner do
  @moduledoc """
  Validates client-supplied `"query"` action context against a view's
  `AshA2ui.Query` allowlist and executes the resulting Ash read.

  The allowlist principle: the client only ever *references* the named query
  declared in the DSL — every requested search/sort/filter/page value is
  validated against `search_fields` / `sortable` / `filters` /
  `max_page_size`, and anything not declared is rejected before Ash is
  called. No arbitrary client sort/filter parameters ever reach the data
  layer.

  ## The `/query` data-model state shape

  `run/3` returns (alongside the records) the map written to the reserved
  `/query` data-model path:

      %{
        "search" => "",
        "filters" => %{"status" => "", "category" => ""},   # every declared filter, "" = inactive
        "sort" => %{"field" => "name", "dir" => "asc"},     # or nil when unsorted
        "page" => 1,
        "pageSize" => 25,
        "totalCount" => 42,                                 # or nil when the data layer can't count
        "hasMore" => true
      }

  ## Pagination mechanism

  Plain `Ash.Query.limit/2` + `Ash.Query.offset/2` with `limit = page_size + 1`
  — the extra row only signals `hasMore` and is dropped from the results. This
  works on any data layer without requiring the read action to enable Ash
  pagination. `totalCount` is computed with `Ash.count/2` on the filtered
  (unpaginated) query and degrades to `nil` on data layers without count
  support. The resource's primary key is appended as a sort tiebreaker so
  pages are stable under equal sort values.
  """

  import Ash.Expr

  require Ash.Query

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.ResolvedView

  @typedoc "Validated query parameters, safe to execute."
  @type params :: %{
          search: String.t(),
          filters: [{atom, term}],
          sort: {atom, :asc | :desc} | nil,
          page: pos_integer,
          page_size: pos_integer
        }

  @doc """
  Parses and validates a `"query"` action context map against the view's
  query allowlist.

  The context shape (all keys optional):

      %{
        "query" => %{"search" => _, "filters" => _, "sort" => _, "page" => _, "pageSize" => _},
        "page" => 1,        # literal page override (used by the Apply button to reset to page 1)
        "pageDelta" => 1    # relative page change (used by the prev/next buttons)
      }

  Returns `{:ok, params}` or `{:error, reason_text}` — non-allowlisted sort
  fields, filters, or search on a query without `search_fields` are rejected,
  never passed through. Page is clamped to >= 1 and page size to
  `1..max_page_size`. Unknown keys inside `"query"` (such as the echoed
  `totalCount`/`hasMore`) are ignored.
  """
  @spec parse(ResolvedView.t(), map) :: {:ok, params} | {:error, String.t()}
  def parse(%{query: nil}, _context) do
    {:error, "No query is configured for this surface."}
  end

  def parse(view, context) when is_map(context) do
    query = view.query

    with {:ok, state} <- query_state(context),
         {:ok, search} <- parse_search(query, state),
         {:ok, filters} <- parse_filters(view.resource, query, state),
         {:ok, sort} <- parse_sort(query, state),
         {:ok, page} <- parse_page(state, context),
         {:ok, page_size} <- parse_page_size(query, state) do
      {:ok, %{search: search, filters: filters, sort: sort, page: page, page_size: page_size}}
    end
  end

  @doc """
  The validated params equivalent to an empty client context: no search, no
  filters, the declared default sort, page 1 at the declared page size. Used
  for initial surface loads and refreshes without client query state.
  """
  @spec default_params(AshA2ui.Query.t()) :: params
  def default_params(query) do
    %{search: "", filters: [], sort: nil, page: 1, page_size: query.page_size}
  end

  @doc """
  Builds the frozen `/query` data-model state map (see the moduledoc) for
  `params` with the given `total_count` (integer or `nil`) and `has_more`.
  """
  @spec state(AshA2ui.Query.t(), params, non_neg_integer | nil, boolean) :: map
  def state(query, params, total_count, has_more) do
    effective_sort = effective_sort(query, params)

    %{
      "search" => params.search,
      "filters" => filters_state(query, params.filters),
      "sort" => sort_state(effective_sort),
      "page" => params.page,
      "pageSize" => params.page_size,
      "totalCount" => total_count,
      "hasMore" => has_more
    }
  end

  @doc """
  Executes the validated `params` through the view's read action and returns
  `{:ok, records, query_state}` — `query_state` being the frozen `/query`
  data-model shape (see the moduledoc) — or `{:error, error}` when the read
  fails.

  `ash_opts` are the usual `:domain` / `:actor` / `:tenant` / `:authorize?`
  read options.
  """
  @spec run(ResolvedView.t(), params, keyword) ::
          {:ok, [Ash.Resource.record()], map} | {:error, term}
  def run(view, params, ash_opts) do
    query = view.query
    effective_sort = effective_sort(query, params)

    filtered =
      view.resource
      |> Ash.Query.for_read(read_action(view), %{}, ash_opts)
      |> apply_filters(params.filters)
      |> apply_search(query, params.search)

    paged =
      filtered
      |> Ash.Query.sort(effective_sort ++ tiebreaker(view.resource, effective_sort))
      |> Ash.Query.limit(params.page_size + 1)
      |> Ash.Query.offset((params.page - 1) * params.page_size)

    case Ash.read(paged) do
      {:ok, rows} ->
        has_more = length(rows) > params.page_size
        records = Enum.take(rows, params.page_size)
        {:ok, records, state(query, params, total_count(filtered), has_more)}

      {:error, error} ->
        {:error, error}
    end
  end

  # --- context parsing --------------------------------------------------------

  defp query_state(context) do
    case Map.get(context, "query", %{}) do
      state when is_map(state) -> {:ok, state}
      _other -> {:error, ~s(Malformed query action: "query" must be a map.)}
    end
  end

  defp parse_search(query, state) do
    case Map.get(state, "search") do
      empty when empty in [nil, ""] ->
        {:ok, ""}

      search when is_binary(search) ->
        if query.search_fields == [] do
          {:error, "Search is not enabled for this query: it declares no search_fields."}
        else
          {:ok, search}
        end

      _other ->
        {:error, ~s(Malformed query action: "search" must be a string.)}
    end
  end

  defp parse_filters(resource, query, state) do
    case Map.get(state, "filters", %{}) do
      filters when is_map(filters) ->
        collect_filters(resource, query, filters)

      _other ->
        {:error, ~s(Malformed query action: "filters" must be a map.)}
    end
  end

  defp collect_filters(resource, query, filters) do
    filters
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      case parse_filter(resource, query, key, value) do
        {:ok, filter} -> {:cont, {:ok, [filter | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, collected} -> {:ok, Enum.reverse(collected)}
      error -> error
    end
  end

  defp parse_filter(resource, query, key, value) do
    case allowlisted(query.filters, key) do
      nil ->
        {:error,
         "Filter #{inspect(key)} is not allowlisted: it is not declared in the query's filters."}

      field ->
        case cast_filter_value(resource, field, value) do
          {:ok, cast} -> {:ok, {field, cast}}
          :error -> {:error, "Filter #{inspect(key)} value #{inspect(value)} is invalid."}
        end
    end
  end

  # ChoicePickers may bind a single string or a string list (multipleSelection);
  # accept both. Every value must cast to the attribute's type + constraints.
  defp cast_filter_value(resource, field, values) when is_list(values) do
    values
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case cast_filter_value(resource, field, value) do
        {:ok, cast} -> {:cont, {:ok, [cast | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, [single]} -> {:ok, single}
      {:ok, cast} -> {:ok, Enum.reverse(cast)}
      :error -> :error
    end
  end

  defp cast_filter_value(resource, field, value) do
    attribute = ResourceInfo.attribute(resource, field)

    with {:ok, cast} <- Ash.Type.cast_input(attribute.type, value, attribute.constraints),
         {:ok, cast} <- Ash.Type.apply_constraints(attribute.type, cast, attribute.constraints) do
      {:ok, cast}
    else
      _error -> :error
    end
  end

  defp parse_sort(query, state) do
    case Map.get(state, "sort") do
      nil ->
        {:ok, nil}

      %{"field" => field} = sort when is_binary(field) ->
        dir = Map.get(sort, "dir", "asc")

        cond do
          is_nil(allowlisted(query.sortable, field)) ->
            {:error,
             "Sort field #{inspect(field)} is not allowlisted: it is not declared in the " <>
               "query's sortable fields."}

          dir not in ["asc", "desc"] ->
            {:error, "Sort direction #{inspect(dir)} is invalid: use \"asc\" or \"desc\"."}

          true ->
            {:ok, {allowlisted(query.sortable, field), String.to_existing_atom(dir)}}
        end

      _other ->
        {:error, ~s(Malformed query action: "sort" must be a {"field", "dir"} map or null.)}
    end
  end

  # Precedence: a literal "page" in the context wins (the Apply button resets
  # to page 1), then "pageDelta" relative to the state's page (prev/next
  # buttons), then the state's page itself. Always clamped to >= 1.
  defp parse_page(state, context) do
    with {:ok, current} <- integer_or_default(Map.get(state, "page"), 1, "page"),
         {:ok, override} <- integer_or_default(Map.get(context, "page"), nil, "page"),
         {:ok, delta} <- integer_or_default(Map.get(context, "pageDelta"), 0, "pageDelta") do
      {:ok, max(override || current + delta, 1)}
    end
  end

  defp parse_page_size(query, state) do
    case integer_or_default(Map.get(state, "pageSize"), query.page_size, "pageSize") do
      {:ok, size} -> {:ok, size |> min(query.max_page_size) |> max(1)}
      error -> error
    end
  end

  defp integer_or_default(nil, default, _key), do: {:ok, default}
  defp integer_or_default(value, _default, _key) when is_integer(value), do: {:ok, value}

  defp integer_or_default(_value, _default, key),
    do: {:error, "Malformed query action: #{inspect(key)} must be an integer."}

  # String-compares client input against the declared atom allowlist — never
  # creating atoms from client input.
  defp allowlisted(allowlist, key) do
    Enum.find(allowlist, &(to_string(&1) == key))
  end

  # --- query building ---------------------------------------------------------

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {field, values}, query when is_list(values) ->
        Ash.Query.filter(query, ^ref(field) in ^values)

      {field, value}, query ->
        Ash.Query.filter(query, ^ref(field) == ^value)
    end)
  end

  defp apply_search(query, _ui_query, ""), do: query

  defp apply_search(query, ui_query, search) do
    ci_search = Ash.CiString.new(search)

    condition =
      ui_query.search_fields
      |> Enum.map(&expr(contains(^ref(&1), ^ci_search)))
      |> Enum.reduce(&expr(^&2 or ^&1))

    Ash.Query.filter(query, ^condition)
  end

  defp effective_sort(query, params) do
    case params.sort do
      nil -> query.default_sort
      sort -> [sort]
    end
  end

  defp tiebreaker(resource, effective_sort) do
    sorted_fields = Enum.map(effective_sort, &elem(&1, 0))

    resource
    |> ResourceInfo.primary_key()
    |> Enum.reject(&(&1 in sorted_fields))
    |> Enum.map(&{&1, :asc})
  end

  defp total_count(filtered_query) do
    case Ash.count(filtered_query) do
      {:ok, count} -> count
      {:error, _error} -> nil
    end
  end

  defp read_action(view),
    do: view.read_action || ResourceInfo.primary_action!(view.resource, :read).name

  # --- /query state -----------------------------------------------------------

  # Every declared filter is present ("" = inactive) so client bindings under
  # /query/filters/<name> are stable.
  defp filters_state(query, active_filters) do
    active = Map.new(active_filters)

    Map.new(query.filters, fn field ->
      {to_string(field), stringify(Map.get(active, field, ""))}
    end)
  end

  defp sort_state([]), do: nil

  defp sort_state([{field, dir} | _rest]),
    do: %{"field" => to_string(field), "dir" => to_string(dir)}

  defp stringify(values) when is_list(values), do: Enum.map(values, &stringify/1)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
