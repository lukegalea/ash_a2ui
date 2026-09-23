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

    Zero jank: the actor read runs in an async task (`start_async/3`) so
    mount never blocks, the links are streamed (`stream/3`), and every load
    before the read lands shows skeleton pills — instant chrome, themed with
    the same `--a2ui-*` custom properties. A failed read crashes the
    LiveView loudly: the picker is the gate to every surface, and a silent
    "no actors" would strand users.
    """

    use Phoenix.LiveView

    @impl true
    def mount(_params, session, socket) do
      socket =
        socket
        |> assign(current_id: session[AshA2ui.Actor.session_key()], actors_loaded?: false)
        |> stream(:actors, [])

      socket =
        if connected?(socket) do
          start_async(socket, :actors, &AshA2ui.Actor.list/0)
        else
          socket
        end

      {:ok, socket}
    end

    @impl true
    def handle_async(:actors, {:ok, actors}, socket) do
      {:noreply, socket |> assign(:actors_loaded?, true) |> stream(:actors, actors, reset: true)}
    end

    def handle_async(:actors, {:exit, reason}, _socket) do
      exit(reason)
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
        <%= if @actors_loaded? == false do %>
          <%!-- three placeholder pills -- the picker is a nav, not a data grid --%>
          <%= for index <- 1..3 do %>
            <span
              id={"actor-skeleton-#{index}"}
              aria-hidden="true"
              style="display:inline-block;width:4.5rem;height:1.4em;
                     border-radius:var(--a2ui-border-radius, 0.25rem);
                     background:var(--a2ui-color-secondary, rgba(148,163,184,0.3));"
            >
            </span>
          <% end %>
        <% end %>
        <div id="actors" phx-update="stream" style="display:contents;">
          <%= for {dom_id, actor} <- @streams.actors do %>
            <a
              id={dom_id}
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
        </div>
      </nav>
      """
    end
  end
end
