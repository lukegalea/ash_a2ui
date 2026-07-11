# The module name mirrors the spec version (v0.9.1) and is part of the frozen
# cross-track contract, so the PascalCase naming check is disabled here.
# credo:disable-for-this-file Credo.Check.Readability.ModuleNames
defmodule AshA2ui.Encoder.V0_9_1 do
  @moduledoc """
  A2UI v0.9.1 encoder: emits the protocol envelope and basic-catalog component
  composition. Tables are `List` + `Row` composition (the basic catalog has no
  Table component); all keys are string camelCase and children are always ID
  references.

  ## Component tree

  The root is a `Column` with id `"root"`. Its children, in order (each only
  present when the corresponding DSL component is declared):

    * `table_heading` — `Text` (h2) with the humanized resource name
    * `query_controls` — only when the table declares a `query`: a `Row` of a
      search `TextField` (`query_search_input`, bound to `/query/search`,
      omitted when the query has no `search_fields`), one `ChoicePicker` per
      declared filter (`query_filter_<name>`, bound to
      `/query/filters/<name>`, with an `"All"` option first) and a
      `query_apply_button` (event `query`, context
      `{"query": {"path": "/query"}, "page": 1}` — the page-1 reset)
    * `records_list` — `List` whose children are a template
      `{"componentId": "record_row", "path": "/records"}`; `record_row` is a
      `Row` of per-field `Text` cells (`table_cell_<field>`, bound to the
      template-relative path `<field>`, `format: :date` rendered through
      `formatDate`), one `Button` per row action
      (`row_action_<action>_button`: event `invoke`, context
      `{"action": "<name>", "recordId": {"path": "id"}}`) and a
      `row_select_button` (event `select_row`, context
      `{"recordId": {"path": "id"}}`)
    * `query_pagination` — only when the table declares a `query`: a `Row` of
      `query_prev_button` / `query_page_text` (bound to `/query/page`) /
      `query_next_button`; the buttons carry event `query` with context
      `{"query": {"path": "/query"}, "pageDelta": -1 | 1}`
    * `form` — `Column` of `form_input_<field>` + `form_error_<field>` pairs
      and a `form_submit_button` (event `submit_form`, context
      `{"values": {"path": "/form"}, "recordId": {"path": "/form/id"}}`).
      Inputs use the field's resolved widget (`TextField` / `CheckBox` /
      `ChoicePicker` / `DateTimeInput`), bind `value` to `/form/<field>`, and
      errors are `Text` (caption) bound to `/errors/<field>`. Relationship
      selects render as `ChoicePicker`s whose loaded options are emitted
      inline (the v0.9.1 basic catalog requires a literal options array) and
      mirrored at `/options/<field>` in the data model
    * `status_text` — `Text` bound to `/ui/status`
    * `action_result_panel` — `Column` wrapping `action_result_text`, a
      `Text` bound to `/ui/action_result_text` (the display text of
      map-returning generic action results; empty until an action produces
      one)

  ## Data model

  The reserved-path value shape (see `topics/data-model-conventions`):

      %{
        "records" => [%{"id" => ..., "<field>" => ...}, ...],
        "form" => %{},
        "errors" => %{},
        "options" => %{"<field>" => [%{"label" => ..., "value" => ...}]},
        "ui" => %{"status" => "", "action_result" => %{}, "action_result_text" => ""}
      }

  `source` table columns serialize by walking the loaded relationship path
  (`[:user, :email]` -> `record.user.email`); a nil or unloaded relationship
  serializes to `""`.

  Query-enabled surfaces additionally carry `"query"` — the `/query` state
  shape documented on `AshA2ui.QueryRunner` — and their `submit_form`/`invoke`
  contexts include `"query": {"path": "/query"}` so success refreshes respect
  the client's active search/filters/sort/page.

  Record values are JSON-safe: dates/datetimes via `to_iso8601`, decimals and
  atoms via `to_string`.
  """

  @behaviour AshA2ui.Encoder

  alias Ash.Resource.Info, as: ResourceInfo

  @version "v0.9.1"
  @catalog_id "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"

  @numeric_types [Ash.Type.Integer, Ash.Type.Decimal, Ash.Type.Float]

  @impl true
  def encode_surface(resolved_view, records, opts) do
    [
      %{
        "version" => @version,
        "createSurface" => %{
          "surfaceId" => resolved_view.surface_id,
          "catalogId" => @catalog_id
        }
      },
      %{
        "version" => @version,
        "updateComponents" => %{
          "surfaceId" => resolved_view.surface_id,
          "components" => components(resolved_view, select_options(resolved_view, opts))
        }
      },
      encode_data_model(resolved_view, records, opts)
    ]
  end

  @doc """
  Encodes a data-only refresh (`updateDataModel`), usable for PubSub-driven
  refresh pushes.

  By default replaces the entire data model (`path: "/"`) with the full
  reserved-path value shape, resetting `form`/`errors`/`ui`. Pass
  `scope: :records` to replace only `/records`, preserving in-flight form
  state on the client.
  """
  @impl true
  def encode_data_model(resolved_view, records, opts) do
    serialized = Enum.map(records, &serialize_record(resolved_view, &1))

    {path, value} =
      case Keyword.get(opts, :scope, :full) do
        :records ->
          {"/records", serialized}

        :full ->
          {"/",
           %{
             "records" => serialized,
             "form" => %{},
             "errors" => %{},
             "options" => options_data(resolved_view, opts),
             "ui" => %{"status" => "", "action_result" => %{}, "action_result_text" => ""}
           }
           |> put_query_state(resolved_view, opts)}
      end

    %{
      "version" => @version,
      "updateDataModel" => %{
        "surfaceId" => resolved_view.surface_id,
        "path" => path,
        "value" => value
      }
    }
  end

  # --- select options ---

  # Options for relationship selects are loaded by the caller
  # (`AshA2ui.Info`) and passed via `opts[:options]` as
  # `%{field_name => [%{"label" => _, "value" => _}]}`. Direct encoder calls
  # without the option fall back to empty option lists per resolved select.
  defp select_options(view, opts) do
    defaults = Map.new(view.selects, fn {name, _select} -> {name, []} end)
    Map.merge(defaults, Keyword.get(opts, :options) || %{})
  end

  # The `/options/<field>` data-model mirror of the inline ChoicePicker
  # options (string keys, same list shape).
  defp options_data(view, opts) do
    view
    |> select_options(opts)
    |> Map.new(fn {name, options} -> {to_string(name), options} end)
  end

  # --- component tree ---

  defp components(view, options) do
    table = Enum.find(view.components, &(&1.name == :table))
    form = Enum.find(view.components, &(&1.name == :form))
    query = (table && view.query) || nil

    table_components = (table && table_components(view, table)) || []
    query_components = (query && query_components(view, query)) || []
    form_components = (form && form_components(view, form)) || []

    root = %{
      "id" => "root",
      "component" => "Column",
      "children" => root_children(table, query, form)
    }

    status = %{
      "id" => "status_text",
      "component" => "Text",
      "text" => %{"path" => "/ui/status"}
    }

    [root | table_components ++ query_components ++ form_components] ++
      table_descendants(view, table) ++
      form_descendants(view, form, options) ++ [status | action_result_components()]
  end

  # Root order: heading, query controls, the list, pagination, form, status,
  # action-result panel — each section present only when declared.
  defp root_children(table, query, form) do
    sections = [
      {"table_heading", table},
      {"query_controls", query},
      {"records_list", table},
      {"query_pagination", query},
      {"form", form},
      {"status_text", true},
      {"action_result_panel", true}
    ]

    for {id, present} <- sections, present, do: id
  end

  # The result panel displays map-returning generic action results: a Column
  # wrapping a Text bound to the reserved /ui/action_result_text path (see
  # topics/data-model-conventions). Empty text renders nothing.
  defp action_result_components do
    [
      %{
        "id" => "action_result_panel",
        "component" => "Column",
        "children" => ["action_result_text"]
      },
      %{
        "id" => "action_result_text",
        "component" => "Text",
        "text" => %{"path" => "/ui/action_result_text"}
      }
    ]
  end

  defp table_components(view, _table) do
    [
      %{
        "id" => "table_heading",
        "component" => "Text",
        "text" => humanize_resource(view.resource),
        "variant" => "h2"
      },
      %{
        "id" => "records_list",
        "component" => "List",
        "children" => %{"componentId" => "record_row", "path" => "/records"}
      }
    ]
  end

  # --- query controls (search / filters / pagination) ---

  # The `"query"` action wire contract: every control sends
  # `{"query": {"path": "/query"}}` — the current query state — plus either a
  # literal page reset (`"page" => 1`, Apply) or a relative page change
  # (`"pageDelta" => -1 | 1`, prev/next). The server validates everything
  # against the declared allowlist (`AshA2ui.QueryRunner`).
  defp query_components(view, query) do
    search = (query.search_fields != [] && [search_input()]) || []
    filters = Enum.map(query.filters, &filter_picker(view.resource, &1))

    controls = %{
      "id" => "query_controls",
      "component" => "Row",
      "children" => Enum.map(search ++ filters, & &1["id"]) ++ ["query_apply_button"]
    }

    [controls | search ++ filters] ++ apply_button() ++ pagination_components()
  end

  defp search_input do
    %{
      "id" => "query_search_input",
      "component" => "TextField",
      "label" => "Search",
      "value" => %{"path" => "/query/search"}
    }
  end

  defp filter_picker(resource, field) do
    %{
      "id" => "query_filter_#{field}",
      "component" => "ChoicePicker",
      "label" => humanize(field),
      "variant" => "mutuallyExclusive",
      "value" => %{"path" => "/query/filters/#{field}"},
      "options" => [%{"label" => "All", "value" => ""} | filter_options(resource, field)]
    }
  end

  defp filter_options(resource, field) do
    if attribute_type(resource, field) == Ash.Type.Boolean do
      [%{"label" => "True", "value" => "true"}, %{"label" => "False", "value" => "false"}]
    else
      choice_options(resource, field)
    end
  end

  defp apply_button do
    [
      query_button("query_apply", %{"query" => %{"path" => "/query"}, "page" => 1}),
      %{"id" => "query_apply_text", "component" => "Text", "text" => "Apply"}
    ]
  end

  defp pagination_components do
    [
      %{
        "id" => "query_pagination",
        "component" => "Row",
        "children" => ["query_prev_button", "query_page_text", "query_next_button"]
      },
      query_button("query_prev", %{"query" => %{"path" => "/query"}, "pageDelta" => -1}),
      %{"id" => "query_prev_text", "component" => "Text", "text" => "Previous"},
      %{"id" => "query_page_text", "component" => "Text", "text" => %{"path" => "/query/page"}},
      query_button("query_next", %{"query" => %{"path" => "/query"}, "pageDelta" => 1}),
      %{"id" => "query_next_text", "component" => "Text", "text" => "Next"}
    ]
  end

  defp query_button(id_prefix, context) do
    %{
      "id" => "#{id_prefix}_button",
      "component" => "Button",
      "child" => "#{id_prefix}_text",
      "action" => %{"event" => %{"name" => "query", "context" => context}}
    }
  end

  # Write-action contexts carry the current /query so success refreshes can
  # re-read with the client's active search/filters/sort/page.
  defp put_query_binding(context, %{query: nil}), do: context

  defp put_query_binding(context, _view),
    do: Map.put(context, "query", %{"path" => "/query"})

  defp table_descendants(_view, nil), do: []

  defp table_descendants(view, table) do
    cell_ids = Enum.map(table.fields, &"table_cell_#{&1}")
    action_button_ids = Enum.map(table.row_actions, &"row_action_#{&1}_button")

    row = %{
      "id" => "record_row",
      "component" => "Row",
      "children" => cell_ids ++ action_button_ids ++ ["row_select_button"]
    }

    cells = Enum.map(table.fields, &cell(view, &1))
    action_buttons = Enum.flat_map(table.row_actions, &row_action_button(view, &1))

    select_button = [
      %{
        "id" => "row_select_button",
        "component" => "Button",
        "child" => "row_select_text",
        "action" => %{
          "event" => %{
            "name" => "select_row",
            "context" => %{"recordId" => %{"path" => "id"}}
          }
        }
      },
      %{"id" => "row_select_text", "component" => "Text", "text" => "Select"}
    ]

    [row] ++ cells ++ action_buttons ++ select_button
  end

  defp cell(view, field_name) do
    field = view.fields[field_name]

    %{
      "id" => "table_cell_#{field_name}",
      "component" => "Text",
      "text" => cell_text(field)
    }
  end

  # Template-relative binding: paths inside a List item template resolve
  # against the item object, so plain "<field>" (no leading /).
  defp cell_text(%{format: :date} = field) do
    %{
      "call" => "formatDate",
      "args" => %{
        "value" => %{"path" => to_string(field.name)},
        "format" => "MMM d, yyyy"
      },
      "returnType" => "string"
    }
  end

  defp cell_text(field), do: %{"path" => to_string(field.name)}

  defp row_action_button(view, action) do
    [
      %{
        "id" => "row_action_#{action}_button",
        "component" => "Button",
        "child" => "row_action_#{action}_text",
        "action" => %{
          "event" => %{
            "name" => "invoke",
            "context" =>
              put_query_binding(
                %{
                  "action" => to_string(action),
                  "recordId" => %{"path" => "id"}
                },
                view
              )
          }
        }
      },
      %{
        "id" => "row_action_#{action}_text",
        "component" => "Text",
        "text" => humanize(action)
      }
    ]
  end

  defp form_components(_view, form) do
    children =
      Enum.flat_map(form.fields, &["form_input_#{&1}", "form_error_#{&1}"]) ++
        ["form_submit_button"]

    [%{"id" => "form", "component" => "Column", "children" => children}]
  end

  defp form_descendants(_view, nil, _options), do: []

  defp form_descendants(view, form, options) do
    inputs = Enum.map(form.fields, &form_input(view, &1, options))
    errors = Enum.map(form.fields, &form_error/1)

    submit = [
      %{
        "id" => "form_submit_button",
        "component" => "Button",
        "variant" => "primary",
        "child" => "form_submit_text",
        "action" => %{
          "event" => %{
            "name" => "submit_form",
            "context" =>
              put_query_binding(
                %{
                  "values" => %{"path" => "/form"},
                  "recordId" => %{"path" => "/form/id"}
                },
                view
              )
          }
        }
      },
      %{"id" => "form_submit_text", "component" => "Text", "text" => "Save"}
    ]

    inputs ++ errors ++ submit
  end

  defp form_input(view, field_name, options) do
    field = view.fields[field_name]
    binding = %{"path" => "/form/#{field_name}"}

    base = %{"id" => "form_input_#{field_name}", "label" => field.label, "value" => binding}

    case field.widget do
      :check_box ->
        Map.put(base, "component", "CheckBox")

      :choice_picker ->
        base
        |> Map.put("component", "ChoicePicker")
        |> Map.put("variant", "mutuallyExclusive")
        |> Map.put("options", picker_options(view, field_name, options))

      :date_time_input ->
        base
        |> Map.put("component", "DateTimeInput")
        |> Map.put("enableDate", true)
        |> Map.put("enableTime", not date_only?(view.resource, field_name))

      _text_field ->
        text_field = Map.put(base, "component", "TextField")

        if numeric?(view.resource, field_name) do
          Map.put(text_field, "variant", "number")
        else
          text_field
        end
    end
  end

  defp form_error(field_name) do
    %{
      "id" => "form_error_#{field_name}",
      "component" => "Text",
      "text" => %{"path" => "/errors/#{field_name}"},
      "variant" => "caption"
    }
  end

  # Relationship selects use the loaded option list; enum-constrained
  # attributes keep their static `one_of` options. The v0.9.1 basic-catalog
  # ChoicePicker only accepts a literal options array (each option's `value`
  # is a plain string, no data binding), so loaded options are emitted inline
  # here and mirrored at /options/<field> in the data model.
  defp picker_options(view, field_name, options) do
    if Map.has_key?(view.selects, field_name) do
      Map.fetch!(options, field_name)
    else
      choice_options(view.resource, field_name)
    end
  end

  defp choice_options(resource, field_name) do
    resource
    |> attribute_constraints(field_name)
    |> Keyword.get(:one_of, [])
    |> Enum.map(&%{"label" => humanize(&1), "value" => to_string(&1)})
  end

  defp numeric?(resource, field_name),
    do: attribute_type(resource, field_name) in @numeric_types

  defp date_only?(resource, field_name),
    do: attribute_type(resource, field_name) == Ash.Type.Date

  defp attribute_type(resource, field_name) do
    case ResourceInfo.attribute(resource, field_name) do
      %{type: type} -> Ash.Type.get_type(type)
      nil -> nil
    end
  end

  defp attribute_constraints(resource, field_name) do
    case ResourceInfo.attribute(resource, field_name) do
      %{constraints: constraints} when is_list(constraints) -> constraints
      _ -> []
    end
  end

  # --- /query state ---

  # The initial data model carries the query state under "query". Callers that
  # ran the query (AshA2ui.Info) pass the real state via `:query_state`; direct
  # encoder calls fall back to the declared defaults with counts derived from
  # the records at hand.
  defp put_query_state(value, %{query: nil}, _opts), do: value

  defp put_query_state(value, view, opts) do
    state =
      Keyword.get(opts, :query_state) ||
        AshA2ui.QueryRunner.state(
          view.query,
          AshA2ui.QueryRunner.default_params(view.query),
          length(value["records"]),
          false
        )

    Map.put(value, "query", state)
  end

  # --- record serialization ---

  defp serialize_record(view, record) do
    table = Enum.find(view.components, &(&1.name == :table))

    field_names =
      case table do
        %{fields: fields} -> fields
        nil -> view.fields |> Map.values() |> Enum.reject(& &1.hidden) |> Enum.map(& &1.name)
      end

    [:id | field_names]
    |> Enum.uniq()
    |> Map.new(fn name -> {to_string(name), field_value(view, record, name)} end)
  end

  # `source` columns read through the loaded relationship path (nil-safe: a
  # nil or unloaded relationship serializes to ""); plain fields read the
  # record key directly.
  defp field_value(view, record, name) do
    case view.fields[name] do
      %{source: [_ | _] = source} -> record |> walk_source(source) |> source_safe()
      _plain -> record |> Map.get(name) |> json_safe()
    end
  end

  defp walk_source(record, [attribute]), do: Map.get(record, attribute)

  defp walk_source(record, [relationship | rest]) do
    case Map.get(record, relationship) do
      %Ash.NotLoaded{} -> nil
      nil -> nil
      related -> walk_source(related, rest)
    end
  end

  defp source_safe(nil), do: ""
  defp source_safe(value), do: json_safe(value)

  defp json_safe(%Decimal{} = decimal), do: Decimal.to_string(decimal)
  defp json_safe(%Date{} = date), do: Date.to_iso8601(date)
  defp json_safe(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp json_safe(%NaiveDateTime{} = naive), do: NaiveDateTime.to_iso8601(naive)
  defp json_safe(%Time{} = time), do: Time.to_iso8601(time)

  defp json_safe(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: to_string(value)

  defp json_safe(value), do: value

  defp humanize_resource(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> humanize()
  end

  defp humanize(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
