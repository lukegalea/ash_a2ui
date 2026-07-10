defmodule AshA2ui.Test.Paginated do
  @moduledoc """
  Fixture resource for the `query` DSL: a named, server-enforced allowlist for
  search, sorting, equality filters, and pagination, referenced by the table
  component. Uses a small `page_size` so pagination is exercised with few
  records.
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

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:open, :closed]],
      default: :open

    attribute :category, :atom,
      public?: true,
      constraints: [one_of: [:bug, :feature]],
      default: :bug

    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  a2ui do
    surface_id "paginated"

    query :default do
      search_fields [:name]
      sortable [:name, :inserted_at]
      filters [:status, :category]
      default_sort name: :asc
      page_size 5
      max_page_size 10
    end

    component :table do
      fields [:name, :status, :category]
      read_action :read
      row_actions [:destroy]
      query :default
    end

    component :form do
      fields [:name, :status, :category]
      create_action :create
      update_action :update
    end
  end
end
