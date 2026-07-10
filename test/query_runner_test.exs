defmodule AshA2ui.QueryRunnerTest do
  @moduledoc """
  `AshA2ui.QueryRunner` tests: allowlist validation of client-supplied query
  context (search/sort/filters/pagination) and execution of the resulting Ash
  read. This file pins the frozen `/query` data-model shape and the `"query"`
  action context parsing rules.
  """

  use ExUnit.Case, async: true

  alias AshA2ui.QueryRunner
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Paginated

  # Paginated declares: search_fields [:name], sortable [:name, :inserted_at],
  # filters [:status, :category], default_sort name: :asc, page_size 5,
  # max_page_size 10.
  defp view, do: ResolvedView.resolve(Paginated)

  defp seed!(count, attrs_fn) do
    for i <- 1..count do
      Ash.create!(Paginated, attrs_fn.(i), authorize?: false)
    end
  end

  defp run!(context) do
    view = view()
    {:ok, params} = QueryRunner.parse(view, context)
    {:ok, records, state} = QueryRunner.run(view, params, domain: AshA2ui.Test.Domain)
    {records, state}
  end

  describe "parse/2 validation (the allowlist)" do
    test "empty context parses to the query's declared defaults" do
      assert {:ok, params} = QueryRunner.parse(view(), %{})

      assert params.search == ""
      assert params.filters == []
      assert params.sort == nil
      assert params.page == 1
      assert params.page_size == 5
    end

    test "rejects a non-allowlisted sort field" do
      context = %{"query" => %{"sort" => %{"field" => "status", "dir" => "asc"}}}

      assert {:error, reason} = QueryRunner.parse(view(), context)
      assert reason =~ ~s(Sort field "status" is not allowlisted)
    end

    test "rejects an invalid sort direction" do
      context = %{"query" => %{"sort" => %{"field" => "name", "dir" => "sideways"}}}

      assert {:error, reason} = QueryRunner.parse(view(), context)
      assert reason =~ ~s(Sort direction "sideways" is invalid)
    end

    test "rejects a non-allowlisted filter" do
      context = %{"query" => %{"filters" => %{"name" => "x"}}}

      assert {:error, reason} = QueryRunner.parse(view(), context)
      assert reason =~ ~s(Filter "name" is not allowlisted)
    end

    test "rejects a filter value that does not cast to the attribute type" do
      context = %{"query" => %{"filters" => %{"status" => "bogus"}}}

      assert {:error, reason} = QueryRunner.parse(view(), context)
      assert reason =~ ~s(Filter "status" value "bogus" is invalid)
    end

    test "rejects search when the query declares no search_fields" do
      no_search_view = %{view() | query: %{view().query | search_fields: []}}

      assert {:error, reason} =
               QueryRunner.parse(no_search_view, %{"query" => %{"search" => "abc"}})

      assert reason =~ ~r/Search is not enabled/
    end

    test "empty filter values are treated as inactive" do
      context = %{"query" => %{"filters" => %{"status" => "", "category" => nil}}}

      assert {:ok, params} = QueryRunner.parse(view(), context)
      assert params.filters == []
    end

    test "page and pageSize are clamped, pageSize to max_page_size" do
      context = %{"query" => %{"page" => 0, "pageSize" => 500}}

      assert {:ok, params} = QueryRunner.parse(view(), context)
      assert params.page == 1
      assert params.page_size == 10
    end

    test "a literal page in the context overrides the query state's page" do
      context = %{"query" => %{"page" => 7}, "page" => 1}

      assert {:ok, params} = QueryRunner.parse(view(), context)
      assert params.page == 1
    end

    test "pageDelta is applied to the query state's page and clamped at 1" do
      assert {:ok, %{page: 3}} =
               QueryRunner.parse(view(), %{"query" => %{"page" => 2}, "pageDelta" => 1})

      assert {:ok, %{page: 1}} =
               QueryRunner.parse(view(), %{"query" => %{"page" => 1}, "pageDelta" => -1})
    end

    test "rejects a malformed query context" do
      assert {:error, reason} = QueryRunner.parse(view(), %{"query" => "nope"})
      assert reason =~ ~r/Malformed query action/

      assert {:error, reason} = QueryRunner.parse(view(), %{"query" => %{"page" => "x"}})
      assert reason =~ ~r/Malformed query action/
    end
  end

  describe "run/3 execution and the frozen /query state shape" do
    test "paginates with default sort and reports totalCount/hasMore" do
      seed!(7, &%{name: "Item #{&1}", status: :open})

      {records, state} = run!(%{})

      assert length(records) == 5
      assert Enum.map(records, & &1.name) == ["Item 1", "Item 2", "Item 3", "Item 4", "Item 5"]

      assert state == %{
               "search" => "",
               "filters" => %{"status" => "", "category" => ""},
               "sort" => %{"field" => "name", "dir" => "asc"},
               "page" => 1,
               "pageSize" => 5,
               "totalCount" => 7,
               "hasMore" => true
             }
    end

    test "the last page reports hasMore false" do
      seed!(7, &%{name: "Item #{&1}"})

      {records, state} = run!(%{"query" => %{"page" => 2}})

      assert Enum.map(records, & &1.name) == ["Item 6", "Item 7"]
      assert state["page"] == 2
      assert state["hasMore"] == false
      assert state["totalCount"] == 7
    end

    test "search is a case-insensitive contains OR'd across search_fields" do
      seed!(1, fn _ -> %{name: "Alpha Widget"} end)
      seed!(1, fn _ -> %{name: "beta wIDGet"} end)
      seed!(1, fn _ -> %{name: "Gamma"} end)

      {records, state} = run!(%{"query" => %{"search" => "widget"}})

      assert Enum.map(records, & &1.name) |> Enum.sort() == ["Alpha Widget", "beta wIDGet"]
      assert state["search"] == "widget"
      assert state["totalCount"] == 2
    end

    test "equality filters narrow the read" do
      seed!(2, &%{name: "Open #{&1}", status: :open, category: :bug})
      seed!(3, &%{name: "Closed #{&1}", status: :closed, category: :feature})

      {records, state} = run!(%{"query" => %{"filters" => %{"status" => "closed"}}})

      assert length(records) == 3
      assert Enum.all?(records, &(&1.status == :closed))
      assert state["filters"] == %{"status" => "closed", "category" => ""}
    end

    test "an allowlisted sort overrides the default sort" do
      seed!(3, &%{name: "Item #{&1}"})

      {records, state} =
        run!(%{"query" => %{"sort" => %{"field" => "name", "dir" => "desc"}}})

      assert Enum.map(records, & &1.name) == ["Item 3", "Item 2", "Item 1"]
      assert state["sort"] == %{"field" => "name", "dir" => "desc"}
    end

    test "search, filter, sort, and pagination compose" do
      seed!(4, &%{name: "Bug #{&1}", status: :open, category: :bug})
      seed!(4, &%{name: "Bug #{&1 + 4}", status: :closed, category: :bug})
      seed!(4, &%{name: "Feature #{&1}", status: :open, category: :feature})

      {records, state} =
        run!(%{
          "query" => %{
            "search" => "bug",
            "filters" => %{"status" => "open"},
            "sort" => %{"field" => "name", "dir" => "desc"},
            "pageSize" => 3
          }
        })

      assert Enum.map(records, & &1.name) == ["Bug 4", "Bug 3", "Bug 2"]
      assert state["totalCount"] == 4
      assert state["hasMore"] == true
    end
  end
end
