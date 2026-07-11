defmodule AshA2ui.Test.Tag do
  @moduledoc """
  Fixture destination resource for pick_existing nested forms: the `has_many`
  target of `AshA2ui.Test.Ticket`'s `:tags` relationship (a many-to-many-free
  pick-and-attach case — relating sets `ticket_id`, unrelating clears it).
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
  end

  relationships do
    belongs_to :ticket, AshA2ui.Test.Ticket, public?: true, allow_nil?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
