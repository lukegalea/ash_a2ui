defmodule AshA2ui.Component do
  @moduledoc """
  Target struct for the `component` DSL entity.

  FROZEN CONTRACT — parallel tracks code against these fields; do not change
  outside an integration commit.
  """

  defstruct [
    :name,
    :as,
    :fields,
    :read_action,
    :create_action,
    :update_action,
    :query,
    row_actions: [],
    nested_forms: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: :table | :form,
          as: atom | nil,
          fields: [atom] | nil,
          read_action: atom | nil,
          create_action: atom | nil,
          update_action: atom | nil,
          query: atom | nil,
          row_actions: [atom],
          nested_forms: [AshA2ui.NestedForm.t()]
        }

  @doc """
  The distinguishing key of the component: its `as` name when given
  (`component :table, :new_items`), otherwise its kind (`:table` / `:form`).

  Component keys are unique per surface (verified at compile time) and are
  the `<component_name>` segment of multi-table data-model paths
  (`/records/<component_name>`, `/query/<component_name>`).
  """
  @spec key(t()) :: atom
  def key(%__MODULE__{as: nil, name: name}), do: name
  def key(%__MODULE__{as: as}), do: as
end
