defmodule AshA2ui.CatalogAssetImportsTest do
  @moduledoc """
  The merged catalog asset must bundle against every `@a2ui` release a host
  may have installed. `@a2ui/web_core` 0.11.0 exported the basic-catalog
  element classes (`A2uiBasicTextElement`, `A2uiBasicButtonElement`) from
  `v0_9/basic_catalog`; 0.10.x and 0.12.0 do not, and a static import of a
  name the installed package lacks fails the host's esbuild outright. The
  asset therefore resolves those classes at runtime from the custom-element
  registry. This guards against the static import coming back.
  """

  use ExUnit.Case, async: true

  @asset "priv/js/ash_a2ui_catalog.js"

  test "the catalog asset has no static imports" do
    source = File.read!(@asset)

    refute Regex.match?(~r/^\s*import\s/m, source),
           "#{@asset} must not import at module scope; the host passes dependencies in, " <>
             "and the upstream element classes are resolved from customElements"
  end

  test "the upstream Text and Button classes are taken from the registry by the basic catalog's tag" do
    source = File.read!(@asset)

    assert source =~ ~s|upstreamElementClass(basicCatalog, "Text")|
    assert source =~ ~s|upstreamElementClass(basicCatalog, "Button")|
    assert source =~ "customElements.get(tagName)"
  end
end
