defmodule AshA2ui.Test.SchemaHelperTest do
  @moduledoc """
  Sanity check for the vendored A2UI v0.9.1 schemas + SchemaHelper: validates
  hand-written minimal messages (per the spec's examples) in both directions,
  proving that schema loading, cross-file $ref resolution (message schema ->
  basic catalog -> common types) and the assertion helpers all work.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  test "hand-written minimal valid messages validate against the vendored schemas" do
    assert_valid_server_message(%{
      "version" => "v0.9.1",
      "createSurface" => %{
        "surfaceId" => "kitchen_sink",
        "catalogId" => "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"
      }
    })

    assert_valid_server_message(%{
      "version" => "v0.9.1",
      "updateComponents" => %{
        "surfaceId" => "kitchen_sink",
        "components" => [
          %{"id" => "root", "component" => "Column", "children" => ["title"]},
          %{"id" => "title", "component" => "Text", "text" => "Hello A2UI"}
        ]
      }
    })

    assert_valid_server_message(%{
      "version" => "v0.9.1",
      "updateDataModel" => %{
        "surfaceId" => "kitchen_sink",
        "path" => "/",
        "value" => %{"records" => []}
      }
    })

    assert_valid_server_message(%{
      "version" => "v0.9.1",
      "deleteSurface" => %{"surfaceId" => "kitchen_sink"}
    })

    assert_valid_client_message(%{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "submit_form",
        "surfaceId" => "kitchen_sink",
        "sourceComponentId" => "form_submit",
        "timestamp" => "2026-07-10T12:00:00Z",
        "context" => %{"name" => "A provider"}
      }
    })
  end

  test "invalid messages are rejected" do
    # missing catalogId
    assert {:error, _} =
             ExJsonSchema.Validator.validate(server_schema(), %{
               "version" => "v0.9.1",
               "createSurface" => %{"surfaceId" => "x"}
             })

    # action envelope missing required context
    assert {:error, _} =
             ExJsonSchema.Validator.validate(client_schema(), %{
               "version" => "v0.9.1",
               "action" => %{
                 "name" => "submit_form",
                 "surfaceId" => "x",
                 "sourceComponentId" => "y",
                 "timestamp" => "2026-07-10T12:00:00Z"
               }
             })
  end
end
