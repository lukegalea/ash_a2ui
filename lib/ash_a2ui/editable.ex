defmodule AshA2ui.Editable do
  @moduledoc """
  Target struct for the `editable` DSL entity (inline cell editing): the
  allowlist of a `:table` component's fields that render as in-row inputs
  committing per cell through the `"edit_cell"` client action, and the
  update action those commits run.

  See the `editable` entity docs on `AshA2ui` and the inline-cell-editing
  section of the multi-section-surfaces topic for the full contract.
  """

  defstruct [
    :update_action,
    fields: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          fields: [atom],
          update_action: atom | nil
        }
end
