defmodule AshA2ui.DslSmokeTest do
  @moduledoc """
  Smoke test for the frozen foundation contract: the `a2ui` section parses on
  resources and standalone UI modules, Info functions work, and
  `ResolvedView.resolve/2` returns the frozen struct.

  Deeper DSL/transformer/verifier behavior is Track 1; normalization is
  Track 2.
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Test.{KitchenSink, Minimal, MinimalUI}

  describe "on-resource DSL" do
    test "surface_id option parses" do
      assert AshA2ui.Info.a2ui_surface_id(KitchenSink) == {:ok, "kitchen_sink"}
      assert AshA2ui.Info.a2ui_surface_id!(KitchenSink) == "kitchen_sink"
    end

    test "component entities parse with args, options and defaults" do
      components = AshA2ui.Info.components(KitchenSink)
      assert length(components) == 2

      table = Enum.find(components, &(&1.name == :table))
      assert %AshA2ui.Component{} = table
      assert table.read_action == :read
      assert table.row_actions == [:update, :destroy]
      assert :inserted_at in table.fields

      form = Enum.find(components, &(&1.name == :form))
      assert form.create_action == :create
      assert form.update_action == :update
      # entity schema default
      assert form.row_actions == []
    end

    test "field entities parse with defaults" do
      fields = AshA2ui.Test.KitchenSink |> AshA2ui.Info.fields() |> Map.new(&{&1.name, &1})

      assert %AshA2ui.Field{label: "Name", widget: :text_field, order: 1, hidden: false} =
               fields[:name]

      assert %AshA2ui.Field{format: :date, order: 99} = fields[:inserted_at]
      assert %AshA2ui.Field{hidden: true, order: 0} = fields[:updated_at]
    end

    test "resource!/1 returns the resource itself" do
      assert AshA2ui.Info.resource!(KitchenSink) == KitchenSink
    end
  end

  describe "standalone UI module DSL" do
    test "for_resource resolves the target resource" do
      assert AshA2ui.Info.a2ui_for_resource(MinimalUI) == {:ok, Minimal}
      assert AshA2ui.Info.resource!(MinimalUI) == Minimal
    end

    test "entities parse in standalone modules" do
      assert AshA2ui.Info.a2ui_surface_id(MinimalUI) == {:ok, "minimal_standalone"}

      assert [%AshA2ui.Component{name: :table, fields: [:name]}] =
               AshA2ui.Info.components(MinimalUI)

      assert [%AshA2ui.Field{name: :name, label: "Name (standalone)"}] =
               AshA2ui.Info.fields(MinimalUI)
    end
  end

  describe "ResolvedView.resolve/2 (frozen struct contract)" do
    test "resolves an on-resource view" do
      view = AshA2ui.ResolvedView.resolve(KitchenSink)

      assert %AshA2ui.ResolvedView{
               resource: KitchenSink,
               surface_id: "kitchen_sink",
               read_action: :read,
               create_action: :create,
               update_action: :update,
               row_actions: [:update, :destroy]
             } = view

      assert length(view.components) == 2
      assert %AshA2ui.Field{} = view.fields[:name]
    end

    test "resolves a standalone view and defaults the surface id from the resource" do
      view = AshA2ui.ResolvedView.resolve(MinimalUI)
      assert view.resource == Minimal
      assert view.surface_id == "minimal_standalone"

      # Minimal itself declares no surface_id -> derived from short name
      assert AshA2ui.ResolvedView.resolve(Minimal).surface_id == "minimal"
    end
  end
end
