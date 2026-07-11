defmodule AshA2ui.Action do
  @moduledoc """
  Target struct for the `action` DSL entity: per-action refresh metadata.

  `refreshes` names the table components (by component key — the unnamed
  table is `:table`) whose records are refreshed after the named Ash action
  succeeds. Actions without an `action` entity refresh every table (the
  default behavior).
  """

  defstruct [
    :name,
    refreshes: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          refreshes: [atom]
        }
end
