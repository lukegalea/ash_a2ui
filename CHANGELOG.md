# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.
This changelog is managed by [git_ops](https://hex.pm/packages/git_ops).

<!-- changelog -->

## Unreleased

### Features:

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
