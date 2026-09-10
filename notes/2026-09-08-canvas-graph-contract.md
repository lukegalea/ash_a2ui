# Canvas graph & objects — Phase D contract

> **Status: contract for A2UI-102/103.** Written before implementation.
> Binding for the canvas lane; changes here require changing the oracle.
> Extracted from the AshCanvas TRD with Phase-D scope pins.

## What this phase builds (library tier, `AshA2ui.Canvas.*`)

The naked-objects foundation: a canonical graph AST over the host's
configured domains, opaque object references, a host-configured registry,
actor/tenant-scoped object resolution, and server-derived capabilities.
What it deliberately does NOT build yet: scenes, navigation intents,
renderers, projections-as-surfaces (the experience compiler wires into
projections in later phases), and any record materialization into the graph.

## Identity model (the security boundary)

- Client-facing refs are **opaque strings**: `"application:<app>"`,
  `"domain:<domain_short_name>"`, `"resource:<domain>.<resource>"`,
  `"record:<domain>.<resource>:<encoded_pk>"`. Nothing in a ref is ever
  converted to an atom or module (`CANVAS-SEC-006`).
- `%AshA2ui.Canvas.ObjectRef{id: String.t(), kind: kind}` is the parsed
  client-safe shape. Kinds: `:application | :domain | :resource | :record`.
- `%AshA2ui.Canvas.Object` is the RESOLVED server-side form: ref, label,
  description, projections (declared data), capabilities (server-derived),
  provenance (the actual modules — these never travel back to clients as
  executable input; they may appear as display metadata only).
- Resolution: `AshA2ui.Canvas.resolve(ref, registry: MyApp.CanvasRegistry,
  actor: ..., tenant: ...)` — module names come ONLY from the registry's
  domain list matched against the parsed ref path. Unknown, malformed, or
  unregistered → `{:error, :unknown_object}` with no registry-content leak.

## Registry

`AshA2ui.Canvas.Registry` is a behaviour: `domains/0` (list of domain
modules, compile-known), optional `label/1` overrides. The host implements
it; the library ships a test registry over the test-support fixtures.
Discovery restriction (`CANVAS-SEC-005`): what the registry doesn't list
doesn't exist.

## Graph AST

```elixir
%AshA2ui.Canvas.Graph{
  revision: "sha256:...",
  roots: ["application:<app>"],
  nodes: %{id => %Node{id: id, kind: :application | :domain | :resource,
                       label: String.t(), metadata: map}},
  edges: [%Edge{kind: :contains | :relationship, from: id, to: id,
                name: atom | nil}]
}
```

- **Structural layer**: application → domains (`:contains`), domains →
  resources (`:contains`), resource → resource relationships
  (`:relationship`, named, from `Ash.Resource.Info.relationships/1`;
  only relationships whose destination resolves inside the registry).
- **Behavioral sub-entities**: actions, policies (count + evaluator
  presence), and state machines are carried as **addressable typed
  sub-entities in node metadata** with stable ids
  (`"<resource_id>#action:<name>"`, `#policy:<idx>`, `#state_machine`),
  not as graph nodes — the visual graph stays navigable while nothing
  semantic is silently dropped (the diagrams-test principle). Revisit as
  first-class nodes only if canvas UX demands it.
- **Records are never graph nodes** (`CANVAS-103/AC-3`): the runtime layer
  is resolution-on-demand only.

## Revision & stability

- `revision` = sha256 over a canonical serialization: nodes sorted by id,
  edges sorted by (from, to, kind, name), metadata restricted to semantic
  fields (labels, kinds, action names/types, relationship names/types,
  policy counts, state-machine state names). Module definition order,
  registration order, and any non-semantic noise MUST NOT affect it.
- `AshA2ui.Canvas.Graph.build(registry)` and `Graph.diff(old, new)` →
  `%Diff{added_nodes, removed_nodes, added_edges, removed_edges,
  changed_nodes, revision_from, revision_to}` — exact, deterministic,
  covering every semantic delta (sub-entity changes surface as
  `changed_nodes`).

## Capabilities & projections (declared data only)

```elixir
%AshA2ui.Canvas.Capability{id, verb, action_name, object_ref, label,
  consequence: :read | :mutation | :destructive, confirmation: :none | :required,
  authorized?: boolean}
```

- Resource-level: action presence (cheap) — `authorized?` reflects
  presence only; execution still routes through the existing authorized
  action paths (the A2UI-101 principle: affordance gating is a UX aid,
  never the security boundary).
- Record-level: `Ash.can?/3` per action with the scene actor/tenant
  (A2UI-103/AC-2).
- Capability ids are server-derived; a client-constructed capability
  envelope is not an input anywhere in Phase D — `rejects_forged_...`
  asserts the resolver never accepts capability data it did not derive.
- Projections are declared kinds on the Object: `:inspect`, `:browse`,
  `:view`, `:create`, `:edit`, `:act`, `:diagram`, `:history` — derived:
  resources get `:inspect` + `:browse` + `:create`/`:edit` by action
  presence; records get `:view` + `:edit`/`:act` by capability. No surface
  building this phase.

## Relationship to AshDiagram / Clarity

One upstream truth: Ash metadata. This builder introspects directly
(`Ash.Domain.Info` / `Ash.Resource.Info` / policy + state-machine info) —
no Mermaid strings, no SVG parsing (`A2UI-102/AC-6`). AshDiagram remains
the diagram/Clarity engine; a later phase may let it consume this AST.
No new dependencies.

## Phase D non-goals

Scenes, viewports, navigation intents, agent context, choreography,
Cytoscape renderer, LiveView host surface (host lane follows this one),
process/BPMN objects (Phase E), record enumeration anywhere.
