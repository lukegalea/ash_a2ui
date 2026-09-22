# AshA2ui.ActorPickerLive is the optional picker half of AshA2ui.Actor,
# guarded like the LiveView transport for the NO_PHOENIX CI job.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.ActorPickerLive do
    @moduledoc """
    A shipped, host-themeable "acting as" picker for `AshA2ui.Actor`.

    Renders one link per configured actor to the plug's endpoint; picking is
    a full round trip (sessions are written over HTTP), landing back where
    the user came from. Style comes entirely from the `--a2ui-*` custom
    properties the host already bridges, so the picker matches the surfaces
    in both light and dark themes with zero host CSS.
    """

    use Phoenix.LiveView

    @impl true
    def mount(_params, session, socket) do
      {:ok,
       assign(socket,
         actors: AshA2ui.Actor.list(),
         current_id: session[AshA2ui.Actor.session_key()]
       )}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <nav
        class="a2ui-actor-picker"
        aria-label="Acting as"
        style="display:flex;align-items:center;gap:0.5rem;flex-wrap:wrap;
               font: var(--a2ui-font-size-sm, 0.875rem) var(--a2ui-font-family, inherit);"
      >
        <span
          style="color: var(--a2ui-color-on-background, inherit);opacity:0.7;"
        >
          Acting as
        </span>
        <%= for actor <- @actors do %>
          <a
            href={"/a2ui/actor?id=#{actor.id}"}
            aria-current={actor.id == @current_id}
            style={
              "text-decoration:none;border-radius:var(--a2ui-border-radius, 0.25rem);
               padding:0.125rem 0.625rem;border:1px solid var(--a2ui-color-border, currentColor);" <>
                if actor.id == @current_id do
                  "background:var(--a2ui-color-primary, currentColor);
                   color:var(--a2ui-color-on-primary, #fff);font-weight:600;"
                else
                  "color:var(--a2ui-color-primary, inherit);"
                end
            }
          >
            <%= actor.label %>
          </a>
        <% end %>
      </nav>
      """
    end
  end
end
