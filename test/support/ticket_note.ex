defmodule AshA2ui.Test.TicketNote do
  @moduledoc """
  Fixture child resource for create_inline nested forms: the `has_many`
  target of `AshA2ui.Test.Ticket`'s `:notes` relationship, managed with
  `type: :direct_control` (create / update / destroy through the parent
  action's `:notes` argument).
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :body, :string, public?: true, allow_nil?: false
    attribute :rating, :integer, public?: true
  end

  relationships do
    belongs_to :ticket, AshA2ui.Test.Ticket, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
