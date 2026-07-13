defmodule AshA2ui.Csv do
  @moduledoc """
  Minimal RFC-4180 CSV encoding for the file-export feature — no dependency,
  server-side only. `encode/2` takes the header cells and the row lists and
  returns one CRLF-joined CSV binary; `data_url/1` wraps a binary as the
  base64 `text/csv` data URL the frozen `downloadFile` contract carries.
  """

  @doc """
  Encodes one CSV document: `headers` (a list of cell values) followed by
  `rows` (lists of cell values), CRLF-separated, with RFC-4180 quoting —
  any cell containing a comma, double quote, CR or LF is wrapped in double
  quotes with inner quotes doubled. Non-binary cells are stringified
  (`nil` -> `""`).
  """
  @spec encode([term], [[term]]) :: binary
  def encode(headers, rows) do
    [headers | rows]
    |> Enum.map_join("\r\n", fn cells -> Enum.map_join(cells, ",", &cell/1) end)
    |> Kernel.<>("\r\n")
  end

  @doc """
  The `data:text/csv;base64,…` URL of a CSV binary — the `"dataUrl"` arg of
  the frozen `downloadFile` contract.
  """
  @spec data_url(binary) :: String.t()
  def data_url(csv) when is_binary(csv) do
    "data:text/csv;base64," <> Base.encode64(csv)
  end

  defp cell(nil), do: ""

  # Composite values (list/map cells of report rows) render inspected —
  # CSV cells are scalar by nature.
  defp cell(value) when is_list(value) or is_map(value), do: cell(inspect(value))

  defp cell(value) do
    text = to_string(value)

    if String.contains?(text, [",", "\"", "\r", "\n"]) do
      "\"" <> String.replace(text, "\"", "\"\"") <> "\""
    else
      text
    end
  end
end
