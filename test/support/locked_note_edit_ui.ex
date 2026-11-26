defmodule AshA2ui.Test.LockedNoteEditUI do
  @moduledoc """
  Standalone UI fixture for saving two cards of one record: the note's title
  and its body are separate editable cards on the same context, both saved
  by the save bar through the note's `:edit`, which carries an optimistic
  lock.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.LockedNote
    surface_id "locked_note_edit"

    context :note do
      resource AshA2ui.Test.LockedNote
      option_label :title
      picker false
    end

    component :detail, :heading do
      context :note
      fields [:title]

      editable do
        fields [:title]
        update_action :edit
      end
    end

    component :detail, :content do
      context :note
      fields [:body]

      editable do
        fields [:body]
        update_action :edit
      end
    end

    save_bar do
      context :note
    end
  end
end
