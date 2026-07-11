defmodule AshA2ui.Test.Ticket do
  @moduledoc """
  Fixture resource for nested relationship forms: its create/update actions
  manage two relationships through arguments —

    * `:notes` (`type: :direct_control` on the has_many `:notes`) — inferred
      as the **create_inline** interaction mode,
    * `:tags` (`type: :append_and_remove` on the has_many `:tags`) — inferred
      as the **pick_existing** interaction mode (many-to-many-free
      pick-and-attach; unrelating clears `Tag.ticket_id`).

  The on-resource surface declares both `nested_form` entities without
  search; `AshA2ui.Test.TicketSearchUI` layers `option_search` on top of the
  same resource for the searchable variants.
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

    attribute :subject, :string, public?: true, allow_nil?: false
  end

  relationships do
    belongs_to :author, AshA2ui.Test.Author, public?: true
    has_many :notes, AshA2ui.Test.TicketNote, public?: true
    has_many :tags, AshA2ui.Test.Tag, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:subject, :author_id]

      argument :notes, {:array, :map}, allow_nil?: true
      argument :tags, {:array, :uuid}, allow_nil?: true

      change manage_relationship(:notes, type: :direct_control)
      change manage_relationship(:tags, type: :append_and_remove)
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:subject, :author_id]

      argument :notes, {:array, :map}, allow_nil?: true
      argument :tags, {:array, :uuid}, allow_nil?: true

      change manage_relationship(:notes, type: :direct_control)
      change manage_relationship(:tags, type: :append_and_remove)
    end
  end

  a2ui do
    surface_id "tickets"

    component :table do
      fields [:subject]
      read_action :read
    end

    component :form do
      fields [:subject, :author_id]
      create_action :create
      update_action :update

      nested_form :notes do
        fields [:body, :rating]
      end

      nested_form :tags do
      end
    end
  end
end
