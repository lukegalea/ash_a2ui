# AshA2ui.LiveRenderer is the optional LiveView transport. The whole module is
# guarded so the protocol core compiles when phoenix_live_view is absent
# (proven by the NO_PHOENIX CI job).
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.LiveRenderer do
    @moduledoc """
    Batteries-included LiveView transport for A2UI surfaces:

        defmodule MyAppWeb.PromotionsProviderA2uiLive do
          use AshA2ui.LiveRenderer,
            ui: MyApp.UI.PromotionsProviderUI,
            actor_fn: &(&1.assigns.current_admin)
        end

    - `mount/3` builds the surface via `AshA2ui.Info.build_surface/2` and
      pushes the messages to the shipped JS hook (`priv/js/ash_a2ui_hook.js`)
      hosting `<a2ui-surface>`.
    - `handle_event("a2ui:action", envelope, socket)` routes through
      `AshA2ui.ActionHandler.handle/3` and pushes follow-up messages.
    - If the resource has `Ash.Notifier.PubSub` configured, it subscribes on
      mount and pushes `AshA2ui.Info.build_data_model/2` refreshes on
      notifications.

    FROZEN CONTRACT — the `use` options (`:ui`, `:actor_fn`) are the interface
    Track 6 codes against; do not change outside an integration commit.

    TODO Track 4: implement the callback bodies (currently skeletons).
    """

    @doc """
    ## Options

      * `:ui` (required) — the resource or standalone UI module whose `a2ui`
        section defines the surface.
      * `:actor_fn` (optional) — a 1-arity function `socket -> actor` used to
        derive the actor on mount and for every action. Defaults to `nil`
        (no actor).
    """
    defmacro __using__(opts) do
      quote bind_quoted: [opts: opts] do
        use Phoenix.LiveView

        @ash_a2ui_ui Keyword.fetch!(opts, :ui)
        @ash_a2ui_actor_fn Keyword.get(opts, :actor_fn)

        @impl true
        def mount(_params, _session, socket) do
          # TODO Track 4: derive actor via @ash_a2ui_actor_fn, call
          # AshA2ui.Info.build_surface(@ash_a2ui_ui, actor: actor), push the
          # messages to the hook via push_event/3, and subscribe to
          # Ash.Notifier.PubSub topics when configured.
          {:ok, socket}
        end

        @impl true
        def render(assigns) do
          # TODO Track 4: real container markup + initial message payload.
          ~H"""
          <div id="ash-a2ui-surface" phx-hook="AshA2ui" phx-update="ignore"></div>
          """
        end

        @impl true
        def handle_event("a2ui:action", envelope, socket) do
          # TODO Track 4: route through AshA2ui.ActionHandler.handle/3 with
          # the mounted actor and push the follow-up messages.
          {:noreply, socket}
        end

        @impl true
        def handle_info(_message, socket) do
          # TODO Track 4: on Ash.Notifier.PubSub notifications, push
          # AshA2ui.Info.build_data_model/2 (debounced) to the hook.
          {:noreply, socket}
        end

        defoverridable mount: 3, render: 1, handle_event: 3, handle_info: 2
      end
    end
  end
end
