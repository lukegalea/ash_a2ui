defmodule AshA2ui.Test.EditableWordsUI do
  @moduledoc """
  Fixture surface for inline cell editing (v0.9.1): a single table over
  `AshA2ui.Test.BucketWord` whose `:replacement` column commits per cell
  through `update_replacement` (which validates lowercase — the error-mirror
  proving case).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "editable_words"

    component :table do
      fields [:word, :replacement]

      editable do
        fields [:replacement]
        update_action :update_replacement
      end
    end
  end
end

defmodule AshA2ui.Test.EditableWordsV1UI do
  @moduledoc """
  The same inline-cell-editing fixture surface as
  `AshA2ui.Test.EditableWordsUI`, but with `spec_version "1.0"` — validates
  editable cells against the v1.0 schemas and the per-cell actionResponse
  handshake.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "editable_words_v1"
    spec_version("1.0")

    component :table do
      fields [:word, :replacement]

      editable do
        fields [:replacement]
        update_action :update_replacement
      end
    end
  end
end
