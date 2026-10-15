defmodule AshA2ui.Board do
  @moduledoc """
  Boards: a sectioned `:table` whose sections are the enumerated values of an
  attribute, rendered as lanes side by side (`display :board`).

  A board adds no component kind. It rides on `sections` (see
  `AshA2ui.Sections`): a `sections` block without a `source` enumerates its
  sections from `scope_by`'s values — an `Ash.Type.Enum`'s `values/0`, or
  the attribute's (or calculation's) `one_of` constraint — in declaration
  order, narrowed and reordered by `values` and headed per `labels`. Each
  lane is an ordinary expanded table: runtime name
  `<template_key>_<sanitized value>`, records at `/records/<lane>`, query
  state at `/query/<lane>`, reads ANDed with `scope_by == value`. No read is
  issued to enumerate the lanes, and an empty lane is kept (it renders its
  empty state).

  Cards move between lanes through **transition row actions**: actions
  gated by `visible_when` on the lane attribute that refresh the template
  key (which fans out to every lane). There is no drag-and-drop: the basic
  catalog has no pointer events.

  ## Lane totals

  Each lane's heading shows its total, served at the reserved root path
  `/_lane_total_<lane>` as a string: the lane query's `totalCount` when it
  has one, else the number of rows in the lane (with a `+` suffix when the
  query reports more rows but no count). Every records rewrite of a lane
  (initial data model, refreshes, `"query"` actions) rewrites it.

  The vocabulary (kanban lanes over an attribute's values) comes from
  PyroManiac (<https://github.com/frankdugan3/pyro_maniac>), an Ash UI DSL.
  This is our own implementation over `sections`; see
  `notes/2026-10-15-pyro-maniac-borrowings.md`.
  """

  alias Ash.Resource.Info, as: ResourceInfo

  @typedoc "One synthesized lane record (the source-less section record)."
  @type lane :: %{value: atom | String.t(), label: String.t()}

  @doc """
  The enumerated values of `name` on `resource` (a resource module or its
  DSL state): an `Ash.Type.Enum`'s values, else a non-empty `one_of`
  constraint. Returns `:error` when `name` is not an attribute or
  calculation, or has no enumerable values.
  """
  @spec enumerated_values(module | map, atom) :: {:ok, [atom | String.t()]} | :error
  def enumerated_values(resource, name) do
    case enumeration(resource, name) do
      {:ok, values, _labeller} -> {:ok, values}
      :error -> :error
    end
  end

  @doc """
  The lanes of a source-less sections config (`%{scope_by, values, labels}`)
  over `resource`, in order: `%{value, label}` per lane. `values` picks a
  subset and an order (matched against the enumeration by string form, the
  enumerated value kept); `labels` overrides headings, which otherwise are
  the enum's label or the humanized value.

  Raises `ArgumentError` when `scope_by` has no enumerable values (the
  verifier rejects that at compile time where the resource is resolvable).
  """
  @spec lanes(module, map) :: [lane]
  def lanes(resource, config) do
    case enumeration(resource, config.scope_by) do
      {:ok, all, labeller} ->
        config
        |> Map.get(:values)
        |> chosen_values(all)
        |> Enum.map(&%{value: &1, label: lane_label(&1, Map.get(config, :labels, []), labeller)})

      :error ->
        raise ArgumentError,
              "sections without a source need enumerable values: scope_by " <>
                "#{inspect(config.scope_by)} of #{inspect(resource)} is neither an " <>
                "Ash.Type.Enum nor constrained by one_of"
    end
  end

  @doc """
  The enumerated value matching `value` by string form, or `nil`.
  """
  @spec match_value(atom | String.t(), [atom | String.t()]) :: atom | String.t() | nil
  def match_value(value, all) do
    string = to_string(value)
    Enum.find(all, &(to_string(&1) == string))
  end

  @doc "Whether an (expanded) resolved table is a board lane."
  @spec lane?(map) :: boolean
  def lane?(%{component: %{display: :board}, section: %{}}), do: true
  def lane?(_table), do: false

  @doc "The reserved root data-model path of a lane's total."
  @spec total_path(map) :: String.t()
  def total_path(table), do: "/_lane_total_#{table.name}"

  @doc """
  The lane total text for `row_count` rows and the lane's `/query` state
  (`nil` for lanes without a query): `totalCount` when known, else the row
  count, suffixed `+` when the query reports more rows.
  """
  @spec total_text(non_neg_integer, map | nil) :: String.t()
  def total_text(_row_count, %{"totalCount" => total}) when is_integer(total),
    do: Integer.to_string(total)

  def total_text(row_count, %{"hasMore" => true}), do: "#{row_count}+"
  def total_text(row_count, _state), do: Integer.to_string(row_count)

  @doc """
  The lanes of the board whose template key is `template`, in order.
  """
  @spec template_lanes([map], atom | String.t()) :: [map]
  def template_lanes(tables, template) do
    Enum.filter(tables, &(lane?(&1) and &1.section.template == template))
  end

  # --- enumeration ---------------------------------------------------------

  defp chosen_values(nil, all), do: all

  defp chosen_values(values, all) do
    values
    |> Enum.map(&match_value(&1, all))
    |> Enum.reject(&is_nil/1)
  end

  defp lane_label(value, labels, labeller) do
    case Enum.find(labels, fn {key, _label} -> to_string(key) == to_string(value) end) do
      {_key, label} -> to_string(label)
      nil -> labeller.(value)
    end
  end

  defp enumeration(resource, name) do
    case field_type(resource, name) do
      {type, constraints} ->
        cond do
          AshA2ui.TypeMapper.enum_type?(type) ->
            {:ok, type.values(), &enum_label(type, &1)}

          match?([_ | _], one_of(constraints)) ->
            {:ok, one_of(constraints), &humanize/1}

          true ->
            :error
        end

      nil ->
        :error
    end
  end

  defp field_type(resource, name) do
    case ResourceInfo.attribute(resource, name) || ResourceInfo.calculation(resource, name) do
      %{type: type, constraints: constraints} -> {type, constraints || []}
      _missing -> nil
    end
  end

  defp one_of(constraints) when is_list(constraints), do: Keyword.get(constraints, :one_of)
  defp one_of(_constraints), do: nil

  # `Ash.Type.Enum.label/1` is nil unless the enum declared explicit labels
  # (same rule as the encoder's choice options).
  defp enum_label(type, value) do
    case type.label(value) do
      nil -> humanize(value)
      label -> to_string(label)
    end
  end

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
