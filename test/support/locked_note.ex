defmodule AshA2ui.Test.LockedNote do
  @moduledoc """
  Fixture resource for saving two cards of one record (admin catalog 3.11):
  a note whose `:edit` carries an optimistic lock on `version`, so an update
  given a row read before another write to it is refused as stale
  (`AshA2ui.Test.LockedNoteEditUI`).
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false
    attribute :body, :string, public?: true
    attribute :version, :integer, public?: true, allow_nil?: false, default: 1
  end

  actions do
    defaults [:read, :destroy, create: :*]

    update :edit do
      accept [:title, :body]
      change optimistic_lock(:version)
    end
  end
end
