defmodule AshA2ui.V10ConformanceTest do
  @moduledoc """
  The executable A2UI v1.0 spec, part 1: the upstream specification's own
  schema test suites (vendored verbatim in priv/a2ui/v1_0/test/cases, see
  priv/a2ui/v1_0/NOTES.md), run against the same resolved schemas every
  encoder/handler test validates with.

  Each suite file is `{"schema": file, "catalog": optional alias,
  "tests": [{"description", "valid", "data"}]}` — the exact corpus the
  reference `ajv` runner (specification/v1_0/test/run_tests.py) executes.
  `contact_form_example.jsonl` is a complete valid v1.0 message stream,
  validated line by line.

  ex_json_schema implements draft-7, so draft-2020-12-only keywords
  (`unevaluatedProperties`) are ignored: negative cases that *only* violate
  such keywords validate here even though the reference runner rejects them.
  Those cases are listed (exhaustively, by description) in
  @draft7_invisible_failures and asserted to be exactly the known set — if a
  schema update shrinks or grows the set, this test fails and the list must
  be re-audited. Every one of them is about extra/unevaluated properties;
  the encoder-facing rules they express (no `returnType`/`callableFrom` on
  wire FunctionCalls, no unknown envelope keys) are covered by explicit
  assertions in v1_0_encoder_test.exs and below.
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Test.SchemaHelper

  @cases_dir Application.app_dir(:ash_a2ui, ["priv", "a2ui", "v1_0", "test", "cases"])

  # Upstream-invalid cases whose only violation is a draft-2020-12
  # `unevaluatedProperties` constraint the draft-7 engine cannot see. Keyed
  # by {suite file, description}. Audited 2026-07-13: all twelve are extra
  # unevaluated keys — a `returnType` on a wire FunctionCall (nine cases; the
  # rule the v1.0 encoder covers with an explicit no-returnType-on-the-wire
  # assertion), removed v0.9-era component props (`enabled`, `primary`), and
  # one surplus `args` key.
  @draft7_invisible_failures MapSet.new([
                               {"button_checks.json",
                                "Button with deprecated enabled property (should fail)"},
                               {"button_checks.json",
                                "Button with invalid check structure (invalid returnType)"},
                               {"button_checks.json",
                                "Button with deprecated 'primary' property (should fail)"},
                               {"checkable_components.json",
                                "TextField with invalid function returnType in check"},
                               {"function_catalog_validation.json",
                                "required: Invalid returnType"},
                               {"function_catalog_validation.json", "regex: Invalid returnType"},
                               {"function_catalog_validation.json",
                                "formatString: Invalid returnType"},
                               {"function_catalog_validation.json",
                                "openUrl: Invalid returnType"},
                               {"function_catalog_validation.json", "and: Invalid returnType"},
                               {"function_catalog_validation.json", "not: Invalid returnType"},
                               {"function_catalog_validation.json",
                                "email: Invalid args count (too many)"},
                               {"function_catalog_validation.json", "@index: Invalid returnType"}
                             ])

  for file <-
        @cases_dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".json")) |> Enum.sort() do
    suite = @cases_dir |> Path.join(file) |> File.read!() |> Jason.decode!()
    schema_file = Map.fetch!(suite, "schema")
    catalog = Map.get(suite, "catalog")

    describe "upstream suite #{file}" do
      for {test_case, index} <- Enum.with_index(Map.fetch!(suite, "tests")) do
        description = Map.get(test_case, "description", "case #{index}")
        expected_valid = Map.fetch!(test_case, "valid")

        invisible =
          MapSet.member?(@draft7_invisible_failures, {file, description})

        @tag :v1_0_conformance
        test "[#{if expected_valid, do: "valid", else: "invalid"}] #{description}" do
          schema =
            SchemaHelper.resolved_schema(
              :v1_0,
              unquote(schema_file),
              catalog: unquote(catalog)
            )

          result =
            SchemaHelper.validate(schema, unquote(Macro.escape(Map.fetch!(test_case, "data"))))

          case {unquote(expected_valid), unquote(invisible)} do
            {true, _} ->
              assert result == :ok,
                     "upstream-valid case failed validation: #{inspect(result)}"

            {false, false} ->
              assert match?({:error, _}, result),
                     "upstream-invalid case unexpectedly validated (if the violation is " <>
                       "draft-2020-12-only, add it to @draft7_invisible_failures with an audit note)"

            {false, true} ->
              # Documented draft-7 blind spot: must (still) pass here.
              assert result == :ok,
                     "case listed in @draft7_invisible_failures now fails under draft-7 — " <>
                       "remove it from the list: #{inspect(result)}"
          end
        end
      end
    end
  end

  describe "upstream contact_form_example.jsonl stream" do
    test "every line is a valid v1.0 server->client message" do
      lines =
        @cases_dir
        |> Path.join("contact_form_example.jsonl")
        |> File.read!()
        |> String.split("\n", trim: true)

      assert lines != []

      for {line, index} <- Enum.with_index(lines, 1) do
        message = Jason.decode!(line)

        assert SchemaHelper.validate(SchemaHelper.server_schema(:v1_0), message) == :ok,
               "line #{index} of the upstream example stream failed validation"
      end
    end
  end

  describe "v0.9.1 schemas are untouched" do
    test "the v0.9.1 assertion helpers still validate a v0.9.1 message" do
      SchemaHelper.assert_valid_server_message(%{
        "version" => "v0.9.1",
        "updateDataModel" => %{"surfaceId" => "s", "path" => "/x", "value" => 1}
      })
    end

    test "a v0.9.1 envelope is not a valid v1.0 message and vice versa" do
      v091 = %{
        "version" => "v0.9.1",
        "updateDataModel" => %{"surfaceId" => "s", "path" => "/x", "value" => 1}
      }

      v10 = %{
        "version" => "v1.0",
        "updateDataModel" => %{"surfaceId" => "s", "path" => "/x", "value" => 1}
      }

      assert {:error, _} = SchemaHelper.validate(SchemaHelper.server_schema(:v1_0), v091)
      assert {:error, _} = SchemaHelper.validate(SchemaHelper.server_schema(:v0_9_1), v10)
      SchemaHelper.assert_valid_server_message(v10, :v1_0)
    end
  end
end
