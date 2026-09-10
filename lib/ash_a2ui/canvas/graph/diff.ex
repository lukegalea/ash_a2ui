defmodule AshA2ui.Canvas.Graph.Diff do
  @moduledoc """
  Exact, deterministic comparison of two `%AshA2ui.Canvas.Graph{}`s.

  Every semantic delta is reported: added/removed nodes, added/removed
  edges, and — for nodes that exist in both but moved semantically (a label
  change, an added action, a policy count change, a state-machine edit) —
  the node id in `changed_nodes`. Nothing is fuzzy: edges compare by their
  full `(from, to, kind, name)` tuple, nodes by the same canonical form the
  revision hash uses.
  """

  alias AshA2ui.Canvas.Graph

  defstruct [
    :added_nodes,
    :removed_nodes,
    :added_edges,
    :removed_edges,
    :changed_nodes,
    :revision_from,
    :revision_to
  ]

  @type t :: %__MODULE__{
          added_nodes: [Graph.Node.t()],
          removed_nodes: [Graph.Node.t()],
          added_edges: [Graph.Edge.t()],
          removed_edges: [Graph.Edge.t()],
          changed_nodes: [String.t()],
          revision_from: String.t() | nil,
          revision_to: String.t() | nil
        }

  @doc """
  Diffs `old` against `new`. Lists are sorted by id (nodes) and by
  `(from, to, kind, name)` (edges), so the result is stable run to run.
  """
  @spec diff(Graph.t(), Graph.t()) :: t()
  def diff(%Graph{} = old, %Graph{} = new) do
    %Graph.Diff{
      added_nodes: added(new.nodes, old.nodes),
      removed_nodes: added(old.nodes, new.nodes),
      added_edges: edge_delta(new.edges, old.edges),
      removed_edges: edge_delta(old.edges, new.edges),
      changed_nodes: changed(old.nodes, new.nodes),
      revision_from: old.revision,
      revision_to: new.revision
    }
  end

  defp added(new_nodes, old_nodes) do
    new_nodes
    |> Map.values()
    |> Enum.reject(&Map.has_key?(old_nodes, &1.id))
    |> Enum.sort_by(& &1.id)
  end

  defp edge_delta(new_edges, old_edges) do
    old_keys = MapSet.new(old_edges, &edge_key/1)

    new_edges
    |> Enum.reject(&MapSet.member?(old_keys, edge_key(&1)))
    |> Enum.sort_by(&edge_key/1)
  end

  defp changed(old_nodes, new_nodes) do
    new_nodes
    |> Map.keys()
    |> Enum.filter(fn id ->
      old_node = Map.get(old_nodes, id)
      new_node = Map.fetch!(new_nodes, id)
      old_node != nil and Graph.canonical_node(old_node) != Graph.canonical_node(new_node)
    end)
    |> Enum.sort()
  end

  defp edge_key(%Graph.Edge{} = edge), do: {edge.from, edge.to, edge.kind, edge.name}
end
