defmodule AshA2ui.Verifiers.VerifyEditable do
  @moduledoc """
  Verifies at compile time that `editable` blocks (inline cell editing) are
  sound:

    * only `:table` components may declare an `editable` block,
    * a table may not combine `editable` with a `row_layout` (card rows
      render read-only meta values),
    * every editable field is one of the table's fields,
    * when the target resource is resolvable: the resolved `update_action`
      is an update action of the resource, and every editable field is
      accepted by it (an attribute in its `accept` list or an argument).

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Checks needing the target resource degrade
  gracefully when it cannot be resolved at verification time, matching the
  other verifiers.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info, as: ResourceInfo
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    components =
      dsl_state
      |> Verifier.get_entities([:a2ui])
      |> Enum.filter(&is_struct(&1, AshA2ui.Component))

    components
    |> Enum.filter(& &1.editable)
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case verify_component(component, dsl_state, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_component(component, dsl_state, module) do
    key = AshA2ui.Component.key(component)

    with :ok <- verify_table(component, key, module),
         :ok <- verify_no_row_layout(component, key, module),
         :ok <- verify_table_fields(component, key, module) do
      verify_update_action(component, key, dsl_state, module)
    end
  end

  defp verify_table(%{name: :table}, _key, _module), do: :ok

  defp verify_table(_component, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :editable],
       message:
         "component #{inspect(key)} cannot declare an editable block: inline cell " <>
           "editing is only supported on :table components"
     )}
  end

  defp verify_no_row_layout(%{row_layout: nil}, _key, _module), do: :ok

  defp verify_no_row_layout(_component, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :editable],
       message:
         "table #{inspect(key)} cannot combine an editable block with a row_layout: " <>
           "card rows render read-only meta values"
     )}
  end

  defp verify_table_fields(component, key, module) do
    table_fields = component.fields || []

    case Enum.find(component.editable.fields, &(&1 not in table_fields)) do
      nil ->
        :ok

      unknown ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :editable, :fields],
           message:
             "editable field #{inspect(unknown)} is not one of table #{inspect(key)}'s " <>
               "fields #{inspect(table_fields)}"
         )}
    end
  end

  defp verify_update_action(component, key, dsl_state, module) do
    case target_resource(dsl_state) do
      nil ->
        :ok

      resource ->
        action_name =
          component.editable.update_action || primary_update_name(resource)

        case action_name && ResourceInfo.action(resource, action_name) do
          %{type: :update} = action ->
            verify_accepted_fields(component, key, action, module)

          _missing_or_not_update ->
            {:error,
             DslError.exception(
               module: module,
               path: [:a2ui, :component, key, :editable, :update_action],
               message:
                 "editable update_action #{inspect(action_name)} is not an update action " <>
                   "of #{inspect(resource_name(resource))}"
             )}
        end
    end
  end

  defp verify_accepted_fields(component, key, action, module) do
    accepted =
      MapSet.new(List.wrap(Map.get(action, :accept)) ++ Enum.map(action.arguments, & &1.name))

    case Enum.find(component.editable.fields, &(not MapSet.member?(accepted, &1))) do
      nil ->
        :ok

      field ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :editable, :fields],
           message:
             "editable field #{inspect(field)} is not accepted by update action " <>
               "#{inspect(action.name)} (accepts/arguments: #{inspect(MapSet.to_list(accepted))})"
         )}
    end
  end

  defp primary_update_name(resource) do
    case primary_update(resource) do
      %{name: name} -> name
      nil -> nil
    end
  end

  defp primary_update(resource) when is_atom(resource),
    do: ResourceInfo.primary_action(resource, :update)

  defp primary_update(dsl_state), do: ResourceInfo.primary_action(dsl_state, :update)

  defp target_resource(dsl_state) do
    case Verifier.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if Ash.Resource.Dsl in Verifier.get_persisted(dsl_state, :extensions, []),
          do: dsl_state

      resource ->
        if Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource), do: resource
    end
  end

  defp resource_name(resource) when is_atom(resource), do: resource
  defp resource_name(dsl_state), do: Verifier.get_persisted(dsl_state, :module)
end
