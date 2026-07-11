# Relationship Rendering

AshA2ui renders two relationship shapes: **form selects** for `belongs_to`
relationships (pick the parent record from a dropdown) and **table columns
read through loaded relationships** (show the author's email on a post row).
Both are server-resolved — the client only ever sees plain options and plain
values.

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
  genuinely large sets need the roadmap's searchable/paginated selects
  (deferred — see below).

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

- **Searchable/paginated selects** — for option sets beyond `option_limit`.
- **Nested forms** via `Ash.Changeset.ManagedRelationshipHelpers`-driven
  interaction-mode inference (create/edit related records inline).
- **Sorting on relationship-sourced columns.**
