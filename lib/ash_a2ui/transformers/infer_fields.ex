defmodule AshA2ui.Transformers.InferFields do
  @moduledoc """
  Fills in `fields` for components that omit them: public attributes (via
  `Ash.Resource.Info.public_attributes/1`) for tables, action accepts +
  arguments for forms.

  TODO Track 1: currently a no-op pass-through; implement inference here.
  """

  use Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    # TODO Track 1: infer component fields from the resource when omitted.
    {:ok, dsl_state}
  end
end
