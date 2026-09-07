defmodule AshA2ui.Experience.AffordancesTest do
  @moduledoc """
  A2UI-101/AC-11..AC-13: experience v2 affordances — the View/Edit row
  controls (gated on the view's update action) and the create affordance
  (gated on the view's create action).
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Test.Experience.NoUpdate
  alias AshA2ui.Test.Experience.ReadOnly
  alias AshA2ui.Test.Experience.Task

  setup do
    Application.put_env(:ash_a2ui, :experience_version, 2)

    on_exit(fn ->
      Application.put_env(:ash_a2ui, :experience_version, 1)
    end)

    :ok
  end

  defp surface!(resource) do
    [_create, components, data] = AshA2ui.Info.build_surface(resource, actor: nil)

    %{"updateDataModel" => %{"value" => model}} = data

    comps =
      Map.new(components["updateComponents"]["components"], &{&1["id"], &1})

    %{comps: comps, model: model}
  end

  describe "without an update action" do
    @tag ac: "A2UI-101/AC-11"
    test "no update action means no edit control" do
      %{comps: comps, model: model} = surface!(NoUpdate)

      # rows offer View...
      assert %{"action" => %{"event" => %{"name" => "view_record"}}} = comps["view_button"]
      assert "view_button" in comps["record_row_content"]["children"]

      # ...but never Edit
      refute Map.has_key?(comps, "edit_button")
      refute Enum.any?(Map.values(comps), &(&1["text"] == "Edit"))

      # and no blank form appears: the panel starts closed
      assert model["ui"]["panel"]["visible"] == []
      assert model["ui"]["intent"] == "browse"
    end
  end

  describe "with a create action" do
    @tag ac: "A2UI-101/AC-12"
    test "create action presence gates the create affordance" do
      %{comps: comps, model: model} = surface!(Task)

      assert %{"action" => %{"event" => %{"name" => "start_create"}}} = comps["create_button"]
      assert %{"text" => "Create Task"} = comps["create_text"]
      assert "create_button" in comps["root"]["children"]

      # no blank form is initially visible
      assert model["ui"]["panel"]["visible"] == []
      assert model["ui"]["intent"] == "browse"
    end
  end

  describe "read-only resources" do
    @tag ac: "A2UI-101/AC-13"
    test "read only resource offers view only" do
      %{comps: comps} = surface!(ReadOnly)

      # rows offer View only
      assert %{"action" => %{"event" => %{"name" => "view_record"}}} = comps["view_button"]
      assert "view_button" in comps["record_row_content"]["children"]
      refute Map.has_key?(comps, "edit_button")

      # no create affordance
      refute Map.has_key?(comps, "create_button")

      # and no form or submit control is emitted
      refute Map.has_key?(comps, "form")
      refute Map.has_key?(comps, "form_slot")
      refute Map.has_key?(comps, "form_submit_button")
    end
  end
end
