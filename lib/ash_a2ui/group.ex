defmodule AshA2ui.Group do
  @moduledoc """
  Target struct for the `group` DSL entity — a labeled section of form
  fields laid out in an N-column grid inside a `:form` component.
  """

  defstruct [
    :name,
    :label,
    fields: [],
    columns: 1,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          fields: [atom],
          columns: pos_integer
        }
end
