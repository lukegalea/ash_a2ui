defmodule AshA2ui.Experience.ModeStateMachineTest do
  @moduledoc """
  A2UI-101/AC-6..AC-10: the experience v2 task-mode state machine — the
  browse start state, the create/view/edit task transitions, and the cancel
  path back to browse.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Experience.NoUpdate
  alias AshA2ui.Test.Experience.Task

  setup do
    Application.put_env(:ash_a2ui, :experience_version, 2)

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
        "surfaceId" => "experience_task",
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

  describe "initial state" do
    @tag ac: "A2UI-101/AC-6"
    test "initial surface is browse with hidden panel" do
      [create, components, data] = AshA2ui.Info.build_surface(Task)
      Enum.each([create, components, data], &assert_valid_server_message/1)

      %{"updateDataModel" => %{"value" => model}} = data
      ui = model["ui"]

      assert ui["intent"] == "browse"
      assert ui["panel"]["visible"] == []
      assert ui["panel"]["submit_visible"] == []
      # neither panel content mode is showing in browse
      assert ui["panel"]["form_visible"] == []
      assert ui["panel"]["view_visible"] == []
      assert ui["panel"]["mode"] == nil

      comps = components_by_id(components)

      # no row control labeled "Select" anywhere in the tree
      refute Enum.any?(Map.values(comps), &(&1["text"] == "Select"))

      # the form renders inside the panel gate, hidden until a task opens
      assert %{"children" => %{"componentId" => "form", "path" => "/ui/panel/visible"}} =
               comps["form_slot"]

      assert "form_slot" in comps["root"]["children"]

      # zero jank: the gated panel is the FIRST root child, so an open
      # create/view/edit task is front-and-center above the tables
      assert hd(comps["root"]["children"]) == "form_slot"
    end

    @tag ac: "A2UI-101/AC-6"
    test "initial v1.0 surface keeps the ui state through the response collapse" do
      [%{"createSurface" => create}] = AshA2ui.Info.build_surface(Task, spec_version: "1.0")

      ui = create["dataModel"]["ui"]

      # the /ui/response collapse does not drop the v2 state
      assert ui["intent"] == "browse"
      assert ui["panel"]["visible"] == []
      assert ui["panel"]["submit_visible"] == []
      assert ui["panel"]["form_visible"] == []
      assert ui["panel"]["view_visible"] == []
      assert ui["feedback"] == %{"kind" => nil, "message" => ""}

      assert %{"status" => "", "message" => "", "result" => %{}, "resultText" => ""} =
               ui["response"]
    end
  end

  describe "create task" do
    @tag ac: "A2UI-101/AC-7"
    test "start_create opens a labeled create task" do
      # open + fail a submission first, so "prior feedback is cleared" is real
      assert {:ok, _} = ActionHandler.handle(Task, envelope("start_create"))

      assert {:error, _} =
               ActionHandler.handle(Task, envelope("submit_form", %{"values" => %{"name" => ""}}))

      assert {:ok, messages} = ActionHandler.handle(Task, envelope("start_create"))
      values = by_path(messages)

      assert values["/ui/intent"] == "create"

      assert %{
                "visible" => visible,
                "mode" => "create",
                "title" => "Create Task",
                "primary_label" => "Create Task",
                "record_id" => nil,
                "submit_visible" => submit,
                "form_visible" => form,
                "view_visible" => view
              } = values["/ui/panel"]

      assert visible != []
      assert submit != []
      # create shows the editable form, never the read-only display
      assert form != []
      assert view == []

      # the form is reset to its initial (empty) values and feedback cleared
      assert values["/form"] == %{}
      assert values["/ui/feedback"] == %{"kind" => nil, "message" => ""}
      assert values["/errors"] == %{}
    end

    @tag ac: "A2UI-101/AC-7"
    test "start_create speaks v1.0 on a v1.0 surface" do
      assert {:ok, messages} =
               ActionHandler.handle(Task, envelope("start_create"), spec_version: "1.0")

      assert Enum.all?(messages, &(&1["version"] == "v1.0"))

      values = by_path(messages)
      assert values["/ui/intent"] == "create"
      assert values["/ui/panel"]["mode"] == "create"
    end
  end

  describe "view task" do
    @tag ac: "A2UI-101/AC-8"
    test "view_record populates the read-only display, never the form buffer" do
      record = Ash.create!(Task, %{name: "Read me"}, authorize?: false)

      assert {:ok, messages} =
               ActionHandler.handle(Task, envelope("view_record", %{"recordId" => record.id}))

      values = by_path(messages)

      assert values["/ui/intent"] == "view"

      panel = values["/ui/panel"]
      assert panel["visible"] != []
      assert panel["mode"] == "view"
      assert panel["title"] == "View Task"
      # no primary submit action is offered in view mode
      assert panel["primary_label"] == ""
      assert panel["submit_visible"] == []
      assert panel["record_id"] == record.id

      # the read-only half of the state machine: the derived display shows,
      # the editable form does not
      assert panel["view_visible"] != []
      assert panel["form_visible"] == []

      # the record's values ride the derived display path...
      assert values["/ui/panel/record"]["name"] == "Read me"
      assert values["/ui/panel/record"]["id"] == record.id

      # ...and /form — the edit buffer — is NEVER written in view mode.
      # This is the "view-opens-edit" fix: viewing must not populate the
      # buffer an edit task would submit.
      refute Map.has_key?(values, "/form")
    end
  end

  describe "edit task" do
    @tag ac: "A2UI-101/AC-9"
    test "start_edit populates edit task with save changes" do
      record = Ash.create!(Task, %{name: "Edit me"}, authorize?: false)

      assert {:ok, messages} =
               ActionHandler.handle(Task, envelope("start_edit", %{"recordId" => record.id}))

      values = by_path(messages)

      assert values["/ui/intent"] == "edit"

      panel = values["/ui/panel"]
      assert panel["visible"] != []
      assert panel["mode"] == "edit"
      assert panel["title"] == "Edit Task"
      assert panel["primary_label"] == "Save changes"
      # the save/cancel pair together, over the editable form
      assert panel["submit_visible"] != []
      assert panel["form_visible"] != []
      assert panel["view_visible"] == []

      assert values["/form"]["name"] == "Edit me"
      assert values["/form"]["id"] == record.id

      # no stale view display values ride along
      refute Map.has_key?(values, "/ui/panel/record")
    end

    @tag ac: "A2UI-101/AC-9"
    test "start_edit is rejected on surfaces without a declared update action" do
      record = Ash.create!(NoUpdate, %{name: "Read only"}, authorize?: false)

      assert {:error, messages} =
               ActionHandler.handle(NoUpdate, envelope("start_edit", %{"recordId" => record.id}))

      assert Enum.any?(messages, fn
               %{"updateDataModel" => %{"path" => "/ui/status", "value" => value}} ->
                 value =~ "does not declare an update action"

               _other ->
                 false
             end)

      # and nothing was written: browse stays browse
      values = by_path(messages)
      refute Map.has_key?(values, "/form")
      refute Map.has_key?(values, "/ui/panel")
    end
  end

  describe "cancel" do
    @tag ac: "A2UI-101/AC-10"
    test "cancel returns to browse and resets the form" do
      assert {:ok, _} = ActionHandler.handle(Task, envelope("start_create"))

      assert {:ok, messages} = ActionHandler.handle(Task, envelope("cancel_record_task"))
      values = by_path(messages)

      assert values["/ui/intent"] == "browse"

      panel = values["/ui/panel"]
      assert panel["visible"] == []
      assert panel["mode"] == nil
      assert panel["submit_visible"] == []
      assert panel["form_visible"] == []
      assert panel["view_visible"] == []

      assert values["/form"] == %{}
      assert values["/ui/feedback"] == %{"kind" => nil, "message" => ""}
    end
  end

  defp components_by_id(components_message) do
    Map.new(components_message["updateComponents"]["components"], &{&1["id"], &1})
  end
end
