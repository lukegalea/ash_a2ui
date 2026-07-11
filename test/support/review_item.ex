defmodule AshA2ui.Test.ReviewItem do
  @moduledoc """
  Fixture resource for multi-table surfaces: two named `:table` components
  (`:new_items` with a query, `:done_items` without), a row action
  (`:approve`, an update-type action moving items between the sections) with
  `refreshes [:new_items]` metadata, and a form.
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
    attribute :count, :integer, public?: true, default: 0

    attribute :state, :atom,
      public?: true,
      constraints: [one_of: [:new, :done]],
      default: :new
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    read :new_items do
      filter expr(state == :new)
    end

    read :done_items do
      filter expr(state == :done)
    end

    update :approve do
      accept []
      change set_attribute(:state, :done)
    end
  end

  a2ui do
    surface_id "review"

    query :new_q do
      search_fields [:name]
      sortable [:name]
      default_sort name: :asc
      page_size 5
      max_page_size 10
    end

    component :table, :new_items do
      fields [:name, :count]
      read_action :new_items
      row_actions [:approve, :destroy]
      query :new_q
    end

    component :table, :done_items do
      fields [:name, :state]
      read_action :done_items
    end

    component :form do
      fields [:name, :count]
      create_action :create
      update_action :update
    end

    action :approve do
      refreshes [:new_items]
    end
  end
end
