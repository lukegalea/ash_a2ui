defmodule AshA2ui.Test.Clinic do
  @moduledoc """
  Fixture resource for dependent contexts: a clinic belongs to owners through
  memberships, so a `:clinic` context can depend on the selected `:owner`
  through the `[:memberships, :owner_id]` path.
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
    has_many :memberships, AshA2ui.Test.ClinicMembership, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
