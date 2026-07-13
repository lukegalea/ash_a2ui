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
    :row_layout,
    :sections,
    :select_context,
    :context,
    context_filter: [],
    require_context: [],
    row_actions: [],
    nested_forms: [],
    groups: [],
    __spark_metadata__: nil
  ]

  # `as` is an atom in the DSL; the per-section component copies
  # `AshA2ui.Sections.expand/2` produces carry their runtime string name.
  @type t :: %__MODULE__{
          name: :table | :form | :detail,
          as: atom | String.t() | nil,
          fields: [atom] | nil,
          read_action: atom | nil,
          create_action: atom | nil,
          update_action: atom | nil,
          query: atom | nil,
          row_layout: AshA2ui.RowLayout.t() | nil,
          sections: AshA2ui.Sections.t() | nil,
          select_context: atom | nil,
          context: atom | nil,
          context_filter: [{atom, atom}],
          require_context: [atom],
          row_actions: [atom],
          nested_forms: [AshA2ui.NestedForm.t()],
          groups: [AshA2ui.Group.t()]
        }

  @doc """
  The distinguishing key of the component: its `as` name when given
  (`component :table, :new_items`), otherwise its kind
  (`:table` / `:form` / `:detail`).

  Component keys are unique per surface (verified at compile time) and are
  the `<component_name>` segment of multi-table data-model paths
  (`/records/<component_name>`, `/query/<component_name>`). On the
  per-section component copies `AshA2ui.Sections.expand/2` produces, the
  key is the runtime string name.
  """
  @spec key(t()) :: atom | String.t()
  def key(%__MODULE__{as: nil, name: name}), do: name
  def key(%__MODULE__{as: as}), do: as
end
