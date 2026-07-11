# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.
This changelog is managed by [git_ops](https://hex.pm/packages/git_ops).

<!-- changelog -->

## Unreleased

### Features:

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
