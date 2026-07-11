# Relationship Rendering

AshA2ui renders three relationship shapes: **form selects** for `belongs_to`
relationships (pick the parent record from a dropdown — searchable when the
option set is large), **nested relationship forms** driven by
`manage_relationship` actions (edit or pick-and-attach related records inside
the parent form), and **table columns read through loaded relationships**
(show the author's email on a post row). All are server-resolved — the client
only ever sees plain options and plain values.

## Form selects for `belongs_to`

### Inference — the zero-config case

When a form field's name matches a `belongs_to` relationship's
`source_attribute`, the field renders as a `ChoicePicker` instead of a
`TextField` — no DSL needed:

```elixir
relationships do
  belongs_to :payment_group, MyApp.Billing.PaymentGroup, public?: true
end

a2ui do
  component :form do
    fields [:name, :payment_group_id]   # payment_group_id -> ChoicePicker
    create_action :create
    update_action :update
  end
end
```

`:payment_group_id` is the relationship's `source_attribute`, so AshA2ui
resolves the select automatically: options come from
`MyApp.Billing.PaymentGroup`, submitted values are cast back to the
attribute's type (UUID etc.) by the normal Ash changeset machinery.

### The `field` options

For everything the inference doesn't cover, the `field` entity takes:

```elixir
field :payment_group_id do
  relationship :payment_group   # explicit override; needed for action-argument fields
  option_label :name            # destination attribute shown as the label
  option_value :id              # destination attribute submitted as the value
  option_sort :name             # destination attribute options are sorted by (asc)
  option_limit 100              # max options loaded
end
```

Defaults:

- `option_label` — the first existing public attribute of
  `[:name, :title, :label, :username, :email]` on the destination, else the
  destination's primary key.
- `option_value` — the destination's primary key. A destination with a
  **composite** primary key has no inferable value; the verifier requires an
  explicit `option_value` at compile time.
- `option_sort` — the resolved `option_label`.
- `option_limit` — 100. Option sets larger than the limit are truncated;
  genuinely large sets should declare `option_search` (below) instead of a
  raised limit.

All of `option_label` / `option_value` / `option_sort` must be public
attributes of the destination, and `relationship` must name a real
relationship — verified at compile time.

### How options are loaded

At `build_surface`/`build_data_model` time, AshA2ui reads the destination
through its **primary read action with the same `actor:` / `tenant:` /
`authorize?:` options as the surface itself** — policies apply to option
reads exactly like every other read. The loaded list lands in two places:

- **inline** in the emitted `ChoicePicker`'s `options` (the v0.9.1 basic
  catalog requires a literal options array), and
- at the reserved **`/options/<field>`** data-model path as
  `[{"label": string, "value": string}]` — the programmatic mirror (see
  [Data Model Conventions](data-model-conventions.md)).

Action follow-ups don't reload options; full refreshes
(`build_data_model/2`, PubSub pushes) do.

### Submitting

Selected values travel back through `/form/<field>` as strings (single-select
ChoicePickers may bind one-element string lists — the handler unwraps them),
and `AshA2ui.ActionHandler` casts them to the accepted attribute or argument
type through the normal Ash changeset.

## Searchable selects (`option_search`)

For destinations with thousands of records, a static picker is useless.
Declaring `option_search` turns the select into a **searchable select**:

```elixir
field :author_id do
  option_search [:name, :email]   # public string attributes of the destination
end
```

Every entry must be a **public string-typed attribute** of the destination
(verified at compile time); the search is a case-insensitive contains, OR'd
across the declared fields — the same semantics as a query's
`search_fields`.

### What is emitted instead of a ChoicePicker

The v0.9.1 basic-catalog `ChoicePicker` only accepts a *literal* inline
options array — its options cannot be refreshed through a data binding, so
a searchable ChoicePicker is not protocol-expressible. AshA2ui instead emits
a composite (a `Column` with the id `form_select_<field>`):

- a `Text` showing the current selection's label, bound to
  `/select/<field>/label`,
- a search `TextField` bound to `/select/<field>/search` plus a **Search**
  `Button` sending the `"option_search"` action,
- a `List` templated over `/options/<field>`, each row a `Button` whose
  label binds to the option's `label` and whose tap sends the
  `"option_select"` action with the option's `value`.

Renderer requirements: template-relative bindings inside `List` children
(already required by tables) and action contexts with `path` bindings —
both basic-catalog features, nothing custom.

### The two client actions

**`"option_search"`** — refresh the option list:

```json
{ "action": { "name": "option_search", "surfaceId": "tickets",
  "context": { "field": "author_id", "search": "ada" } } }
```

The server queries the destination through its primary read action **with
the surface's `actor:`/`tenant:`/`authorize?:` options**, filters by the
allowlisted `option_search` fields only, clamps to `option_limit`, sorts by
`option_sort`, and answers with one `updateDataModel` at
`/options/<field>`. An empty `search` returns the default first page.
Unknown fields, fields without `option_search`, and non-string search values
are rejected via `/ui/status`.

**`"option_select"`** — commit a choice (the selection mechanism):

```json
{ "action": { "name": "option_select", "surfaceId": "tickets",
  "context": { "field": "author_id", "value": "018f…" } } }
```

