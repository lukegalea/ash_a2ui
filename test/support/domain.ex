defmodule AshA2ui.Test.Domain do
  @moduledoc """
  Test domain for the shared Ets-backed fixture resources.

  FROZEN CONTRACT — parallel tracks share these fixtures; extend only via an
  integration commit.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.KitchenSink
    resource AshA2ui.Test.Minimal
  end
end
