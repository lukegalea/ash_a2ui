defmodule Mix.Tasks.AshA2ui.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  test "adds :ash_a2ui to import_deps and Spark.Formatter to plugins in .formatter.exs" do
    igniter =
      test_project()
      |> Igniter.compose_task("ash_a2ui.install", [])

    content =
      igniter.rewrite
      |> Rewrite.source!(".formatter.exs")
      |> Rewrite.Source.get(:content)

    assert content =~ ":ash_a2ui"
    assert content =~ "Spark.Formatter"
  end

  test "is idempotent for a project that already has a formatter config" do
    igniter =
      test_project(
        files: %{
          ".formatter.exs" => """
          [
            import_deps: [:ash_a2ui],
            plugins: [Spark.Formatter],
            inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
          ]
          """
        }
      )
      |> Igniter.compose_task("ash_a2ui.install", [])

    assert_unchanged(igniter, ".formatter.exs")
  end
end
