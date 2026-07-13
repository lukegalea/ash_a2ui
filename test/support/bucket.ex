defmodule AshA2ui.Test.Bucket do
  @moduledoc """
  Fixture section source for dynamic table sets: each Bucket becomes one
  runtime table section of `AshA2ui.Test.BucketWordsUI`'s `:per_bucket`
  template table.
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
    attribute :position, :integer, public?: true, default: 0
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
