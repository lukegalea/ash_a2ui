defmodule AshA2ui.Transformers.AddRenderAction do
  @moduledoc """
  Adds a generic `render_a2ui` `:map` action to the resource (opt-out) so
  surface building flows through the normal action layer (policies, tracing,
  code interfaces).

  TODO Track 1: currently a no-op pass-through; implement action injection
  here (skip standalone UI modules, which are not resources).
  """

  use Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    # TODO Track 1: add the `render_a2ui` generic action (opt-out).
    {:ok, dsl_state}
  end
end
