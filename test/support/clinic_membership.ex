defmodule AshA2ui.Test.ClinicMembership do
  @moduledoc """
  Join fixture between `AshA2ui.Test.Owner` and `AshA2ui.Test.Clinic` — the
  relationship path dependent contexts filter through.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
  end

  relationships do
    belongs_to :owner, AshA2ui.Test.Owner, public?: true, allow_nil?: false
    belongs_to :clinic, AshA2ui.Test.Clinic, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
