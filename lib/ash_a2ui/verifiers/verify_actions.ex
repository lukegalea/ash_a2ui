defmodule AshA2ui.Verifiers.VerifyActions do
  @moduledoc """
  Verifies at compile time that every referenced action (`read_action`,
  `create_action`, `update_action`, `row_actions`) exists on the resource with
  a compatible type (read/create/update/generic).

  TODO Track 1: currently a no-op; implement the checks and raise
  `Spark.Error.DslError` with a helpful path/message on failure.
  """

  use Spark.Dsl.Verifier

  @impl true
  def verify(_dsl_state) do
    # TODO Track 1: verify referenced actions exist with compatible types.
    :ok
  end
end
