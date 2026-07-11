# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.
This changelog is managed by [git_ops](https://hex.pm/packages/git_ops).

<!-- changelog -->

## Unreleased

### Features:

- Theming toolkit for `@a2ui/lit`-rendered surfaces (see the new
  [Theming](documentation/topics/theming.md) topic):
  - `priv/js/ash_a2ui_theme.css` — a neutral, dependency-free CSS-variable
    theme for the basic catalog (`--a2ui-*` tokens; shadow DOM makes CSS
    custom properties the only styling seam), designed to be imported and
    then overridden with the host app's design tokens.
  - `priv/js/ash_a2ui_catalog.js` — `createAshA2uiCatalog(deps)` builds a
    merged catalog registered under the basic catalog id whose
    ChoicePicker renders a native, token-themed `<select>` for
    `mutuallyExclusive` pickers (checkbox list for `multipleSelection`);
    the basic catalog has no dropdown display style through spec v1.0.
  - `configureAshA2ui` accepts an optional
    `markdown: {ContextProvider, context, render}` entry; the hook mounts
    a Lit context provider on its container so Text headings render as
    real headings instead of literal `## ...` markdown
    (upstream renders raw markdown without an injected renderer —
    google/A2UI#1226).
- Encoder: each table record now renders as a `Card` (`record_row`)
  wrapping `record_row_content` (the `Row` of cells), and every cell is a
  labeled pair — `table_cell_<field>` is a `Row` of a caption `Text`
  (`table_cell_<field>_label`, humanized field name) and the value `Text`
  (`table_cell_<field>_value`) — giving themed surfaces card chrome and
  readable "Label: value" rows with no DSL changes.
- Searchable relationship selects: the `field` entity gains `option_search`
  (a list of public string-typed destination attributes, compile-verified).
  Non-empty `option_search` swaps the static ChoicePicker for a composite —
  a selection-label Text (`/select/<field>/label`), a search TextField
  (`/select/<field>/search`) with a Search button dispatching the new
  `"option_search"` client action (case-insensitive contains OR'd across
  the allowlisted fields, actor/tenant-scoped destination read, clamped to
  `option_limit`, answered with one `updateDataModel` at
  `/options/<field>`), and an option List templated over `/options/<field>`
  whose per-option Buttons dispatch the new `"option_select"` action — the
  server re-fetches the picked record (policies apply), writes the value to
  `/form/<field>` and the canonical label to `/select/<field>`.
  Non-searchable selects are unchanged.
- Nested relationship forms: the new `nested_form` DSL entity inside `:form`
  components, named by the **action argument** a `manage_relationship`
  change consumes (compile-verified on every action the form submits by the
  new `AshA2ui.Verifiers.VerifyNestedForms`). The interaction mode is
  inferred from the change's options via
  `Ash.Changeset.ManagedRelationshipHelpers` — lookups (e.g.
  `type: :append_and_remove`) render as **pick_existing** (a picker adding
  existing records — searchable via `option_search` — and current rows with
  remove buttons), creates (e.g. `type: :direct_control`) as
  **create_inline** (sub-form rows; `fields` defaults to the destination
  create action's accepts minus the relationship's destination attribute).
  `/form/<argument>` is an always-present array of row maps mutated through
  the new server-mediated `"nested_add"`/`"nested_remove"` client actions
  (rows carry server-stamped `"_row"` identity keys); `select_row`
  populates the rows from the record's related records, `submit_form`
  strips underscore keys / reduces pick rows to ids before the argument
  cast, and nested validation errors map to
  `/errors/<argument>/<index>/<field>` plus `"_error_<field>"` in-row
  mirrors. Surfaces using these features carry a new `/select/<name>` state
  path. Deferred: many_to_many join-resource fields, recursive nesting,
  in-picker pagination.
- Row-action prompts: `action` entities gain `prompt_fields` (arguments/
  accepts of the Ash action, compile-verified) and `prompt_title`. Prompt
  actions render as a basic-catalog `Modal` (`row_action_<action>_modal`
  wrapping the trigger button and a content Column of TextFields bound to
  the new reserved `/prompt/values/<action>/<field>` paths). The trigger
  dispatches the new `"prompt"` client action (allowlist + `visible_when`
  enforced; pre-fills `/prompt/values/<action>` from the record and clears
  `/errors`); the Modal's Confirm sends `"invoke"` whose context now may
  carry a `"values"` map — filtered to the declared prompt fields, cast
  against the action's arguments/accepts, and passed as the action params
  (ignored entirely on prompt-less actions). Successful prompt invokes
  clear `/prompt/values/<action>`; validation errors land on
  `/errors/<field>` as usual. `refreshes` on `action` entities is now
  optional (omitted = refresh every table).
- Relationship-path search: `search_fields` entries may be relationship
  paths to public string attributes (`[:referrer, :email]`) — every step but
  the last a public relationship, verified at compile time; matched with the
  same case-insensitive contains through the path (`exists` semantics on
  to-many paths).
- Calculation filters: query `filters` may name expression-backed public
  calculations (equality on the calc value, cast against the calculation's
  type/constraints); module-based calculations are rejected at compile time,
  mirroring the sorting rule.
- Named filter presets: `preset` entities inside `query` declare server-side
  composite predicates the client selects by name only —
  `preset :pending do filter status: :pending, deleted_at: nil end`
  (keyword conditions ANDed; `nil` = `is_nil`, list = membership) or
  `preset :deleted do read_action :deleted end` (the escape hatch for
  predicates the keyword form can't express). `default_preset` applies when
  the client selects none and closes the preset set. `/query` state gains a
  `"preset"` key (only on preset-declaring queries) and the encoder emits a
  `query_preset_picker` ChoicePicker.
- Conditional row-action visibility: `action` entities gain `visible_when`
  (keyword equality/is_nil/membership conditions on public attributes or
  expression calculations, compile-verified castable). The handler enforces
  the conditions on every `invoke`/`prompt` (fetching the record with any
  condition calculations loaded; non-visible actions rejected via
  `/ui/status`). Rendering is best-effort: rows of affected tables gain
  `"_actions"` (visible action names) and `"_visible_<action>"`
  (`[{"id": ...}]`/`[]`) keys, and conditional actions render inside a
  `List` slot templated over the row-relative `_visible_<action>` path —
  the v0.9.1 basic catalog has no visibility property, so renderers without
  nested-template support fall back to `"_actions"`.
- Multi-key calculation sorting verified: `default_sort` and client sorts
  compose expression calculations with attributes
  (`default_sort status_priority: :asc, code: :asc`); no new machinery,
  pinned by test.

- `Ash.Type.Enum` attributes render as ChoicePickers: the TypeMapper now
  detects `Ash.Type.Enum` implementations (previously they fell back to
  TextField because their values live in the module, not in a `one_of`
  constraint), and form inputs and query filter pickers source their options
  from the enum's `values/0`, labeled via `label/1` when declared and
  humanized otherwise.

- Calculation & aggregate columns: table (and display) fields may name
  public calculations and aggregates. They are `Ash.Query.load`ed on every
  read path (initial render, post-action refreshes, `query` reads) and
  serialized through the JSON-safe serializer like attributes. Query
  `sortable`/`default_sort` allowlists accept public aggregates and
  expression-based calculations (anything `Ash.Resource.Info.sortable?/3`
  approves); module-based calculations and any calculation/aggregate in
  `search_fields`/`filters` are rejected at compile time with tailored
  messages, as are calculations/aggregates in form components (not
  writable).
- Multiple named table components: `component :table, :new_items do ... end`
  declares additional, independently configured table sections (own
  `fields`/`read_action`/`row_actions`/`query` each); the unnamed
  `component :table` keeps working (implicit name `:table`). Multi-table
  surfaces scope the data model per table (`/records/<component_name>`,
  `/query/<component_name>`), infix component ids with the table name, and
  render humanized section headings; single-table surfaces are entirely
  unchanged. `invoke`/`select_row` contexts additively carry
  `"component"`; `query` contexts require it on multi-table surfaces. New
  `AshA2ui.Verifiers.VerifyComponents` enforces unique component names,
  table-only naming, and a single `:form`.
- `refreshes` action metadata: `action :approve do refreshes [:new_items] end`
  limits which table components a successful action rewrites (default stays
  refresh-everything); targets and action reachability are compile-time
  verified. `/form`/`/errors`/`/ui/*` follow-up semantics are unchanged.

### Bug Fixes:

- `invoke` on an update-type action in `row_actions` now calls that action
  argument-less on the identified record. Previously it silently routed to
  the form's `update_action` with empty params — a no-op unless the invoked
  action happened to be the form's update action.

- Relationship rendering, part 1 — `belongs_to` form selects: a form field
  whose name matches a `belongs_to` relationship's `source_attribute` renders
  as a `ChoicePicker` automatically (options loaded from the destination's
  primary read action with the surface's `actor:`/`tenant:`/`authorize?:`
  opts). New `field` entity options `relationship` (explicit override),
  `option_label` (default: first existing public attribute of
  `[:name, :title, :label, :username, :email]`, else the destination PK),
  `option_value` (default: destination PK; composite PKs require it
  explicitly), `option_sort` (default: the resolved label, ascending) and
  `option_limit` (default: 100). Options are emitted inline in the picker and
  mirrored at the new reserved `/options/<field>` data-model path;
  single-select string-list submissions are unwrapped before casting.
  Compile-time verification via `AshA2ui.Verifiers.VerifyRelationships`.
- Relationship rendering, part 2 — `source` table columns: the new `source`
  field option (e.g. `source [:user, :email]`) renders a column read through
  the loaded relationship path. Record loading gains the needed
  `Ash.Query.load` statements on every read path; serialization walks the
  path nil-safely (nil/unloaded relationship -> `""`). Source columns are
  table-only and rejected in `ui_query` allowlists at compile time.
- Generic action results are now visible: `AshA2ui.ActionHandler` serializes
  map results to display text at the new reserved `/ui/action_result_text`
  path (one "Humanized key: value" line per key; the raw map stays at
  `/ui/action_result`), the encoder emits an always-present
  `action_result_panel` (Column wrapping a Text bound to it), and both paths
  are cleared on every subsequent successful action.

- Ship [`usage_rules`](https://hexdocs.pm/usage_rules)-compatible LLM usage
  rules: `usage-rules.md` plus `usage-rules/actions.md` and
  `usage-rules/liveview.md` sub-rules, included in the hex package so
  consumers can sync them with `mix usage_rules.sync`.
- `query` DSL entity: named, server-enforced allowlists for search
  (case-insensitive contains OR'd across `search_fields`), sorting
  (`sortable`), equality filters (`filters`), and pagination
  (`page_size`/`max_page_size`, limit/offset with a look-ahead `hasMore`).
  Tables reference a query via the new `query` component option; the encoder
  emits search/filter/pagination controls wired to the new `"query"` client
  action; `AshA2ui.ActionHandler` validates every request against the
  allowlist and rejects anything undeclared via `/ui/status`. The reserved
  `/query` data-model path carries the authoritative query state, and
  `submit_form`/`invoke` success refreshes respect the client's active query.
  Compile-time verification via `AshA2ui.Verifiers.VerifyQueries`.
- PubSub live refreshes preserve the user's query: `AshA2ui.LiveRenderer`
  tracks the last `/query` state pushed to the client and passes it to
  `AshA2ui.Info.build_data_model/2` via the new `:query_state` option
  (validated against the query allowlist; invalid state falls back to the
  declared defaults), so a refresh re-runs the current
  search/filters/sort/page instead of resetting the surface.

### Bug Fixes:

- A `multipleSelection` ChoicePicker reset to its "All" option submits
  `[""]`, which was cast to `field in []` (matching nothing) — empty-string
  list filter values are now treated as inactive, like `""` and `nil`.
