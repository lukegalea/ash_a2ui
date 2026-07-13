defmodule AshA2ui.Dynamic do
  @moduledoc """
  Agent-composed surfaces: build and serve A2UI surfaces from a runtime,
  JSON-serializable **surface spec** — typically emitted by an LLM as
  structured tool output — with the same validation rigor as the compile-time
  `a2ui` DSL.

  A spec is *not* raw A2UI. It is a declarative mirror of the DSL vocabulary
  (components, fields, queries, presets, groups, row layouts, actions,
  contexts) that references resources, attributes and actions **by name**;
  the server resolves, validates, and encodes everything. The spec composer
  never controls the wire payload, only the same knobs a DSL author has.

  ## Pipeline

      spec (JSON map)
        │  AshA2ui.Dynamic.resolve(spec, allowlist: [...])
        ├─ resource looked up in the host-configured allowlist
        ├─ entities built through Spark's own entity schemas
        │    (AshA2ui.Dynamic.Parser — same option types/defaults as the DSL)
        ├─ field inference (AshA2ui.Transformers.InferFields)
        ├─ THE compile-time verifiers, run at runtime over a synthetic
        │    standalone-style DSL state (VerifyComponents/Layouts/Contexts/
        │    Fields/Actions/Queries/Relationships/NestedForms — the same
        │    modules, the same messages)
        └─ {:ok, %AshA2ui.Dynamic.Surface{}} | {:error, [%Dynamic.Error{}]}

  The returned surface then flows through the exact machinery declared
  surfaces use:

    * `build_surface/2` → `AshA2ui.Info.build_surface/2` → the versioned
      encoder (authorized reads, query allowlists, context scoping),
    * `handle_action/3` → `AshA2ui.ActionHandler.handle/3` (row-action
      allowlist, `visible_when` enforcement, actor-based authorization with
      `authorize?: true` by default).

  ## The allowlist

  Dynamic surfaces may only render resources the host explicitly offers:

      allowlist = AshA2ui.Dynamic.allowlist([MyApp.Feedback, MyApp.User])

  `allowlist/1` names each resource by its short module name
  (`"Feedback"`); pass a `%{"name" => Module}` map to control naming. The
  allowlist gates the surface's own resource and every `context` resource.
  Relationship traversal (selects, `source` columns, search paths) is
  bounded the same way it is for declared surfaces: only the resource's own
  public relationships are walkable, and every read is authorized against
  the actor.

  `extension_resources/1` collects every resource of an OTP app's Ash
  domains that carries the `AshA2ui` extension — a convenient default
  allowlist ("what already has a declared surface may also be composed").

  ## Serving surfaces safely (the host contract)

  `resolve/2` is stateless; making the round trip tamper-proof is a
  **storage discipline** (see `AshA2ui.Dynamic.Surface`):

    1. resolve once, server-side; keep the `%Surface{}` in server state
       (LiveView assign, ETS, cache) keyed by `surface.surface_id`,
    2. serve client `action` envelopes with `handle_action/3` on the
       **server-held** struct — never rebuild a surface from anything the
       client echoes back,
    3. drop the struct when the surface is dismissed.

  Specs never contain secrets and validation is deterministic, so storing
  and re-resolving the raw spec (e.g. after a LiveView reconnect) is also
  sound — the important invariant is that the *server* is the only source
  of the spec.

  ## LLM integration

  `spec_schema/1` returns a JSON Schema for the spec, ready to hand to an
  LLM as a tool parameter schema. `describe_resources/1` returns a compact
  JSON-able description of each allowlisted resource (fields, actions,
  relationships) for the tool description or system prompt — an LLM cannot
  compose against fields it cannot see. Validation errors are structured
  and reuse the compile-time verifier messages (which enumerate what *is*
  available), so a tool loop can feed them back for self-correction:

      case AshA2ui.Dynamic.resolve(spec, allowlist: allowlist) do
        {:ok, surface} -> render(surface)
        {:error, errors} -> {:error, AshA2ui.Dynamic.Error.messages(errors)}
      end
  """

  alias AshA2ui.Dynamic.Error
  alias AshA2ui.Dynamic.Parser
  alias AshA2ui.Dynamic.Surface
  alias AshA2ui.Transformers.InferFields

  @resolve_opts [:allowlist, :surface_id, :spec_version]

  @doc """
  Resolves and validates a surface `spec` (a JSON-decoded, string-keyed map)
  into an `AshA2ui.Dynamic.Surface`.

  ## Options

    * `:allowlist` (required) — the resources the spec may render, as
      returned by `allowlist/1` (or any `%{"name" => Module}` map).
    * `:surface_id` — the A2UI surface id. Defaults to a generated
      `"dyn_<resource>_<hex>"` id, unique per resolve, so a newly composed
      surface always replaces a previous one client-side.
    * `:spec_version` — the A2UI protocol version the surface speaks:
      `"0.9.1"` (the default) or `"1.0"`. Host configuration (matched to the
      renderer's capability), not part of the LLM-facing spec. A v1.0
      dynamic surface bootstraps as a *single* inline `createSurface`
      message — exactly what agent-panel transports want (see the A2UI 1.0
      topic).

  Returns `{:ok, surface}` or `{:error, [%AshA2ui.Dynamic.Error{}]}`.
  """
  @spec resolve(map, keyword) :: {:ok, Surface.t()} | {:error, [Error.t()]}
  def resolve(spec, opts) do
    Keyword.validate!(opts, @resolve_opts)
    allowlist = Keyword.fetch!(opts, :allowlist)
    spec_version = Keyword.get(opts, :spec_version, "0.9.1")

    unless spec_version in ["0.9.1", "1.0"] do
      raise ArgumentError,
            "spec_version must be \"0.9.1\" or \"1.0\", got: #{inspect(spec_version)}"
    end

    with {:ok, resource} <- spec_resource(spec, allowlist),
         {:ok, title} <- spec_title(spec),
         {:ok, entities} <- Parser.parse(Map.drop(spec, ["resource", "title"]), allowlist),
         :ok <- require_component(entities),
         surface_id = Keyword.get_lazy(opts, :surface_id, fn -> generate_surface_id(resource) end),
         {:ok, dsl_state} <-
           infer_fields(synthetic_dsl_state(resource, surface_id, spec_version, entities)),
         :ok <- run_verifiers(dsl_state) do
      {:ok,
       %Surface{
         surface_id: surface_id,
         resource: resource,
         title: title,
         spec: spec,
         dsl_state: dsl_state
       }}
    end
  end

  @doc """
  Builds the surface's A2UI message list through
  `AshA2ui.Info.build_surface/2`: the v0.9.1 `createSurface` →
  `updateComponents` → `updateDataModel` triple, or (for surfaces resolved
  with `spec_version: "1.0"`) a single inline `createSurface` message.

  Takes the same options (`:actor`, `:tenant`, `:authorize?`, `:domain`,
  `:query_state`, `:context_state`); reads are authorized by default.
  """
  @spec build_surface(Surface.t(), keyword) :: [map]
  def build_surface(%Surface{} = surface, opts \\ []) do
    AshA2ui.Info.build_surface(surface.dsl_state, opts)
  end

  @doc """
  Builds a data-only refresh (`updateDataModel`) through
  `AshA2ui.Info.build_data_model/2`. Same options as `build_surface/2`.
  """
  @spec build_data_model(Surface.t(), keyword) :: map
  def build_data_model(%Surface{} = surface, opts \\ []) do
    AshA2ui.Info.build_data_model(surface.dsl_state, opts)
  end

  @doc """
  Handles a client `action` envelope for a **server-held** surface through
  `AshA2ui.ActionHandler.handle/3` — the row-action allowlist, query
  allowlists, `visible_when` enforcement, and actor-based authorization
  apply exactly as on declared surfaces.

  Takes the same options as `AshA2ui.ActionHandler.handle/3` (`:actor`,
  `:tenant`, `:authorize?`).
  """
  @spec handle_action(Surface.t(), map, keyword) :: {:ok, [map]} | {:error, [map]}
  def handle_action(%Surface{} = surface, action_message, opts \\ []) do
    AshA2ui.ActionHandler.handle(surface.dsl_state, action_message, opts)
  end

  # --- allowlist ----------------------------------------------------------------

  @doc """
  Normalizes an allowlist: a list of Ash resource modules (named by their
  short module name) or a `%{"name" => Module}` map (names must match the
  spec name format). Raises on non-resources and name collisions —
  the allowlist is host configuration, not client input.
  """
  @spec allowlist([module] | %{String.t() => module}) :: %{String.t() => module}
  def allowlist(resources) when is_list(resources) do
    resources
    |> Map.new(fn resource -> {short_name(resource), resource} end)
    |> tap(fn named ->
      if map_size(named) != length(Enum.uniq(resources)) do
        raise ArgumentError,
              "resource short names collide in #{inspect(resources)} — " <>
                "pass a %{\"name\" => Module} map to disambiguate"
      end
    end)
    |> allowlist()
  end

  def allowlist(named) when is_map(named) do
    Enum.each(named, fn {name, resource} ->
      unless is_binary(name) and name =~ ~r/^[a-zA-Z][a-zA-Z0-9_]*$/ do
        raise ArgumentError, "allowlist name #{inspect(name)} must match ^[a-zA-Z]\\w*$"
      end

      unless Ash.Resource.Info.resource?(resource) do
        raise ArgumentError, "#{inspect(resource)} is not an Ash resource"
      end
    end)

    named
  end

  @doc """
  Every resource of `otp_app`'s configured Ash domains that carries the
  `AshA2ui` extension — a convenient default allowlist: what already has a
  declared surface may also be composed dynamically.
  """
  @spec extension_resources(atom) :: [module]
  def extension_resources(otp_app) do
    otp_app
    |> Application.get_env(:ash_domains, [])
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.filter(&(AshA2ui in Spark.extensions(&1)))
    |> Enum.uniq()
  end

  # --- LLM-facing descriptions -----------------------------------------------------

  @doc """
  A compact, JSON-able description of every allowlisted resource — the
  vocabulary an LLM needs to compose valid specs: public attributes
  (name/type/enum values), public calculations and aggregates, actions
  (type, accepts, arguments), and public relationships. Embed it in the
  tool description or system prompt alongside `spec_schema/1`.
  """
  @spec describe_resources(%{String.t() => module}) :: [map]
  def describe_resources(allowlist) do
    allowlist
    |> Enum.sort_by(fn {name, _resource} -> name end)
    |> Enum.map(fn {name, resource} -> describe_resource(name, resource) end)
  end

  defp describe_resource(name, resource) do
    %{
      "resource" => name,
      "attributes" => Enum.map(Ash.Resource.Info.public_attributes(resource), &describe_field/1),
      "calculations" =>
        Enum.map(Ash.Resource.Info.public_calculations(resource), &describe_field/1),
      "aggregates" =>
        Enum.map(Ash.Resource.Info.public_aggregates(resource), &%{"name" => to_string(&1.name)}),
      "actions" => Enum.map(Ash.Resource.Info.actions(resource), &describe_action/1),
      "relationships" =>
        for relationship <- Ash.Resource.Info.public_relationships(resource) do
          %{
            "name" => to_string(relationship.name),
            "type" => to_string(relationship.type),
            "destination" => short_name(relationship.destination)
          }
        end
    }
  end

  defp describe_field(%{name: name, type: type} = field) do
    base = %{"name" => to_string(name), "type" => type_name(type)}

    case enum_values(field) do
      nil -> base
      values -> Map.put(base, "one_of", Enum.map(values, &to_string/1))
    end
  end

  defp describe_field(%{name: name}), do: %{"name" => to_string(name)}

  defp describe_action(action) do
    base = %{"name" => to_string(action.name), "type" => to_string(action.type)}

    base
    |> put_names("accepts", List.wrap(Map.get(action, :accept)))
    |> put_names("arguments", Enum.map(Map.get(action, :arguments, []), & &1.name))
  end

  defp put_names(map, _key, []), do: map
  defp put_names(map, key, names), do: Map.put(map, key, Enum.map(names, &to_string/1))

  defp enum_values(%{type: Ash.Type.Atom, constraints: constraints}) do
    constraints[:one_of]
  end

  defp enum_values(%{type: type}) do
    if AshA2ui.TypeMapper.enum_type?(Ash.Type.get_type(type)) do
      Ash.Type.get_type(type).values()
    end
  end

  defp type_name(type) do
    type |> Ash.Type.get_type() |> Module.split() |> List.last() |> Macro.underscore()
  rescue
    _not_a_module -> inspect(type)
  end

  # --- spec schema ------------------------------------------------------------------

  @doc """
  The JSON Schema (draft-07-compatible object schema) of the surface spec,
  ready to use as an LLM tool parameter schema. `allowlist` constrains the
  `resource` (and context `resource`) enums to the host's allowlisted names.
  """
  @spec spec_schema(%{String.t() => module}) :: map
  def spec_schema(allowlist) do
    resource_names = allowlist |> Map.keys() |> Enum.sort()
    name = %{"type" => "string", "pattern" => "^[a-zA-Z][a-zA-Z0-9_]*$", "maxLength" => 64}
    name_list = %{"type" => "array", "items" => name, "maxItems" => 64}

    %{
      "type" => "object",
      "description" =>
        "A declarative A2UI surface spec: components over ONE resource, referencing " <>
          "its attributes and actions by name. The server validates every reference " <>
          "and builds the actual UI payload.",
      "properties" => %{
        "resource" => %{
          "type" => "string",
          "enum" => resource_names,
          "description" => "The resource this surface renders."
        },
        "title" => %{
          "type" => "string",
          "maxLength" => 120,
          "description" => "Human-readable panel title."
        },
        "components" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 64,
          "items" => component_schema(name, name_list),
          "description" =>
            "The surface's components: usually one table (plus optionally one form). " <>
              "Multiple tables/details need distinguishing names."
        },
        "queries" => %{
          "type" => "array",
          "maxItems" => 64,
          "items" => query_schema(name, name_list),
          "description" =>
            "Named search/sort/filter/pagination allowlists referenced by tables via " <>
              "their \"query\". Only declared fields become searchable/sortable/filterable."
        },
        "fields" => %{
          "type" => "array",
          "maxItems" => 64,
          "items" => field_schema(name, name_list),
          "description" => "Optional per-field presentation overrides, shared across components."
        },
        "actions" => %{
          "type" => "array",
          "maxItems" => 64,
          "items" => action_schema(name, name_list),
          "description" =>
            "Optional per-action metadata for row actions or the form's actions: refresh " <>
              "targets, argument prompts, per-row visibility conditions."
        },
        "contexts" => %{
          "type" => "array",
          "maxItems" => 64,
          "items" => context_schema(name, name_list, resource_names),
          "description" =>
            "Named record selections (\"pick a user\") that scope tables " <>
              "(context_filter) and detail components. Advanced; omit unless needed."
        }
      },
      "required" => ["resource", "components"],
      "additionalProperties" => false
    }
  end

  defp component_schema(name, name_list) do
    %{
      "type" => "object",
      "properties" => %{
        "kind" => %{
          "type" => "string",
          "enum" => ["table", "form", "detail"],
          "description" =>
            "table renders records of a read action; form renders a create/update form; " <>
              "detail renders a context's selected record."
        },
        "name" => Map.put(name, "description", "Distinguishing name (multi-table/detail only)."),
        "fields" =>
          Map.put(
            name_list,
            "description",
            "Fields shown, in order. Omit to infer (public attributes for tables, the " <>
              "create action's accepts for forms). Form fields must be accepted by the " <>
              "form's actions."
          ),
        "read_action" =>
          Map.put(name, "description", "Read action for tables (default: primary read)."),
        "create_action" => Map.put(name, "description", "Create action the form submits."),
        "update_action" => Map.put(name, "description", "Update action the form submits."),
        "row_actions" =>
          Map.put(
            name_list,
            "description",
            "Actions rendered as per-row buttons (update/destroy/generic actions of the resource)."
          ),
        "query" => Map.put(name, "description", "Name of a declared query (tables only)."),
        "context_filter" => %{
          "type" => "object",
          "additionalProperties" => name,
          "description" =>
            "Table scoping: attribute name -> context name; the context's selected " <>
              "record id filters the table."
        },
        "require_context" =>
          Map.put(
            name_list,
            "description",
            "Contexts that must be selected before the table reads."
          ),
        "select_context" =>
          Map.put(
            name,
            "description",
            "Context a table row's Select button selects into (master/detail)."
          ),
        "context" =>
          Map.put(
            name,
            "description",
            "The context a detail component renders (required on detail)."
          ),
        "row_layout" => %{
          "type" => "object",
          "description" => "Card-style table rows: a title header plus a labeled metadata grid.",
          "properties" => %{
            "title" => Map.put(name, "description", "Field rendered as the card heading."),
            "badge" => Map.put(name, "description", "Field rendered as a status badge."),
            "badge_text" => %{
              "type" => "object",
              "additionalProperties" => %{"type" => "string"},
              "description" => "Display text per badge value, e.g. {\"true\": \"Active\"}."
            },
            "meta" =>
              Map.put(
                name_list,
                "description",
                "Fields in the metadata grid (defaults to the rest)."
              ),
            "columns" => %{"type" => "integer", "minimum" => 1, "maximum" => 6}
          },
          "required" => ["title"],
          "additionalProperties" => false
        },
        "groups" => %{
          "type" => "array",
          "maxItems" => 64,
          "description" => "Labeled N-column sections of form fields (forms only).",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "name" => name,
              "label" => %{"type" => "string"},
              "columns" => %{"type" => "integer", "minimum" => 1, "maximum" => 6},
              "fields" => name_list
            },
            "required" => ["name", "fields"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["kind"],
      "additionalProperties" => false
    }
  end

  defp query_schema(name, name_list) do
    %{
      "type" => "object",
      "properties" => %{
        "name" => name,
        "search_fields" => %{
          "type" => "array",
          "maxItems" => 64,
          "items" => %{"anyOf" => [name, name_list]},
          "description" =>
            "String attributes searched case-insensitively; entries are names or " <>
              "relationship paths like [\"author\", \"email\"]."
        },
        "sortable" => Map.put(name_list, "description", "Attributes the client may sort by."),
        "filters" =>
          Map.put(name_list, "description", "Attributes the client may equality-filter on."),
        "range_filters" =>
          Map.put(
            name_list,
            "description",
            "Date/numeric attributes the client may range-filter on."
          ),
        "default_sort" => %{
          "type" => "array",
          "maxItems" => 8,
          "items" => %{
            "type" => "object",
            "properties" => %{
              "field" => name,
              "direction" => %{"type" => "string", "enum" => ["asc", "desc"]}
            },
            "required" => ["field"],
            "additionalProperties" => false
          }
        },
        "presets" => %{
          "type" => "array",
          "maxItems" => 64,
          "description" => "Named server-side composite filters selected by name.",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "name" => name,
              "filter" => %{
                "type" => "object",
                "description" =>
                  "Attribute -> value conditions ANDed together (null means is-nil, " <>
                    "an array means membership)."
              },
              "read_action" => name
            },
            "required" => ["name"],
            "additionalProperties" => false
          }
        },
        "default_preset" => name,
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100},
        "max_page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      },
      "required" => ["name"],
      "additionalProperties" => false
    }
  end

  defp field_schema(name, name_list) do
    %{
      "type" => "object",
      "properties" => %{
        "name" => name,
        "label" => %{"type" => "string", "maxLength" => 120},
        "widget" => %{
          "type" => "string",
          "enum" => ["text_field", "check_box", "choice_picker", "date_time_input"]
        },
        "format" => %{"type" => "string", "enum" => ["date"]},
        "order" => %{"type" => "integer", "minimum" => 0, "maximum" => 1000},
        "hidden" => %{"type" => "boolean"},
        "source" =>
          Map.put(
            name_list,
            "description",
            "Relationship path a table column reads through, e.g. [\"user\", \"email\"]. Table-only."
          ),
        "relationship" =>
          Map.put(
            name,
            "description",
            "belongs_to relationship this form field selects a record for."
          ),
        "option_label" => name,
        "option_value" => name,
        "option_sort" => name,
        "option_limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 500},
        "option_search" =>
          Map.put(
            name_list,
            "description",
            "Destination string attributes searched; makes a relationship select searchable."
          )
      },
      "required" => ["name"],
      "additionalProperties" => false
    }
  end

  defp action_schema(name, name_list) do
    %{
      "type" => "object",
      "properties" => %{
        "name" => Map.put(name, "description", "The Ash action this metadata applies to."),
        "refreshes" =>
          Map.put(
            name_list,
            "description",
            "Table components refreshed after success (default: all)."
          ),
        "prompt_fields" =>
          Map.put(
            name_list,
            "description",
            "Action arguments/accepts collected in a modal prompt before invoking (row actions only)."
          ),
        "prompt_title" => %{"type" => "string", "maxLength" => 120},
        "visible_when" => %{
          "type" => "object",
          "description" =>
            "Per-record conditions gating the row action (attribute -> value; null means " <>
              "is-nil, an array means membership)."
        }
      },
      "required" => ["name"],
      "additionalProperties" => false
    }
  end

  defp context_schema(name, name_list, resource_names) do
    %{
      "type" => "object",
      "properties" => %{
        "name" => name,
        "resource" => %{"type" => "string", "enum" => resource_names},
        "label" => %{"type" => "string", "maxLength" => 120},
        "option_label" => name,
        "option_value" => name,
        "option_sort" => name,
        "option_limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 500},
        "option_search" => name_list,
        "depends_on" => name,
        "depends_on_path" => name_list,
        "auto_select_single" => %{"type" => "boolean"},
        "picker" => %{"type" => "boolean"}
      },
      "required" => ["name", "resource"],
      "additionalProperties" => false
    }
  end

  # --- internals ----------------------------------------------------------------------

  defp spec_resource(spec, allowlist) when is_map(spec) do
    case Map.fetch(spec, "resource") do
      {:ok, name} when is_binary(name) ->
        case Map.fetch(allowlist, name) do
          {:ok, resource} ->
            {:ok, resource}

          :error ->
            {:error,
             [
               Error.new(
                 "resource",
                 "resource #{inspect(name)} is not available to dynamic surfaces — " <>
                   "use one of: #{Enum.join(Enum.sort(Map.keys(allowlist)), ", ")}"
               )
             ]}
        end

      _missing_or_not_binary ->
        {:error, [Error.new("resource", ~s(the spec must name a "resource" string))]}
    end
  end

  defp spec_resource(_spec, _allowlist),
    do: {:error, [Error.new("", "the surface spec must be a JSON object")]}

  defp spec_title(spec) do
    case Map.get(spec, "title") do
      nil -> {:ok, nil}
      title when is_binary(title) -> {:ok, title}
      _other -> {:error, [Error.new("title", "title must be a string")]}
    end
  end

  defp require_component(entities) do
    if Enum.any?(entities, &is_struct(&1, AshA2ui.Component)) do
      :ok
    else
      {:error, [Error.new("components", "the spec must declare at least one component")]}
    end
  end

  # The synthetic standalone-style DSL state the shared transformers,
  # verifiers, ResolvedView, Info, and ActionHandler all consume — the same
  # map shape Spark hands them at compile time, minus a real module.
  defp synthetic_dsl_state(resource, surface_id, spec_version, entities) do
    %{
      [:a2ui] => %{
        entities: entities,
        opts: [for_resource: resource, surface_id: surface_id, spec_version: spec_version]
      },
      :persist => %{module: __MODULE__, extensions: []}
    }
  end

  defp infer_fields(dsl_state) do
    case InferFields.transform(dsl_state) do
      {:ok, dsl_state} -> {:ok, dsl_state}
      {:error, error} -> {:error, [Error.new("", error_text(error))]}
    end
  end

  # The compile-time verifiers, unchanged, in the extension's declared
  # order. Every verifier runs (an LLM correcting several mistakes at once
  # converges faster than one-error-at-a-time).
  defp run_verifiers(dsl_state) do
    AshA2ui.verifiers()
    |> Enum.flat_map(fn verifier ->
      case verifier.verify(dsl_state) do
        :ok -> []
        {:error, %Spark.Error.DslError{} = error} -> [Error.from_dsl_error(error)]
        {:error, error} -> [Error.new("", error_text(error))]
      end
    end)
    |> case do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp error_text(error) when is_binary(error), do: error
  defp error_text(error) when is_exception(error), do: Exception.message(error)
  defp error_text(error), do: inspect(error)

  defp generate_surface_id(resource) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "dyn_#{Macro.underscore(short_name(resource))}_#{suffix}"
  end

  defp short_name(resource) do
    resource |> Module.split() |> List.last()
  end
end
