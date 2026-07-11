defmodule AshA2ui.Verifiers.VerifyNestedForms do
  @moduledoc """
  Verifies at compile time that every `nested_form` entity is sound:

    * `nested_form` entities may only appear inside `:form` components,
    * the entity's name must be an argument consumed by a
      `manage_relationship` change on **every** action the form submits
      (the declared — or primary — create and update actions), mirroring the
      AshSDUI argument→relationship mapping,
    * those changes must infer the same interaction mode on every action
      (`AshA2ui.ManagedForms.mode/1` over the sanitized manage options), and
      the mode must be v1-renderable — update-only/ignore configurations
      (no lookups, no creates) are rejected,
    * declared `fields` (create_inline) must be public writable attributes
      of the relationship's destination,
    * `option_label` / `option_value` / `option_sort` (pick_existing) must
      be public attributes of the destination; a composite destination
      primary key requires an explicit `option_value`,
    * `option_search` entries must be public string-typed attributes of the
      destination (same rule as searchable selects).

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Skipped when no resource can be resolved
  (standalone UI module without `for_resource`).
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias AshA2ui.ManagedForms
  alias AshA2ui.Verifiers.VerifyRelationships
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @option_keys [:option_label, :option_value, :option_sort]

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
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Component))
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case verify_component(component, target, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_component(%{nested_forms: []}, _target, _module), do: :ok

  defp verify_component(%{name: name, nested_forms: [nested | _]}, _target, module)
       when name != :form do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, name, :nested_form, nested.name],
       message:
         "nested_form #{inspect(nested.name)} is declared inside the #{inspect(name)} " <>
           "component: nested forms only render inside :form components"
     )}
  end

  defp verify_component(form, target, module) do
    actions = form_actions(form, target)

    Enum.reduce_while(form.nested_forms, :ok, fn nested, :ok ->
      case verify_nested_form(nested, actions, target, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # The actions the form submits through: the declared create/update
  # actions, falling back to the resource's primaries (matching
  # ResolvedView.component_action/4). A form may legitimately have only one.
  defp form_actions(form, target) do
    [
      form.create_action || primary_action_name(target, :create),
      form.update_action || primary_action_name(target, :update)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp verify_nested_form(nested, actions, target, module) do
    with {:ok, manages} <- resolve_manages(nested, actions, target, module),
         {:ok, mode, manage} <- consistent_mode(nested, manages, module) do
      destination = manage.relationship.destination

      with :ok <- verify_fields(nested, mode, destination, module),
           :ok <- verify_option_attributes(nested, destination, module),
           :ok <- verify_option_value_pk(nested, mode, destination, module) do
        VerifyRelationships.verify_option_search(
          nested.option_search,
          destination,
          module,
          [:a2ui, :component, :form, :nested_form, nested.name, :option_search],
          "nested_form #{inspect(nested.name)}"
        )
      end
    end
  end

  defp resolve_manages(nested, actions, target, module) do
    Enum.reduce_while(actions, {:ok, []}, fn action_name, {:ok, acc} ->
      case ManagedForms.manage(target, action_name, nested.name) do
        {:ok, manage} ->
          {:cont, {:ok, [{action_name, manage} | acc]}}

        :error ->
          {:halt,
           {:error,
            DslError.exception(
              module: module,
              path: [:a2ui, :component, :form, :nested_form, nested.name],
              message:
                "nested_form #{inspect(nested.name)} requires a manage_relationship change " <>
                  "consuming argument #{inspect(nested.name)} on action " <>
                  "#{inspect(action_name)} of #{inspect(target_name(target, module))} — " <>
                  "declare `argument #{inspect(nested.name)}, {:array, :map}` (or `{:array, " <>
                  ":uuid}`) plus `change manage_relationship(#{inspect(nested.name)}, ...)`"
            )}}
      end
    end)
  end

  # Every form action must infer the same interaction mode; update-only /
  # ignore configurations have no v1 rendering.
  defp consistent_mode(nested, manages, module) do
    modes =
      Enum.map(manages, fn {action_name, manage} ->
        {action_name, ManagedForms.mode(manage.opts)}
      end)

    cond do
      unrenderable = Enum.find(modes, &match?({_action, :error}, &1)) ->
        {action_name, :error} = unrenderable

        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, :form, :nested_form, nested.name],
           message:
             "nested_form #{inspect(nested.name)}'s manage_relationship on action " <>
               "#{inspect(action_name)} allows neither lookups (on_lookup) nor creates " <>
               "(on_no_match: :create) — update-only/ignore configurations have no v1 " <>
               "rendering. Use e.g. `type: :append_and_remove` (pick_existing) or " <>
               "`type: :direct_control` (create_inline)."
         )}

      modes |> Enum.map(fn {_action, mode} -> mode end) |> Enum.uniq() |> length() > 1 ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, :form, :nested_form, nested.name],
           message:
             "nested_form #{inspect(nested.name)} infers different interaction modes across " <>
               "the form's actions (#{inspect(modes)}): the create and update actions must " <>
               "manage the relationship with compatible options"
         )}

      true ->
        [{_action, {:ok, mode}} | _rest] = modes
        {_action, manage} = hd(manages)
        {:ok, mode, manage}
    end
  end

  defp verify_fields(%{fields: fields} = nested, :create_inline, destination, module)
       when is_list(fields) do
    Enum.reduce_while(fields, :ok, fn name, :ok ->
      if public_writable_attribute?(destination, name) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          DslError.exception(
            module: module,
            path: [:a2ui, :component, :form, :nested_form, nested.name, :fields],
            message:
              "nested_form #{inspect(nested.name)} field #{inspect(name)} must be a public " <>
                "writable attribute of #{inspect(destination)}"
          )}}
      end
    end)
  end

  defp verify_fields(_nested, _mode, _destination, _module), do: :ok

  defp verify_option_attributes(nested, destination, module) do
    @option_keys
    |> Enum.reject(&is_nil(Map.get(nested, &1)))
    |> Enum.reduce_while(:ok, fn option, :ok ->
      name = Map.get(nested, option)

      if match?(%{public?: true}, Info.attribute(destination, name)) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          DslError.exception(
            module: module,
            path: [:a2ui, :component, :form, :nested_form, nested.name, option],
            message:
              "#{option} #{inspect(name)} on nested_form #{inspect(nested.name)} must be a " <>
                "public attribute of #{inspect(destination)}"
          )}}
      end
    end)
  end

  defp verify_option_value_pk(%{option_value: nil} = nested, :pick_existing, destination, module) do
    case Info.primary_key(destination) do
      [_single] ->
        :ok

      composite ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, :form, :nested_form, nested.name, :option_value],
           message:
             "nested_form #{inspect(nested.name)} picks from #{inspect(destination)}, which " <>
               "has a composite primary key #{inspect(composite)} — set option_value explicitly"
         )}
    end
  end

  defp verify_option_value_pk(_nested, _mode, _destination, _module), do: :ok

  defp public_writable_attribute?(destination, name) do
    match?(%{public?: true, writable?: true}, Info.attribute(destination, name))
  end

  defp primary_action_name(target, type) do
    case Info.primary_action(target, type) do
      %{name: name} -> name
      nil -> nil
    end
  end

  defp target_name(target, _module) when is_atom(target) and not is_nil(target), do: target
  defp target_name(_dsl_state, module), do: module

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
