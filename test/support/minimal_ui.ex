defmodule AshA2ui.Test.MinimalUI do
  @moduledoc """
  Standalone UI module fixture: an `a2ui` block living outside the resource,
  pointed at `AshA2ui.Test.Minimal` via `for_resource`.

  FROZEN CONTRACT — parallel tracks share this fixture; extend only via an
  integration commit.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Minimal
    surface_id "minimal_standalone"

    component :table do
      fields [:name]
      read_action :read
    end

    field :name do
      label "Name (standalone)"
    end
  end
end
