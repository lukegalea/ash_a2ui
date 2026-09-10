defmodule AshA2ui.Canvas.Object do
  @moduledoc """
  The resolved, server-side form of a canvas object — the answer to
  `AshA2ui.Canvas.resolve/2`.

  * `ref` — the parsed `%AshA2ui.Canvas.ObjectRef{}`.
  * `label` — the object's display identity: the registry's `label/1`
    override when given, a humanized fallback otherwise; for records, the
    record's own display identity.
  * `description` — reserved host-provided prose; `nil` unless the registry
    supplies it.
  * `projections` — the declared rendering kinds this object supports
    (`:inspect`, `:browse`, `:view`, `:create`, `:edit`, `:act`, `:diagram`,
    `:history`), derived per the contract. No surface is built in Phase D —
    projections are data the experience compiler consumes later.
  * `capabilities` — server-derived `%AshA2ui.Canvas.Capability{}` list.
  * `provenance` — the actual Ash modules behind the object (domain,
    resource, record). Provenance is server-side truth: it never travels
    back to clients as executable input, and may appear as display metadata
    only.
  """

  defstruct [:ref, :label, :description, :projections, :capabilities, :provenance]

  @type t :: %__MODULE__{
          ref: AshA2ui.Canvas.ObjectRef.t(),
          label: String.t(),
          description: String.t() | nil,
          projections: [atom()],
          capabilities: [AshA2ui.Canvas.Capability.t()],
          provenance: map()
        }
end
