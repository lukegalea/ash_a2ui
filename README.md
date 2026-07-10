# AshA2ui

AshA2ui is an [Ash](https://ash-hq.org) extension that generates
[A2UI (Agent to UI)](https://github.com/a2ui-project/a2ui) v0.9.1 payloads directly from
your Ash resources. Declare an `a2ui` block on a resource (or in a standalone UI module),
and AshA2ui builds the `createSurface` / `updateComponents` / `updateDataModel` message
stream for any A2UI renderer (such as `@a2ui/lit`), routes client `action` envelopes back
into Ash actions with full actor/authorization support, and — when `phoenix_live_view` is
available — ships a batteries-included LiveView transport (`AshA2ui.LiveRenderer`) with
PubSub-driven live data refresh. The protocol core depends only on `ash`.

> **🚧 Under construction.** This library is being actively built and is not yet published
> to Hex. APIs may change without notice.