Selection round-trips through the server on purpose: the value is
re-fetched from the destination (policies apply — a spoofed or unauthorized
id is rejected via `/ui/status`), and the server writes **two** messages:
`/form/<field>` gets the value (what `submit_form` later casts), and
`/select/<field>` gets `{"search": "", "label": "<canonical label>"}` so the
UI shows what was picked. Non-searchable selects keep the frozen
Wave 2 ChoicePicker shape — nothing changes for them.

## Nested relationship forms (`nested_form`)

Forms whose actions manage relationships through arguments (the standard
`manage_relationship` pattern) can edit those related records inline:

```elixir
actions do
  create :create do
    accept [:subject]
    argument :notes, {:array, :map}, allow_nil?: true
    argument :tags, {:array, :uuid}, allow_nil?: true
    change manage_relationship(:notes, type: :direct_control)
    change manage_relationship(:tags, type: :append_and_remove)
  end
end

a2ui do
  component :form do
    fields [:subject]
    create_action :create
    update_action :update

    nested_form :notes do          # inferred: create_inline
      fields [:body, :rating]
    end

    nested_form :tags do           # inferred: pick_existing
      option_search [:name]        # searchable picker (optional)
    end
  end
end
```

The entity is named by the **action argument**, and the argument must be
consumed by a `manage_relationship` change on every action the form submits
— verified at compile time (`AshA2ui.Verifiers.VerifyNestedForms`).

### Interaction-mode inference

You never declare the mode. It is inferred from the `manage_relationship`
options via `Ash.Changeset.ManagedRelationshipHelpers` (the same helpers Ash
uses at changeset time; `type:` shorthands are expanded first):

- **lookups possible** (`on_lookup` not `:ignore` — e.g.
  `type: :append_and_remove`) → **pick_existing**: a picker adds existing
  destination records by id; current rows render with a remove button.
- else **creates possible** (`on_no_match: :create` — e.g.
  `type: :direct_control`) → **create_inline**: each row is a sub-form
  (`fields`, defaulting to the destination create action's accepts minus the
  relationship's destination attribute); add/remove buttons manage the rows.
- neither (update-only / all-`:ignore` configurations) → compile-time error;
  they have no v1 rendering.

The form's create and update actions must infer the **same** mode.

### Data model and wire contract

`/form/<argument>` is an **array of maps** — one per row, always present
(initially `[]`). The `List` rendering the rows templates over it. Because
the v0.9.1 protocol does not guarantee write-back semantics for
template-relative paths on editable inputs, **row mutation is
server-mediated**: the add/remove buttons carry the current array in their
action context (a `"rows"` path binding at `/form/<argument>`), and the
server answers with one `updateDataModel` replacing the array.

- `"nested_add"` (create_inline) appends a blank row; (pick_existing)
  validates the picked `"value"` against the destination (policies apply)
  and appends `{"_row": id, "id": id, "label": label}` — already-present ids
  are a no-op.
- `"nested_remove"` drops the row whose `"_row"` matches the context's
  `"row"`.

Every row carries a server-stamped **`"_row"`** key (the record id for
existing rows, a generated UUID for new ones) used as the remove target and
the template key — indexes are never used for targeting. Underscore-prefixed
keys are client state: `submit_form` strips them (keeping `"id"`, so
`on_match` updates existing records instead of recreating), and pick_existing
rows reduce to their `"id"` values before the argument cast. Ash's
`manage_relationship` machinery does the rest.

### Validation errors on nested rows

Errors on nested rows carry Ash's error path and land at
**`/errors/<argument>/<index>/<field>`** (index into the submitted array):

```json
{ "updateDataModel": { "surfaceId": "tickets",
  "path": "/errors/notes/1/body", "value": "is required" } }
```

Because the emitted row template can only bind template-relative paths, the
handler additionally mirrors each row's errors **into the row itself** as
`"_error_<field>"` keys (one `/form/<argument>` rewrite), which the row's
error `Text` components bind to. The `/errors/...` paths are the
programmatic contract; the mirrors are a rendering aid.

### Deferred in v1

- **Join-resource fields on `many_to_many`** (editing attributes of the join
  row, e.g. a membership's role): needs join-form modeling; the
  pick-and-attach case works today through `has_many`-based lookups.
- **Recursive nesting** (nested forms inside nested rows): the row template
  cannot host another templated `List` without index-addressed writes.
- **Pagination inside pickers**: `option_search` re-querying replaces paging;
  `option_limit` clamps every page.

## Table columns from relationships

The `source` field option renders a column whose value is read through a
loaded relationship path:

```elixir
a2ui do
  component :table do
    fields [:role, :user_email]
  end

  field :user_email do
    label "Email"
    source [:user, :email]
  end
end
```

- The **field name** (`:user_email`) stays the column identity: the data-model
  key in each `/records` row, the cell binding, and the label default.
- Record loading gains `Ash.Query.load/2` for every needed path (initial
  render, action follow-up refreshes, and query-enabled reads alike).
- Serialization walks the path nil-safely: a `nil` (or unloaded) relationship
  renders as `""`.
- Verified at compile time: every step but the last must be a **public
  relationship**, the last a **public attribute** of the final destination.

### Not sortable

Relationship-sourced columns are **not sortable** in this wave: `ui_query`
sorting works only for plain public attributes. Listing a source field in a
query's `sortable` (or `filters`/`search_fields`) is a compile-time error.
Forms can't render source fields either — they are table-only.

## Deferred (roadmap)

- **Sorting on relationship-sourced columns.**
- **`many_to_many` join-resource fields and recursive nesting** in nested
  forms (see above).
