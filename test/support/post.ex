defmodule AshA2ui.Test.Post do
  @moduledoc """
  Fixture resource for relationship rendering: a `belongs_to :author`
  relationship whose `author_id` form field is inferred as a ChoicePicker
  (options loaded from `AshA2ui.Test.Author`), plus an `author_email` table
  column read through the relationship via `source [:author, :email]`.
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

    attribute :title, :string, public?: true, allow_nil?: false
  end

  relationships do
    belongs_to :author, AshA2ui.Test.Author, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:title, :author_id]
    end

    update :update do
      primary? true
      accept [:title, :author_id]
    end
  end

  a2ui do
    surface_id "posts"

    component :table do
      fields [:title, :author_email]
      read_action :read
      row_actions [:destroy]
    end

    component :form do
      fields [:title, :author_id]
      create_action :create
      update_action :update
    end

    field :author_email do
      label "Author email"
      source [:author, :email]
    end
  end
end
