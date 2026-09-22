defmodule AshA2ui.Experience.CompatV1Test do
  @moduledoc """
  A2UI-101/AC-17: with `experience_version` pinned to 1 output is
  byte-compatible with the pre-v2 release — the "Save" submit, the "Select"
  row control, always-present pagination, and the select_row handling all
  behave exactly as before. (The unpinned default is v2 — asserted below;
  the pin is the escape hatch.)
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Paginated

  setup do
    # the legacy emission is opt-in now; make the pin explicit and restore
    # on exit
    Application.put_env(:ash_a2ui, :experience_version, 1)

    on_exit(fn ->
      Application.delete_env(:ash_a2ui, :experience_version)
    end)

    :ok
  end

  defp envelope(name, context \\ %{}) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "paginated",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp by_path(messages) do
    messages
    |> Enum.filter(&Map.has_key?(&1, "updateDataModel"))
    |> Map.new(&{&1["updateDataModel"]["path"], &1["updateDataModel"]["value"]})
  end

  test "the unpinned default is experience v2" do
    Application.delete_env(:ash_a2ui, :experience_version)

    assert AshA2ui.Experience.version() == 2
    assert AshA2ui.Experience.v2?()
  end

  test "hosts can pin experience v1 (the escape hatch)" do
    assert AshA2ui.Experience.version() == 1
    refute AshA2ui.Experience.v2?()
  end

  @tag ac: "A2UI-101/AC-17"
  test "version one output is unchanged" do
    assert AshA2ui.Experience.version() == 1

    [create, components, data] = AshA2ui.Info.build_surface(Paginated, actor: nil)
    Enum.each([create, components, data], &assert_valid_server_message/1)

    comps = Map.new(components["updateComponents"]["components"], &{&1["id"], &1})

    # the Select row control is present
    assert %{"text" => "Select"} = comps["row_select_text"]
    assert %{"action" => %{"event" => %{"name" => "select_row"}}} = comps["row_select_button"]

    # the persistent form with its "Save" submit
    assert %{"text" => "Save"} = comps["form_submit_text"]
    assert "form_submit_button" in comps["form"]["children"]
    refute Map.has_key?(comps, "form_slot")
    refute Map.has_key?(comps, "form_submit_slot")
    refute Map.has_key?(comps, "form_title")
    refute Map.has_key?(comps, "form_cancel_button")

    # pagination is always present, regardless of result count (none here)
    assert %{"component" => "Row", "children" => pagination_children} =
             comps["query_pagination"]

    assert pagination_children == [
             "query_prev_button",
             "query_page_text",
             "query_next_button"
           ]

    # frozen root children order
    assert comps["root"]["children"] == [
             "table_heading",
             "query_controls",
             "records_list",
             "query_pagination",
             "form",
             "status_text",
             "action_result_panel"
           ]

    # frozen data model: the classic /ui trio, no experience state, no
    # pagination sentinels on the query state
    %{"updateDataModel" => %{"value" => model}} = data

    assert model["ui"] == %{
             "status" => "",
             "action_result" => %{},
             "action_result_text" => ""
           }

    assert model["query"]["page"] == 1
    refute Map.has_key?(model["query"], "_pagination_visible")
    refute Map.has_key?(model, "_empty_visible")
    refute Map.has_key?(model, "_empty_message")

    # select_row still populates the form
    record = Ash.create!(Paginated, %{name: "Compat"}, authorize?: false)

    assert {:ok, messages} =
             ActionHandler.handle(Paginated, envelope("select_row", %{"recordId" => record.id}))

    assert by_path(messages)["/form"]["name"] == "Compat"

    # submit_form still returns the classic success writes — no experience
    # state writes leak in
    assert {:ok, messages} =
             ActionHandler.handle(
               Paginated,
               envelope("submit_form", %{"values" => %{"name" => "Compat create"}})
             )

    values = by_path(messages)
    assert values["/ui/status"] == "Created successfully."
    refute Map.has_key?(values, "/ui/intent")
    refute Map.has_key?(values, "/ui/panel")
    refute Map.has_key?(values, "/ui/feedback")

    # experience v2 action names are still unknown actions under v1
    assert {:error, [message]} = ActionHandler.handle(Paginated, envelope("start_create"))

    assert message["updateDataModel"]["value"] =~ "Unknown action"
  end
end
