# The inline registry is defined BEFORE the test module: with `async: true`
# ExUnit can start tests as soon as the test module registers, while the
# script is still evaluating — a trailing defmodule would race the tests.

defmodule Canvas.Test.Reorder.Registry do
  @moduledoc false

  # Same last segment as `Canvas.Test.Registry` (so the derived application
  # id matches), reversed domain order, same labels.
  @behaviour AshA2ui.Canvas.Registry

  @impl true
  def domains, do: Enum.reverse(Canvas.Test.Registry.domains())

  @impl true
  def label(target), do: Canvas.Test.Registry.label(target)
end

defmodule AshA2ui.Canvas.GraphIdentityTest do
  @moduledoc """
  A2UI-102/AC-2: the revision hash and the whole graph AST are invariant
  under registration order — the same domains listed in a different order
  produce byte-identical node ids, edges, and revision.
  """

  use ExUnit.Case, async: true

  # This file lives under `AshA2ui.Canvas.*`, so a bare `Canvas.*` would
  # expand into the wrong namespace — pin the fixture namespace explicitly.
  alias Elixir.Canvas

  @tag ac: "A2UI-102/AC-2"
  test "stable across registration order" do
    ordered = AshA2ui.Canvas.build_graph(Canvas.Test.Registry)
    reversed = AshA2ui.Canvas.build_graph(Canvas.Test.Reorder.Registry)

    # the registries share the application id and every domain/resource
    # short name, so the entire semantic content — including the revision —
    # must be identical
    assert ordered.revision == reversed.revision
    assert ordered.roots == reversed.roots
    assert ordered.nodes == reversed.nodes
    assert ordered.edges == reversed.edges

    # sanity: the two registries really do list the domains differently
    assert Canvas.Test.Registry.domains() != Canvas.Test.Reorder.Registry.domains()

    assert Enum.sort(Canvas.Test.Registry.domains()) ==
             Enum.sort(Canvas.Test.Reorder.Registry.domains())
  end
end
