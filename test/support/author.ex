defmodule AshA2ui.Test.Author do
  @moduledoc """
  Fixture destination resource for relationship rendering: the `belongs_to`
  target of `AshA2ui.Test.Post`. Carries a `name` (the option-label fallback
  chain hit) and an `email` (read through a `source` table column).
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
    attribute :email, :string, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
