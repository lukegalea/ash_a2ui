defmodule AshA2ui.Encoder do
  @moduledoc """
  Behaviour for encoding a resolved view + records into A2UI protocol
  messages. Implementations are versioned per spec release (see
  `AshA2ui.Encoder.V0_9_1`).

  FROZEN CONTRACT — callback signatures are the interface every parallel track
  codes against; do not change outside an integration commit.

  Messages are plain maps with string (camelCase) keys, ready for JSON
  encoding, each validating against the vendored spec schemas in
  `priv/a2ui/v0_9_1/`.
  """

  @doc """
  Encodes the full surface bootstrap: the ordered message list
  `createSurface` -> `updateComponents` -> `updateDataModel`.
  """
  @callback encode_surface(
              resolved_view :: AshA2ui.ResolvedView.t(),
              records :: [map],
              opts :: keyword
            ) :: [map]

  @doc """
  Encodes a data-only refresh: a single `updateDataModel` message.
  """
  @callback encode_data_model(
              resolved_view :: AshA2ui.ResolvedView.t(),
              records :: [map],
              opts :: keyword
            ) :: map
end
