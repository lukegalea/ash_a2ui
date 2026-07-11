defmodule AshA2ui.Dynamic.Parser do
  @moduledoc """
  Turns a JSON-decoded surface spec (see `AshA2ui.Dynamic`) into the same
  entity structs the `a2ui` DSL compiles to.

  Every entity is built through `Spark.Dsl.Entity.build/5` with the
  extension's own entity definitions, so Spark's option schemas (types,
  `one_of` values, required options, defaults) apply to dynamic specs exactly
  as they do to DSL blocks. The parser's own job is shape conversion —
  JSON strings/objects/arrays to the atoms, keyword lists, and tuples the
  schemas expect — plus the dynamic-only checks that need spec-level
  context (identifier format, widget/format vocabulary, resource-allowlist
  lookups for contexts).

  Identifier atoms (component/query/group/preset/context names and field
  references) are created from validated spec strings (`^[a-zA-Z]\\w*$`, at
  most 64 bytes). Creation is bounded by the spec limits enforced by
  `AshA2ui.Dynamic.spec_schema/1` and re-checked here; misspelled *field*
  references still become atoms, on purpose — the shared verifiers then
  reject them with the compile-time messages that list what is available,
  which is what lets an LLM self-correct.
  """

  alias AshA2ui.Dynamic.Error
  alias Spark.Dsl.Entity
  alias Spark.Options.ValidationError

  @name_regex ~r/^[a-zA-Z][a-zA-Z0-9_]*$/
  @max_name_bytes 64
  @max_list_entries 64

  # Every widget the encoder renders / format it applies. Arbitrary atoms
  # would silently fall back to TextField — reject them loudly instead.
  @widgets ~w(text_field check_box choice_picker date_time_input)
  @formats ~w(date)

  @top_level_keys ~w(resource title components queries fields actions contexts)

  @doc """
  Parses `spec` (a JSON-decoded, string-keyed map) into the `a2ui` section's
  entity structs, in the section's canonical order (contexts, queries,
  components, fields, actions).

  `allowlist` is the `%{"Name" => module}` resource allowlist (used to
  resolve context resources). Returns `{:ok, entities}` or
  `{:error, [%AshA2ui.Dynamic.Error{}]}` with every problem found.
  """
  @spec parse(map, %{String.t() => module}) ::
          {:ok, [struct]} | {:error, [Error.t()]}
  def parse(spec, allowlist) when is_map(spec) do
    with :ok <- check_unknown_keys(spec) do
      collect_entities(spec, allowlist)
    end
  end

  def parse(_spec, _allowlist) do
    {:error, [Error.new("", "the surface spec must be a JSON object")]}
  end

  defp collect_entities(spec, allowlist) do
    results = [
      parse_entities(spec, "contexts", &parse_context(&1, &2, allowlist)),
      parse_entities(spec, "queries", &parse_query/2),
      parse_entities(spec, "components", &parse_component/2),
      parse_entities(spec, "fields", &parse_field/2),
      parse_entities(spec, "actions", &parse_action/2)
    ]

    case Enum.flat_map(results, fn {_entities, errors} -> errors end) do
      [] -> {:ok, Enum.flat_map(results, fn {entities, _errors} -> entities end)}
      errors -> {:error, errors}
    end
  end

  defp check_unknown_keys(spec) do
    case Enum.find(Map.keys(spec), &(&1 not in @top_level_keys)) do
      nil ->
        :ok

      unknown ->
        {:error,
         [
           Error.new(
             to_string(unknown),
             "unknown spec key #{inspect(unknown)} — the spec supports: " <>
               Enum.join(@top_level_keys, ", ")
           )
         ]}
    end
  end

  defp parse_entities(spec, key, parser) do
    case Map.get(spec, key, []) do
      entries when is_list(entries) and length(entries) <= @max_list_entries ->
        entries
        |> Enum.with_index()
        |> Enum.map(fn {entry, index} -> parser.(entry, "#{key}[#{index}]") end)
        |> Enum.reduce({[], []}, fn
          {:ok, entity}, {entities, errors} -> {entities ++ [entity], errors}
          {:error, new_errors}, {entities, errors} -> {entities, errors ++ new_errors}
        end)

      entries when is_list(entries) ->
        {[], [Error.new(key, "at most #{@max_list_entries} #{key} are supported")]}

      _not_a_list ->
        {[], [Error.new(key, "#{inspect(key)} must be an array")]}
    end
  end

  # --- components -------------------------------------------------------------

  @component_keys %{
    "kind" => :name,
    "name" => :as,
    "fields" => :fields,
    "read_action" => :read_action,
    "create_action" => :create_action,
    "update_action" => :update_action,
    "row_actions" => :row_actions,
    "query" => :query,
    "context_filter" => :context_filter,
    "require_context" => :require_context,
    "select_context" => :select_context,
    "context" => :context
  }

  @component_nested ~w(row_layout groups nested_forms)

  defp parse_component(entry, path) when is_map(entry) do
    with :ok <- require_kind(entry, path),
         {:ok, opts} <- convert_options(entry, @component_keys, @component_nested, path),
         {:ok, nested} <- parse_component_nested(entry, path) do
      build_entity(:component, entity_def(:component), opts, nested, path)
    end
  end

  defp parse_component(_entry, path),
    do: {:error, [Error.new(path, "each component must be a JSON object")]}

  defp require_kind(entry, path) do
    if Map.has_key?(entry, "kind") do
      :ok
    else
      {:error,
       [
         Error.new(
           "#{path}.kind",
           ~s(each component must declare a "kind": "table", "form" or "detail")
         )
       ]}
    end
  end

  defp parse_component_nested(entry, path) do
    component_def = entity_def(:component)
    [row_layout_def] = component_def.entities[:row_layout]
    [group_def] = component_def.entities[:groups]

    with {:ok, row_layout} <- parse_row_layout(Map.get(entry, "row_layout"), row_layout_def, path),
         {:ok, groups} <- parse_groups(Map.get(entry, "groups"), group_def, path) do
      {:ok, [row_layout: row_layout, groups: groups, nested_forms: []]}
    end
  end

  @row_layout_keys %{
    "title" => :title,
    "badge" => :badge,
    "badge_text" => :badge_text,
    "meta" => :meta,
    "columns" => :columns
  }

  defp parse_row_layout(nil, _def, _path), do: {:ok, []}

  defp parse_row_layout(entry, row_layout_def, path) when is_map(entry) do
    path = "#{path}.row_layout"

    with {:ok, opts} <- convert_options(entry, @row_layout_keys, [], path),
         {:ok, layout} <- build_entity(:row_layout, row_layout_def, opts, [], path) do
      {:ok, [layout]}
    end
  end

  defp parse_row_layout(_entry, _def, path),
    do: {:error, [Error.new("#{path}.row_layout", "row_layout must be a JSON object")]}

  @group_keys %{"name" => :name, "label" => :label, "columns" => :columns, "fields" => :fields}

  defp parse_groups(nil, _def, _path), do: {:ok, []}

  defp parse_groups(entries, group_def, path) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
      group_path = "#{path}.groups[#{index}]"

      result =
        with true <- is_map(entry) || {:error, [Error.new(group_path, "must be a JSON object")]},
             {:ok, opts} <- convert_options(entry, @group_keys, [], group_path) do
          build_entity(:group, group_def, opts, [], group_path)
        end

      case result do
        {:ok, group} -> {:cont, {:ok, acc ++ [group]}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp parse_groups(_entries, _def, path),
    do: {:error, [Error.new("#{path}.groups", "groups must be an array")]}

  # --- queries ----------------------------------------------------------------

  @query_keys %{
    "name" => :name,
    "search_fields" => :search_fields,
    "sortable" => :sortable,
    "filters" => :filters,
    "range_filters" => :range_filters,
    "default_sort" => :default_sort,
    "default_preset" => :default_preset,
    "page_size" => :page_size,
    "max_page_size" => :max_page_size
  }

  defp parse_query(entry, path) when is_map(entry) do
    query_def = entity_def(:query)
    [preset_def] = query_def.entities[:presets]

    with {:ok, opts} <- convert_options(entry, @query_keys, ["presets"], path),
         {:ok, presets} <- parse_presets(Map.get(entry, "presets"), preset_def, path) do
      build_entity(:query, query_def, opts, [presets: presets], path)
    end
  end

  defp parse_query(_entry, path),
    do: {:error, [Error.new(path, "each query must be a JSON object")]}

  @preset_keys %{"name" => :name, "filter" => :filter, "read_action" => :read_action}

  defp parse_presets(nil, _def, _path), do: {:ok, []}

  defp parse_presets(entries, preset_def, path) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
      preset_path = "#{path}.presets[#{index}]"

      result =
        with true <- is_map(entry) || {:error, [Error.new(preset_path, "must be a JSON object")]},
             {:ok, opts} <- convert_options(entry, @preset_keys, [], preset_path) do
          build_entity(:preset, preset_def, opts, [], preset_path)
        end

      case result do
        {:ok, preset} -> {:cont, {:ok, acc ++ [preset]}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp parse_presets(_entries, _def, path),
    do: {:error, [Error.new("#{path}.presets", "presets must be an array")]}

  # --- fields -------------------------------------------------------------------

  @field_keys %{
    "name" => :name,
    "label" => :label,
    "widget" => :widget,
    "format" => :format,
    "order" => :order,
    "hidden" => :hidden,
    "source" => :source,
    "relationship" => :relationship,
    "option_label" => :option_label,
    "option_value" => :option_value,
    "option_sort" => :option_sort,
    "option_limit" => :option_limit,
    "option_search" => :option_search
  }

  defp parse_field(entry, path) when is_map(entry) do
    with {:ok, opts} <- convert_options(entry, @field_keys, [], path),
         :ok <- check_vocabulary(opts, :widget, @widgets, path),
         :ok <- check_vocabulary(opts, :format, @formats, path) do
      build_entity(:field, entity_def(:field), opts, [], path)
    end
  end

  defp parse_field(_entry, path),
    do: {:error, [Error.new(path, "each field must be a JSON object")]}

  defp check_vocabulary(opts, key, supported, path) do
    case Keyword.get(opts, key) do
      nil ->
        :ok

      value ->
        if to_string(value) in supported do
          :ok
        else
          {:error,
           [
             Error.new(
               "#{path}.#{key}",
               "#{key} #{inspect(to_string(value))} is not supported — " <>
                 "use one of: #{Enum.join(supported, ", ")}"
             )
           ]}
        end
    end
  end

  # --- actions --------------------------------------------------------------------

  @action_keys %{
    "name" => :name,
    "refreshes" => :refreshes,
    "prompt_fields" => :prompt_fields,
    "prompt_title" => :prompt_title,
    "visible_when" => :visible_when
  }

  defp parse_action(entry, path) when is_map(entry) do
    with {:ok, opts} <- convert_options(entry, @action_keys, [], path) do
      build_entity(:action, entity_def(:action), opts, [], path)
    end
  end

  defp parse_action(_entry, path),
    do: {:error, [Error.new(path, "each action must be a JSON object")]}

  # --- contexts -------------------------------------------------------------------

  @context_keys %{
    "name" => :name,
    "label" => :label,
    "option_label" => :option_label,
    "option_value" => :option_value,
    "option_sort" => :option_sort,
    "option_limit" => :option_limit,
    "option_search" => :option_search,
    "depends_on" => :depends_on,
    "depends_on_path" => :depends_on_path,
    "auto_select_single" => :auto_select_single,
    "picker" => :picker
  }

  defp parse_context(entry, path, allowlist) when is_map(entry) do
    with {:ok, resource} <- context_resource(entry, path, allowlist),
         {:ok, opts} <- convert_options(Map.delete(entry, "resource"), @context_keys, [], path) do
      build_entity(:context, entity_def(:context), [{:resource, resource} | opts], [], path)
    end
  end

  defp parse_context(_entry, path, _allowlist),
    do: {:error, [Error.new(path, "each context must be a JSON object")]}

  defp context_resource(entry, path, allowlist) do
    case Map.fetch(entry, "resource") do
      {:ok, name} when is_binary(name) ->
        case Map.fetch(allowlist, name) do
          {:ok, resource} ->
            {:ok, resource}

          :error ->
            {:error,
             [
               Error.new(
                 "#{path}.resource",
                 "resource #{inspect(name)} is not available to dynamic surfaces — " <>
                   "use one of: #{Enum.join(Map.keys(allowlist), ", ")}"
               )
             ]}
        end

      _missing_or_not_binary ->
        {:error, [Error.new("#{path}.resource", ~s(each context must name a "resource" string))]}
    end
  end

  # --- generic option conversion ---------------------------------------------------

  # Converts a spec entry's JSON options into the keyword list
  # `Spark.Dsl.Entity.build/5` expects, using the entity's own Spark schema
  # to pick the target shape per key. Unknown keys are rejected with the
  # supported vocabulary.
  defp convert_options(entry, key_mapping, nested_keys, path) do
    entry
    |> Enum.reject(fn {key, _value} -> to_string(key) in nested_keys end)
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      case convert_entry_option(key, value, key_mapping, nested_keys, path) do
        {:ok, converted} -> {:cont, {:ok, acc ++ [converted]}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp convert_entry_option(key, value, key_mapping, nested_keys, path) do
    case Map.fetch(key_mapping, to_string(key)) do
      {:ok, option} ->
        with {:ok, converted} <- convert_option(option, value, path) do
          {:ok, {option, converted}}
        end

      :error ->
        {:error,
         [
           Error.new(
             "#{path}.#{key}",
             "unknown key #{inspect(to_string(key))} — supported keys: " <>
               Enum.join(Map.keys(key_mapping) ++ nested_keys, ", ")
           )
         ]}
    end
  end

  # Option-shaped conversions, keyed by the DSL option name. Anything not
  # special-cased passes through for Spark's schema validation to type-check.
  defp convert_option(option, value, path) do
    case option_shape(option) do
      :name -> convert_name(option, value, path, true)
      :name_list -> convert_name_list(option, value, path)
      :name_keyword -> convert_keyword(option, value, path, &convert_name(option, &1, path, true))
      :raw_keyword -> convert_keyword(option, value, path, &{:ok, &1})
      :string_keyword -> convert_keyword(option, value, path, &convert_string(option, &1, path))
      :search_fields -> convert_search_fields(value, path)
      :default_sort -> convert_default_sort(value, path)
      :raw -> {:ok, value}
    end
  end

  defp option_shape(option)
       when option in [
              :name,
              :as,
              :read_action,
              :create_action,
              :update_action,
              :query,
              :select_context,
              :context,
              :widget,
              :format,
              :relationship,
              :option_label,
              :option_value,
              :option_sort,
              :title,
              :badge,
              :depends_on,
              :default_preset
            ],
       do: :name

  defp option_shape(option)
       when option in [
              :fields,
              :row_actions,
              :require_context,
              :option_search,
              :source,
              :sortable,
              :filters,
              :range_filters,
              :refreshes,
              :prompt_fields,
              :meta,
              :depends_on_path
            ],
       do: :name_list

  defp option_shape(:context_filter), do: :name_keyword
  defp option_shape(option) when option in [:visible_when, :filter], do: :raw_keyword
  defp option_shape(:badge_text), do: :string_keyword
  defp option_shape(:search_fields), do: :search_fields
  defp option_shape(:default_sort), do: :default_sort
  defp option_shape(_option), do: :raw

  defp convert_name(_option, value, _path)
       when is_binary(value) and byte_size(value) <= @max_name_bytes do
    if value =~ @name_regex do
      # Bounded by the spec limits; see the moduledoc.
      # sobelow_skip ["DOS.StringToAtom"]
      {:ok, String.to_atom(value)}
    else
      :error
    end
  end

  defp convert_name(_option, _value, _path), do: :error

  defp convert_name(option, value, path, wrap_error?) when wrap_error? do
    case convert_name(option, value, path) do
      {:ok, name} ->
        {:ok, name}

      :error ->
        {:error,
         [
           Error.new(
             "#{path}.#{option}",
             "#{inspect(value)} is not a valid name: names are strings of letters, " <>
               "digits and underscores, starting with a letter (at most " <>
               "#{@max_name_bytes} bytes)"
           )
         ]}
    end
  end

  defp convert_name_list(option, values, path)
       when is_list(values) and length(values) > @max_list_entries do
    {:error, [Error.new("#{path}.#{option}", "at most #{@max_list_entries} entries")]}
  end

  defp convert_name_list(option, values, path) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case convert_name(option, value, path, true) do
        {:ok, name} -> {:cont, {:ok, acc ++ [name]}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp convert_name_list(option, _values, path),
    do: {:error, [Error.new("#{path}.#{option}", "#{option} must be an array of names")]}

  defp convert_keyword(option, object, path, convert_value) when is_map(object) do
    object
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      with {:ok, name} <- convert_name(option, to_string(key), path, true),
           {:ok, converted} <- convert_value.(value) do
        {:cont, {:ok, acc ++ [{name, converted}]}}
      else
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp convert_keyword(option, _object, path, _convert_value) do
    {:error,
     [Error.new("#{path}.#{option}", "#{option} must be a JSON object of key/value pairs")]}
  end

  defp convert_string(_option, value, _path) when is_binary(value), do: {:ok, value}

  defp convert_string(option, value, path),
    do: {:error, [Error.new("#{path}.#{option}", "#{inspect(value)} must be a string")]}

  # search_fields entries are names or name paths (["author", "email"]).
  defp convert_search_fields(values, path) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn
      value, {:ok, acc} when is_list(value) ->
        case convert_name_list(:search_fields, value, path) do
          {:ok, names} -> {:cont, {:ok, acc ++ [names]}}
          {:error, errors} -> {:halt, {:error, errors}}
        end

      value, {:ok, acc} ->
        case convert_name(:search_fields, value, path, true) do
          {:ok, name} -> {:cont, {:ok, acc ++ [name]}}
          {:error, errors} -> {:halt, {:error, errors}}
        end
    end)
  end

  defp convert_search_fields(_values, path) do
    {:error,
     [
       Error.new(
         "#{path}.search_fields",
         "search_fields must be an array of names or name paths (e.g. " <>
           ~s(["subject", ["author", "email"]])
       )
     ]}
  end

  # default_sort entries are {"field": ..., "direction": "asc" | "desc"}.
  defp convert_default_sort(values, path) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn
      %{"field" => field} = entry, {:ok, acc} ->
        direction = Map.get(entry, "direction", "asc")

        with true <-
               direction in ["asc", "desc"] ||
                 {:error,
                  [
                    Error.new(
                      "#{path}.default_sort",
                      ~s(direction #{inspect(direction)} must be "asc" or "desc")
                    )
                  ]},
             {:ok, name} <- convert_name(:default_sort, field, path, true) do
          {:cont, {:ok, acc ++ [{name, String.to_existing_atom(direction)}]}}
        else
          {:error, errors} -> {:halt, {:error, errors}}
        end

      _entry, {:ok, _acc} ->
        {:halt,
         {:error,
          [
            Error.new(
              "#{path}.default_sort",
              ~s|default_sort entries must be objects like {"field": "inserted_at", | <>
                ~s|"direction": "desc"}|
            )
          ]}}
    end)
  end

  defp convert_default_sort(_values, path),
    do: {:error, [Error.new("#{path}.default_sort", "default_sort must be an array")]}

  # --- entity building --------------------------------------------------------------

  # Spark's Entity.build validates the converted options against the same
  # option schema the DSL macros use — dynamic specs get identical type
  # checking, one_of enforcement, required options, and defaults.
  defp build_entity(entity_name, entity_def, opts, nested_entities, path) do
    case Entity.build(entity_def, opts, nested_entities, nil, nil) do
      {:ok, entity} ->
        {:ok, entity}

      {:error, %ValidationError{key: key, message: message}} ->
        {:error, [Error.new("#{path}.#{key}", message)]}

      {:error, error} ->
        {:error, [Error.new(path, "invalid #{entity_name}: #{error_text(error)}")]}
    end
  end

  defp error_text(error) when is_binary(error), do: error
  defp error_text(error) when is_exception(error), do: Exception.message(error)
  defp error_text(error), do: inspect(error)

  defp entity_def(name) do
    [section] = AshA2ui.sections()
    Enum.find(section.entities, &(&1.name == name))
  end
end
