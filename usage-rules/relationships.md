# Rules for relationship rendering

AshA2ui renders `belongs_to` **form selects** (ChoicePicker with options
loaded from the destination) and **table columns read through loaded
relationships** (the `source` field option). Both are server-resolved; the
client only ever sees plain option lists and plain values.

## Form selects for belongs_to

- **Rely on inference for the common case.** A form field whose name matches
  a `belongs_to` relationship's `source_attribute` (e.g. `:payment_group_id`
  for `belongs_to :payment_group`) renders as a ChoicePicker automatically —
  no `field` block needed:

```elixir
component :form do
  fields [:name, :payment_group_id]   # payment_group_id -> ChoicePicker
  create_action :create
end
```

- Use the `field` options only when the defaults are wrong:

```elixir
field :payment_group_id do
  relationship :payment_group   # explicit override (action-argument fields)
  option_label :name            # default: first of [:name, :title, :label, :username, :email], else PK
  option_value :id              # default: destination PK (composite PK requires explicit)
  option_sort :name             # default: the resolved option_label, ascending
  option_limit 100              # default: 100
end
```

- `relationship`, `option_label`, `option_value`, and `option_sort` are
  verified at compile time (real relationship; public destination
  attributes). A composite destination primary key without an explicit
  `option_value` is a compile-time error — fix the declaration.
- **Options are loaded through the destination's primary read action with
  the surface's `actor:`/`tenant:`/`authorize?:` opts** — destination
  policies apply. If option lists come back empty, check the destination's
  policies before anything else.
- Options land inline in the ChoicePicker *and* at the reserved
  `/options/<field>` data-model path (`[{"label": _, "value": _}]`, all
  strings). Code against `/options/<field>`; the inline copy exists because
  the v0.9.1 basic-catalog ChoicePicker can't bind dynamic options.
- **Do not raise `option_limit` for large option sets.** Truncation at the
  limit is deliberate; genuinely large sets need the roadmap's searchable
  selects — don't ship a 5,000-option dropdown.
- Submitted values arrive as strings through `/form/<field>` and are cast by
  the normal Ash changeset; one-element string lists from single-select
  pickers are unwrapped automatically. Don't pre-cast in transport code.

## Table columns through relationships (`source`)

```elixir
component :table do
  fields [:role, :user_email]
end

field :user_email do
  label "Email"
  source [:user, :email]       # every step but the last: public relationship;
end                             # last step: public attribute of the destination
```

- The field name (`:user_email`) is the column identity — the `/records` row
  key, the cell binding, and the label default. It does not need to exist as
  an attribute.
- Relationship loading (`Ash.Query.load`) happens automatically on every
  read path (initial render, action refreshes, query reads).
- Nil (or unloaded) relationships render as `""` — don't add nil-handling
  calculations for display purposes.
- **Source columns are table-only and not sortable/filterable.** Listing one
  in a `:form` component or in a query's `sortable`/`filters`/
  `search_fields` is a compile-time error. If you need to sort by a related
  value, that's the roadmap's relationship-sorted columns — don't fake it
  with a duplicated attribute.

## Avoid list

- ❌ Declaring `field ... relationship ...` when the field name already
  matches the `belongs_to` source attribute (the inference covers it).
- ❌ Raising `option_limit` past a UI-sensible dropdown size.
- ❌ Binding renderers to the inline ChoicePicker options instead of
  `/options/<field>`.
- ❌ Source paths through private relationships or ending in private
  attributes (verifier error; make them public deliberately or don't render
  them).
- ❌ Working around "not sortable" verifier errors by duplicating related
  data onto the resource just for sorting.
