defmodule AshA2ui.Experience do
  @moduledoc """
  The opt-in "experience v2" layer: explicit task modes (browse / create /
  view / edit), conditional pagination, semantic action labels, typed
  feedback, and data-driven empty states.

  Enabled per application:

      config :ash_a2ui, :experience_version, 2

  The default (`1`, or any non-`2` value) is the pre-existing behavior byte
  for byte: nothing in the encoders or the action handler consults this
  module unless `v2?/0` is true.

  ## The /ui reserved state (v2)

  The initial data model's `"ui"` region gains (alongside the classic
  `"status"` / `"action_result"` / `"action_result_text"` entries):

    * `"intent"` — the client-facing task intent: `"browse"`, `"create"`,
      `"view"`, or `"edit"`.
    * `"panel"` — the record task panel: `"visible"` and `"submit_visible"`
      are zero-or-one visibility sentinels (`[]` hidden, one item visible —
      the exact technique the row-action `visible_when` slots use, see
      `AshA2ui.Conditions`), plus `"mode"`, `"title"`, `"primary_label"`,
      and `"record_id"`.
    * `"feedback"` — the last action outcome: `"kind"` (`nil`, `"success"`,
      or `"error"`) and `"message"`.

  ## Query-state sentinels (v2)

  Every `/query` state (initial and refreshed) carries
  `"_pagination_visible"`, `"_previous_visible"`, `"_next_visible"` (the
  zero-or-one sentinels the pagination row and its prev/next buttons are
  templated over) and `"_range_text"` (the result-range text, e.g.
  `"1–5 of 42"` / `"Showing 1–5"`). See `pagination_state/2`.

  ## Per-table empty-state sentinels (v2)

  The data model carries `"_empty_visible"` (`"_empty_visible_<table>"` on
  multi-table surfaces) — the same sentinel shape, `[]` while records exist —
  and `"_empty_message"` with the humanized "No <resource> records yet."
  text. Every records rewrite refreshes the sentinel, so the empty state
  toggles with the data.

  ## New client actions (v2)

    * `"start_create"` — open the panel in create mode over a fresh `/form`.
    * `"view_record"` — authorized read + form population in view mode
      (no submit offered).
    * `"start_edit"` — authorized read + form population in edit mode
      ("Save changes" submit).
    * `"cancel_record_task"` — back to browse, form reset, feedback cleared.

  Under experience v1 these names are rejected like any unknown action.
  """

  alias AshA2ui.ResolvedView

  @typedoc "The record task panel modes (`:hidden` for the closed state)."
  @type mode :: :create | :view | :edit | :hidden

  @doc """
  The configured experience version: `1` (default, byte-identical behavior)
  or `2` (the experience layer).
  """
  @spec version() :: 1 | 2
  def version, do: Application.get_env(:ash_a2ui, :experience_version, 1)

  @doc """
  Whether the experience v2 layer is enabled.
  """
  @spec v2?() :: boolean
  def v2?, do: version() == 2

  @doc """
  The zero-or-one visibility sentinel value: `[]` (hidden) or a one-item
  list (visible) — the exact shape the row-action `visible_when` slots bind
  (see `AshA2ui.Conditions.row_visibility/3`).
  """
  @spec sentinel(boolean) :: list
  def sentinel(true), do: [%{"id" => "on"}]
  def sentinel(false), do: []

  @doc """
  The initial `/ui/*` state as a flat `%{path => value}` map (paths keyed
  exactly like the `updateDataModel` writes the action handler emits).
  `/ui/panel/visible` and `/ui/panel/submit_visible` hold the hidden
  sentinel — a fresh surface is in browse mode with the record panel closed.
  """
  @spec initial_ui_state(ResolvedView.t()) :: %{String.t() => term}
  def initial_ui_state(_view) do
    %{
      "/ui/intent" => "browse",
      "/ui/panel/visible" => sentinel(false),
      "/ui/panel/mode" => nil,
      "/ui/panel/title" => "",
      "/ui/panel/primary_label" => "",
      "/ui/panel/record_id" => nil,
      "/ui/panel/submit_visible" => sentinel(false),
      "/ui/feedback/kind" => nil,
      "/ui/feedback/message" => ""
    }
  end

  @doc false
  # The initial state nested under the data model's `"ui"` key (the flat
  # `initial_ui_state/1` map is the single source of truth).
  def ui_data(view) do
    Enum.reduce(initial_ui_state(view), %{}, fn {path, value}, acc ->
      ["ui" | segments] = path |> String.trim_leading("/") |> String.split("/")
      put_in_segments(acc, segments, value)
    end)
  end

  defp put_in_segments(map, [key], value), do: Map.put(map, key, value)

  defp put_in_segments(map, [key | rest], value) do
    Map.update(map, key, put_in_segments(%{}, rest, value), &put_in_segments(&1, rest, value))
  end

  @doc """
  The create affordance / create-task label: `"Create " <> humanized
  resource name` (e.g. `"Create Appointment"`).
  """
  @spec create_label(ResolvedView.t()) :: String.t()
  def create_label(view), do: "Create #{resource_label(view)}"

  @doc """
  The edit-task primary button label.
  """
  @spec save_changes_label() :: String.t()
  def save_changes_label, do: "Save changes"

  @doc """
  The panel heading for `mode` (`:create` / `:view` / `:edit`), e.g.
  `"Edit Appointment"`.
  """
  @spec panel_title(:create | :view | :edit, ResolvedView.t()) :: String.t()
  def panel_title(:create, view), do: create_label(view)
  def panel_title(:view, view), do: "View #{resource_label(view)}"
  def panel_title(:edit, view), do: "Edit #{resource_label(view)}"

  @doc """
  The humanized resource short name (e.g. `"Appointment"`).
  """
  @spec resource_label(ResolvedView.t()) :: String.t()
  def resource_label(view) do
    view.resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> humanize()
  end

  @doc """
  The per-table empty-state text (e.g. `"No Appointment records yet."`).
  """
  @spec empty_message(ResolvedView.t(), ResolvedView.table()) :: String.t()
  def empty_message(view, table) do
    label =
      if ResolvedView.multi_table?(view) do
        table.name |> to_string() |> humanize()
      else
        resource_label(view)
      end

    "No #{label} records yet."
  end

  @doc false
  # The root data-model path of a table's `_empty_visible` sentinel
  # (unsuffixed on single-table surfaces, `_<table>`-suffixed on
  # multi-table surfaces — the same scheme as the component ids).
  def empty_visible_path(view, table) do
    if ResolvedView.multi_table?(view) do
      "/_empty_visible_#{table.name}"
    else
      "/_empty_visible"
    end
  end

  @doc """
  The `/ui/panel` value for the task panel in `mode`:

    * `:hidden` — the closed state (empty sentinels, everything blank).
    * `:create` — visible, primary label = `create_label/1`.
    * `:view` — visible, no primary label (the submit stays hidden).
    * `:edit` — visible, primary label = `save_changes_label/0`.
  """
  @spec panel_state(mode, ResolvedView.t(), term) :: map
  def panel_state(:hidden) do
    %{
      "visible" => sentinel(false),
      "mode" => nil,
      "title" => "",
      "primary_label" => "",
      "record_id" => nil,
      "submit_visible" => sentinel(false)
    }
  end

  def panel_state(mode, view, record_id) when mode in [:create, :view, :edit] do
    primary_label =
      case mode do
        :create -> create_label(view)
        :edit -> save_changes_label()
        :view -> ""
      end

    %{
      "visible" => sentinel(true),
      "mode" => to_string(mode),
      "title" => panel_title(mode, view),
      "primary_label" => primary_label,
      "record_id" => (record_id && to_string(record_id)) || nil,
      "submit_visible" => sentinel(primary_label != "")
    }
  end

  @doc """
  A typed feedback value: `%{"kind" => kind, "message" => message}` where
  `kind` is `"success"` / `"error"` / `nil`.
  """
  @spec feedback(String.t() | nil, String.t()) :: map
  def feedback(kind, message \\ "")
  def feedback(kind, message) when is_binary(message), do: %{"kind" => kind, "message" => message}

  @doc """
  The cleared feedback value (`nil` kind, empty message).
  """
  @spec clear_feedback() :: map
  def clear_feedback, do: feedback(nil, "")

  @doc """
  The pagination visibility/range state derived from a `/query` state map
  (string-keyed, as built by `AshA2ui.QueryRunner.state/4`):

    * `visible?` — the pagination row shows when paging back is possible
      (`page > 1`) or there are further records (`hasMore`).
    * `previous?` / `next?` — the individual affordances.
    * `range_text` — with a `totalCount` present: `"<first>–<last> of
      <total>"`; otherwise `"Showing <first>–<last>"`. `record_count` (the
      rows on the current page, when the caller has them) sharpens the last
      entry on a sparse final page. Empty result sets render `""`.

  `record_count` defaults to `nil` (upper-bound estimate from page/pageSize).
  """
  @spec pagination_state(map, non_neg_integer | nil) :: %{
          visible?: boolean,
          previous?: boolean,
          next?: boolean,
          range_text: String.t()
        }
  def pagination_state(query_state, record_count \\ nil) when is_map(query_state) do
    page = integer_value(query_state["page"], 1)
    page_size = integer_value(query_state["pageSize"], 10)
    has_more = query_state["hasMore"] == true
    total = query_state["totalCount"]
    first = (page - 1) * page_size + 1
    last = last_entry(first, page * page_size, total, has_more, record_count)

    %{
      visible?: page > 1 or has_more,
      previous?: page > 1,
      next?: has_more,
      range_text: range_text(first, last, total)
    }
  end

  # A known total caps the range; the probe (`hasMore`) extends it; on the
  # final page the actual row count settles it.
  defp last_entry(_first, upper, total, _has_more, _count) when is_integer(total),
    do: min(upper, total)

  defp last_entry(_first, upper, _total, true, _count), do: upper

  defp last_entry(first, _upper, _total, false, count) when is_integer(count),
    do: first + count - 1

  defp last_entry(_first, upper, _total, false, _count), do: upper

  defp range_text(_first, last, _total) when last < 1, do: ""
  defp range_text(first, last, total) when is_integer(total), do: "#{first}–#{last} of #{total}"
  defp range_text(first, last, _total), do: "Showing #{first}–#{last}"

  @doc false
  # Adorns a `/query` state map with the v2 sentinel keys (a no-op under
  # v1). Idempotent, so callers that already-adorned states pass through
  # unchanged in value.
  def with_pagination_sentinels(query_state, record_count) do
    if v2?() and is_map(query_state) do
      state = pagination_state(query_state, record_count)

      Map.merge(query_state, %{
        "_pagination_visible" => sentinel(state.visible?),
        "_previous_visible" => sentinel(state.previous?),
        "_next_visible" => sentinel(state.next?),
        "_range_text" => state.range_text
      })
    else
      query_state
    end
  end

  defp integer_value(value, _default) when is_integer(value), do: value

  defp integer_value(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _unparsable -> default
    end
  end

  defp integer_value(_value, default), do: default

  defp humanize(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
