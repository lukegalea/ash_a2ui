defmodule AshA2ui.Test.KitchenSink do
  @moduledoc """
  Fixture resource covering every mapped Ash type (string, boolean, integer,
  decimal, date, utc_datetime, enum-constrained atom) plus timestamps, with a
  full `a2ui` block exercising the DSL.

  FROZEN CONTRACT — parallel tracks share this fixture; extend only via an
  integration commit.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :active, :boolean, public?: true, default: false
    attribute :count, :integer, public?: true
    attribute :price, :decimal, public?: true
    attribute :birthday, :date, public?: true
    attribute :scheduled_at, :utc_datetime, public?: true

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:draft, :published, :archived]],
      default: :draft

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  a2ui do
    surface_id "kitchen_sink"

    component :table do
      fields [:name, :active, :count, :price, :birthday, :scheduled_at, :status, :inserted_at]
      read_action :read
      row_actions [:update, :destroy]
    end

    component :form do
      fields [:name, :active, :count, :price, :birthday, :scheduled_at, :status]
      create_action :create
      update_action :update
    end

    field :name do
      label "Name"
      widget :text_field
      order 1
    end

    field :inserted_at do
      label "Created"
      format :date
      order 99
    end

    field :updated_at do
      hidden true
    end
  end
end
