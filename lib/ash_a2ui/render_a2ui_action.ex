defmodule AshA2ui.RenderA2uiAction do
  @moduledoc """
  The run module of the auto-added `render_a2ui` generic action (see
  `AshA2ui.Transformers.AddRenderAction`): delegates to
  `AshA2ui.Info.build_surface/2`, passing the calling context (actor, tenant,
  authorization, tracer) through as options.
  """

  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, context) do
    {:ok, AshA2ui.Info.build_surface(input.resource, Ash.Context.to_opts(context))}
  end
end
