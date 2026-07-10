defmodule AshA2ui.ResolvedViewTest do
  @moduledoc """
  Normalization matrix for `AshA2ui.ResolvedView.resolve/2`: per-component
  effective field lists (ordering, hidden dropped), label/widget defaults,
  declared overrides, and `format` carry-through.
  """

  use ExUnit.Case, async: true

  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.{KitchenSink, Minimal, MinimalUI}

  defmodule HiddenFieldResource do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      validate_domain_inclusion?: false,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshA2ui]

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id

      attribute :name, :string, public?: true
      attribute :secret, :string, public?: true
    end

    actions do
      defaults [:read, create: :*]
    end

    a2ui do
      component :table do
        fields [:name, :secret]
        read_action :read
      end

      field :secret do
        hidden true
      end
    end
  end

  defp component(view, name), do: Enum.find(view.components, &(&1.name == name))

  describe "per-component effective field lists" do
    test "orders by field order, stable by declaration otherwise" do
      view = ResolvedView.resolve(KitchenSink)

      # name has order 1, inserted_at order 99; everything else defaults to 0
      # and keeps its declaration order within the component's fields list.
      assert component(view, :table).fields ==
               [:active, :count, :price, :birthday, :scheduled_at, :status, :name, :inserted_at]

      assert component(view, :form).fields ==
               [:active, :count, :price, :birthday, :scheduled_at, :status, :name]
    end

    test "drops hidden fields from component field lists but keeps their metadata" do
      view = ResolvedView.resolve(HiddenFieldResource)

      assert component(view, :table).fields == [:name]
      assert view.fields[:secret].hidden
    end
  end

  describe "field metadata defaults" do
    test "label defaults to the humanized field name" do
      view = ResolvedView.resolve(KitchenSink)

      assert view.fields[:scheduled_at].label == "Scheduled at"
      assert view.fields[:active].label == "Active"
    end

    test "widget defaults via TypeMapper on the attribute's Ash type" do
      view = ResolvedView.resolve(KitchenSink)

      assert view.fields[:active].widget == :check_box
      assert view.fields[:count].widget == :text_field
      assert view.fields[:price].widget == :text_field
      assert view.fields[:birthday].widget == :date_time_input
      assert view.fields[:scheduled_at].widget == :date_time_input
      assert view.fields[:status].widget == :choice_picker
    end

    test "explicit overrides win over defaults and format is carried" do
      view = ResolvedView.resolve(KitchenSink)

      assert view.fields[:name].label == "Name"
      assert view.fields[:name].widget == :text_field
      assert view.fields[:name].order == 1

      assert view.fields[:inserted_at].label == "Created"
      assert view.fields[:inserted_at].format == :date
      # no widget override -> type default (utc_datetime timestamp)
      assert view.fields[:inserted_at].widget == :date_time_input
    end

    test "fields without any field entity get fully-defaulted metadata" do
      view = ResolvedView.resolve(Minimal)

      assert %AshA2ui.Field{
               name: :name,
               label: "Name",
               widget: :text_field,
               order: 0,
               hidden: false,
               format: nil
             } = view.fields[:name]
    end
  end

  describe "standalone UI modules" do
    test "normalizes against the for_resource target" do
      view = ResolvedView.resolve(MinimalUI)

      assert view.resource == Minimal
      assert view.surface_id == "minimal_standalone"
      assert component(view, :table).fields == [:name]
      assert view.fields[:name].label == "Name (standalone)"
      assert view.fields[:name].widget == :text_field
    end
  end

  describe "action resolution" do
    test "keeps explicitly declared actions" do
      view = ResolvedView.resolve(KitchenSink)

      assert view.read_action == :read
      assert view.create_action == :create
      assert view.update_action == :update
      assert view.row_actions == [:update, :destroy]
    end

    test "defaults the read action to the primary read when a table omits it" do
      # Minimal's table declares no read_action; :read is the primary read.
      assert ResolvedView.resolve(Minimal).read_action == :read
    end
  end

  describe "options" do
    test "accepts the reserved option keys" do
      view = ResolvedView.resolve(Minimal, actor: nil, tenant: nil, domain: nil, authorize?: true)
      assert %ResolvedView{} = view
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, fn ->
        ResolvedView.resolve(Minimal, bogus: true)
      end
    end
  end
end
