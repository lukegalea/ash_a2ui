# Queries and Pagination

Real tables need search, filtering, sorting, and pagination — but a wire
protocol must never accept arbitrary client query parameters. AshA2ui's
answer is the `query` DSL entity: a **named, declarative allowlist the
server enforces**. The client only ever references the query by name (via
the table component) and submits state; every requested search, sort,
filter, and page value is validated against the declaration and anything
not declared is rejected before Ash is called.

## Declaring a query

```elixir
a2ui do
  query :default do
    search_fields [:subject]              # string attributes, ci-contains, OR'd
    sortable [:subject, :inserted_at]     # the only sortable fields
    filters [:status]                     # equality filters on these fields
    default_sort inserted_at: :desc
    page_size 25                          # default page size
    max_page_size 100                     # hard clamp for client requests
  end

  component :table do
    fields [:subject, :status, :inserted_at]
    query :default
  end
end
```

All referenced fields must be **plain public attributes** (and
`search_fields` must be string-typed) — verified at compile time, like every
other DSL reference. Relationship-sourced `source` columns (see
[Relationship Rendering](relationships.md)) are render-only and rejected in
query allowlists. A table without a `query` behaves exactly as before: all
records, no query controls.

## What gets emitted

When the table declares a query, the encoder adds to the component tree:

- a search `TextField` bound to `/query/search` (omitted when there are no
  `search_fields`),
- one `ChoicePicker` per filter bound to `/query/filters/<name>` with an
  `"All"` (empty value) option first — options come from the attribute's
  `one_of` constraints (or True/False for booleans),
- an **Apply** button and **Previous/Next** pagination buttons.

All of them dispatch the `"query"` client action. The wire contract:

```json
{
  "action": {
    "name": "query",
    "context": {
      "query": { "search": "...", "filters": {...}, "sort": {...}, "page": 2, "pageSize": 25 },
      "page": 1,
      "pageDelta": 1
    }
  }
}
```

- `"query"` is the current `/query` data-model map (the controls bind it via
  `{"path": "/query"}`).
- `"page"` is an optional literal override — the Apply button sends
  `"page": 1` so a new search/filter starts from the first page.
- `"pageDelta"` is an optional relative change — the Previous/Next buttons
  send `-1` / `1`. Precedence: literal `page` wins, then `page + pageDelta`,
  always clamped to ≥ 1.

The server answers with two `updateDataModel` messages: `/records` (the
page) and `/query` (the authoritative state — see
[Data Model Conventions](data-model-conventions.md) for the exact shape).

## Enforcement (the allowlist)

`AshA2ui.QueryRunner` validates the context before anything touches Ash:

- a sort field not in `sortable` → rejected,
- a filter name not in `filters` → rejected,
- a filter value that doesn't cast to the attribute's type/constraints →
  rejected,
- a search on a query with no `search_fields` → rejected,
- requested `pageSize` is clamped to `1..max_page_size`, `page` to ≥ 1.

Rejections return `{:error, [message]}` with a human-readable explanation on
`/ui/status` — the same convention as every other handler error — and **no
read is executed**. Unknown extra keys inside the submitted `"query"` map
(such as the echoed `totalCount`/`hasMore`) are ignored.

Search builds a case-insensitive `contains` expression OR'd across the
declared `search_fields`; filters are equality (`in` when a list of values
is submitted, e.g. from a `multipleSelection` ChoicePicker); sort falls back
to `default_sort` when the client requests none.

## Pagination mechanism

Pagination uses plain `Ash.Query.limit/2` + `Ash.Query.offset/2` with
`limit = page_size + 1`: the extra row only signals `hasMore` and is dropped
from the results. This deliberately works on **any** data layer without
requiring the read action to enable Ash's `pagination` — resources need no
changes. `totalCount` is computed with `Ash.count/2` on the filtered,
unpaginated query and degrades to `null` on data layers without count
support. The primary key is appended as a sort tiebreaker so pages are
stable under equal sort values.

## Writes respect the active query

On query-enabled surfaces the emitted `submit_form` and row-action `invoke`
contexts also carry `"query": {"path": "/query"}`. After a successful write,
the refresh re-runs the *current* query (same search/filters/sort/page) and
includes a fresh `/query` message — the user stays on their page with their
filters intact. A missing or invalid carried query state falls back to the
query's declared defaults; the write itself never fails over refresh state.

PubSub-driven refreshes preserve the query too: `AshA2ui.LiveRenderer`
tracks the last `/query` state it pushed to the client and passes it to
`AshA2ui.Info.build_data_model/2` as `:query_state` (validated against the
allowlist like any client input; invalid state falls back to the declared
defaults). A live refresh therefore re-runs the user's current
search/filters/sort/page instead of resetting the surface. Callers driving
`build_data_model/2` directly get the default (page 1, default sort) unless
they pass `:query_state` themselves.

## Limitations (v0)

- Filters are equality-only (`filters [:status]` = "status equals the
  submitted value"). Ranged/custom filters are roadmap.
- One query per table; queries are per-surface, not shared.
- No sort UI is emitted (sort arrives via the `"query"` action, e.g. from an
  agent or custom client); the allowlist still applies.
