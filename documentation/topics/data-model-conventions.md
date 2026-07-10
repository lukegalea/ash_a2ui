# Data Model Conventions

A2UI components don't carry data — they carry **bindings**: JSON Pointer
paths into a per-surface data model that the server updates with
`updateDataModel` messages. The protocol doesn't prescribe how that data
model is laid out, so AshA2ui reserves a small, stable set of paths and
promises to keep them consistent across every surface it emits. Renderers,
custom hooks, and tests can rely on them.

## The reserved paths

| Path | Contains | Written when |
|---|---|---|
| `/records` | The list of records backing the table component | Initial render; every refresh (action follow-ups, PubSub) |
| `/form` | The form component's current field values | Initial render; row selection (edit); after submit |
| `/errors/<field>` | Human-readable validation error text for `<field>` | A submitted action fails validation |
| `/ui/status` | Operation feedback text (the flash-equivalent) | After every handled action (success/error) |
| `/ui/action_result` | The map returned by a map-returning generic action | An `invoke`d generic action returns a plain map |

Everything under these paths uses camelCase string keys, matching the rest of
the wire format.

## `/records` — table data

The table component's `List` binds to `/records`; each record is a map of the
surface's fields (values already run through any `format` hints from `field`
options). A data-only refresh — from `AshA2ui.Info.build_data_model/2` or the
LiveView transport's PubSub subscription — is one message:

```json
{
  "version": "v0.9.1",
  "updateDataModel": {
    "surfaceId": "tickets",
    "path": "/records",
    "value": [
      { "id": "…", "subject": "Printer on fire", "status": "open" }
    ]
  }
}
```

Because `updateDataModel` replaces the value at `path`, refreshes are
whole-region in v0: the list is replaced, not diffed. (Named per-region
refreshes via `refreshes` action metadata are on the roadmap.)

## `/form` — form state

Form inputs bind to `/form/<field>`. Selecting a row (the `select_row`
action) loads that record's editable values into `/form`; a successful create
or update clears it back to `{}`. Clients that keep local edit state
should treat a server write to `/form` as authoritative.

## `/errors/<field>` — validation errors

When `AshA2ui.ActionHandler` invokes an Ash action and gets validation errors
back (an `Ash.Error.Invalid` with field-attributed errors), it maps each
error's field to its reserved path and pushes the message text:

```json
{
  "version": "v0.9.1",
  "updateDataModel": {
    "surfaceId": "tickets",
    "path": "/errors/subject",
    "value": "has already been taken"
  }
}
```

Conventions:

- The value is display-ready text (multiple errors on one field are joined),
  not a structured error object.
- A subsequent successful submit **clears** the error paths (`/errors` is
  reset wholesale to `{}`).
- Errors that can't be attributed to a field (e.g. a policy denial) go to
  `/ui/status` instead.

Renderers bind error `Text` components next to each input at
`/errors/<field>` and get inline validation for free — no error-specific
message types needed.

## `/ui/status` — the flash-equivalent

Stateless protocols have no "flash" concept, so AshA2ui reserves `/ui/status`
for operation lifecycle feedback. The value is display-ready text:

```json
{
  "version": "v0.9.1",
  "updateDataModel": {
    "surfaceId": "tickets",
    "path": "/ui/status",
    "value": "Created successfully."
  }
}
```

`AshA2ui.ActionHandler` writes it after every handled action — a success text
on completion, an explanation on rejected/unknown actions, a "not authorized"
text on policy denials (deliberately without detail), and a generic failure
text when errors can't be attributed to a field. The emitted surface includes
a `Text` component bound to `/ui/status`, so it behaves like a flash bar out
of the box.

## `/ui/action_result` — generic action results

Row actions (`invoke`) may target **generic actions** — think "generate an
API secret" or "recompute stats". Two handler conventions apply (both are
AshA2ui conventions layered on the protocol, not part of the A2UI spec):

- **`:record_id` pass-through** — if the generic action declares a
  `:record_id` argument, the `invoke` context's `"recordId"` is passed to it,
  so row-scoped generic actions know which record they were invoked on.
- **`/ui/action_result`** — when the action returns a plain map, the handler
  serializes it (JSON-safe values, string keys) and writes it to
  `/ui/action_result` alongside the usual success follow-ups:

```json
{
  "version": "v0.9.1",
  "updateDataModel": {
    "surfaceId": "tickets",
    "path": "/ui/action_result",
    "value": { "secret": "s3cr3t", "record_id": "…" }
  }
}
```

Surfaces that want to display the result bind components to paths under
`/ui/action_result`. Non-map results (`:ok`, records) emit no extra message.

## Why conventions instead of message types

The A2UI protocol keeps its message vocabulary tiny on purpose — data and
lifecycle signals all travel as `updateDataModel`. Encoding lifecycle state
*into the data model at known paths* means any conforming renderer displays
it with plain bindings, nothing custom to implement. These four paths are
part of AshA2ui's public contract: additions may come (they'll be documented
here), but existing paths won't change meaning within a major version.

> #### Precise payload shapes {: .info}
>
> The exact grouping of these writes (single message vs. one per path, order
> relative to `/records` refreshes) is pinned down by the encoder/handler
> test suites rather than this document — the vendored v0.9.1 JSON Schemas
> in `priv/a2ui/v0_9_1/` validate every emitted message. Treat the *paths and
> meanings* above as frozen, and the message batching as an implementation
> detail.
