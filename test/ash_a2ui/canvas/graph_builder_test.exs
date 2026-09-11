# --- inline fixture pair for AC-4: two semantically identical resources
# under identically-named domains/registries, differing by exactly one
# action. Identical last segments give identical opaque ids, so the only
# delta is the sub-entity change.

defmodule Canvas.Test.Builder.V1.Blog do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Canvas.Test.Builder.V1.Thing
  end
end

defmodule Canvas.Test.Builder.V1.Thing do
  @moduledoc false
  use Ash.Resource,
    domain: Canvas.Test.Builder.V1.Blog,
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

defmodule Canvas.Test.Builder.V1.Registry do
  @moduledoc false
  def domains, do: [Canvas.Test.Builder.V1.Blog]
end

defmodule Canvas.Test.Builder.V2.Blog do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Canvas.Test.Builder.V2.Thing
  end
end

defmodule Canvas.Test.Builder.V2.Thing do
  @moduledoc false
  use Ash.Resource,
    domain: Canvas.Test.Builder.V2.Blog,
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

    update :publish do
      accept []
    end
  end
end

defmodule Canvas.Test.Builder.V2.Registry do
  @moduledoc false
  def domains, do: [Canvas.Test.Builder.V2.Blog]
end

defmodule AshA2ui.Canvas.GraphBuilderTest do
  @moduledoc """
  A2UI-102/AC-1 + AC-4: the canonical graph over the canvas fixtures — every
  domain and resource under a stable opaque id, typed and named containment
  and relationship edges, behavioral layers as addressable sub-entities that
  the revision hash covers, and no Mermaid or SVG anywhere.
  """

  use ExUnit.Case, async: false

  # This file lives under `AshA2ui.Canvas.*`, so a bare `Canvas.*` would
  # expand into the wrong namespace — pin the fixture namespace explicitly.
  alias Elixir.Canvas

  alias AshA2ui.Canvas.Graph

  @registry Canvas.Test.Registry

  describe "the complete application graph" do
    @tag ac: "A2UI-102/AC-1"
    test "derives the complete application graph" do
      graph = AshA2ui.Canvas.build_graph(@registry)

      # stable opaque ids for the application, both domains, and every
      # resource
      assert graph.roots == ["application:registry"]

      assert MapSet.new(Map.keys(graph.nodes)) ==
               MapSet.new([
                 "application:registry",
                 "domain:blog",
                 "domain:catalog",
                 "resource:blog.page",
                 "resource:blog.post",
                 "resource:blog.task",
                 "resource:catalog.product"
               ])

      kinds = Map.new(graph.nodes, fn {id, node} -> {id, node.kind} end)
      assert kinds["application:registry"] == :application
      assert kinds["domain:blog"] == :domain
      assert kinds["resource:blog.post"] == :resource

      # containment edges: typed, application → domains → resources
      assert {:contains, "application:registry", "domain:blog", nil} in edge_tuples(graph)
      assert {:contains, "application:registry", "domain:catalog", nil} in edge_tuples(graph)
      assert {:contains, "domain:blog", "resource:blog.post", nil} in edge_tuples(graph)
      assert {:contains, "domain:catalog", "resource:catalog.product", nil} in edge_tuples(graph)

      # the cross-domain relationship edge is typed and NAMED
      assert {:relationship, "resource:blog.post", "resource:catalog.product", :product} in edge_tuples(
               graph
             )

      # the relationship whose destination is NOT registered produces no
      # edge — the connection does not exist
      refute Enum.any?(edge_tuples(graph), fn {_kind, _from, _to, name} -> name == :tag end)
      refute Map.has_key?(graph.nodes, "resource:blog.minimal")

      # labels: registry overrides and humanized fallbacks, all Ash-derived
      # (no Mermaid or SVG is parsed or produced anywhere in the namespace —
      # the graph is plain data straight out of Ash introspection)
      assert graph.nodes["application:registry"].label == "Canvas Test App"
      assert graph.nodes["resource:blog.post"].label == "Posts"
      assert graph.nodes["resource:catalog.product"].label == "Product"

      Enum.each(graph.nodes, fn {_id, node} ->
        assert is_binary(node.label)
        assert is_map(node.metadata)

        serialized = inspect({node.label, node.metadata})

        refute serialized =~ "mermaid"
        refute serialized =~ "graph LR"
        refute serialized =~ "<svg"
      end)
    end
  end

  describe "behavioral layers" do
    @tag ac: "A2UI-102/AC-4"
    test "behavioral layers are addressable and versioned" do
      graph = AshA2ui.Canvas.build_graph(@registry)

      # actions are addressable typed sub-entities of the resource node
      post = graph.nodes["resource:blog.post"]
      action_ids = Enum.map(post.metadata["actions"], & &1["id"])

      assert "resource:blog.post#action:create" in action_ids
      assert "resource:blog.post#action:publish_summary" in action_ids

      create_action = Enum.find(post.metadata["actions"], &(&1["name"] == "create"))
      assert create_action["type"] == "create"

      # policies: count + evaluator presence
      page = graph.nodes["resource:blog.page"]
      assert length(page.metadata["policies"]) == 3
      assert page.metadata["authorizer"] == true

      assert Enum.all?(
               page.metadata["policies"],
               &String.starts_with?(&1["id"], "resource:blog.page#policy:")
             )

      # no policies declared → none carried, no authorizer
      assert post.metadata["policies"] == []
      assert post.metadata["authorizer"] == false

      # the state machine is a sub-entity with its state names as semantic
      # content
      task = graph.nodes["resource:blog.task"]

      assert %{"id" => "resource:blog.task#state_machine", "states" => states} =
               task.metadata["state_machine"]

      assert Enum.sort(states) == ["done", "pending", "running"]

      # non-resource nodes carry no behavioral metadata
      assert graph.nodes["domain:blog"].metadata == %{}

      # adding an action changes the revision and surfaces the node in the
      # diff (same opaque ids, one semantic delta)
      old = AshA2ui.Canvas.build_graph(Canvas.Test.Builder.V1.Registry)
      new = AshA2ui.Canvas.build_graph(Canvas.Test.Builder.V2.Registry)

      refute old.revision == new.revision

      diff = Graph.Diff.diff(old, new)
      assert diff.changed_nodes == ["resource:blog.thing"]
      assert diff.added_nodes == [] and diff.removed_nodes == []
      assert diff.added_edges == [] and diff.removed_edges == []
    end
  end

  defp edge_tuples(graph) do
    Enum.map(graph.edges, &{&1.kind, &1.from, &1.to, &1.name})
  end
end
