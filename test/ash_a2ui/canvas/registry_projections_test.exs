defmodule AshA2ui.Canvas.RegistryProjectionsTest do
  @moduledoc """
  A host can say which projections an object has, within the vocabulary.

  Projections were derived entirely from action shape: `:browse` because a read
  exists, `:create` because a create does, and so on. That works for everything
  CRUD can describe and cannot reach the rest — `:diagram` and `:history` have
  been in the declared vocabulary since the canvas landed, and nothing has ever
  emitted them, because no amount of reading a resource's actions reveals that
  the host ships a renderer for it. A process definition is drawable; a business
  unit is not; their actions look the same.

  The override is deliberately narrow. It chooses among the declared kinds
  rather than extending them, so a host cannot hand the experience compiler a
  projection it has no meaning for — the compiler's vocabulary stays the
  library's to define, and only the question "which of these applies here"
  becomes the host's to answer.
  """

  use ExUnit.Case, async: false

  @base Canvas.Test.Registry
  @ref "resource:blog.post"

  defmodule AddsDiagram do
    @moduledoc false
    @behaviour AshA2ui.Canvas.Registry

    @impl true
    def domains, do: Canvas.Test.Registry.domains()

    @impl true
    def projections(_target, derived), do: derived ++ [:diagram, :history]
  end

  defmodule InventsAKind do
    @moduledoc false
    @behaviour AshA2ui.Canvas.Registry

    @impl true
    def domains, do: Canvas.Test.Registry.domains()

    @impl true
    def projections(_target, derived), do: derived ++ [:teleport, :diagram]
  end

  defmodule SaysNothing do
    @moduledoc false
    @behaviour AshA2ui.Canvas.Registry

    @impl true
    def domains, do: Canvas.Test.Registry.domains()

    @impl true
    def projections(_target, _derived), do: nil
  end

  defmodule SaysNone do
    @moduledoc false
    @behaviour AshA2ui.Canvas.Registry

    @impl true
    def domains, do: Canvas.Test.Registry.domains()

    @impl true
    def projections(_target, _derived), do: []
  end

  test "a registry that does not implement the callback keeps the derived list" do
    {:ok, object} = AshA2ui.Canvas.resolve(@ref, registry: @base)

    assert :browse in object.projections
    refute :diagram in object.projections
  end

  test "a host can add the projections that action shape cannot reveal" do
    {:ok, base} = AshA2ui.Canvas.resolve(@ref, registry: @base)
    {:ok, object} = AshA2ui.Canvas.resolve(@ref, registry: AddsDiagram)

    assert :diagram in object.projections
    assert :history in object.projections

    # Additive: what the library derived is still there.
    for projection <- base.projections, do: assert(projection in object.projections)
  end

  test "a kind outside the vocabulary is dropped, and the rest survives" do
    {:ok, object} = AshA2ui.Canvas.resolve(@ref, registry: InventsAKind)

    # The invented kind is filtered out rather than rejecting the whole list --
    # one bad entry must not cost the host its legitimate ones.
    refute :teleport in object.projections
    assert :diagram in object.projections
  end

  test "returning nil means the same as not implementing it" do
    {:ok, base} = AshA2ui.Canvas.resolve(@ref, registry: @base)
    {:ok, object} = AshA2ui.Canvas.resolve(@ref, registry: SaysNothing)

    assert object.projections == base.projections
  end

  test "returning an empty list is a decision, not a fallback" do
    {:ok, object} = AshA2ui.Canvas.resolve(@ref, registry: SaysNone)

    # The distinction that makes `nil` meaningful: a host must be able to say
    # "this object has no projections" without that being read as "I have no
    # opinion", which would silently restore the derived list.
    assert object.projections == []
  end
end
