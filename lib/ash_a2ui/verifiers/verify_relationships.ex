defmodule AshA2ui.Verifiers.VerifyRelationships do
  @moduledoc """
  Verifies at compile time that relationship-backed field options are sound:

    * an explicit `relationship` must name a real relationship of the
      resolved resource,
    * `option_label` / `option_value` / `option_sort` must be public
      attributes of the relationship's destination — and require a
      relationship (explicit or inferred from a `belongs_to`
      `source_attribute` match on a form field) in the first place,
    * a relationship select whose destination has a composite primary key
      must set `option_value` explicitly,
    * `option_search` entries must be public **string-typed** attributes of
      the relationship's destination (they are matched with a
      case-insensitive contains by the `"option_search"` client action),
    * a `source` path must contain at least one relationship step and a
      terminal attribute; every non-terminal step must be a public
      relationship and the terminal step a public attribute of the final
      destination,
    * `source` fields are table-only: they may not appear in `:form`
      component fields (relationship-sourced columns are also rejected in
      query `sortable` lists by `AshA2ui.Verifiers.VerifyQueries`).

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Skipped when no resource can be resolved (standalone
  UI module without `for_resource`) — `AshA2ui.Info.resource!/1` reports that
  at runtime.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @option_keys [:option_label, :option_value, :option_sort]
  @string_types [Ash.Type.String, Ash.Type.CiString]

  @impl true
  def verify(dsl_state) do
    case target_resource(dsl_state) do
      nil ->
        :ok

      target ->
        module = Verifier.get_persisted(dsl_state, :module)
        fields = declared_fields(dsl_state)

        with :ok <- verify_selects(dsl_state, fields, target, module) do
          verify_sources(dsl_state, fields, target, module)
        end
    end
  end

  # --- relationship selects ---------------------------------------------------

  defp verify_selects(dsl_state, fields, target, module) do
    form_field_names = form_field_names(dsl_state)
    declared_names = MapSet.new(fields, & &1.name)

    # Form fields without a declared `field` entity still resolve inferred
    # selects at runtime, so they get the same checks (composite-PK guard).
    synthesized =
      for name <- form_field_names,
          not MapSet.member?(declared_names, name),
          do: %AshA2ui.Field{name: name}

    Enum.reduce_while(fields ++ synthesized, :ok, fn field, :ok ->
      case verify_select(field, form_field_names, target, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_select(field, form_field_names, target, module) do
    relationship = select_relationship(field, form_field_names, target)

    cond do
      not is_nil(field.relationship) and is_nil(relationship) ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :field, field.name, :relationship],
           message:
             "relationship #{inspect(field.relationship)} does not exist on " <>
               inspect(resource_name(target, module))
         )}

      is_nil(relationship) ->
        verify_no_orphan_options(field, module)

      true ->
        verify_select_options(field, relationship, module)
    end
  end

  # The same resolution ResolvedView applies at runtime: an explicit
  # `relationship` wins; otherwise a form field whose name matches a
  # `belongs_to` source_attribute is an inferred select.
  defp select_relationship(%{relationship: name}, _form_field_names, target)
       when not is_nil(name) do
    Info.relationship(target, name)
  end

  defp select_relationship(field, form_field_names, target) do
    if field.name in form_field_names do
      target
      |> Info.relationships()
      |> Enum.find(&(&1.type == :belongs_to and &1.source_attribute == field.name))
    end
  end

  defp verify_no_orphan_options(field, module) do
    orphan_keys =
      if match?([_ | _], field.option_search),
        do: [:option_search | @option_keys],
        else: @option_keys

    case Enum.find(orphan_keys, &Map.get(field, &1)) do
      nil ->
        :ok

      option ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :field, field.name, option],
           message:
             "#{option} is set on field #{inspect(field.name)}, which has no relationship " <>
               "(neither an explicit `relationship` nor a form field matching a " <>
               "belongs_to source_attribute)"
         )}
    end
  end

  defp verify_select_options(field, relationship, module) do
    destination = relationship.destination

    with :ok <- verify_destination_attributes(field, destination, module),
         :ok <- verify_option_value_pk(field, destination, module) do
      verify_option_search(
        field.option_search,
        destination,
        module,
        [:a2ui, :field, field.name, :option_search],
        "field #{inspect(field.name)}"
      )
    end
  end

  @doc false
  # Shared with AshA2ui.Verifiers.VerifyNestedForms: every option_search
  # entry must be a public string-typed attribute of the destination.
  def verify_option_search(option_search, destination, module, path, owner) do
    Enum.reduce_while(option_search, :ok, fn name, :ok ->
      case verify_option_search_entry(name, destination, module, path, owner) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_option_search_entry(name, destination, module, path, owner) do
    case Info.attribute(destination, name) do
      %{public?: true, type: type} ->
        if Ash.Type.get_type(type) in @string_types do
          :ok
        else
          {:error,
           DslError.exception(
             module: module,
             path: path,
             message:
               "option_search entry #{inspect(name)} on #{owner} must be a string-typed " <>
                 "attribute of #{inspect(destination)} (search uses a case-insensitive " <>
                 "contains)"
           )}
        end

      _private_or_missing ->
        {:error,
         DslError.exception(
           module: module,
           path: path,
           message:
             "option_search entry #{inspect(name)} on #{owner} must be a public " <>
               "attribute of #{inspect(destination)}"
         )}
    end
  end

  defp verify_destination_attributes(field, destination, module) do
    @option_keys
    |> Enum.reject(&is_nil(Map.get(field, &1)))
    |> Enum.reduce_while(:ok, fn option, :ok ->
      name = Map.get(field, option)

      if public_attribute?(destination, name) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          DslError.exception(
            module: module,
            path: [:a2ui, :field, field.name, option],
            message:
              "#{option} #{inspect(name)} must be a public attribute of " <>
                inspect(destination)
          )}}
      end
    end)
  end

  defp verify_option_value_pk(%{option_value: nil} = field, destination, module) do
    case Info.primary_key(destination) do
      [_single] ->
        :ok

      composite ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :field, field.name, :option_value],
           message:
             "field #{inspect(field.name)} selects #{inspect(destination)}, which has a " <>
               "composite primary key #{inspect(composite)} — set option_value explicitly"
         )}
    end
  end

  defp verify_option_value_pk(_field, _destination, _module), do: :ok

  # --- source columns ----------------------------------------------------------

  defp verify_sources(dsl_state, fields, target, module) do
    source_fields = Enum.filter(fields, & &1.source)

    with :ok <- verify_source_paths(source_fields, target, module) do
      verify_sources_not_in_forms(dsl_state, source_fields, module)
    end
  end

  defp verify_source_paths(source_fields, target, module) do
    Enum.reduce_while(source_fields, :ok, fn field, :ok ->
      case verify_source_path(field, target, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_source_path(%{source: source} = field, target, module) when length(source) < 2 do
    {:error, source_error(field, module, "must have at least two steps", target)}
  end

  defp verify_source_path(field, target, module) do
    {relationship_steps, [terminal]} = Enum.split(field.source, -1)

    case walk_relationships(relationship_steps, target) do
      {:error, step} ->
        {:error,
         source_error(
           field,
           module,
           "step #{inspect(step)} is not a public relationship",
           target
         )}

      {:ok, destination} ->
        if public_attribute?(destination, terminal) do
          :ok
        else
          {:error,
           source_error(
             field,
             module,
             "terminal step #{inspect(terminal)} is not a public attribute of " <>
               inspect(destination),
             target
           )}
        end
    end
  end

  defp walk_relationships(steps, target) do
    Enum.reduce_while(steps, {:ok, target}, fn step, {:ok, current} ->
      case Info.relationship(current, step) do
        %{public?: true, destination: destination} -> {:cont, {:ok, destination}}
        _private_or_missing -> {:halt, {:error, step}}
      end
    end)
  end

  defp verify_sources_not_in_forms(dsl_state, source_fields, module) do
    source_names = MapSet.new(source_fields, & &1.name)

    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&(is_struct(&1, AshA2ui.Component) and &1.name == :form))
    |> Enum.flat_map(&(&1.fields || []))
    |> Enum.find(&MapSet.member?(source_names, &1))
    |> case do
      nil ->
        :ok

      name ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, :form, :fields],
           message:
             "source field #{inspect(name)} cannot be rendered by a :form component: " <>
               "source columns are table-only"
         )}
    end
  end

  defp source_error(field, module, detail, target) do
    DslError.exception(
      module: module,
      path: [:a2ui, :field, field.name, :source],
      message:
        "source #{inspect(field.source)} on field #{inspect(field.name)} is invalid: " <>
          "#{detail}. Every step but the last must be a public relationship of " <>
          "#{inspect(resource_name(target, module))}, and the last a public attribute " <>
          "of the final destination."
    )
  end

  # --- shared helpers ----------------------------------------------------------

  defp public_attribute?(resource, name) do
    match?(%{public?: true}, Info.attribute(resource, name))
  end

  defp form_field_names(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&(is_struct(&1, AshA2ui.Component) and &1.name == :form))
    |> Enum.flat_map(&(&1.fields || []))
    |> MapSet.new()
  end

  defp declared_fields(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Field))
  end

  defp resource_name(target, _module) when is_atom(target) and not is_nil(target), do: target
  defp resource_name(_dsl_state, module), do: module

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
