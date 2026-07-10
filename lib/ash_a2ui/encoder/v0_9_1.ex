defmodule AshA2ui.Encoder.V0_9_1 do
  @moduledoc """
  A2UI v0.9.1 encoder: emits the protocol envelope and basic-catalog component
  composition (tables as `List` + `Row`/`Column` — the basic catalog has no
  Table component).

  TODO Track 2: implement. Both callbacks currently raise.
  """

  @behaviour AshA2ui.Encoder

  @impl true
  def encode_surface(_resolved_view, _records, _opts) do
    # TODO Track 2: emit createSurface -> updateComponents -> updateDataModel
    # (camelCase keys, basic catalogId, JSON-Pointer data bindings).
    raise "TODO Track 2: AshA2ui.Encoder.V0_9_1.encode_surface/3 is not implemented yet"
  end

  @impl true
  def encode_data_model(_resolved_view, _records, _opts) do
    # TODO Track 2: emit the updateDataModel message for the surface's data.
    raise "TODO Track 2: AshA2ui.Encoder.V0_9_1.encode_data_model/3 is not implemented yet"
  end
end
