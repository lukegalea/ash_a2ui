defmodule AshA2ui.Test.BucketWord do
  @moduledoc """
  Fixture resource for dynamic table sets and inline cell editing: words are
  either `:new` (a static table section) or assigned to a
  `AshA2ui.Test.Bucket` (one runtime table section per bucket).
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :word, :string, public?: true, allow_nil?: false
    attribute :replacement, :string, public?: true
    attribute :bucket_id, :uuid, public?: true

    attribute :state, :atom,
      public?: true,
      constraints: [one_of: [:new, :bucketed]],
      default: :new
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    read :new_words do
      filter expr(state == :new)
    end

    read :bucketed do
      filter expr(state == :bucketed)
    end

    update :approve do
      accept []
      change set_attribute(:state, :bucketed)
    end

    update :update_replacement do
      accept [:replacement]

      validate match(:replacement, ~r/^[a-z ]*$/),
        message: "must be lowercase"
    end
  end
end
