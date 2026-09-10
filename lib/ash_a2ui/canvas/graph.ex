defmodule AshA2ui.Canvas.Graph do
  @moduledoc """
  The canonical graph AST over a registry — the structural truth of what
  the host's Ash estate looks like.

  * `nodes` — `%{"application:app" | "domain:short" | "resource:d.r" =>
    %Node{}}`. Node ids are the same opaque strings clients use as refs.
  * `edges` — `%Edge{kind: :contains | :relationship, from: id, to: id,
    name: atom | nil}`: application → domain and domain → resource
    containment, plus named resource-to-resource relationship edges (only
    relationships whose destination resolves inside the registry).
  * `roots` — the application node id(s).
  * `revision` — `"sha256:<hex>"` over the canonicalized *semantic*
    content: nodes sorted by id, edges sorted by (from, to, kind, name),
    metadata restricted to the semantic fields (labels, kinds, action
    names/types, relationship names/types, policy data, state-machine state
    names). Module definition order and registration order do not affect
    it.

  Behavioral layers (actions, policies, state machines) are not graph
  nodes: they ride as addressable typed sub-entities in their resource
  node's metadata with stable ids (`"resource:d.r#action:create"`,
  `"#policy:0"`, `"#state_machine"`). Records are never nodes.

  `AshA2ui.Canvas.Graph.Diff.diff/2` compares two revisions exactly.
  """

  defmodule Node do
    @moduledoc """
    One structural node. `metadata` carries the behavioral sub-entities of
    resource nodes (see `AshA2ui.Canvas.Graph`'s moduledoc); application and
    domain nodes carry an empty map.
    """
    defstruct [:id, :kind, :label, :metadata]

    @type kind :: :application | :domain | :resource
    @type t :: %__MODULE__{id: String.t(), kind: kind, label: String.t(), metadata: map()}
  end

  defmodule Edge do
    @moduledoc "A typed, optionally-named edge between node ids."
    defstruct [:kind, :from, :to, :name]

    @type kind :: :contains | :relationship
    @type t :: %__MODULE__{kind: kind, from: String.t(), to: String.t(), name: atom() | nil}
  end

  defstruct [:revision, :roots, :nodes, :edges]

  @typedoc "`revision` is nil only between construction and hashing."
  @type t :: %__MODULE__{
          revision: String.t() | nil,
          roots: [String.t()],
          nodes: %{String.t() => Node.t()},
          edges: [Edge.t()]
        }

  @digest_prefix "sha256:"

  @doc """
  Computes the revision hash of a graph: sha256 over the canonical
  serialization of its semantic content.
  """
  @spec revision(t()) :: String.t()
  def revision(%__MODULE__{} = graph) do
    digest =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary(
          {"ash_a2ui.canvas.graph.v1", canonical_nodes(graph), canonical_edges(graph)}
        )
      )

    @digest_prefix <> Base.encode16(digest, case: :lower)
  end

  @doc false
  # The semantic identity of a node: exactly the fields the revision hash
  # covers. Sub-entity lists are sorted by their stable ids so neither
  # module definition order nor registration order can leak into the hash.
  def canonical_node(%Node{} = node) do
    {node.id, node.kind, node.label, semantic_metadata(node.metadata)}
  end

  def canonical_edges(%__MODULE__{} = graph) do
    graph.edges
    |> Enum.map(&{&1.from, &1.to, &1.kind, &1.name})
    |> Enum.sort()
  end

  defp canonical_nodes(%__MODULE__{} = graph) do
    graph.nodes
    |> Map.values()
    |> Enum.map(&canonical_node/1)
    |> Enum.sort()
  end

  # The whitelisted semantic projection of node metadata. Anything a future
  # change adds to metadata is invisible to the revision hash until it is
  # deliberately added here — the conservative direction to be wrong in.
  defp semantic_metadata(metadata) do
    {
      Enum.sort_by(Map.get(metadata, "actions", []), & &1["id"]),
      Enum.sort_by(Map.get(metadata, "policies", []), & &1["id"]),
      Map.get(metadata, "authorizer", false),
      Map.get(metadata, "state_machine")
    }
  end
end
