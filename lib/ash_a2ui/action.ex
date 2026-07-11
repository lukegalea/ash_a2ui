defmodule AshA2ui.Action do
  @moduledoc """
  Target struct for the `action` DSL entity: per-action metadata.

  * `refreshes` names the table components (by component key — the unnamed
    table is `:table`) whose records are refreshed after the named Ash action
    succeeds. `nil` (the default) refreshes every table; `[]` refreshes none.
  * `prompt_fields` declares action arguments/accepts collected from the user
    in a per-row prompt (Modal) before the action is invoked.
  * `visible_when` is a keyword list of per-record equality conditions
    (`nil` means `is_nil`, a list means membership) that gate whether the row
    action is offered — and, mandatorily, whether the handler accepts it.
  """

  defstruct [
    :name,
    :refreshes,
    :prompt_title,
    prompt_fields: [],
    visible_when: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          refreshes: [atom] | nil,
          prompt_fields: [atom],
          prompt_title: String.t() | nil,
          visible_when: [{atom, term}]
        }
end
