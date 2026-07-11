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

    - `mount/3` derives the actor/tenant (via `:actor_fn` / `:tenant_fn`),
      builds the surface via `AshA2ui.Info.build_surface/2` and pushes the
      messages as the `"a2ui:messages"` event to the shipped JS hook
      (`priv/js/ash_a2ui_hook.js`) hosting `<a2ui-surface>`. On the static
      (disconnected) render only the introspection assigns are set — the
      surface is built once, on the connected mount.
    - `render/1` renders the hook container
      (`<div id="ash-a2ui-surface" phx-hook="AshA2ui" phx-update="ignore">`).
    - `handle_event("a2ui:action", envelope, socket)` routes the client
      `action` envelope through `AshA2ui.ActionHandler.handle/3` and pushes
      the follow-up messages — for both `{:ok, messages}` and
      `{:error, messages}` results (error messages carry validation feedback
      on the reserved `/errors/<field>` and `/ui/status` data-model paths).
    - With `:pubsub` configured it subscribes on the connected mount and
      pushes debounced `AshA2ui.Info.build_data_model/2` refreshes when
      broadcasts arrive (see "PubSub live refresh" below).

    All injected callbacks are `defoverridable`.

    ## Options

      * `:ui` (required) — the resource or standalone UI module whose `a2ui`
        section defines the surface.
      * `:actor_fn` (optional) — a 1-arity function `socket -> actor` used to
        derive the actor on mount; the actor is passed to every surface,
        data-model and action call. Defaults to `nil` (no actor).
      * `:tenant_fn` (optional) — a 1-arity function `socket -> tenant`,
        same semantics as `:actor_fn`. Defaults to `nil` (no tenant).
      * `:pubsub` (optional) — enables live refresh:
        `pubsub: [module: MyApp.PubSub, topics: ["providers:created", ...]]`.
        Topics are explicit configuration: pass the topics your resource's
        `Ash.Notifier.PubSub` notifier publishes (the extension does not try
        to introspect them). See "PubSub live refresh".

    ## PubSub live refresh

    When `:pubsub` is configured, the connected mount subscribes to every
    listed topic via `Phoenix.PubSub.subscribe/2`. Ash's PubSub notifier
    broadcasts a `%Ash.Notifier.Notification{}` by default (`broadcast_type
    :notification`), but may also send `%Phoenix.Socket.Broadcast{}` or a
    plain `%{topic: _, event: _, payload: _}` map depending on
    `broadcast_type` — so `handle_info/2` treats *any* message it receives
    (other than its internal refresh timer) as a data-change signal.
    Notifications are debounced: the first one schedules a refresh 150 ms
    out (`Process.send_after/3`) and further notifications coalesce into it. The refresh calls `AshA2ui.Info.build_data_model/2` with the
    mounted actor/tenant and pushes the resulting `updateDataModel` message
    (wrapped in a one-element list) as `"a2ui:messages"`.

    For surfaces with a `query`, the LiveView tracks the last `/query` state
    it pushed (from the mount payload and every action follow-up) and passes
    it to the refresh as `:query_state`, so a PubSub refresh re-runs the
    user's current search/filters/sort/page instead of resetting the surface
    to the query defaults. Surfaces with `context` entities get the same
    treatment for `/context` (passed as `:context_state`), so refreshes keep
    the user's selections, dependent option lists, details, and table
    scoping.

    Override `handle_info/2` if your LiveView receives unrelated messages.

    ## Introspection assigns

    `mount/3` assigns `:ash_a2ui_ui`, `:ash_a2ui_actor` and
    `:ash_a2ui_tenant` on the socket.

    ## Test seams (not public API)

    Internal override options used by the test suite to inject stubs while
    the encoder and action handler are built in parallel — do not rely on
    them in applications:

      * `:surface_fn` — `(ui, opts -> [message])`, defaults to
        `AshA2ui.Info.build_surface/2`.
      * `:data_model_fn` — `(ui, opts -> message)`, defaults to
        `AshA2ui.Info.build_data_model/2`.
      * `:action_fn` — `(ui, envelope, opts -> {:ok, [message]} |
        {:error, [message]})`, defaults to `AshA2ui.ActionHandler.handle/3`.
      * `:refresh_debounce_ms` — PubSub refresh debounce window, defaults
        to `150`.

    FROZEN CONTRACT — the `use` options (`:ui`, `:actor_fn`) are the interface
    Track 6 codes against; do not change outside an integration commit.
    """

    use Phoenix.Component

    import Phoenix.LiveView, only: [connected?: 1, push_event: 3]

    @messages_event "a2ui:messages"
    @refresh_message {:ash_a2ui, :refresh}
    @default_debounce_ms 150

    defmacro __using__(opts) do
      quote do
        use Phoenix.LiveView

        @doc false
        def __ash_a2ui_config__ do
          AshA2ui.LiveRenderer.build_config(unquote(opts))
        end

        @impl true
        def mount(params, session, socket) do
          AshA2ui.LiveRenderer.mount(__ash_a2ui_config__(), params, session, socket)
        end

        @impl true
        def render(assigns) do
          AshA2ui.LiveRenderer.surface_container(assigns)
        end

        @impl true
        def handle_event("a2ui:action", envelope, socket) do
          AshA2ui.LiveRenderer.handle_action(__ash_a2ui_config__(), envelope, socket)
        end

        @impl true
        def handle_info(message, socket) do
          AshA2ui.LiveRenderer.handle_notification(__ash_a2ui_config__(), message, socket)
        end

        defoverridable mount: 3, render: 1, handle_event: 3, handle_info: 2
      end
    end

    @doc false
    def build_config(opts) do
      %{
        ui: Keyword.fetch!(opts, :ui),
        actor_fn: Keyword.get(opts, :actor_fn) || fn _socket -> nil end,
        tenant_fn: Keyword.get(opts, :tenant_fn) || fn _socket -> nil end,
        pubsub: normalize_pubsub(Keyword.get(opts, :pubsub)),
        refresh_debounce_ms: Keyword.get(opts, :refresh_debounce_ms, @default_debounce_ms),
        surface_fn: Keyword.get(opts, :surface_fn, &AshA2ui.Info.build_surface/2),
        data_model_fn: Keyword.get(opts, :data_model_fn, &AshA2ui.Info.build_data_model/2),
        action_fn: Keyword.get(opts, :action_fn, &AshA2ui.ActionHandler.handle/3)
      }
    end

    @doc false
    def mount(config, _params, _session, socket) do
      actor = config.actor_fn.(socket)
      tenant = config.tenant_fn.(socket)

      socket =
        assign(socket,
          ash_a2ui_ui: config.ui,
          ash_a2ui_actor: actor,
          ash_a2ui_tenant: tenant,
          ash_a2ui_refresh_scheduled?: false,
          ash_a2ui_query_state: nil,
          ash_a2ui_context_state: nil
        )

      socket =
        if connected?(socket) do
          subscribe(config.pubsub)
          messages = config.surface_fn.(config.ui, actor: actor, tenant: tenant)

          socket
          |> track_query_state(messages)
          |> track_context_state(messages)
          |> push_messages(messages)
        else
          socket
        end

      {:ok, socket}
    end

    @doc false
    def surface_container(assigns) do
      ~H"""
      <div id="ash-a2ui-surface" phx-hook="AshA2ui" phx-update="ignore"></div>
      """
    end

    @doc false
    def handle_action(config, envelope, socket) do
      messages =
        case config.action_fn.(config.ui, envelope, call_opts(socket)) do
          {:ok, messages} -> messages
          {:error, messages} -> messages
        end

      socket =
        socket
        |> track_query_state(messages)
        |> track_context_state(messages)
        |> push_messages(messages)

      {:noreply, socket}
    end

    @doc false
    def handle_notification(config, message, socket)

    def handle_notification(config, @refresh_message, socket) do
      socket = assign(socket, :ash_a2ui_refresh_scheduled?, false)
      data_model = config.data_model_fn.(config.ui, refresh_opts(socket))

      socket =
        socket
        |> track_query_state([data_model])
        |> track_context_state([data_model])

      {:noreply, push_messages(socket, [data_model])}
    end

    def handle_notification(%{pubsub: nil}, _message, socket) do
      {:noreply, socket}
    end

    # Any other message while :pubsub is configured is treated as a broadcast
    # on a subscribed topic (an %Ash.Notifier.Notification{}, a
    # %Phoenix.Socket.Broadcast{}, or an arbitrary payload) and coalesced into
    # the next scheduled refresh.
    def handle_notification(config, _message, socket) do
      {:noreply, schedule_refresh(config, socket)}
    end

    defp subscribe(nil), do: :ok

    defp subscribe(%{module: module, topics: topics}) do
      Enum.each(topics, &Phoenix.PubSub.subscribe(module, &1))
    end

    defp schedule_refresh(config, socket) do
      if socket.assigns.ash_a2ui_refresh_scheduled? do
        socket
      else
        Process.send_after(self(), @refresh_message, config.refresh_debounce_ms)
        assign(socket, :ash_a2ui_refresh_scheduled?, true)
      end
    end

    defp push_messages(socket, messages) do
      push_event(socket, @messages_event, %{messages: messages})
    end

    # Remembers the last /query state pushed to the client (from the full
    # data model on mount/refresh or a /query update in an action follow-up)
    # so PubSub refreshes can re-run the user's current query instead of the
    # declared defaults.
    defp track_query_state(socket, messages) do
      state =
        Enum.reduce(messages, socket.assigns.ash_a2ui_query_state, fn
          %{"updateDataModel" => %{"path" => "/query", "value" => value}}, _acc
          when is_map(value) ->
            value

          %{"updateDataModel" => %{"path" => "/", "value" => %{"query" => value}}}, _acc
          when is_map(value) ->
            value

          # Multi-table surfaces scope follow-ups per table
          # (/query/<component_name>); fold them into the tracked keyed map.
          %{"updateDataModel" => %{"path" => "/query/" <> table, "value" => value}}, acc
          when is_map(value) ->
            Map.put((is_map(acc) && acc) || %{}, table, value)

          _message, acc ->
            acc
        end)

      assign(socket, :ash_a2ui_query_state, state)
    end

    # Same for the last /context state (surface contexts): a context change
    # rewrites /context wholesale; the full data model carries it under
    # "context".
    defp track_context_state(socket, messages) do
      state =
        Enum.reduce(messages, socket.assigns.ash_a2ui_context_state, fn
          %{"updateDataModel" => %{"path" => "/context", "value" => value}}, _acc
          when is_map(value) ->
            value

          %{"updateDataModel" => %{"path" => "/", "value" => %{"context" => value}}}, _acc
          when is_map(value) ->
            value

          _message, acc ->
            acc
        end)

      assign(socket, :ash_a2ui_context_state, state)
    end

    defp call_opts(socket) do
      [actor: socket.assigns.ash_a2ui_actor, tenant: socket.assigns.ash_a2ui_tenant]
    end

    defp refresh_opts(socket) do
      opts =
        case socket.assigns.ash_a2ui_query_state do
          nil -> call_opts(socket)
          state -> Keyword.put(call_opts(socket), :query_state, state)
        end

      case socket.assigns.ash_a2ui_context_state do
        nil -> opts
        state -> Keyword.put(opts, :context_state, state)
      end
    end

    defp normalize_pubsub(nil), do: nil

    defp normalize_pubsub(opts) do
      %{module: Keyword.fetch!(opts, :module), topics: Keyword.get(opts, :topics, [])}
    end
  end
end
