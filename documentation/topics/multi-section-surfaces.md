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

## Dynamic table sets: `sections`

Sometimes the sections themselves are data — one table per category, per
bucket, per team, where the set of sections is only known at render time. A
`sections` block turns a `:table` component into a **template** expanded at
runtime into one concrete table per record of a `source` resource:

```elixir
component :table, :per_bucket do
  fields [:word, :replacement]
  read_action :bucketed
  query :bucket_q

  sections do
    source MyApp.Dictionary.Bucket   # enumerates the sections
    scope_by :bucket_id              # the table's rows are filtered by this
    label :name                      # each section's heading
  end
end
```

At render (and action-handling) time the source is read — actor-scoped and
authorized like any other read — and each returned record becomes one table:

- **Runtime names**: `<template_key>_<sanitized value>` (every
  non-alphanumeric run of the section's `value` — default: the source's
  primary key — becomes `_`). All the multi-table contracts above apply
  under those names: `/records/<runtime name>`, `/query/<runtime name>`,
  `"component"` in emitted action contexts, component-id infixes.
- A surface with a sectioned table is **always multi-table** (even when the
  source yields zero or one section at runtime), so path shapes never change
  between renders.
- Each section's reads AND `scope_by == <section value>` onto the declared
  `read_action` — search/filters/pagination stay per-section.
- Headings show the section record's `label` attribute (not the humanized
  component name).
- `refreshes` may target the template key (`refreshes [:per_bucket]`) — it
  fans out to every runtime table of the set.
- Options: `value` (section value/name attribute; required when the source's
  primary key is composite), `read_action`, `sort` (defaults to the label),
  `limit` (max sections, default 50). `sections` cannot combine with
  `select_context` (compile-time verified by
  `AshA2ui.Verifiers.VerifySections`).

## Inline cell editing: `editable`

An `editable` block renders an allowlist of a table's fields as in-row
inputs committing **per cell** — no form roundtrip:

```elixir
component :table, :per_bucket do
  fields [:word, :replacement]

  editable do
    fields [:replacement]
    update_action :update_replacement   # defaults to the primary update
  end
end

action :update_replacement do
  refreshes [:per_bucket]
end
```

- Each editable cell is a TextField bound to the template-relative field
  path (edits stay client-side until committed), a Save button dispatching
  the **`"edit_cell"`** client action (context: `recordId`, `component`,
  `field`, and the field's current `value`), and an error Text bound to the
  row's reserved `_error_<field>` key.
- The server runs `update_action` on the identified record with just that
  field's value, cast like any client input. The edited field must be in
  the declared allowlist — like `row_actions`, that list is the
  authorization surface for client-triggered commits.
- On success the standard refresh conventions apply (the action's
  `refreshes` metadata included). On a validation error the standard
  `/errors/<field>` + status writes are joined by a **row-scoped mirror**:
  the table's records are rewritten with the failing row carrying the
  submitted value (for in-place correction) and the message at
  `_error_<field>`.
- On v1.0 surfaces the per-action `actionResponse` handshake gives each
  cell pending→settled feedback (the shipped hook holds the pending state
  per `actionId`).
- Not supported together with a `row_layout` (card rows render read-only
  meta values); every editable field must be a table field accepted by the
  update action (compile-time verified by
  `AshA2ui.Verifiers.VerifyEditable`).

Editable cells compose with dynamic table sets: on an expanded table the
Save buttons carry the runtime `component` name, and `refreshes` targeting
the template key covers the whole set.
