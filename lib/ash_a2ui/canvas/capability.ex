defmodule AshA2ui.Canvas.Capability do
  @moduledoc """
  A server-derived statement of one thing an actor may do with one object.

  Capabilities are **derived data, never input**: the resolver computes them
  from Ash metadata (action presence at resource level) and `Ash.can?/3`
  (record level, with the scene's actor and tenant). A client-constructed
  capability envelope is not accepted anywhere in Phase D — the resolver
  ignores capability-shaped options entirely, and the acceptance tests pin
  that (`A2UI-103/AC-2`).

  * `verb` — the human-facing action family: `:view`, `:create`, `:edit`,
    `:destroy`, or `:act`.
  * `consequence` — what running it does: `:read`, `:mutation`,
    `:destructive`.
  * `confirmation` — `:required` for destructive verbs, `:none` otherwise.
  * `authorized?` — at resource level this reflects *presence* only
    (execution still routes through the library's authorized action paths —
    affordance gating is a UX aid, never the security boundary); at record
    level it is the `Ash.can?/3` verdict for the scene actor.
  """

  defstruct [
    :id,
    :verb,
    :action_name,
    :object_ref,
    :label,
    :consequence,
    :confirmation,
    :authorized?
  ]

  @typedoc """
  `action_name` is the Ash action's name as a string (never an atom built
  from client input); `object_ref` is the ref string the capability was
  derived for.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          verb: :view | :create | :edit | :destroy | :act,
          action_name: String.t(),
          object_ref: String.t(),
          label: String.t(),
          consequence: :read | :mutation | :destructive,
          confirmation: :none | :required,
          authorized?: boolean
        }
end
