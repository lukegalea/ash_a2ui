defmodule AshA2ui.Transformers.AddRenderAction do
  @moduledoc """
  Adds a generic `render_a2ui` action returning `:map` to the resource, run by
  `AshA2ui.RenderA2uiAction`, so surface building flows through the normal
  action layer (policies, tracing, code interfaces).

  Skipped when:

    * the DSL module is not an Ash resource (standalone UI modules), or
    * the `a2ui` section sets `add_render_action?` to `false`, or
    * an action named `render_a2ui` already exists on the resource.

  Runs after all other transformers (`after?/1` returns `true`) so Ash's
  default actions are already in place when checking for a name collision.
  """

  use Spark.Dsl.Transformer

  alias Ash.Resource.Builder
  alias Spark.Dsl.Transformer

  @impl true
  def after?(_), do: true

  @impl true
  def transform(dsl_state) do
    if add_action?(dsl_state) do
      Builder.add_new_action(dsl_state, :action, :render_a2ui,
        returns: :map,
        run: {AshA2ui.RenderA2uiAction, []},
        description: "Builds the A2UI surface messages for this resource."
      )
    else
      {:ok, dsl_state}
    end
  end

  defp add_action?(dsl_state) do
    Ash.Resource.Dsl in Transformer.get_persisted(dsl_state, :extensions, []) and
      Transformer.get_option(dsl_state, [:a2ui], :add_render_action?, true)
  end
end
