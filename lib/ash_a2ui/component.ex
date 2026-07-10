defmodule AshA2ui.Component do
  @moduledoc """
  Target struct for the `component` DSL entity.

  FROZEN CONTRACT — parallel tracks code against these fields; do not change
  outside an integration commit.
  """

  defstruct [
    :name,
    :fields,
    :read_action,
    :create_action,
    :update_action,
    :query,
    row_actions: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: :table | :form,
          fields: [atom] | nil,
          read_action: atom | nil,
          create_action: atom | nil,
          update_action: atom | nil,
          query: atom | nil,
          row_actions: [atom]
        }
end
