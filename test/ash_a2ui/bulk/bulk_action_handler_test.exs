defmodule AshA2ui.Bulk.BulkActionHandlerTest do
  @moduledoc """
  A2UI-104: `bulk_invoke` runs the action once per selected record through
  the single-row dispatch, reports the outcome at `/bulk/<table>/result`
  and refreshes once; `bulk_select` rewrites the page's selection from an
  authorized re-read.
  """

  # Shared ETS fixtures and the experience application env.
  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper
  import AshA2ui.Test.BulkHelpers

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.BulkTasksUI

  setup do
    Application.put_env(:ash_a2ui, :experience_version, 2)
    on_exit(fn -> Application.delete_env(:ash_a2ui, :experience_version) end)

    reset!()
    %{project: project!("Apollo")}
  end

  defp bulk_invoke(action, rows, project) do
    ActionHandler.handle(
      BulkTasksUI,
      envelope("bulk_invoke", %{
        "action" => action,
        "component" => "table",
        "records" => rows,
        "contexts" => contexts(project)
      }),
      actor: actor()
    )
  end

  @tag ac: "A2UI-104/AC-2"
  test "runs the action on every selected record", %{project: project} do
    [a, b, c, d] =
      for title <- ["Alpha", "Bravo", "Charlie", "Delta"],
          do: task!(title, %{project_id: project.id})

    assert {:ok, messages} = bulk_invoke("approve", rows([a, b, c, d], [a, b, c]), project)
    Enum.each(messages, &assert_valid_server_message/1)

    # each selected record went through the action as the actor
    assert Enum.map([a, b, c, d], &reload!(&1).status) == [:approved, :approved, :approved, :open]

    assert value_at(messages, "/bulk/table/result") == %{
             "ok" => 3,
             "failed" => 0,
             "refused" => 0,
             "skipped" => 0,
             "errors" => []
           }

    # the target table is refreshed exactly once, every row deselected
    assert Enum.count(paths(messages), &(&1 == "/records")) == 1
    records = value_at(messages, "/records")
    assert length(records) == 4
    assert Enum.all?(records, &(&1["_selected"] == false))

    assert value_at(messages, "/ui/status") == "Approve: 3 of 3 selected records done."
    assert value_at(messages, "/ui/feedback")["kind"] == "success"
  end

  @tag ac: "A2UI-104/AC-5"
  test "visible_when skips records per record", %{project: project} do
    open_one = task!("Alpha", %{project_id: project.id})
    open_two = task!("Bravo", %{project_id: project.id})
    rejected = task!("Charlie", %{project_id: project.id, status: :rejected})

    tasks = [open_one, open_two, rejected]
    assert {:ok, messages} = bulk_invoke("approve", rows(tasks, tasks), project)

    # approve is visible_when status: :open — the same predicate the
    # single-row invoke enforces
    assert reload!(open_one).status == :approved
    assert reload!(open_two).status == :approved
    assert reload!(rejected).status == :rejected

    assert %{"ok" => 2, "skipped" => 1, "refused" => 0, "failed" => 0} =
             value_at(messages, "/bulk/table/result")

    assert value_at(messages, "/ui/status") ==
             "Approve: 2 of 3 selected records done; 1 skipped."

    assert value_at(messages, "/ui/feedback")["kind"] == "warning"

    # the single-row invoke refuses the same record
    assert {:error, _messages} =
             ActionHandler.handle(
               BulkTasksUI,
               envelope("invoke", %{"action" => "approve", "recordId" => rejected.id}),
               actor: actor()
             )
  end

  @tag ac: "A2UI-104/AC-6"
  test "partial failure is reported not rolled back", %{project: project} do
    good_one = task!("Alpha", %{project_id: project.id})
    bad = task!("Bravo", %{project_id: project.id, score: -1})
    good_two = task!("Charlie", %{project_id: project.id})

    tasks = [good_one, bad, good_two]
    assert {:ok, messages} = bulk_invoke("approve", rows(tasks, tasks), project)
    Enum.each(messages, &assert_valid_server_message/1)

    assert reload!(good_one).status == :approved
    assert reload!(good_two).status == :approved
    assert reload!(bad).status == :open

    assert %{
             "ok" => 2,
             "failed" => 1,
             "refused" => 0,
             "skipped" => 0,
             "errors" => [%{"id" => bad_id, "message" => message}]
           } = value_at(messages, "/bulk/table/result")

    assert bad_id == bad.id
    assert message =~ ~r/^score: must be greater than or equal to 0/

    assert value_at(messages, "/ui/status") ==
             "Approve: 2 of 3 selected records done; 1 failed."

    assert value_at(messages, "/ui/feedback") == %{
             "kind" => "warning",
             "message" => "Approve: 2 of 3 selected records done; 1 failed."
           }
  end

  test "a run that writes nothing is an error and refreshes nothing", %{project: project} do
    bad = task!("Bravo", %{project_id: project.id, score: -1})

    assert {:error, messages} = bulk_invoke("approve", rows([bad], [bad]), project)

    assert %{"ok" => 0, "failed" => 1} = value_at(messages, "/bulk/table/result")
    refute "/records" in paths(messages)
    assert value_at(messages, "/ui/feedback")["kind"] == "error"
  end

  test "a v1.0 run answers with the result in the action response", %{project: project} do
    a = task!("Alpha", %{project_id: project.id})

    message =
      envelope("bulk_invoke", %{
        "action" => "reject",
        "component" => "table",
        "records" => rows([a], [a])
      })
      |> put_in(["action", "actionId"], "act-1")

    assert {:ok, [response | messages]} =
             ActionHandler.handle(BulkTasksUI, message, actor: actor(), spec_version: "1.0")

    Enum.each([response | messages], &assert_valid_server_message(&1, :v1_0))

    assert %{"value" => %{"status" => "ok", "result" => %{"ok" => 1}}} =
             response["actionResponse"]

    assert reload!(a).status == :rejected
  end

  @tag ac: "A2UI-104/AC-9"
  test "select page and clear rewrite selection", %{project: project} do
    visible = for title <- ["Alpha", "Bravo"], do: task!(title, %{project_id: project.id})
    _secret = task!("Charlie", %{project_id: project.id, secret: true})

    select = fn selected ->
      ActionHandler.handle(
        BulkTasksUI,
        envelope("bulk_select", %{
          "component" => "table",
          "selected" => selected,
          # the carried rows are never echoed back: a forged row is ignored
          "records" => [%{"id" => "forged", "title" => "Forged", "_selected" => true}],
          "contexts" => contexts(project)
        }),
        actor: actor()
      )
    end

    assert {:ok, messages} = select.(true)
    Enum.each(messages, &assert_valid_server_message/1)

    records = value_at(messages, "/records")

    assert Enum.map(records, & &1["id"]) |> Enum.sort() ==
             Enum.map(visible, & &1.id) |> Enum.sort()

    assert Enum.all?(records, &(&1["_selected"] == true))

    assert {:ok, messages} = select.(false)
    records = value_at(messages, "/records")
    assert length(records) == 2
    assert Enum.all?(records, &(&1["_selected"] == false))

    # nothing was written
    assert Enum.all?(visible, &(reload!(&1).status == :open))
  end
end
