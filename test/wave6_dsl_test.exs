defmodule AshA2ui.Wave6DslTest do
  @moduledoc """
  DSL and normalization tests for Wave 6: the `group` and `row_layout`
  entities, their defaults, and `AshA2ui.ResolvedView` normalization.
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Test.Promotion

  describe "group entity" do
    test "parses into AshA2ui.Group structs on the form component" do
      form =
        Promotion
        |> AshA2ui.Info.components()
        |> Enum.find(&(&1.name == :form))

      assert [
               %AshA2ui.Group{name: :details, label: "Details", columns: 2},
               %AshA2ui.Group{name: :scheduling, label: nil, columns: 2}
             ] = form.groups

      assert Enum.map(form.groups, & &1.fields) == [[:name, :slug], [:trial_days, :expires_at]]
    end

    test "normalization defaults the label to the humanized group name" do
      view = AshA2ui.ResolvedView.resolve(Promotion)
      form = Enum.find(view.components, &(&1.name == :form))

      assert Enum.map(form.groups, & &1.label) == ["Details", "Scheduling"]
    end

    test "columns defaults to 1" do
      defmodule DefaultColumnsUI do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.Promotion

          component :form do
            fields [:name]
            create_action :create

            group :details do
              fields [:name]
            end
          end
        end
      end

      form =
        DefaultColumnsUI
        |> AshA2ui.Info.components()
        |> Enum.find(&(&1.name == :form))

      assert [%AshA2ui.Group{columns: 1}] = form.groups
    end
  end

  describe "row_layout entity" do
    test "parses into a singleton AshA2ui.RowLayout struct on the table component" do
      table =
        Promotion
        |> AshA2ui.Info.components()
        |> Enum.find(&(&1.name == :table))

      assert %AshA2ui.RowLayout{
               title: :name,
               badge: :is_active,
               badge_text: [true: "Active", false: "Inactive"],
               meta: [:slug, :trial_days, :expires_at],
               columns: 3
             } = table.row_layout
    end

    test "meta defaults to the table's fields minus title and badge, columns to 2" do
      defmodule DefaultMetaUI do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.Promotion

          component :table do
            fields [:name, :slug, :trial_days, :is_active]

            row_layout do
              title :name
              badge :is_active
            end
          end
        end
      end

      view = AshA2ui.ResolvedView.resolve(DefaultMetaUI)
      table = Enum.find(view.components, &(&1.name == :table))

      assert %AshA2ui.RowLayout{meta: [:slug, :trial_days], columns: 2} = table.row_layout
    end

    test "components without layout declarations resolve unchanged" do
      view = AshA2ui.ResolvedView.resolve(AshA2ui.Test.KitchenSink)

      assert Enum.all?(view.components, &(&1.groups == [] and is_nil(&1.row_layout)))
    end
  end
end
