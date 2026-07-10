defmodule AshA2ui.Query do
  @moduledoc """
  Target struct for the `query` DSL entity: a named, server-enforced allowlist
  for search, sorting, equality filters, and pagination.

  A `query` never lets clients supply arbitrary sort/filter parameters — the
  `"query"` client action is validated against these lists (see
  `AshA2ui.QueryRunner`) and anything not declared here is rejected before
  Ash is called.
  """

  defstruct [
    :name,
    search_fields: [],
    sortable: [],
    filters: [],
    default_sort: [],
    page_size: 25,
    max_page_size: 100,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          search_fields: [atom],
          sortable: [atom],
          filters: [atom],
          default_sort: [{atom, :asc | :desc}],
          page_size: pos_integer,
          max_page_size: pos_integer
        }
end
