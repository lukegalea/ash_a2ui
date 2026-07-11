defmodule AshA2ui.NestedForm do
  @moduledoc """
  Target struct for the `nested_form` DSL entity (declared inside a `:form`
  component).

  `name` is the **action argument** managed by a `manage_relationship` change
  on the form's create/update action; the relationship, destination, and
  interaction mode are resolved from that change by `AshA2ui.ResolvedView`
  (via `Ash.Changeset.ManagedRelationshipHelpers`).
  """

  defstruct [
    :name,
    :label,
    :fields,
    :option_label,
    :option_value,
    :option_sort,
    option_limit: 100,
    option_search: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          fields: [atom] | nil,
          option_label: atom | nil,
          option_value: atom | nil,
          option_sort: atom | nil,
          option_limit: pos_integer,
          option_search: [atom]
        }
end
