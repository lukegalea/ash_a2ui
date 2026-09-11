defmodule AshA2ui.Canvas.ObjectResolverSecurityTest do
  @moduledoc """
  A2UI-103/AC-3 (`CANVAS-SEC-006`): malformed and unregistered refs fail
  closed to `{:error, :unknown_object}` — no input ever becomes an atom or
  module, unregistered modules are never loaded, and the error carries no
  registry content.
  """

  use ExUnit.Case, async: false

  # This file lives under `AshA2ui.Canvas.*`, so a bare `Canvas.*` would
  # expand into the wrong namespace — pin the fixture namespace explicitly.
  alias Elixir.Canvas

  @registry Canvas.Test.Registry

  @malformed_refs [
    # not a ref shape at all
    "nonsense",
    "",
    ":",
    "application:",
    "domain:",
    "resource:",
    "record:",
    # unknown kind word
    "module:Canvas.Test.Post",
    "record2:blog.post:abc",
    # malformed paths
    "resource:blog",
    "resource:blog.",
    "resource:.post",
    "resource:blog.post.extra",
    "domain:blog.catalog",
    # record refs with broken pk segments
    "record:blog.post:",
    "record:blog.post"
  ]

  @unregistered_refs [
    # the module exists (it backs another fixture domain) but the registry
    # does not list it — from the canvas's point of view it does not exist
    "resource:blog.minimal",
    "domain:test_domain",
    "record:test_domain.minimal:something",
    # plausible-but-absent names
    "domain:audit",
    "resource:audit.ledger",
    "record:audit.ledger:abc"
  ]

  @tag ac: "A2UI-103/AC-3"
  test "rejects unregistered module input" do
    Enum.each(@malformed_refs ++ @unregistered_refs, fn ref ->
      assert AshA2ui.Canvas.resolve(ref, registry: @registry, actor: %{admin: true}) ==
               {:error, :unknown_object},
             "expected #{inspect(ref)} to be rejected"
    end)

    # non-binary input fails the same way
    assert AshA2ui.Canvas.resolve(123, registry: @registry) == {:error, :unknown_object}
    assert AshA2ui.Canvas.resolve(nil, registry: @registry) == {:error, :unknown_object}

    assert AshA2ui.Canvas.resolve(%{id: "resource:blog.post"}, registry: @registry) ==
             {:error, :unknown_object}

    # case is significant: string matching against registry short names only,
    # no normalization into atoms
    assert AshA2ui.Canvas.resolve("resource:blog.POST", registry: @registry) ==
             {:error, :unknown_object}
  end

  @tag ac: "A2UI-103/AC-3"
  test "resolving garbage never creates atoms and never loads modules" do
    garbage = [
      "resource:totally_made_up_#{System.unique_integer([:positive])}.thing",
      "domain:also_made_up_#{System.unique_integer([:positive])}"
    ]

    atoms_before = :erlang.system_info(:atom_count)

    Enum.each(garbage, fn ref ->
      assert AshA2ui.Canvas.resolve(ref, registry: @registry) == {:error, :unknown_object}
    end)

    assert :erlang.system_info(:atom_count) == atoms_before

    # no module derived from the garbage input was ever loaded
    Enum.each(garbage, fn ref ->
      [_, path] = String.split(ref, ":", parts: 2)
      candidate = path |> String.split(".") |> Enum.map_join(".", &Macro.camelize/1)

      refute Code.ensure_loaded?(String.to_atom("Elixir.Canvas.Test.#{candidate}")),
             "the resolver must never have loaded #{candidate}"
    end)
  end

  @tag ac: "A2UI-103/AC-3"
  test "errors leak no registry content" do
    # every failure mode returns exactly the bare atom — no domain lists, no
    # module names, no hints about what WOULD have matched
    for ref <- @unregistered_refs do
      assert {:error, :unknown_object} ==
               AshA2ui.Canvas.resolve(ref, registry: @registry, actor: %{admin: true})
    end
  end
end
