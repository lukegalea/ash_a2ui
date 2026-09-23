defmodule AshA2ui.Actor do
  alias Ash.Resource.Info

  @label_candidates [:full_name, :name, :title, :username, :email]

  defstruct [:id, :label]

  @moduledoc """
  Session-backed actor selection for hosts without authentication.

  Every a2ui action runs under an actor: policies check presence, and process
  engines attribute work to whoever acted. Demos and internal tools still
  need that, without a full auth stack. The host names the resource whose
  records are the possible actors, `AshA2ui.ActorPlug` stores the chosen id
  in the session, and this module's `on_mount/4` hook loads it into every
  LiveView of the `live_session`, ready for
  `actor_fn: & &1.assigns.a2ui_actor`.

      # config/config.exs
      config :ash_a2ui,
        actor: [
          resource: MyApp.Staff.Clinician,
          label: :full_name,
          filter: [active: true]
        ]

      # router
      pipeline :browser do
        # ... existing plugs ...
        plug AshA2ui.ActorPlug
      end

      live_session :a2ui, on_mount: AshA2ui.Actor do
        live "/schedule", ScheduleLive
      end

  Options:

    * `resource` (required) — the Ash resource whose records are the actors.
    * `label` — the attribute shown in the picker and banner. Defaults to the
      first of `[:full_name, :name, :title, :username, :email]` the resource
      defines.
    * `filter` — a filter expression the actor reads apply (e.g.
      `[active: true]`); an actor filtered out cannot be picked *back*.
    * `sort` — the attribute the picker list is ordered by. Defaults to the
      label attribute.
    * `read_action` — the read used for both list and load. Defaults to the
      primary read.

  Actor reads are infrastructural — the picker must show actors before any
  is chosen, like any sign-in screen — so they run with `authorize?: false`.
  The session id is validated against the configured list on every switch,
  so a stale session id degrades to "no actor" rather than an error.
  """

  require Ash.Query

  @doc "The session key the plug writes and the hook reads."
  def session_key, do: "a2ui_actor_id"

  @doc "The configured actor selection, or nil when the host has none."
  def config, do: Application.get_env(:ash_a2ui, :actor)

  @doc "The choosable actors, labelled, filtered and ordered as configured."
  def list do
    case config() do
      nil -> []
      cfg -> read_actors(cfg)
    end
  end

  @doc """
  The actor for a session id: `%__MODULE__{id: id, label: label}` or nil.
  Unknown and filtered-out ids both return nil — a stale session degrades to
  "no actor" rather than an error.
  """
  def load(nil), do: nil

  def load(id) when is_binary(id) do
    case config() do
      nil -> nil
      _cfg -> Enum.find(list(), &(&1.id == id))
    end
  end

  # A plain socket-struct update: the hook must stay usable in hosts whose
  # LiveView version has its own assign helpers.
  @doc false
  def on_mount(_reason, _params, session, socket) do
    actor = load(session[session_key()])

    assigns =
      socket.assigns
      |> Map.put(:a2ui_actor, actor)
      |> Map.put(:a2ui_actor_label, actor && actor.label)

    {:cont, %{socket | assigns: assigns}}
  end

  defp read_actors(cfg) do
    resource = Keyword.fetch!(cfg, :resource)
    label = Keyword.get(cfg, :label) || label_attribute(resource)
    filter = Keyword.get(cfg, :filter, [])
    sort = Keyword.get(cfg, :sort, label)

    # Actor lists are small (a staff roster); sorting after the read keeps
    # this clear of the sort macros' pin support.
    resource
    |> Ash.Query.filter(^filter)
    |> Ash.read!(action: cfg[:read_action], authorize?: false)
    |> Enum.sort_by(&Map.get(&1, sort))
    |> Enum.map(&%__MODULE__{id: &1.id, label: Map.get(&1, label)})
  end

  defp label_attribute(resource) do
    Enum.find(@label_candidates, &Info.attribute(resource, &1)) ||
      raise ArgumentError,
        message:
          "AshA2ui.Actor: #{inspect(resource)} has none of " <>
            "#{inspect(@label_candidates)} — configure the actor :label attribute"
  end
end
