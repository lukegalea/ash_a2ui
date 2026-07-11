# Contexts and Details

Admin screens are often *selection-driven*: pick a user, see their
practices, pick a practice, see its visits, pick a visit, see its detail.
AshA2ui models this with **surface contexts** — named, server-validated
record selections that scope everything else on the surface — plus
**dependent option sources**, **context-scoped tables**, and **`:detail`
components** for the master/detail pattern.

## Declaring contexts

```elixir
defmodule MyApp.UI.VisitsAdminUI do
  use AshA2ui.Standalone

  a2ui do
    for_resource MyApp.Visits.Visit
    surface_id "visits_admin"

    context :user do
      resource MyApp.Accounts.User
      option_label :email
      option_search [:email, :name]
    end

    context :practice do
      resource MyApp.Practices.Practice
      option_label :name
      depends_on :user
      depends_on_path [:memberships, :user_id]
      auto_select_single true
    end

    context :visit do
      resource MyApp.Visits.Visit
      picker false
    end

    component :detail, :user_card do
      context :user
      fields [:name, :email]
    end

    component :table do
      fields [:patient_name, :status, :inserted_at]
      query :default
      context_filter user_id: :user, practice_id: :practice
      require_context [:user]
      select_context :visit
    end

    component :detail, :visit_detail do
      context :visit
      fields [:patient_name, :status, :note_text]
    end

    query :default do
      search_fields [:patient_name]
      sortable [:inserted_at]
      range_filters [:inserted_at]
      default_sort inserted_at: :desc
      page_size 25
    end
  end
end
```

A `context` is a named record selection over any Ash resource (not
necessarily the surface's). Its option-loading config (`option_label` /
`option_value` / `option_sort` / `option_limit` / `option_search`) works
exactly like a relationship select's. Everything is compile-time verified
by `AshA2ui.Verifiers.VerifyContexts`.

## The emitted picker

Each context with `picker true` (the default) renders a surface-level
composite (ids frozen): a `context_<name>` Column with a label, the current
selection's label + a **Clear** button, a search input + button (only with
`option_search`), and an option `List` over `/options/<name>` whose buttons
select. Pickerless contexts (`picker false`) render nothing — they are
selected through a table's `select_context` row button.

Three client actions drive selection (wire contract, frozen):

| Action | Context | Effect |
|---|---|---|
| `"context_search"` | `{"context": name, "search": str, "contexts": {"path": "/context"}}` | Rewrites `/options/<name>` (dependency-filtered, allowlisted search) |
| `"context_select"` | `{"context": name, "value": id, "contexts": ..., "query": ...}` | Validates the id through an **authorized read**, cascades, re-emits state |
| `"context_clear"` | `{"context": name, "contexts": ..., "query": ...}` | Unselects and cascades |

A selection change emits: the rewritten `/context` map, `/options/<name>`
for every dependent picker the cascade re-derived, `/detail/<context>` for
every changed context with detail components, and a refresh of every table
whose `context_filter` references a changed context (through the carried
query state, like any refresh).

## Dependencies and cascades

`depends_on` + `depends_on_path` make a context dependent on another
(declared **before** it — declaration order doubles as the dependency
order, which also rules out cycles):

- its options are filtered by
  `<depends_on_path's terminal> == <parent's selected value>` — every step
  but the last a public relationship, the last a public attribute
  (to-many paths get exists semantics; `[:owner_id]` works for plain
  `belongs_to` columns),
- while the parent is unselected, its options are `[]`,
- when the parent **changes or clears**, it is cleared and its options
  re-derived — transitively down the chain,
- with `auto_select_single true`, a cascade leaving exactly one option
  selects it automatically (and that counts as a change for *its*
  dependents).

Selection is server-authoritative: the client only ever sends a record id,
and the changed context's id is validated through the context resource's
primary read **with the surface's actor/tenant/authorize? and the
dependency filter applied** — an id the actor cannot read, or one outside
the selected parent's scope, is rejected. Carried values of *other*
contexts are scoping input like query filters (the reads they scope are
themselves authorized); authorization stays in Ash policies.

## Scoping tables

- `context_filter user_id: :user, practice_id: :practice` — ANDs
  `<attribute> == <context's selected value>` onto every read of the table
  (initial load, refreshes, `query` actions) for each **selected** context;
  unselected contexts contribute no filter.
- `require_context [:user]` — until at least one of the named contexts is
  selected, the table renders `[]` and **no read executes** (the query
  state reports `totalCount: 0`). Required contexts must appear in the
  table's `context_filter`.
- `select_context :visit` — adds a per-row button (`row_context_button`)
  dispatching `context_select` for the named context with the row's id: the
  master/detail hook. The context's resource must be the table's resource.

## `:detail` components

A `:detail` component renders its context's selected record: a heading and
one label/value row per field, each value bound to
`/detail/<context>/<field>`. Fields default to the **context resource's**
public attributes and may include public calculations/aggregates (loads are
computed against the context's resource). Multiple details may render the
same context; they share the `/detail/<context>` value.

## Refreshes and transports

Every action context on a context-enabled surface carries the current
`/context` map under `"contexts"` — success refreshes and `query` reads run
under that scope. `AshA2ui.Info.build_surface/2` /
`build_data_model/2` accept `:context_state` (the carried `/context` map)
so full refreshes preserve selections; `AshA2ui.LiveRenderer` tracks the
last pushed `/context` automatically and passes it to PubSub refreshes,
exactly like `:query_state`.

Surfaces without `context` entities are byte-for-byte unchanged (no
`"context"`/`"detail"` keys, no `"contexts"` bindings — frozen contract).

See [Data Model Conventions](data-model-conventions.md) for the reserved
paths and [Queries and Pagination](queries-and-pagination.md) for
`range_filters`, which pairs naturally with context-scoped tables.
