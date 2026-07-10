defmodule AshA2ui.DslTest do
  @moduledoc """
  Thorough section/entity parsing tests for the `a2ui` DSL beyond the
  foundation smoke test: option defaults, both authoring modes, `Info`
  getters, and the `add_render_action?` section option.
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Test.{KitchenSink, Minimal, MinimalUI}
  alias Spark.Dsl.Extension

  defmodule BareResource do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshA2ui]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read, create: :*]
    end
  end

  defmodule OptedOutResource do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshA2ui]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read, create: :*]
    end

    a2ui do
      add_render_action?(false)

      component :table do
        fields [:name]
      end
    end
  end

  defmodule StandaloneWithoutForResource do
    @moduledoc false
    use AshA2ui.Standalone

    a2ui do
      surface_id "orphan"

      component :table do
        fields [:name]
      end
    end
  end

  describe "a2ui section options" do
    test "surface_id is optional and unset by default" do
      assert AshA2ui.Info.a2ui_surface_id(BareResource) == :error
      assert AshA2ui.Info.a2ui_surface_id(Minimal) == :error
      assert AshA2ui.Info.a2ui_surface_id(KitchenSink) == {:ok, "kitchen_sink"}
    end

    test "for_resource is only set in standalone modules" do
      assert AshA2ui.Info.a2ui_for_resource(KitchenSink) == :error
      assert AshA2ui.Info.a2ui_for_resource(MinimalUI) == {:ok, Minimal}
    end

    test "add_render_action? defaults to true" do
      assert AshA2ui.Info.a2ui_add_render_action?(KitchenSink) == true
      assert AshA2ui.Info.a2ui_add_render_action?(Minimal) == true
    end

    test "add_render_action? can be set to false" do
      assert AshA2ui.Info.a2ui_add_render_action?(OptedOutResource) == false
    end

    test "add_render_action? defaults to true when the a2ui section is absent" do
      assert AshA2ui.Info.a2ui_add_render_action?(BareResource) == true
    end
  end

  describe "component entities" do
    test "component options parse with entity-schema defaults" do
      table = KitchenSink |> AshA2ui.Info.components() |> Enum.find(&(&1.name == :table))

      assert %AshA2ui.Component{
               name: :table,
               read_action: :read,
               create_action: nil,
               update_action: nil,
               row_actions: [:update, :destroy]
             } = table

      form = KitchenSink |> AshA2ui.Info.components() |> Enum.find(&(&1.name == :form))

      assert %AshA2ui.Component{
               name: :form,
               read_action: nil,
               create_action: :create,
               update_action: :update,
               row_actions: []
             } = form
    end

    test "a resource without an a2ui section has no components" do
      assert AshA2ui.Info.components(BareResource) == []
    end
  end

  describe "field entities" do
    test "field options parse with entity-schema defaults" do
      fields = KitchenSink |> AshA2ui.Info.fields() |> Map.new(&{&1.name, &1})

      assert %AshA2ui.Field{
               name: :name,
               label: "Name",
               widget: :text_field,
               order: 1,
               hidden: false,
               format: nil
             } = fields[:name]

      assert %AshA2ui.Field{name: :inserted_at, format: :date, order: 99} = fields[:inserted_at]
      assert %AshA2ui.Field{name: :updated_at, hidden: true, order: 0} = fields[:updated_at]
    end

    test "a resource without an a2ui section has no fields" do
      assert AshA2ui.Info.fields(BareResource) == []
    end

    test "components/1 and fields/1 partition the section's entities" do
      components = AshA2ui.Info.components(KitchenSink)
      fields = AshA2ui.Info.fields(KitchenSink)

      assert Enum.all?(components, &is_struct(&1, AshA2ui.Component))
      assert Enum.all?(fields, &is_struct(&1, AshA2ui.Field))

      all = Extension.get_entities(KitchenSink, [:a2ui])
      assert length(all) == length(components) + length(fields)
    end
  end

  describe "authoring modes / resource!/1" do
    test "on-resource mode resolves to the resource itself" do
      assert AshA2ui.Info.resource!(KitchenSink) == KitchenSink
      assert AshA2ui.Info.resource!(BareResource) == BareResource
    end

    test "standalone mode resolves to for_resource" do
      assert AshA2ui.Info.resource!(MinimalUI) == Minimal
    end

    test "standalone module without for_resource raises" do
      assert_raise ArgumentError, ~r/for_resource/, fn ->
        AshA2ui.Info.resource!(StandaloneWithoutForResource)
      end
    end

    test "standalone modules parse the same entities as resources" do
      assert AshA2ui.Info.a2ui_surface_id(StandaloneWithoutForResource) == {:ok, "orphan"}

      assert [%AshA2ui.Component{name: :table, fields: [:name]}] =
               AshA2ui.Info.components(StandaloneWithoutForResource)
    end
  end
end
