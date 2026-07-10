# Rendering Clients

AshA2ui's protocol core produces plain maps (A2UI v0.9.1 messages, string
camelCase keys, ready for JSON encoding) and consumes plain maps (client
`action` envelopes). *How* those maps travel between your server and a
renderer is the transport's job. This guide covers the two supported
transports and the browser-side renderers.

## The message contract (both directions)

Server → client, in order on first render:

| Message | Purpose |
|---|---|
| `createSurface` | Announce the surface (`surfaceId`, `catalogId`) |
| `updateComponents` | The full component list (one component has id `"root"`) |
| `updateDataModel` | The data the components bind to (records, form state) |
| `deleteSurface` | Tear the surface down (supported by the encoder; rarely needed) |

Data-only refreshes are a single `updateDataModel` message
(`AshA2ui.Info.build_data_model/2`).

Client → server is one envelope shape:

```json
{
  "version": "v0.9.1",
  "action": {
    "name": "submit_form",
    "surfaceId": "tickets",
    "sourceComponentId": "form_submit",
    "timestamp": "2026-07-10T12:00:00Z",
    "context": { "...": "resolved data bindings" }
  }
}
```

The `action.name` values AshA2ui emits and accepts in v0 are `"submit_form"`,
`"select_row"`, and `"invoke"` (generic/row actions). See
[Actions and Authorization](actions-and-authorization.md).

## Transport 1: `AshA2ui.LiveRenderer` (LiveView)

The batteries-included option when your renderer host is a Phoenix app.
Requires the optional `phoenix_live_view` dependency (the module simply isn't
compiled without it).

```elixir
defmodule MyAppWeb.TicketA2uiLive do
  use AshA2ui.LiveRenderer,
    ui: MyApp.UI.TicketUI,
    actor_fn: & &1.assigns.current_user
end
```

What it does:

- **mount** — derives the actor via `:actor_fn`, calls
  `AshA2ui.Info.build_surface/2`, and pushes the messages to the JS hook via
  `push_event`. If the resource has `Ash.Notifier.PubSub` configured, it also
  subscribes to the relevant topics.
- **`"a2ui:action"` events** — incoming client envelopes are routed through
  `AshA2ui.ActionHandler.handle/3` with the mounted actor; follow-up messages
  (refreshes, error payloads) are pushed back to the hook.
- **PubSub notifications** — on record changes, it pushes a
  `AshA2ui.Info.build_data_model/2` refresh, so every mounted client stays
  live. Rapid notification bursts are debounced; the refresh is
  whole-data-model in v0 (targeted region refreshes are on the roadmap).

All callbacks are `defoverridable`, so you can layer custom behavior on top
of the generated LiveView when needed.

### The hook contract

The package ships the LiveView JS hook at `priv/js/ash_a2ui_hook.js`:

- Register it under the name **`AshA2ui`** in your `LiveSocket` hooks.
- The LiveView renders a container `div` with `phx-hook="AshA2ui"` and
  `phx-update="ignore"`; the hook owns everything inside it.
- On mount, the hook creates an `<a2ui-surface>` element (provided by your
  installed renderer, e.g. `@a2ui/lit`) and feeds it every A2UI
  server→client message pushed by the LiveView.
- User interactions surface as A2UI `action` envelopes, which the hook
  forwards to the server as the **`"a2ui:action"`** LiveView event.

> #### Not yet final {: .warning}
>
> The name of the server→client `push_event` the hook listens on is an
> internal detail between `AshA2ui.LiveRenderer` and the shipped hook and is
> being finalized during integration. Use the shipped hook rather than
> hand-rolling one, and this never affects you.

Wiring in `assets/js/app.js`:

```javascript
import "@a2ui/lit/v0_9";
import { AshA2ui } from "../../deps/ash_a2ui/priv/js/ash_a2ui_hook.js";

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { AshA2ui },
  params: { _csrf_token: csrfToken },
});
```

## Transport 2: plain JSON endpoints

The protocol core is transport-agnostic — a read-only surface is one
controller action:

```elixir
defmodule MyAppWeb.A2uiController do
  use MyAppWeb, :controller

  def tickets(conn, _params) do
    messages =
      AshA2ui.Info.build_surface(MyApp.UI.TicketUI,
        actor: conn.assigns.current_user
      )

    json(conn, messages)
  end
end
```

For mutations, accept the client `action` envelope on a POST endpoint and
hand it to the handler:

```elixir
def action(conn, envelope) do
  case AshA2ui.ActionHandler.handle(MyApp.UI.TicketUI, envelope,
         actor: conn.assigns.current_user
       ) do
    {:ok, messages} -> json(conn, messages)
    {:error, messages} -> conn |> put_status(422) |> json(messages)
  end
end
```

Both branches return valid server→client A2UI messages — the error branch
carries validation errors on the reserved `/errors/<field>` data-model paths
(see [Data Model Conventions](data-model-conventions.md)), so the renderer
treats them like any other data update.

JSON endpoints don't get PubSub live refresh (there's no persistent
connection); pair them with polling or use the LiveView transport when you
need liveness. Other streaming transports (SSE, raw WebSocket) are roadmap.

## Browser renderers: `@a2ui/lit` and `@a2ui/react`

The published renderer packages are **0.10.x** and expose **`/v0_9` entry
points** compatible with the v0.9.x protocol AshA2ui emits:

- [`@a2ui/lit`](https://www.npmjs.com/package/@a2ui/lit) — web components;
  the `<a2ui-surface>` element renders a surface from a message feed. This is
  what the shipped hook targets, and works in any framework (or none).
- [`@a2ui/react`](https://www.npmjs.com/package/@a2ui/react) — React
  bindings, useful when the consuming client is a React app talking to the
  JSON transport.

Notes:

- Check each package's README for the exact `/v0_9` import path in the
  version you install — the packages version independently from the spec.
- `@a2ui/lit`'s `A2uiController` class is only needed for registering
  *custom* components; plain embedding is `<a2ui-surface>` plus the message
  feed.
- AshA2ui emits the **basic catalog** (`Text`, `TextField`, `CheckBox`,
  `ChoicePicker`, `DateTimeInput`, `Button`, `List`, `Row`, `Column`, `Card`,
  ...). Tables are `List` + `Row`/`Column` composition — the basic catalog
  has no Table component. Custom catalogs are on the roadmap.

Anything else that speaks A2UI v0.9.x — including agent canvases that accept
A2UI surfaces — can consume the same messages without changes on the server.
