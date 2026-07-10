defmodule AshA2ui.ResolvedView do
  @moduledoc """
  The normalization seam between the DSL and the encoder: `resolve/2` turns a
  resource (or standalone UI module) plus request options into a plain struct
  that the encoder consumes. The encoder never reads compiled DSL state
  directly.

  FROZEN CONTRACT — the struct fields and `resolve/2` signature are the
  interface every parallel track codes against; do not change outside an
  integration commit.
  """

  defstruct [
    :resource,
    :surface_id,
    :read_action,
    :create_action,
    :update_action,
    components: [],
    fields: %{},
    row_actions: []
  ]

  @type t :: %__MODULE__{
          resource: module,
          surface_id: String.t(),
          components: [AshA2ui.Component.t()],
          fields: %{atom => AshA2ui.Field.t()},
          read_action: atom | nil,
          create_action: atom | nil,
          update_action: atom | nil,
          row_actions: [atom]
        }

  @doc """
  Resolves the `a2ui` DSL of `resource_or_ui_module` (an `Ash.Resource` using
  the `AshA2ui` extension, or an `AshA2ui.Standalone` UI module with
  `for_resource`) into a `#{inspect(__MODULE__)}` struct.

  ## Options

    * `:actor` / `:tenant` — passed through to data loading (Track 2/3).
  """
  @spec resolve(module, keyword) :: t()
  # TODO Track 2: rename _opts back to opts once normalization consumes it.
  def resolve(resource_or_ui_module, _opts \\ []) do
    resource = AshA2ui.Info.resource!(resource_or_ui_module)
    components = AshA2ui.Info.components(resource_or_ui_module)
    fields = Map.new(AshA2ui.Info.fields(resource_or_ui_module), &{&1.name, &1})

    surface_id =
      case AshA2ui.Info.a2ui_surface_id(resource_or_ui_module) do
        {:ok, surface_id} -> surface_id
        :error -> default_surface_id(resource)
      end

    table = Enum.find(components, &(&1.name == :table))
    form = Enum.find(components, &(&1.name == :form))

    # TODO Track 2: full normalization — merge inferred/declared fields per
    # component, apply Field overrides (order/hidden/label defaults), resolve
    # default actions from the resource's primary actions, honor opts
    # (actor/tenant and future overrides/context).
    %__MODULE__{
      resource: resource,
      surface_id: surface_id,
      components: components,
      fields: fields,
      read_action: table && table.read_action,
      create_action: form && form.create_action,
      update_action: form && form.update_action,
      row_actions: (table && table.row_actions) || []
    }
  end

  defp default_surface_id(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end
end
