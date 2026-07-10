defmodule AshA2ui.Verifiers.VerifyActions do
  @moduledoc """
  Verifies at compile time that every action referenced by a component exists
  on the resolved resource with a compatible type:

    * `read_action` must exist and be of type `:read`,
    * `create_action` must exist and be of type `:create`,
    * `update_action` must exist and be of type `:update`,
    * every entry in `row_actions` must exist (any type — destroy and generic
      actions are allowed).

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Skipped when no resource can be resolved (standalone
  UI module without `for_resource`) — `AshA2ui.Info.resource!/1` reports that
  at runtime.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @typed_options [read_action: :read, create_action: :create, update_action: :update]

  @impl true
  def verify(dsl_state) do
    case target_resource(dsl_state) do
      nil ->
        :ok

      target ->
        module = Verifier.get_persisted(dsl_state, :module)
        verify_components(dsl_state, target, module)
    end
  end

  defp verify_components(dsl_state, target, module) do
    dsl_state
    |> components()
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case verify_component(component, target, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_component(component, target, module) do
    with :ok <- verify_typed_actions(component, target, module) do
      verify_row_actions(component, target, module)
    end
  end

  defp verify_typed_actions(component, target, module) do
    Enum.reduce_while(@typed_options, :ok, fn {option, type}, :ok ->
      case verify_typed_action(component, Map.fetch!(component, option), option, type,
             target: target,
             module: module
           ) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_typed_action(_component, nil, _option, _type, _ctx), do: :ok

  defp verify_typed_action(component, name, option, type, ctx) do
    case Info.action(ctx[:target], name) do
      nil ->
        {:error,
         DslError.exception(
           module: ctx[:module],
           path: [:a2ui, :component, component.name, option],
           message: "#{option} #{inspect(name)} does not exist on #{inspect(resource_name(ctx))}"
         )}

      %{type: ^type} ->
        :ok

      %{type: actual} ->
        {:error,
         DslError.exception(
           module: ctx[:module],
           path: [:a2ui, :component, component.name, option],
           message:
             "#{option} #{inspect(name)} must be of type #{inspect(type)}, " <>
               "but it is a #{inspect(actual)} action"
         )}
    end
  end

  defp verify_row_actions(component, target, module) do
    case Enum.find(component.row_actions, &is_nil(Info.action(target, &1))) do
      nil ->
        :ok

      missing ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, component.name, :row_actions],
           message:
             "row action #{inspect(missing)} does not exist on " <>
               inspect(resource_name(target: target, module: module))
         )}
    end
  end

  # For on-resource mode the target is the DSL state map; name the module
  # being compiled instead.
  defp resource_name(ctx) do
    case ctx[:target] do
      target when is_atom(target) -> target
      _dsl_state -> ctx[:module]
    end
  end

  defp components(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Component))
  end

  defp target_resource(dsl_state) do
    case Verifier.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if Ash.Resource.Dsl in Verifier.get_persisted(dsl_state, :extensions, []),
          do: dsl_state

      resource ->
        if Code.ensure_loaded?(resource) and Info.resource?(resource), do: resource
    end
  end
end
