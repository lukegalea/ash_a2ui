defmodule AshA2ui.Test.Comment do
  @moduledoc """
  Fixture child resource for aggregate rendering: the `has_many` target of
  `AshA2ui.Test.Article`, counted by its `comment_count` aggregate.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :body, :string, public?: true
  end

  relationships do
    belongs_to :article, AshA2ui.Test.Article, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
