defmodule AshA2ui.ActorTest do
  @moduledoc """
  Session-backed actor selection: the configured resource read as labelled
  actors, load/1's degrade-to-nil contract, and the no-configuration case.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Test.{ActorRoster, Owner}

  setup do
    previous = Application.get_env(:ash_a2ui, :actor)

    on_exit(fn -> Application.put_env(:ash_a2ui, :actor, previous) end)

    Application.put_env(:ash_a2ui, :actor, resource: Owner, label: :name)

    :ok
  end

  defp roster(name) do
    ActorRoster
    |> Ash.Changeset.for_create(:create, %{name: name})
    |> Ash.create!()
  end

  # The roster table is shared (public ETS), so rows leak between tests —
  # every roster-dependent test starts from a clean table.
  defp clear_roster do
    Enum.each(Ash.read!(ActorRoster, authorize?: false), &Ash.destroy!(&1))
  end

  test "list/0 reads the configured resource as labelled actors" do
    actors = AshA2ui.Actor.list()

    for owner <- Ash.read!(Owner, authorize?: false) do
      actor = Enum.find(actors, &(&1.id == owner.id))
      assert actor && actor.label == owner.name
    end
  end

  test "load/1 round-trips a listed actor and degrades unknowns to nil" do
    owner =
      Owner
      |> Ash.Changeset.for_create(:create, %{name: "Zed Actorson", email: "zed@example.com"})
      |> Ash.create!()

    owner_id = owner.id
    assert %AshA2ui.Actor{id: ^owner_id, label: "Zed Actorson"} = AshA2ui.Actor.load(owner_id)

    refute AshA2ui.Actor.load("00000000-0000-0000-0000-000000000099")
    refute AshA2ui.Actor.load(nil)
  end

  test "list/0 is empty without host configuration" do
    Application.put_env(:ash_a2ui, :actor, nil)

    assert AshA2ui.Actor.list() == []
  end

  # --- the load path: a primary-key read, not a roster scan -------------------

  test "load/1 reads by primary key instead of scanning the roster" do
    clear_roster()

    Application.put_env(:ash_a2ui, :actor, resource: ActorRoster, label: :name)
    ada = roster("Ada")
    roster("Grace")

    :persistent_term.put({ActorRoster, :last_filter}, :unset)
    actor = AshA2ui.Actor.load(ada.id)
    assert %AshA2ui.Actor{label: "Ada"} = actor
    assert actor.id == ada.id

    filter = :persistent_term.get({ActorRoster, :last_filter}, :unset)
    assert filter != :unset, "expected load/1 to run exactly one read"
    assert inspect(filter) =~ ada.id, "expected the read to carry the id filter"

    # list/0 stays the roster read: no id filter
    :persistent_term.put({ActorRoster, :last_filter}, :unset)
    assert length(AshA2ui.Actor.list()) == 2
    filter = :persistent_term.get({ActorRoster, :last_filter}, :unset)
    refute inspect(filter) =~ ada.id
  end

  test "load/1 honors the configured :filter (a filtered-out actor cannot be loaded back)" do
    clear_roster()

    Application.put_env(:ash_a2ui, :actor,
      resource: ActorRoster,
      label: :name,
      filter: [name: "Ada"]
    )

    ada = roster("Ada")
    grace = roster("Grace")

    actor = AshA2ui.Actor.load(ada.id)
    assert %AshA2ui.Actor{label: "Ada"} = actor
    assert actor.id == ada.id

    refute AshA2ui.Actor.load(grace.id)
  end

  test "load/1 honors the configured :read_action like list/0" do
    clear_roster()

    Application.put_env(:ash_a2ui, :actor,
      resource: ActorRoster,
      label: :name,
      read_action: :ada_only
    )

    ada = roster("Ada")
    grace = roster("Grace")

    actor = AshA2ui.Actor.load(ada.id)
    assert %AshA2ui.Actor{label: "Ada"} = actor
    assert actor.id == ada.id

    refute AshA2ui.Actor.load(grace.id)
    assert [%AshA2ui.Actor{label: "Ada"}] = AshA2ui.Actor.list()
  end

  test "load/1 degrades invalid ids to nil" do
    clear_roster()

    Application.put_env(:ash_a2ui, :actor, resource: ActorRoster, label: :name)
    roster("Ada")

    refute AshA2ui.Actor.load("not-a-uuid")
    refute AshA2ui.Actor.load("")
  end
end
