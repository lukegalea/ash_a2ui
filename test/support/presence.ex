# Minimal presence fixtures for the AshA2ui.Presence tests: a real
# Phoenix.Presence module over the shared test PubSub, plus a surface
# LiveView wired exactly as the moduledoc shows hosts (mount_surface +
# handle_broadcast + PresenceBar + the nav contract). Guarded so the
# NO_PHOENIX CI job (which strips the Phoenix stack) still compiles
# test/support cleanly.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.Test.Presence do
    @moduledoc false

    use AshA2ui.Presence, pubsub_server: AshA2ui.Test.PubSub
  end

  defmodule AshA2ui.Test.PresenceLive do
    @moduledoc false

    use Phoenix.LiveView

    @presence AshA2ui.Test.Presence

    @impl true
    def mount(params, _session, socket) do
      socket =
        AshA2ui.Presence.mount_surface(@presence, socket, Map.get(params, "surface", "clinic"),
          key: Map.get(params, "key", "anon"),
          label: Map.get(params, "label", "Guest")
        )

      {:ok, socket}
    end

    @impl true
    def handle_params(_params, uri, socket) do
      {:noreply, Phoenix.Component.assign(socket, current_path: URI.parse(uri).path)}
    end

    @impl true
    def handle_info(msg, socket) do
      case AshA2ui.Presence.handle_broadcast(msg, @presence, socket) do
        {:noreply, socket} -> {:noreply, socket}
        :ignored -> {:noreply, socket}
      end
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div>
        <AshA2ui.PresenceBar.bar presences={@a2ui_presences} max_visible={3} />
        <nav aria-label="Clinic" style="display:flex;gap:1rem;">
          <a href="/presence" {AshA2ui.PresenceBar.nav_current_attrs(@current_path, "/presence")}>
            Schedule
          </a>
          <a href="/presence/patients" {AshA2ui.PresenceBar.nav_current_attrs(@current_path, "/presence/patients")}>
            Patients
          </a>
        </nav>
      </div>
      """
    end
  end
end
