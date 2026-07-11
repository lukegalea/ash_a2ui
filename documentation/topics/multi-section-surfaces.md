# Multi-Section Surfaces

Dashboards and review screens often need several independent tables on one
surface — "new items" and "done items", each with its own read action and
query, where approving a row refreshes only its own section. AshA2ui models
this with **named table components**, a **scoped data model**, and per-action
**`refreshes`** metadata.

## Declaring multiple tables

Give each `:table` component a distinguishing name as the second argument:

```elixir
defmodule MyApp.UI.ReviewUI do
  use AshA2ui.Standalone

  a2ui do
    for_resource MyApp.Review.Item
    surface_id "review"

    component :table, :new_items do
      fields [:name, :count]
      read_action :new_items
      row_actions [:approve, :destroy]
      query :new_q
    end

    component :table, :done_items do
      fields [:name, :state]
      read_action :done_items
    end

    query :new_q do
      search_fields [:name]
      sortable [:name, :count]
      page_size 25
    end

    action :approve do
      refreshes [:new_items]
    end
  end
end
```

Rules (compile-time verified by `AshA2ui.Verifiers.VerifyComponents`):

- `component :table` without a name keeps working — its implicit name is
  `:table`. A surface is **multi-table** exactly when it declares more than
  one `:table` component.
- Only `:table` components may carry a name; component names must be unique;
  at most one `:form` per surface (unchanged this wave).
- Each table has its own `fields`, `read_action`, `row_actions`, and
  (optionally) `query` — queries stay per-table, referenced by name.
- The rendered section heading is the humanized component name
  (`:new_items` → "New items"); a single-table surface keeps the resource
  name as its heading.

## The scoped data model (frozen contract)

Single-table surfaces are byte-for-byte unchanged. On a multi-table surface:

- `/records` is an object keyed by table component name —
  `/records/<component_name>` holds each table's record list (every declared
  table always has a key).
- `/query` is an object with one `/query/<component_name>` entry per
  query-attached table; tables without a query have no key.
- Refreshes target the scoped paths (`/records/new_items`,
  `/query/new_items`), never the whole object — except full data-model
  refreshes (`AshA2ui.Info.build_data_model/2`, PubSub pushes), which write
  the complete keyed objects at `/`.

See [Data Model Conventions](data-model-conventions.md) for the full
reserved-path table.

## Component ids (frozen contract)

Multi-table surfaces infix the table component name right after each id's
leading noun; single-table surfaces keep today's unsuffixed ids:

| Single-table id | Multi-table id |
|---|---|
| `table_heading` | `table_heading_<name>` |
| `records_list` / `record_row` | `records_list_<name>` / `record_row_<name>` |
| `table_cell_<field>` | `table_cell_<name>_<field>` |
| `row_action_<action>_button` | `row_action_<name>_<action>_button` |
| `row_select_button` | `row_select_<name>_button` |
| `query_controls`, `query_search_input`, `query_filter_<f>`, `query_apply_button`, `query_pagination`, `query_prev_button`, `query_next_button`, `query_page_text` | `query_<name>_controls`, `query_<name>_search_input`, `query_<name>_filter_<f>`, `query_<name>_apply_button`, `query_<name>_pagination`, `query_<name>_prev_button`, `query_<name>_next_button`, `query_<name>_page_text` |

Root children order: per table in declaration order — heading, query
controls (if any), records list, pagination (if any) — then the form, the
status text, and the action-result panel.

## Action contexts carry `"component"`

- Row-action buttons and row-select buttons additively include
  `"component": "<component_name>"` in their `invoke`/`select_row` contexts
  (the handler tolerates its absence — older clients keep working).
- The `query` action **requires** `"component"` on multi-table surfaces (the
  emitted controls always send it); its context `"query"` value is that
  table's state map, and the response targets `/records/<name>` +
  `/query/<name>`.
- The carried query state on `invoke`/`submit_form` contexts binds the whole
  `/query` object (`{"path": "/query"}`), i.e. an object keyed by table
  name on multi-table surfaces — success refreshes parse each table's entry
  and fall back to that query's defaults when missing or invalid.

## `refreshes`: scoping success refreshes

By default every successful `submit_form`/`invoke` re-reads and rewrites
**every** table (today's behavior). An `action` entity narrows it:

```elixir
action :approve do
  refreshes [:new_items]
end
```

- `refreshes` lists table component names; each must exist (compile-time
  verified), and the `action` name must be reachable from some component's
  `row_actions` or the form's create/update actions.
- On success of that action, only the named tables' `/records/<name>` (and
  `/query/<name>`) messages are emitted. `/form`, `/errors`, and `/ui/*`
  follow-ups are unaffected.
- An empty `refreshes []` means "refresh no table" — useful for actions whose
  results only surface via `/ui/action_result`.

## PubSub live refresh

`AshA2ui.Info.build_data_model/2` (and therefore the LiveView transport's
PubSub refresh) always covers **all** tables — it re-reads every table with
its query defaults and writes the complete keyed `records`/`query` objects.
