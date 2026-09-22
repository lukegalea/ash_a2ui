defmodule AshA2ui.ActorTest do
  @moduledoc """
  Session-backed actor selection: the configured resource read as labelled
  actors, load/1's degrade-to-nil contract, and the no-configuration case.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Test.Owner

  setup do
    previous = Application.get_env(:ash_a2ui, :actor)

    on_exit(fn -> Application.put_env(:ash_a2ui, :actor, previous) end)

    Application.put_env(:ash_a2ui, :actor, resource: Owner, label: :name)

    :ok
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
end
