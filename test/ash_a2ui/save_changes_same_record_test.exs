defmodule AshA2ui.SaveChangesSameRecordTest do
  @moduledoc """
  Two editable cards of one record, saved together: each card's update runs
  from the row the previous card's save left, so an update action with an
  optimistic lock is not refused as stale by the save before it.
  """

  # Not async: the catalog is application config.
  use ExUnit.Case, async: false

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.{LockedNote, LockedNoteEditUI, Messages}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      Ets.stop(LockedNote)
    end)

    %{note: Ash.create!(LockedNote, %{title: "Draft", body: "First body"}, authorize?: false)}
  end

  defp save(note, edits) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    context = %{
      "edits" =>
        Map.new(edits, fn {card, values} ->
          {card, %{"recordId" => note.id, "values" => values}}
        end),
      "choice" => "save",
      "recordId" => note.id,
      "contexts" => %{"note" => %{"value" => note.id, "label" => note.title}}
    }

    ActionHandler.handle(
      LockedNoteEditUI,
      Messages.call("save_changes", "locked_note_edit", context),
      authorize?: false
    )
  end

  defp reload(note), do: Ash.get!(LockedNote, note.id, authorize?: false)

  test "both cards save, each from the row the other left", %{note: note} do
    assert {:ok, _messages} =
             save(note, %{"heading" => %{"title" => "Final"}, "content" => %{"body" => "Second"}})

    saved = reload(note)
    assert saved.title == "Final"
    assert saved.body == "Second"
    assert saved.version == 3
  end

  test "one card saves as before", %{note: note} do
    assert {:ok, _messages} = save(note, %{"content" => %{"body" => "Second"}})

    saved = reload(note)
    assert saved.body == "Second"
    assert saved.version == 2
  end
end
