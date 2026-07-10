defmodule AshA2ui.Test.Minimal do
  @moduledoc """
  Minimal fixture resource: a single `name` attribute and the smallest
  possible `a2ui` block.

  FROZEN CONTRACT — parallel tracks share this fixture; extend only via an
  integration commit.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  a2ui do
    component :table do
      fields [:name]
    end
  end
end
