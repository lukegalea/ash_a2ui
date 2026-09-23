# AshA2ui.Presence is the optional who-else-is-here layer. The whole module
# is guarded so the protocol core compiles when phoenix_live_view is absent
# (proven by the NO_PHOENIX CI job), exactly like LiveRenderer and the
# actor picker.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.Presence do
    @moduledoc """
    Who-else-is-here for A2UI surfaces: a thin `Phoenix.Presence` wrapper so
    everyone looking at a surface sees who else is there — an avatar stack
    (see `AshA2ui.PresenceBar`) riding the surface's own topic.

    ## The tracking contract

    Presence is tracked **per surface**, on a topic derived from the A2UI
    surface id (the same `surface_id` the encoder emits), so the presence
    traffic rides right beside the surface's LiveView traffic and never
    mixes between surfaces:

        AshA2ui.Presence.topic("schedule")  # => "a2ui:surface:schedule"

    Identity is **a label plus a stable key**: the key is whatever stably
    identifies the human across mounts — the actor's id
    (`AshA2ui.Actor` puts it in the session; a real authn stack: the
    `current_user` id) or a stable per-browser UUID — and the label is the
    display name the avatar renders (initials come from it).

    ## Host wiring

    `Phoenix.Presence` needs a host-owned module (each presence module
    supervises one CRDT replica per PubSub), so `AshA2ui.Presence` is
    *used*, not started:

        defmodule MyAppWeb.A2uiPresence do
          use AshA2ui.Presence, pubsub_server: MyApp.PubSub
        end

        # application.ex — add to the supervision tree:
        MyAppWeb.A2uiPresence

    A surface LiveView then mounts presence and renders the bar:

        defmodule MyAppWeb.ScheduleLive do
          use Phoenix.LiveView

          def mount(_params, _session, socket) do
            {:ok,
             AshA2ui.Presence.mount_surface(
               MyAppWeb.A2uiPresence,
               socket,
               "schedule",
               key: socket.assigns.current_user.id,
               label: socket.assigns.current_user.name
             )}
          end

          def handle_info(msg, socket) do
            case AshA2ui.Presence.handle_broadcast(msg, MyAppWeb.A2uiPresence, socket) do
              {:noreply, socket} -> {:noreply, socket}
              # not ours — fall through to your other handle_info clauses
              :ignored -> handle_other(msg, socket)
            end
          end

          def render(assigns) do
            ~H\"""
            <AshA2ui.PresenceBar.bar presences={@a2ui_presences} />
            \"""
          end
        end

    `mount_surface/4` assigns the presence rows to `:a2ui_presences`
    (override with `as:`), stashes the surface id for the refresh contract,
    subscribes to the surface topic and tracks this visitor on the
    connected mount (the static render seeds the rows already present, so
    the first paint shows who is there). `handle_broadcast/3` answers the
    presence broadcasts (`presence_state` / `presence_diff`) with a
    re-list — the **PubSub-driven refresh contract**: hosts subscribe
    through `AshA2ui.Presence.subscribe/2` (or mount through the helper),
    and every join or leave re-renders the bar on all connected viewers.

    Leaving is automatic (presence is tied to the LiveView process);
    `untrack/3` exists for explicit leaves within a living process (e.g. a
    surface switch without a remount).

    ## The nav active-state contract

    Nav links pointing at the page currently rendered carry
    `aria-current="page"` — the WAI-ARIA contract screen readers and
    current-page themes key on. Spread
    `AshA2ui.PresenceBar.nav_current_attrs/2` on every nav link, with
    `:current_path` assigned from the mount URI. Clinic-demo ready:

        def handle_params(_params, uri, socket) do
          {:noreply, assign(socket, current_path: URI.parse(uri).path)}
        end

        <nav aria-label="Clinic" style="display:flex;gap:1rem;">
          <a href="/clinic/schedule"
             {AshA2ui.PresenceBar.nav_current_attrs(@current_path, "/clinic/schedule")}>
            Schedule
          </a>
          <a href="/clinic/patients"
             {AshA2ui.PresenceBar.nav_current_attrs(@current_path, "/clinic/patients")}>
            Patients
          </a>
        </nav>

    The helper returns `%{"aria-current" => "page"}` for the current page and
    `%{"aria-current" => nil}` (rendered as nothing) otherwise — the spread is
    the SAME call on every link; only the destination differs.

    Like the LiveView transport, the whole module vanishes without
    `phoenix_live_view` (kept `optional: true` in mix.exs).
    """

    import Phoenix.Component, only: [assign: 2, assign: 3]
    import Phoenix.LiveView, only: [connected?: 1]

    @topic_prefix "a2ui:surface"
    @default_assign :a2ui_presences
    @presence_events ["presence_state", "presence_diff"]

    defmacro __using__(opts) do
      pubsub_server =
        Keyword.get(opts, :pubsub_server) ||
          raise ArgumentError, "AshA2ui.Presence requires :pubsub_server"

      quote bind_quoted: [pubsub_server: pubsub_server] do
        # Phoenix.Presence requires :otp_app (AshA2ui's) and carries the
        # explicit pubsub_server through to the child spec, so the host
        # supervises `MyAppWeb.A2uiPresence` with no extra config.
        use Phoenix.Presence, otp_app: :ash_a2ui, pubsub_server: pubsub_server

        @doc false
        def __ash_a2ui_pubsub__, do: unquote(pubsub_server)
      end
    end

    @doc """
    The presence topic of a surface: `"a2ui:surface:<surface_id>"`.
    """
    @spec topic(term) :: String.t()
    def topic(surface_id), do: "#{@topic_prefix}:#{surface_id}"

    @doc """
    Tracks the calling LiveView's process on `surface_id` under `key` with
    the display `label` (plus any extra `metadata`, JSON-serializable).
    The key must be stable across mounts (see the moduledoc) and both key
    and label non-empty strings.
    """
    @spec track(module, term, String.t(), String.t(), %{String.t() => term}) :: :ok
    def track(presence_mod, surface_id, key, label, metadata \\ %{})
        when is_binary(key) and is_binary(label) do
      presence_mod.track(self(), topic(surface_id), key, presence_metadata(label, metadata))
    end

    @doc """
    Stops tracking the calling process on `surface_id` under `key` — the
    explicit-leave escape hatch (process death already untracks for free).
    """
    @spec untrack(module, term, String.t()) :: :ok
    def untrack(presence_mod, surface_id, key) when is_binary(key) do
      presence_mod.untrack(self(), topic(surface_id), key)
    end

    @doc """
    Subscribes the calling process to a surface's presence broadcasts —
    the subscribe half of the refresh contract (`mount_surface/4` does
    this for surface LiveViews). Every join or leave then arrives as a
    `%Phoenix.Socket.Broadcast{}` on the surface's topic.
    """
    @spec subscribe(module, term) :: :ok
    def subscribe(presence_mod, surface_id) do
      Phoenix.PubSub.subscribe(presence_mod.__ash_a2ui_pubsub__(), topic(surface_id))
    end

    @doc """
    The surface's presences as render-ready rows — `%{key: key, label:
    label}`, one per stable key, sorted by key for a stable avatar order.
    (Presences ARE grouped by surface: a surface's topic only ever holds
    its own visitors.)
    """
    @spec list(module, term) :: [%{key: String.t(), label: String.t()}]
    def list(presence_mod, surface_id) do
      presence_mod
      |> Phoenix.Presence.list(topic(surface_id))
      |> Enum.map(fn {key, %{metas: metas}} -> %{key: key, label: label_from(metas, key)} end)
      |> Enum.sort_by(& &1.key)
    end

    @doc """
    Mounts surface presence on a LiveView socket: stashes the surface id
    and assign name, subscribes and tracks the visitor on the connected
    mount, and seeds the rows assign on both mounts (the static render
    already shows who is there).

    Options:

      * `:key` (required) — the visitor's stable key.
      * `:label` (required) — the visitor's display label.
      * `:metadata` — extra JSON-serializable presence metadata.
      * `:as` — the rows assign, defaults to `:a2ui_presences`.
    """
    @spec mount_surface(module, Phoenix.LiveView.Socket.t(), term, keyword) ::
            Phoenix.LiveView.Socket.t()
    def mount_surface(presence_mod, socket, surface_id, opts) do
      key = Keyword.fetch!(opts, :key)
      label = Keyword.fetch!(opts, :label)
      assign_key = Keyword.get(opts, :as, @default_assign)

      socket =
        assign(socket, [
          {assign_key, []},
          a2ui_presence_surface_id: surface_id,
          a2ui_presence_assign: assign_key
        ])

      if connected?(socket) do
        subscribe(presence_mod, surface_id)
        track(presence_mod, surface_id, key, label, Keyword.get(opts, :metadata, %{}))
      end

      refresh(socket, presence_mod)
    end

    @doc """
    The refresh contract's `handle_info` adapter: when `message` is a
    presence broadcast for the mounted surface, re-lists the rows assign
    and returns `{:noreply, socket}`; anything else returns `:ignored` so
    the host can fall through to its own clauses.
    """
    @spec handle_broadcast(term, module, Phoenix.LiveView.Socket.t()) ::
            {:noreply, Phoenix.LiveView.Socket.t()} | :ignored
    def handle_broadcast(
          %Phoenix.Socket.Broadcast{event: event} = broadcast,
          presence_mod,
          socket
        )
        when event in @presence_events do
      if broadcast.topic == topic(socket.assigns[:a2ui_presence_surface_id]) do
        {:noreply, refresh(socket, presence_mod)}
      else
        :ignored
      end
    end

    def handle_broadcast(_other, _presence_mod, _socket), do: :ignored

    @doc """
    Re-lists the mounted surface's presences into the rows assign — the
    heart of the refresh contract (see the moduledoc). A socket without a
    stashed surface id is returned untouched.
    """
    @spec refresh(Phoenix.LiveView.Socket.t(), module) :: Phoenix.LiveView.Socket.t()
    def refresh(socket, presence_mod) do
      case socket.assigns[:a2ui_presence_surface_id] do
        nil ->
          socket

        surface_id ->
          assign(
            socket,
            socket.assigns[:a2ui_presence_assign] || @default_assign,
            list(presence_mod, surface_id)
          )
      end
    end

    defp presence_metadata(label, metadata) do
      metadata
      |> Map.new()
      |> Map.put("label", label)
    end

    defp label_from([meta | _], key) when is_map(meta) do
      Map.get(meta, "label") || Map.get(meta, :label) || to_string(key)
    end

    defp label_from([], key), do: to_string(key)
  end
end
