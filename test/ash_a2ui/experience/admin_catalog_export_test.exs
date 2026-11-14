defmodule AshA2ui.Experience.AdminCatalogExportTest do
  @moduledoc """
  A table with an `export` block on an admin surface (#114): it stays an
  admin `dataGrid`, and the export controls the basic surface draws (the
  Export CSV Button dispatching the `"export"` action, and the column
  CheckBoxes under `column_select`) sit after the grid, byte-equal to the
  basic ones apart from the catalog qualification. The export through that
  Button still answers with the CSV.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Experience
  alias AshA2ui.Test.ExportContract
  alias AshA2ui.Test.ExportContractsSelectUI
  alias AshA2ui.Test.ExportContractsUI
  alias AshA2ui.Test.Surface

  defp build(module, catalog) do
    [message] =
      AshA2ui.Info.build_surface(module, catalog: catalog, actor: %{role: :admin})

    message
  end

  # What a renderer does with a Button's ashAction: resolve the context's
  # `@path` bindings against the data model and call the agent function.
  defp click(message, button_id) do
    button = Surface.components_by_id(message)[button_id]

    %{"functionCall" => %{"@call" => "ashAction", "catalogId" => catalog_id, "args" => args}} =
      button["action"]

    model = Surface.data_model(message)

    %{
      "version" => "1.0",
      "callAgentFunction" => %{
        "surfaceId" => message["createSurface"]["surfaceId"],
        "functionCallId" => "fc_admin_export",
        "callFunction" => %{
          "@call" => "ashAction",
          "catalogId" => catalog_id,
          "args" => %{args | "context" => resolve(args["context"], model)}
        }
      }
    }
  end

  defp resolve(%{"@path" => "/" <> path}, model),
    do: get_in(model, String.split(path, "/"))

  defp resolve(%{} = map, model), do: Map.new(map, fn {k, v} -> {k, resolve(v, model)} end)
  defp resolve(other, _model), do: other

  defp csv(messages) do
    Enum.find_value(messages, fn
      %{"callRendererFunction" => %{"callFunction" => %{"@call" => "downloadFile"} = call}} ->
        ["data:text/csv;base64," <> base64] = [call["args"]["dataUrl"]]
        Base.decode64!(base64)

      _other ->
        nil
    end)
  end

  test "a table with an export block stays a dataGrid, its export controls after it" do
    message = build(ExportContractsUI, :admin_v1)
    assert_valid_agent_message(message, catalogs: admin_catalogs())

    components = Surface.components_by_id(message)

    assert message["createSurface"]["catalogId"] == Experience.admin_catalog_id()
    assert components["root"]["component"] == "entityPage"
    assert components["data_grid"]["component"] == "dataGrid"
    refute Map.has_key?(components, "records_list")
    refute Map.has_key?(components, "table_heading")

    children = components["root"]["children"]
    assert "export_controls" in children

    assert Enum.find_index(children, &(&1 == "export_controls")) >
             Enum.find_index(children, &(&1 == "data_grid"))

    assert components["export_controls"]["children"] == ["export_button"]
    assert %{"component" => "Button"} = button = components["export_button"]
    assert Surface.event(button)["name"] == "export"
    assert components["export_button_text"]["text"] == "Export CSV"
  end

  test "the admin export controls are the basic surface's, byte-equal" do
    for module <- [ExportContractsUI, ExportContractsSelectUI] do
      admin = Surface.components_by_id(build(module, :admin_v1))
      basic = Surface.components_by_id(build(module, :basic))

      ids = Enum.filter(Map.keys(basic), &String.starts_with?(&1, "export_"))
      assert "export_button" in ids

      for id <- ids do
        assert Surface.unqualified(admin[id]) == basic[id], "#{inspect(module)} #{id} diverged"
      end
    end
  end

  test "a column-selectable export keeps its CheckBoxes and the /export state" do
    message = build(ExportContractsSelectUI, :admin_v1)
    assert_valid_agent_message(message, catalogs: admin_catalogs())

    components = Surface.components_by_id(message)

    assert components["data_grid"]["component"] == "dataGrid"

    assert components["export_controls"]["children"] == [
             "export_column_name",
             "export_column_value",
             "export_column_status",
             "export_button"
           ]

    # CheckBox is one of the basic kinds the admin catalog renders itself
    checkbox = components["export_column_value"]
    assert checkbox["component"] == "CheckBox"
    refute Map.has_key?(checkbox, "@catalogId")
    assert checkbox["value"] == %{"@path" => "/export/table/columns/value"}

    assert Surface.event(components["export_button"])["context"]["columns"] ==
             %{"@path" => "/export/table/columns"}

    assert Surface.data_model(message)["export"] == %{
             "table" => %{"columns" => %{"name" => true, "value" => true, "status" => true}}
           }
  end

  describe "an export through the admin surface's button" do
    setup do
      for {name, value, currency} <- [{"Acme", "1200.50", "CAD"}, {"Beta", "80", "USD"}] do
        Ash.create!(ExportContract, %{name: name, value: value, currency: currency},
          authorize?: false
        )
      end

      :ok
    end

    test "produces the CSV the basic surface's button produces" do
      for {module, header} <- [
            {ExportContractsUI, "Name,Contract value,Status,Currency,Priced name,Line count"},
            {ExportContractsSelectUI, "Name,Value,Status"}
          ] do
        admin = build(module, :admin_v1)
        call = click(admin, "export_button")
        assert_valid_renderer_message(call, catalogs: admin_catalogs())

        assert {:ok, messages} = ActionHandler.handle(module, call, actor: %{role: :admin})
        assert_valid_agent_messages(messages, catalogs: admin_catalogs())

        assert csv(messages) =~ header
        assert csv(messages) =~ "\r\nAcme,1200.50,"
        assert csv(messages) =~ "\r\nBeta,80,"

        basic = build(module, :basic)

        assert {:ok, basic_messages} =
                 ActionHandler.handle(module, click(basic, "export_button"),
                   actor: %{role: :admin}
                 )

        assert csv(messages) == csv(basic_messages)
      end
    end
  end
end
