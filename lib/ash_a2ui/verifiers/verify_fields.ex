defmodule AshA2ui.Verifiers.VerifyFields do
  @moduledoc """
  Verifies at compile time that every referenced field is a real public
  attribute/calculation/aggregate of the resource, and that form fields are a
  subset of the target action's accepts + arguments.

  TODO Track 1: currently a no-op; implement the checks and raise
  `Spark.Error.DslError` with a helpful path/message on failure.
  """

  use Spark.Dsl.Verifier

  @impl true
  def verify(_dsl_state) do
    # TODO Track 1: verify component/field references against the resource.
    :ok
  end
end
