defmodule AshA2ui.Context do
  @moduledoc """
  Target struct for the `context` DSL entity: a named, surface-level record
  selection that scopes other sections.

  A context is picked by the user (through an emitted searchable picker, or a
  table row's `select_context` button) and its selected record's id becomes
  server-side scoping input: tables reference contexts through
  `context_filter`, dependent contexts through `depends_on`, and `:detail`
  components render the selected record. The client only ever sends a record
  id — every selection round-trips through an authorized read.
  """

  defstruct [
    :name,
    :resource,
    :label,
    :option_label,
    :option_value,
    :option_sort,
    :depends_on,
    :depends_on_path,
    option_limit: 100,
    option_search: [],
    auto_select_single: false,
    picker: true,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          resource: module,
          label: String.t() | nil,
          option_label: atom | nil,
          option_value: atom | nil,
          option_sort: atom | nil,
          option_limit: pos_integer,
          option_search: [atom],
          depends_on: atom | nil,
          depends_on_path: [atom] | nil,
          auto_select_single: boolean,
          picker: boolean
        }
end
