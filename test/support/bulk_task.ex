defmodule AshA2ui.Test.BulkTask do
  @moduledoc """
  Fixture resource for bulk actions (A2UI-104), with policies so the
  authorized re-read of a selection can be exercised:

    * reads only return records whose `secret` is `false`,
    * writes require an actor,
    * `:approve` fails validation for a record with a negative `score`
      (the partial-failure case), `:reject` always succeeds, `:flag` is a
      row-only action.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:open, :approved, :rejected]],
      default: :open

    attribute :score, :integer, public?: true, default: 0
    attribute :secret, :boolean, public?: true, default: false
  end

  relationships do
    belongs_to :project, AshA2ui.Test.BulkProject, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :approve do
      accept []
      require_atomic? false
      validate compare(:score, greater_than_or_equal_to: 0)
      change set_attribute(:status, :approved)
    end

    update :reject do
      accept []
      change set_attribute(:status, :rejected)
    end

    update :flag do
      accept []
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(secret == false)
    end

    policy action_type([:create, :update, :destroy, :action]) do
      authorize_if actor_present()
    end
  end
end
