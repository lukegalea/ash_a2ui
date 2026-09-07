defmodule AshA2ui.Experience.AdminCatalogFallbackTest do
  @moduledoc """
  A2UI-101B/AC-7..AC-9: the catalog selection's fallback rules — advanced
  features stay basic-composed (byte-equal subtrees), the default
  configuration stays byte-identical to the A2UI-101 basic-v2 emission, and
  an `:admin_v1` selection under experience v1 is ignored (basic v1,
  byte-identical).
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Experience
  alias AshA2ui.Test.Experience.Task
  alias AshA2ui.Test.Paginated
  alias AshA2ui.Test.Ticket

  setup do
    Application.put_env(:ash_a2ui, :experience_version, 2)
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    on_exit(fn ->
      Application.put_env(:ash_a2ui, :experience_version, 1)
      Application.put_env(:ash_a2ui, :catalog, :basic)
    end)

    :ok
  end

  defp components_by_id(components_message) do
    Map.new(components_message["updateComponents"]["components"], &{&1["id"], &1})
  end

  describe "advanced features" do
    @tag ac: "A2UI-101B/AC-7"
    test "advanced features stay basic composed" do
      # Ticket's form carries nested_form entities (the contract's
      # advanced-feature list): its form subtree must stay byte-equal to
      # the basic-v2 emission while the core subtree upgrades.
      admin_surface = AshA2ui.Info.build_surface(Ticket, actor: nil)

      Application.put_env(:ash_a2ui, :catalog, :basic)
      basic_surface = AshA2ui.Info.build_surface(Ticket, actor: nil)
      Application.put_env(:ash_a2ui, :catalog, :admin_v1)

      [_create_admin, components_admin, data_admin] = admin_surface
      [_create_basic, components_basic, data_basic] = basic_surface

      admin = components_by_id(components_admin)
      basic = components_by_id(components_basic)

      # the core subtree upgraded
      assert admin["root"]["component"] == "entityPage"
      assert basic["root"]["component"] == "Column"
      assert Map.has_key?(admin, "data_grid")
      assert Map.has_key?(basic, "records_list")
      refute Map.has_key?(admin, "records_list")
      assert "form_slot" in admin["root"]["children"]
      assert "form_slot" in basic["root"]["children"]

      # the advanced form subtree is byte-equal: every component id the two
      # emissions share (form slot composition, inputs, errors, nested
      # rows, submit/cancel, create affordance, action-result panel) is
      # identical — only the root shell and the core-table/empty-state
      # components legitimately differ
      shared =
        MapSet.intersection(MapSet.new(Map.keys(admin)), MapSet.new(Map.keys(basic)))
        |> MapSet.difference(MapSet.new(["root", "empty_state"]))
        |> MapSet.to_list()

      assert "form_slot" in shared
      assert "form" in shared
      assert "nested_notes" in shared
      assert "form_submit_button" in shared

      Enum.each(shared, fn id ->
        assert admin[id] == basic[id], "shared component #{id} diverged from basic-v2"
      end)

      # and the whole data model is byte-equal (the ticket table has no
      # query, so the admin boolean props have nothing to attach to)
      assert data_admin == data_basic
    end
  end

  describe "default configuration" do
    @tag ac: "A2UI-101B/AC-8"
    test "basic catalog output is unchanged" do
      Application.delete_env(:ash_a2ui, :catalog)
      refute Experience.admin?()
      refute Experience.effective_admin?()

      unset_surface = AshA2ui.Info.build_surface(Task, actor: nil)

      Application.put_env(:ash_a2ui, :catalog, :basic)
      assert Experience.catalog() == :basic
      refute Experience.effective_admin?()

      basic_surface = AshA2ui.Info.build_surface(Task, actor: nil)

      # byte-identical to the A2UI-101 basic-v2 emission
      assert unset_surface == basic_surface
      Enum.each(basic_surface, &assert_valid_server_message/1)

      [create, components, data] = basic_surface
      comps = components_by_id(components)

      assert comps["root"]["component"] == "Column"
      assert Map.has_key?(comps, "form_slot")

      assert create["createSurface"]["catalogId"] ==
               "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"

      %{"updateDataModel" => %{"value" => model}} = data
      assert Map.has_key?(model["query"], "_pagination_visible")
      refute Map.has_key?(model["query"], "paginationVisible")
    end
  end

  describe "admin under experience v1" do
    @tag ac: "A2UI-101B/AC-9"
    test "admin catalog requires experience v2" do
      Application.put_env(:ash_a2ui, :experience_version, 1)
      Application.put_env(:ash_a2ui, :catalog, :admin_v1)

      refute Experience.v2?()
      assert Experience.admin?()
      refute Experience.effective_admin?()

      admin_selected_surface = AshA2ui.Info.build_surface(Paginated, actor: nil)

      Application.put_env(:ash_a2ui, :catalog, :basic)
      basic_surface = AshA2ui.Info.build_surface(Paginated, actor: nil)

      # byte-identical to basic v1 — the configuration is ignored, not
      # partially applied
      assert admin_selected_surface == basic_surface
      Enum.each(basic_surface, &assert_valid_server_message/1)

      [create, components, _data] = basic_surface

      assert create["createSurface"]["catalogId"] ==
               "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"

      comps = components_by_id(components)

      # basic v1 markers intact
      assert comps["root"]["component"] == "Column"
      assert %{"text" => "Select"} = comps["row_select_text"]
      assert %{"text" => "Save"} = comps["form_submit_text"]
      assert Map.has_key?(comps, "query_pagination")
      refute Map.has_key?(comps, "data_grid")
    end
  end
end
