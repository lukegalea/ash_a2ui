defmodule AshA2ui.DynamicImporterTest do
  @moduledoc """
  The composer's Import: a declared surface reads back as the dynamic spec
  vocabulary, with every feature that vocabulary cannot carry surfaced as a
  rejection instead of silently dropped.
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Importer

  describe "import/1 — the happy path round-trips through resolve/2" do
    test "a standalone UI module imports to a spec that resolves" do
      {:ok, spec, rejections} = Importer.import(AshA2ui.Test.MinimalUI)

      assert spec["resource"] == "Minimal"
      assert [%{"kind" => "table"} = table] = spec["components"]
      assert table["fields"] == ["name"]
      assert [%{"name" => "name", "label" => "Name (standalone)"}] = spec["fields"]

      # surface_id is resolve/deploy metadata, not spec vocabulary — the one
      # honest rejection this fixture produces.
      assert [%{feature: "surface_id", path: "a2ui.surface_id"}] = rejections

      # The imported spec resolves like any composed one.
      allow = Dynamic.allowlist([AshA2ui.Test.Minimal])

      assert {:ok, %Dynamic.Surface{}} = Dynamic.resolve(spec, allowlist: allow)
    end

    test "an inline resource surface imports, with its nested forms rejected by name" do
      {:ok, spec, rejections} = Importer.import(AshA2ui.Test.Ticket)

      kinds = spec["components"] |> Enum.map(& &1["kind"]) |> Enum.sort()
      assert kinds == ["form", "table"]

      # Nested relationship forms have no spec vocabulary; the resolver's
      # parser would silently ignore a "nested_forms" key, so both forms are
      # rejected visibly instead.
      nested = Enum.filter(rejections, &String.contains?(&1.path, "nested_forms"))
      assert length(nested) == 2
      assert Enum.all?(nested, &String.contains?(&1.reason, "no spec vocabulary"))
      refute Enum.any?(spec["components"], &Map.has_key?(&1, "nested_forms"))

      allow = Dynamic.allowlist([AshA2ui.Test.Ticket])
      assert {:ok, %Dynamic.Surface{}} = Dynamic.resolve(spec, allowlist: allow)
    end
  end

  describe "import/1 — declared features the spec cannot say are visible rejections" do
    test "via-delegated actions are rejected, not silently re-pointed" do
      {:ok, spec, rejections} = Importer.import(AshA2ui.ActionHandlerTest.Ticket)

      via = Enum.find(rejections, &(&1.feature == "via"))
      assert via.path =~ "via"
      assert via.reason =~ "rejects it"

      # The action itself still imports (name, refreshes), minus the
      # host-provided delegation.
      assert action = Enum.find(spec["actions"], &(&1["name"] == "check_in"))
      refute Map.has_key?(action, "via")
    end

    test "inline editing and sectioned tables are rejected" do
      {:ok, _spec, rejections} = Importer.import(AshA2ui.Test.EditableWordsUI)
      assert Enum.any?(rejections, &(&1.feature == "editable"))

      {:ok, _spec, rejections} = Importer.import(AshA2ui.Test.BucketWordsUI)
      assert Enum.any?(rejections, &(&1.feature == "sections"))
    end
  end

  describe "import/1 — nothing to import" do
    test "a module without an a2ui section is an error, not an empty spec" do
      # (Every resource in the test support carries the extension; a plain
      # module is the honest no-surface case.)
      assert {:error, %{feature: "a2ui"}} = Importer.import(Enum)
    end
  end

  test "Rejection.messages/1 renders one path (feature): reason line per rejection" do
    {:ok, _spec, rejections} = Importer.import(AshA2ui.Test.MinimalUI)

    [line] = Importer.Rejection.messages(rejections)
    assert line =~ "a2ui.surface_id (surface_id):"
    assert line =~ "resolve :surface_id option"
  end
end
