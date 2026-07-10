defmodule AshA2ui.Transformers.InferFields do
  @moduledoc """
  Fills in `fields` for components that omit them:

    * `:table` components get the resource's public attributes (via
      `Ash.Resource.Info.public_attributes/1`), in declaration order,
      excluding primary key attributes.
    * `:form` components get the create action's `accept` list (the
      component's `create_action` if set, otherwise the primary create),
      falling back to the update action's accepts when no create action
      matches.

  In standalone UI modules the target resource is the section's
  `for_resource`. When inference is impossible (no resolvable resource, no
  matching action, or no public attributes), `fields` is left as `nil` for
  verifiers/runtime to handle.

  Runs after all other transformers (`after?/1` returns `true`) so Ash has
  already expanded default actions and `accept :*` lists before inference.
  """

  use Spark.Dsl.Transformer

  alias Ash.Resource.Info
  alias Spark.Dsl.Transformer

  @impl true
  def after?(_), do: true

  @impl true
  def transform(dsl_state) do
    target = target_resource(dsl_state)

    dsl_state
    |> Transformer.get_entities([:a2ui])
    |> Enum.filter(&(is_struct(&1, AshA2ui.Component) and is_nil(&1.fields)))
    |> Enum.reduce({:ok, dsl_state}, fn component, {:ok, dsl_state} ->
      case infer_fields(target, component) do
        nil ->
          {:ok, dsl_state}

        fields ->
          {:ok,
           Transformer.replace_entity(
             dsl_state,
             [:a2ui],
             %{component | fields: fields},
             &(is_struct(&1, AshA2ui.Component) and &1.name == component.name and
                 is_nil(&1.fields))
           )}
      end
    end)
  end

  # Resolves what we introspect against: the compiled `for_resource` module in
  # standalone mode, or the in-flight DSL state itself in on-resource mode
  # (`Ash.Resource.Info` accepts both). Returns `nil` when nothing usable.
  defp target_resource(dsl_state) do
    case Transformer.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if ash_resource_dsl?(dsl_state), do: dsl_state

      resource ->
        if Code.ensure_loaded?(resource) and Info.resource?(resource), do: resource
    end
  end

  defp ash_resource_dsl?(dsl_state) do
    Ash.Resource.Dsl in Transformer.get_persisted(dsl_state, :extensions, [])
  end

  defp infer_fields(nil, _component), do: nil

  defp infer_fields(target, %AshA2ui.Component{name: :table}) do
    target
    |> Info.public_attributes()
    |> Enum.reject(& &1.primary_key?)
    |> Enum.map(& &1.name)
    |> case do
      [] -> nil
      fields -> fields
    end
  end

  defp infer_fields(target, %AshA2ui.Component{name: :form} = component) do
    action =
      form_action(target, component.create_action, :create) ||
        form_action(target, component.update_action, :update)

    action && action.accept
  end

  defp form_action(target, nil, type), do: Info.primary_action(target, type)

  defp form_action(target, name, type) do
    case Info.action(target, name) do
      %{type: ^type} = action -> action
      _ -> nil
    end
  end
end
