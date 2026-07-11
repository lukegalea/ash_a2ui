defmodule AshA2ui.RowLayout do
  @moduledoc """
  Target struct for the `row_layout` DSL entity — the card-style record
  layout of a `:table` component: a header row (title + optional badge,
  alongside the row's actions) above an N-column grid of caption-labeled
  metadata values.
  """

  defstruct [
    :title,
    :badge,
    :meta,
    badge_text: [],
    columns: 2,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          title: atom,
          badge: atom | nil,
          meta: [atom] | nil,
          badge_text: keyword(String.t()),
          columns: pos_integer
        }

  @doc """
  The computed badge row data a serialized record carries when its table
  declares a `row_layout` with a `badge`: `%{"_badge_<field>" => text}`,
  where the text is the `badge_text` entry matching the record's value
  (atom/boolean values only — keyword keys), the humanized value otherwise,
  and `""` for `nil`. Empty for layout-less tables and badge-less layouts.

  Shared by the encoder and `AshA2ui.ActionHandler` so initial renders and
  query/action refreshes serialize rows identically.
  """
  @spec badge_data(t() | nil, Ash.Resource.record()) :: %{String.t() => String.t()}
  def badge_data(layout, record)

  def badge_data(nil, _record), do: %{}
  def badge_data(%__MODULE__{badge: nil}, _record), do: %{}

  def badge_data(%__MODULE__{badge: badge} = layout, record) do
    %{"_badge_#{badge}" => badge_text(layout, Map.get(record, badge))}
  end

  defp badge_text(_layout, nil), do: ""

  defp badge_text(layout, value) do
    declared = is_atom(value) && Keyword.get(layout.badge_text, value)

    declared ||
      value
      |> to_string()
      |> String.replace("_", " ")
      |> String.capitalize()
  end
end
