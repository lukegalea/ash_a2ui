# --- inline fixture pair for AC-3: identical opaque ids everywhere, the
# only semantic delta being one relationship edge (V2's Thing relates to the
# Anchor resource both configurations register).

defmodule Canvas.Test.DiffGraph.V1.Blog do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Canvas.Test.DiffGraph.V1.Thing
    resource Canvas.Test.DiffGraph.V1.Anchor
  end
end

defmodule Canvas.Test.DiffGraph.V1.Thing do
  @moduledoc false
  use Ash.Resource,
    domain: Canvas.Test.DiffGraph.V1.Blog,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule Canvas.Test.DiffGraph.V1.Anchor do
  @moduledoc false
  use Ash.Resource,
    domain: Canvas.Test.DiffGraph.V1.Blog,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule Canvas.Test.DiffGraph.V1.Registry do
  @moduledoc false
  def domains, do: [Canvas.Test.DiffGraph.V1.Blog]
end

defmodule Canvas.Test.DiffGraph.V2.Blog do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Canvas.Test.DiffGraph.V2.Thing
    resource Canvas.Test.DiffGraph.V2.Anchor
  end
end

defmodule Canvas.Test.DiffGraph.V2.Thing do
  @moduledoc false
  use Ash.Resource,
    domain: Canvas.Test.DiffGraph.V2.Blog,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    belongs_to :extra, Canvas.Test.DiffGraph.V2.Anchor, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule Canvas.Test.DiffGraph.V2.Anchor do
  @moduledoc false
  use Ash.Resource,
    domain: Canvas.Test.DiffGraph.V2.Blog,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule Canvas.Test.DiffGraph.V2.Registry do
  @moduledoc false
  def domains, do: [Canvas.Test.DiffGraph.V2.Blog]
end

defmodule AshA2ui.Canvas.GraphDiffTest do
  @moduledoc """
  A2UI-102/AC-3 + AC-5: the diff is exact and deterministic — a semantic
  change moves the revision and reports exactly that delta, and every
  added/removed/changed element is listed with from/to revisions.
  """

  use ExUnit.Case, async: true

  # This file lives under `AshA2ui.Canvas.*`, so a bare `Canvas.*` would
  # expand into the wrong namespace — pin the fixture namespace explicitly.
  alias Elixir.Canvas

  alias AshA2ui.Canvas.Graph
  alias AshA2ui.Canvas.Graph.Diff

  describe "one-relationship delta" do
    @tag ac: "A2UI-102/AC-3"
    test "semantic change moves the revision" do
      old = AshA2ui.Canvas.build_graph(Canvas.Test.DiffGraph.V1.Registry)
      new = AshA2ui.Canvas.build_graph(Canvas.Test.DiffGraph.V2.Registry)

      refute old.revision == new.revision

      diff = Diff.diff(old, new)

      # exactly that relationship edge — no other deltas anywhere
      assert diff.added_edges == [
               %Graph.Edge{
                 kind: :relationship,
                 from: "resource:blog.thing",
                 to: "resource:blog.anchor",
                 name: :extra
               }
             ]

      assert diff.removed_edges == []
      assert diff.added_nodes == []
      assert diff.removed_nodes == []
      assert diff.changed_nodes == []

      # and the reverse diff removes exactly that edge
      reverse = Diff.diff(new, old)

      assert Enum.map(reverse.removed_edges, &{&1.from, &1.to, &1.kind, &1.name}) == [
               {"resource:blog.thing", "resource:blog.anchor", :relationship, :extra}
             ]

      assert reverse.added_edges == []
      assert reverse.changed_nodes == []

      # deterministic: same inputs, same diff, every time
      assert Diff.diff(old, new) == diff
    end
  end

  describe "exact deltas" do
    @tag ac: "A2UI-102/AC-5"
    test "diff reports exact deltas" do
      node = fn id, label, metadata ->
        %Graph.Node{id: id, kind: :resource, label: label, metadata: metadata}
      end

      edge = fn from, to, name ->
        %Graph.Edge{kind: :relationship, from: from, to: to, name: name}
      end

      old = %Graph{
        revision: "sha256:old",
        roots: ["application:app"],
        nodes: %{
          "application:app" => %Graph.Node{
            id: "application:app",
            kind: :application,
            label: "App",
            metadata: %{}
          },
          "resource:a.old" => node.("resource:a.old", "Old", %{}),
          "resource:a.both" =>
            node.("resource:a.both", "Both", %{
              "actions" => [
                %{"id" => "resource:a.both#action:read", "name" => "read", "type" => "read"}
              ],
              "policies" => [],
              "authorizer" => false
            })
        },
        edges: [
          edge.("resource:a.old", "resource:a.both", :related),
          edge.("resource:a.both", "resource:a.old", :back)
        ]
      }

      new = %Graph{
        revision: "sha256:new",
        roots: ["application:app"],
        nodes: %{
          "application:app" => %Graph.Node{
            id: "application:app",
            kind: :application,
            label: "App",
            metadata: %{}
          },
          "resource:a.both" =>
            node.("resource:a.both", "Both", %{
              "actions" => [
                %{"id" => "resource:a.both#action:read", "name" => "read", "type" => "read"},
                %{
                  "id" => "resource:a.both#action:publish",
                  "name" => "publish",
                  "type" => "update"
                }
              ],
              "policies" => [],
              "authorizer" => false
            }),
          "resource:a.added" => node.("resource:a.added", "Added", %{})
        },
        edges: [
          edge.("resource:a.both", "resource:a.old", :back),
          edge.("resource:a.added", "resource:a.both", :related)
        ]
      }

      diff = Diff.diff(old, new)

      assert %Diff{
               added_nodes: [%Graph.Node{id: "resource:a.added"}],
               removed_nodes: [%Graph.Node{id: "resource:a.old"}],
               added_edges: [%Graph.Edge{from: "resource:a.added"}],
               removed_edges: [%Graph.Edge{from: "resource:a.old", name: :related}],
               changed_nodes: ["resource:a.both"],
               revision_from: "sha256:old",
               revision_to: "sha256:new"
             } = diff

      # the sub-entity change is the reason "both" is changed — same id, same
      # label, different semantic metadata
      assert Graph.canonical_node(old.nodes["resource:a.both"]) !=
               Graph.canonical_node(new.nodes["resource:a.both"])
    end
  end
end
