defmodule AshA2ui.Conditions do
  @moduledoc """
  Evaluates `visible_when` per-record conditions (see `AshA2ui.Action`) and
  computes the per-row visibility data serialized into record rows.

  A condition list is a keyword list ANDed together. For each `{key, expected}`
  pair the record's `key` value is compared:

    * `expected == nil` — the value must be `nil` (`is_nil` semantics)
    * `expected` is a list — the value must be a member (each member cast to
      the field's type first)
    * anything else — equality, with `expected` cast to the field's type

  Keys are public attributes or public expression calculations; calculation
  keys must be loaded on the record (a missing/`Ash.NotLoaded` value evaluates
  as `nil`). This is deliberately *not* a rules engine — anything beyond
  simple equality belongs in a dedicated read action or Ash policy.

  ## Per-row visibility data

  When a table's `row_actions` include actions with `visible_when`
  conditions, every serialized row gains (see `row_visibility/3`):

    * `"_actions"` — the names (strings) of the row actions visible for this
      record (unconditional actions always included)
    * `"_visible_<action>"` per conditional action — `[%{"id" => <record id>}]`
      when visible, `[]` when hidden. This list powers the emitted per-action
      template slot (a `List` templated over the row-relative
      `_visible_<action>` path) so renderers that support nested templates
      hide the button; renderers that don't can still consult `"_actions"`.
  """

  alias Ash.Resource.Info, as: ResourceInfo

  @doc """
  Whether `record` satisfies every condition in `conditions` (an empty list
  is always visible).
  """
  @spec visible?(module, [{atom, term}], Ash.Resource.record()) :: boolean
  def visible?(_resource, [], _record), do: true

  def visible?(resource, conditions, record) do
    Enum.all?(conditions, fn {key, expected} ->
      matches?(loaded_value(record, key), expected, resource, key)
    end)
  end

  @doc """
  The calculation names among the condition keys — the `Ash.Query.load/2`
  statement needed before evaluating the conditions on a record.
  """
  @spec condition_loads(module, [{atom, term}]) :: [atom]
  def condition_loads(resource, conditions) do
    conditions
    |> Keyword.keys()
    |> Enum.filter(&(not is_nil(ResourceInfo.calculation(resource, &1))))
    |> Enum.uniq()
  end

  @doc """
  The `{action_name, conditions}` pairs among `table.row_actions` that carry
  `visible_when` conditions (from the view's `action` entities).
  """
  @spec conditional_actions(AshA2ui.ResolvedView.t(), map) :: [{atom, [{atom, term}]}]
  def conditional_actions(view, table) do
    for name <- table.row_actions,
        action = Map.get(view.actions, name),
        match?(%{visible_when: [_ | _]}, action),
        do: {name, action.visible_when}
  end

  @doc """
  The extra row keys (`"_actions"` + `"_visible_<action>"`, see the
  moduledoc) for `record` in `table`. Returns `%{}` when none of the table's
  row actions carry conditions — rows on condition-free surfaces are
  unchanged.
  """
  @spec row_visibility(AshA2ui.ResolvedView.t(), map, Ash.Resource.record()) :: map
  def row_visibility(view, table, record) do
    case conditional_actions(view, table) do
      [] ->
        %{}

      conditional ->
        visible =
          Map.new(conditional, fn {name, conditions} ->
            {name, visible?(view.resource, conditions, record)}
          end)

        id = json_id(Map.get(record, :id))

        slots =
          Map.new(conditional, fn {name, _conditions} ->
            {"_visible_#{name}", (visible[name] && [%{"id" => id}]) || []}
          end)

        Map.put(
          slots,
          "_actions",
          for(name <- table.row_actions, Map.get(visible, name, true), do: to_string(name))
        )
    end
  end

  defp matches?(actual, nil, _resource, _key), do: is_nil(actual)

  defp matches?(actual, expected, resource, key) when is_list(expected) do
    Enum.any?(expected, &(cast(resource, key, &1) == actual))
  end

  defp matches?(actual, expected, resource, key) do
    cast(resource, key, expected) == actual
  end

  defp loaded_value(record, key) do
    case Map.get(record, key) do
      %Ash.NotLoaded{} -> nil
      value -> value
    end
  end

  # Cast the DSL-side expected value to the field's type so conditions like
  # `status: :pending` match regardless of how the term was written. A failed
  # cast falls back to the raw term (plain equality).
  defp cast(resource, key, value) do
    case ResourceInfo.attribute(resource, key) || ResourceInfo.calculation(resource, key) do
      %{type: type, constraints: constraints} ->
        case Ash.Type.cast_input(type, value, constraints) do
          {:ok, cast} -> cast
          _error -> value
        end

      nil ->
        value
    end
  end

  defp json_id(value) when is_binary(value) or is_number(value) or is_nil(value), do: value
  defp json_id(value), do: to_string(value)
end
