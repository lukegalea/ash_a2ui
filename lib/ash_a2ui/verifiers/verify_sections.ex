defmodule AshA2ui.Verifiers.VerifySections do
  @moduledoc """
  Verifies at compile time that `sections` blocks (dynamic table sets) are
  sound:

    * only `:table` components may declare a `sections` block,
    * a sectioned table may not also declare `select_context` (per-row
      context selection assumes a statically named table),
    * `scope_by` is a public attribute of the surface's resource,
    * `label` / `value` / `sort`, when declared, are public attributes of the
      section `source`,
    * `read_action`, when declared, is a read action of the source,
    * a source with a composite primary key requires an explicit `value`.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Skipped checks degrade gracefully when the target
  resource cannot be resolved at verification time (cross-module compile
  ordering), matching the other verifiers.
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
    |> Enum.filter(& &1.sections)
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
         :ok <- verify_no_select_context(component, key, module),
         :ok <- verify_scope_by(component, key, dsl_state, module) do
      verify_source(component, key, module)
    end
  end

  defp verify_table(%{name: :table}, _key, _module), do: :ok

  defp verify_table(_component, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :sections],
       message:
         "component #{inspect(key)} cannot declare a sections block: dynamic table " <>
           "sets are only supported on :table components"
     )}
  end

  defp verify_no_select_context(%{select_context: nil}, _key, _module), do: :ok

  defp verify_no_select_context(_component, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :sections],
       message:
         "table #{inspect(key)} cannot combine a sections block with select_context: " <>
           "per-row context selection assumes a statically named table"
     )}
  end

  defp verify_scope_by(component, key, dsl_state, module) do
    case target_resource(dsl_state) do
      nil ->
        :ok

      resource ->
        if public_attribute?(resource, component.sections.scope_by) do
          :ok
        else
          {:error,
           DslError.exception(
             module: module,
             path: [:a2ui, :component, key, :sections, :scope_by],
             message:
               "scope_by #{inspect(component.sections.scope_by)} is not a public " <>
                 "attribute of #{inspect(resource_name(resource))}"
           )}
        end
    end
  end

  defp verify_source(component, key, module) do
    sections = component.sections
    source = sections.source

    if Code.ensure_loaded?(source) and ResourceInfo.resource?(source) do
      with :ok <- verify_source_attribute(sections, :label, key, module),
           :ok <- verify_source_attribute(sections, :value, key, module),
           :ok <- verify_source_attribute(sections, :sort, key, module),
           :ok <- verify_read_action(sections, key, module) do
        verify_value_inferable(sections, key, module)
      end
    else
      :ok
    end
  end

  defp verify_source_attribute(sections, option, key, module) do
    case Map.fetch!(sections, option) do
      nil ->
        :ok

      name ->
        if public_attribute?(sections.source, name) do
          :ok
        else
          {:error,
           DslError.exception(
             module: module,
             path: [:a2ui, :component, key, :sections, option],
             message:
               "#{option} #{inspect(name)} is not a public attribute of the section " <>
                 "source #{inspect(sections.source)}"
           )}
        end
    end
  end

  defp verify_read_action(%{read_action: nil}, _key, _module), do: :ok

  defp verify_read_action(sections, key, module) do
    case ResourceInfo.action(sections.source, sections.read_action) do
      %{type: :read} ->
        :ok

      _missing_or_not_read ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :sections, :read_action],
           message:
             "read_action #{inspect(sections.read_action)} is not a read action of the " <>
               "section source #{inspect(sections.source)}"
         )}
    end
  end

  defp verify_value_inferable(%{value: nil} = sections, key, module) do
    case ResourceInfo.primary_key(sections.source) do
      [_single] ->
        :ok

      composite ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :sections, :value],
           message:
             "cannot infer the section value: #{inspect(sections.source)} has a " <>
               "composite primary key #{inspect(composite)} — set value explicitly"
         )}
    end
  end

  defp verify_value_inferable(_sections, _key, _module), do: :ok

  defp public_attribute?(resource, name) do
    match?(%{public?: true}, ResourceInfo.attribute(resource, name))
  end

  # The resource whose attributes scope_by must exist on: for_resource in a
  # standalone UI module, the resource itself otherwise. Unresolvable (e.g.
  # not yet compiled) -> checks are skipped, like VerifyFields.
  defp target_resource(dsl_state) do
    case Verifier.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if Ash.Resource.Dsl in Verifier.get_persisted(dsl_state, :extensions, []),
          do: dsl_state

      resource ->
        if Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource), do: resource
    end
  end

  defp resource_name(dsl_state_or_module) when is_atom(dsl_state_or_module),
    do: dsl_state_or_module

  defp resource_name(dsl_state), do: Verifier.get_persisted(dsl_state, :module)
end
