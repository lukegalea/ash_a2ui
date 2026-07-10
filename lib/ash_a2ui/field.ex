defmodule AshA2ui.Field do
  @moduledoc """
  Target struct for the `field` DSL entity.

  FROZEN CONTRACT — parallel tracks code against these fields; do not change
  outside an integration commit.
  """

  defstruct [
    :name,
    :label,
    :widget,
    :format,
    order: 0,
    hidden: false,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          widget: atom | nil,
          format: atom | nil,
          order: non_neg_integer,
          hidden: boolean
        }
end
