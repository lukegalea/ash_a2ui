# Actions and Authorization

Everything a client can *see* or *do* through an AshA2ui surface goes through
ordinary Ash actions with your actor and `authorize?: true`. There is no
side channel: if a policy forbids it, the surface can't do it either.

## Reading: the `render_a2ui` generic action

Compiling a resource with the `AshA2ui` extension adds a generic action
`render_a2ui` (returning `{:array, :map}` — the surface message list) to the
resource — opt out with `add_render_action? false` in the `a2ui` section if
you don't want it. It wraps
`AshA2ui.Info.build_surface/2`, which means surface rendering:

- shows up in code interfaces like any other action,
- participates in tracing/observability,
- and, most importantly, runs **through the policy pipeline**.

`build_surface/2` and `build_data_model/2` accept `actor:` and `tenant:` and
load records via the component's `read_action` with `authorize?: true`.
Defaults, spelled out:

| Option | Default | Meaning |
|---|---|---|
| `actor:` | `nil` | No actor — policies evaluate against a nil actor |
| `tenant:` | `nil` | No tenant |
| `authorize?` | always `true` | Never bypassed by AshA2ui |

If your resource has no policies, `authorize?: true` is a no-op — **an
AshA2ui surface on a policy-less resource is not access-controlled** beyond
whatever authentication your transport applies (router pipelines,
`live_session` mounts). Don't mistake the correct default posture for
enforcement you haven't written.

## Writing: the `action` envelope

Clients send a single envelope message; `AshA2ui.ActionHandler.handle/3`
consumes it:

```elixir
AshA2ui.ActionHandler.handle(MyApp.UI.TicketUI, envelope, actor: current_user)
# => {:ok, messages} | {:error, messages}
```

The v0 `action.name` vocabulary:

| `action.name` | Meaning | Maps to |
|---|---|---|
| `"submit_form"` | The form component was submitted | The form's `create_action` or `update_action` (with `recordId` → update, without → create) |
| `"invoke"` | A row action button was clicked | The named action in `row_actions` |
| `"select_row"` | A table row was selected | Selection state (e.g. loading a record into the form) |

When the view declares no form/table action, the handler falls back to the
resource's **primary** create/update/read action — so minimal surfaces work
without spelling every action out.

Both result tuples carry valid server→client messages: on success, a data
refresh plus `/ui/status` feedback; on failure, validation errors mapped onto
`/errors/<field>` paths (see
[Data Model Conventions](data-model-conventions.md)).

## `row_actions` is the allowlist

This is the load-bearing security property of the DSL:

```elixir
component :table do
  row_actions [:update, :archive]  # ← the ONLY actions "invoke" may call
end
```

`ActionHandler` rejects any `invoke` envelope naming an action outside the
declared `row_actions` — *before* touching Ash. (`submit_form` envelopes
carry no action name at all: the server always runs the view's declared
create/update action, so there is nothing for a client to redirect.)
A malicious client editing the envelope cannot reach `:destroy` if you didn't
declare it. Corollary: **declare `row_actions` explicitly and minimally**;
never expose an action through the surface just because it exists.

The declared actions are verified to exist (with compatible types) at compile
time, so the allowlist can't silently drift from the resource.

## Layering your authorization

Defense in depth, from outside in:

1. **Transport auth** — router pipelines / `live_session` `on_mount` decide
   who reaches the surface at all, and supply the actor
   (`actor_fn:` on `AshA2ui.LiveRenderer`, `conn.assigns` for JSON
   endpoints).
2. **The DSL allowlist** — `row_actions` + declared form actions bound what
   can be attempted.
3. **Ash policies** — decide whether *this* actor may perform the attempted
   action on *this* record, exactly as everywhere else in your app.

## Documented limitation: no field-level visibility

v0 field visibility is Ash's public/private attribute distinction plus the
static `hidden` field option — nothing actor-dependent. If two actors are
allowed to read the same records but should see *different fields*, AshA2ui
cannot express that yet: the surface's component tree and field list are the
same for every actor.

Workarounds today: define separate surfaces per audience in standalone UI
modules (`use AshA2ui.Standalone`, one module per audience) and choose which
to render in plain Elixir. First-class support arrives with the roadmap
context struct (`audience`-conditional surfaces) and field-visibility rules.
