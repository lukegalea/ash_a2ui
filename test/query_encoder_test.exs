defmodule AshA2ui.QueryEncoderTest do
  @moduledoc """
  Encoder tests for query-enabled surfaces: the query controls component tree
  (search TextField, per-filter ChoicePickers, prev/next pagination Buttons),
  the frozen `"query"` action wire contract on every control, the `/query`
  state in the initial data model, and the `"query"` binding added to
  `submit_form`/`invoke` contexts. Every message is schema-validated.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Encoder.V0_9_1
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.{KitchenSink, Paginated}

  defp encode(records \\ [], opts \\ []) do
    Paginated |> ResolvedView.resolve() |> V0_9_1.encode_surface(records, opts)
  end

  defp components_by_id(messages) do
    update = Enum.find(messages, &Map.has_key?(&1, "updateComponents"))
    Map.new(update["updateComponents"]["components"], &{&1["id"], &1})
  end

  describe "query component tree" do
    test "all messages are schema-valid and root interleaves the query sections" do
      messages = encode()
      Enum.each(messages, &assert_valid_server_message/1)

      components = components_by_id(messages)

      assert components["root"]["children"] == [
               "table_heading",
               "query_controls",
               "records_list",
               "query_pagination",
               "form",
               "status_text",
               "action_result_panel"
             ]
    end

    test "query_controls is a Row of search input, filter pickers, and the apply button" do
      components = encode() |> components_by_id()

      assert %{"component" => "Row", "children" => children} = components["query_controls"]

      assert children == [
               "query_search_input",
               "query_filter_status",
               "query_filter_category",
               "query_apply_button"
             ]
    end

    test "the search TextField binds to /query/search" do
      components = encode() |> components_by_id()

      assert %{
               "component" => "TextField",
               "label" => "Search",
               "value" => %{"path" => "/query/search"}
             } = components["query_search_input"]
    end

    test "a query without search_fields omits the search input" do
      view = ResolvedView.resolve(Paginated)
      view = %{view | query: %{view.query | search_fields: []}}

      messages = V0_9_1.encode_surface(view, [], [])
      Enum.each(messages, &assert_valid_server_message/1)

      components = components_by_id(messages)
      refute Map.has_key?(components, "query_search_input")

      assert components["query_controls"]["children"] == [
               "query_filter_status",
               "query_filter_category",
               "query_apply_button"
             ]
    end

    test "filter ChoicePickers bind under /query/filters with an All option first" do
      components = encode() |> components_by_id()

      assert %{
               "component" => "ChoicePicker",
               "label" => "Status",
               "variant" => "mutuallyExclusive",
               "value" => %{"path" => "/query/filters/status"},
               "options" => [
                 %{"label" => "All", "value" => ""},
                 %{"label" => "Open", "value" => "open"},
                 %{"label" => "Closed", "value" => "closed"}
               ]
             } = components["query_filter_status"]

      assert %{"value" => %{"path" => "/query/filters/category"}} =
               components["query_filter_category"]
    end

    test "the apply button carries the frozen query contract with a page-1 reset" do
      components = encode() |> components_by_id()

      assert %{
               "component" => "Button",
               "child" => "query_apply_text",
               "action" => %{
                 "event" => %{
                   "name" => "query",
                   "context" => %{"query" => %{"path" => "/query"}, "page" => 1}
                 }
               }
             } = components["query_apply_button"]

      assert %{"component" => "Text", "text" => "Apply"} = components["query_apply_text"]
    end

    test "prev/next pagination buttons carry the frozen pageDelta contract" do
      components = encode() |> components_by_id()

      assert %{
               "component" => "Row",
               "children" => ["query_prev_button", "query_page_text", "query_next_button"]
             } =
               components["query_pagination"]

      assert %{
               "component" => "Button",
               "child" => "query_prev_text",
               "action" => %{
                 "event" => %{
                   "name" => "query",
                   "context" => %{"query" => %{"path" => "/query"}, "pageDelta" => -1}
                 }
               }
             } = components["query_prev_button"]

      assert %{
               "action" => %{
                 "event" => %{
                   "name" => "query",
                   "context" => %{"query" => %{"path" => "/query"}, "pageDelta" => 1}
                 }
               }
             } = components["query_next_button"]

      assert %{"component" => "Text", "text" => %{"path" => "/query/page"}} =
               components["query_page_text"]
    end

    test "a surface without a query emits no query components (unchanged tree)" do
      messages = KitchenSink |> ResolvedView.resolve() |> V0_9_1.encode_surface([], [])
      components = components_by_id(messages)

      assert components["root"]["children"] == [
               "table_heading",
               "records_list",
               "form",
               "status_text",
               "action_result_panel"
             ]

      refute Map.has_key?(components, "query_controls")
      refute Map.has_key?(components, "query_pagination")
    end
  end

  describe "query bindings on write-action contexts" do
    test "the form submit button context carries the current /query" do
      components = encode() |> components_by_id()

      assert %{
               "event" => %{
                 "name" => "submit_form",
                 "context" => %{
                   "values" => %{"path" => "/form"},
                   "recordId" => %{"path" => "/form/id"},
                   "query" => %{"path" => "/query"}
                 }
               }
             } = components["form_submit_button"]["action"]
    end

    test "row-action invoke buttons carry the current /query" do
      components = encode() |> components_by_id()

      assert %{
               "event" => %{
                 "name" => "invoke",
                 "context" => %{
                   "action" => "destroy",
                   "recordId" => %{"path" => "id"},
                   "query" => %{"path" => "/query"}
                 }
               }
             } = components["row_action_destroy_button"]["action"]
    end

    test "surfaces without a query keep the original submit_form context" do
      components =
        KitchenSink
        |> ResolvedView.resolve()
        |> V0_9_1.encode_surface([], [])
        |> components_by_id()

      context = components["form_submit_button"]["action"]["event"]["context"]
      refute Map.has_key?(context, "query")
    end
  end

  describe "/query in the initial data model" do
    test "the bootstrap data model includes the query state" do
      state = %{
        "search" => "",
        "filters" => %{"status" => "", "category" => ""},
        "sort" => %{"field" => "name", "dir" => "asc"},
        "page" => 1,
        "pageSize" => 5,
        "totalCount" => 0,
        "hasMore" => false
      }

      assert [_, _, message] = encode([], query_state: state)
      assert_valid_server_message(message)

      assert message["updateDataModel"]["value"]["query"] == state
      assert message["updateDataModel"]["value"]["records"] == []
    end

    test "without an explicit query_state the encoder derives a default" do
      assert [_, _, message] = encode()

      assert %{
               "search" => "",
               "filters" => %{"status" => "", "category" => ""},
               "sort" => %{"field" => "name", "dir" => "asc"},
               "page" => 1,
               "pageSize" => 5,
               "totalCount" => 0,
               "hasMore" => false
             } = message["updateDataModel"]["value"]["query"]
    end

    test "surfaces without a query have no /query in the data model" do
      messages = KitchenSink |> ResolvedView.resolve() |> V0_9_1.encode_surface([], [])
      [_, _, message] = messages

      refute Map.has_key?(message["updateDataModel"]["value"], "query")
    end
  end

  describe "Info.build_surface/2 with a query" do
    test "loads the first page with default sort and real totalCount/hasMore" do
      for i <- 1..7 do
        Ash.create!(Paginated, %{name: "Row #{i}", status: :open}, authorize?: false)
      end

      messages = AshA2ui.Info.build_surface(Paginated, actor: nil)
      Enum.each(messages, &assert_valid_server_message/1)

      [_, _, data] = messages
      value = data["updateDataModel"]["value"]

      names = Enum.map(value["records"], & &1["name"])
      assert length(names) == 5
      assert names == Enum.sort(names)

      assert %{
               "page" => 1,
               "pageSize" => 5,
               "totalCount" => total,
               "hasMore" => true
             } = value["query"]

      assert total >= 7
    end
  end
end
