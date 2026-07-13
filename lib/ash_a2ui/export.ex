defmodule AshA2ui.Export do
  @moduledoc """
  Target struct for the `export` DSL entity (CSV file export): declares that
  a `:table` or `:report` component offers a server-generated CSV download,
  delivered through the v1.0 `callFunction` channel as a `downloadFile`
  client-function call (the shipped hook registers it as a built-in).

  ## The frozen `downloadFile` wire contract

  A successful `"export"` action emits one `callFunction` message:

      {
        "version": "v1.0",
        "functionCallId": "fc_…",
        "callFunction": {
          "call": "downloadFile",
          "args": {
            "filename": "misspellings.csv",
            "mimeType": "text/csv",
            "dataUrl": "data:text/csv;base64,…"
          }
        }
      }

  The client function triggers a browser download of `dataUrl` (a hook may
  alternatively receive an `"url"` arg — a signed one-time URL — for hosts
  that upload instead of inlining; the built-in prefers `dataUrl` and falls
  back to `url`). Because delivery rides `callFunction`, **export is
  v1.0-only**: declaring an `export` block on a `spec_version "0.9.1"`
  surface is a compile-time error (`AshA2ui.Verifiers.VerifyExport`). There
  is no 0.9.1 fallback — 0.9.1 has no server->client RPC channel to carry a
  download, and encoding files into the data model would be a protocol
  abuse.

  See the `export` entity docs on `AshA2ui` for the DSL options.
  """

  defstruct [
    :filename,
    :columns,
    column_select: false,
    limit: 10_000,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          filename: String.t() | nil,
          columns: [atom] | nil,
          column_select: boolean,
          limit: pos_integer
        }
end
