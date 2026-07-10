# Actions: routing client envelopes into Ash

Every inbound A2UI `action` envelope must go through
`AshA2ui.ActionHandler.handle/3`. It validates the envelope, enforces the
DSL allowlist, invokes the Ash action with the actor, and maps errors onto
the reserved data-model paths. Calling Ash actions directly from transport
code skips all of that.

## `handle/3` contract

```elixir
AshA2ui.ActionHandler.handle(resource_or_ui_module, envelope,
  actor: current_user,
  tenant: tenant          # optional
  # authorize?: true      # the default — leave it on
)
# => {:ok, [updateDataModel, ...]} | {:error, [updateDataModel, ...]}
```

- The first argument is a resource using the `AshA2ui` extension or an
  `AshA2ui.Standalone` UI module — the same module you pass to
  `AshA2ui.Info.build_surface/2`.
- The envelope may be the full client->server message
  (`%{"version" => ..., "action" => %{"name" => ..., "context" => ...}}`)
  or a bare inner action map — both are accepted.
- Push the returned messages to the client **for both `{:ok, _}` and
  `{:error, _}`** — error messages carry the validation feedback the
  renderer must display.

## The three v0 action names

Only `"submit_form"`, `"invoke"` and `"select_row"` exist. Don't invent new
`action.name` values; add a proper Ash action and expose it via
`row_actions` instead.

- `"submit_form"` — context `%{"values" => %{...}, "recordId" => id | nil}`.
  No `recordId` runs the form's create action; with one, the update action.
  String-keyed values are cast against the target action's accepted
  attributes/arguments (no dynamic atom creation); unknown keys are silently
  dropped.
- `"invoke"` — context `%{"action" => name, "recordId" => id | nil}`.
  **The named action must be listed in the surface's `row_actions`** — that
  list is the server-side allowlist and the authorization surface for
  client-triggered actions. Anything not listed is rejected with a
  `/ui/status` error before Ash is ever called. Destroy, update and generic
  actions are supported; a generic action with a `:record_id` argument
  receives the context's `"recordId"`.
- `"select_row"` — context `%{"recordId" => id}`. Returns one
  `updateDataModel` populating `/form` with the record's values (edit-form
  population).

## Reserved data-model paths

All follow-up messages are `updateDataModel` messages on these paths —
never invent ad-hoc paths or custom message types; renderers depend on
them:

- `/records` — the re-read table rows after a successful write (each row
  includes `"id"`).
- `/form` — cleared to `%{}` on success; populated by `select_row`.
- `/errors/<field>` — per-field validation error text; `/errors` is cleared
  to `%{}` on success.
- `/ui/status` — human-readable lifecycle feedback (success text, rejection
  reasons, "not authorized").
- `/ui/action_result` — the map result of a map-returning generic action
  (an AshA2ui handler convention, not part of the A2UI spec).

On `Ash.Error.Forbidden` only a `/ui/status` "not authorized" message is
emitted — no field errors, to avoid leaking policy details.

## Rules

- Keep `row_actions` minimal — it is an allowlist, not documentation. Never
  mirror every action on the resource.
- Always pass `actor:` (and `tenant:` where relevant); `authorize?` defaults
  to `true` and should stay on.
- On a resource with **no policies**, `authorize?: true` is a no-op —
  transport-level authentication is the only gate. Say so in review rather
  than assuming enforcement.
- Values are serialized JSON-safe on the way out (dates/datetimes to
  ISO 8601, decimals to strings, atoms to strings) — don't re-serialize.
