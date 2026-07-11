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
  alias AshA2ui.ResolvedView

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
    serialized = records_value(resolved_view, records)

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

  # The value at "/records": on single-table surfaces the serialized row
  # list (records arrive as a list); on multi-table surfaces an object keyed
  # by table component name (records arrive as %{table_name => [record]},
  # see AshA2ui.Info) — every declared table gets a key, missing ones [].
  defp records_value(view, records) do
    if ResolvedView.multi_table?(view) do
      unless is_map(records) do
        raise ArgumentError,
              "multi-table surfaces expect records as a map keyed by table component " <>
                "name (%{table_name => [record]}), got: #{inspect(records)}"
      end

      Map.new(view.tables, fn table ->
        rows = Map.get(records, table.name, [])
        {to_string(table.name), Enum.map(rows, &serialize_record(view, table, &1))}
      end)
    else
      Enum.map(records, &serialize_record(view, List.first(view.tables), &1))
    end
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

  # Multi-table id scheme: single-table surfaces keep the frozen unsuffixed
  # ids ("records_list", "table_cell_<field>", "query_apply_button", ...);
  # multi-table surfaces infix the table component name right after the id's
  # leading noun ("records_list_<name>", "table_cell_<name>_<field>",
  # "query_<name>_apply_button", ...) — see the sfx/1-using call sites.
  defp components(view, options) do
    form = Enum.find(view.components, &(&1.name == :form))

    table_sections =
      Enum.flat_map(view.tables, fn table ->
        sfx = table_suffix(view, table)

        table_components(view, table, sfx) ++
          query_components(view, table, sfx) ++
          table_descendants(view, table, sfx)
      end)

    form_components = (form && form_components(view, form)) || []

    root = %{
      "id" => "root",
      "component" => "Column",
      "children" => root_children(view, form)
    }

    status = %{
      "id" => "status_text",
      "component" => "Text",
      "text" => %{"path" => "/ui/status"}
    }

    [root | table_sections ++ form_components] ++
      form_descendants(view, form, options) ++ [status | action_result_components()]
  end

  defp table_suffix(view, table) do
    if ResolvedView.multi_table?(view), do: "_#{table.name}", else: ""
  end

  # Root order: per table (in declaration order) heading, query controls,
  # the list, pagination; then form, status, action-result panel — each
  # section present only when declared.
  defp root_children(view, form) do
    table_children =
      Enum.flat_map(view.tables, fn table ->
        sfx = table_suffix(view, table)

        ["table_heading#{sfx}"] ++
          ((table.query && ["query#{sfx}_controls"]) || []) ++
          ["records_list#{sfx}"] ++
          ((table.query && ["query#{sfx}_pagination"]) || [])
      end)

    table_children ++ ((form && ["form"]) || []) ++ ["status_text", "action_result_panel"]
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

  # Single-table headings show the humanized resource name (frozen); each
  # multi-table section is headed by its humanized component name.
  defp table_components(view, table, sfx) do
    heading =
      if ResolvedView.multi_table?(view),
        do: humanize(table.name),
        else: humanize_resource(view.resource)

    [
      %{
        "id" => "table_heading#{sfx}",
        "component" => "Text",
        "text" => heading,
        "variant" => "h2"
      },
      %{
        "id" => "records_list#{sfx}",
        "component" => "List",
        "children" => %{"componentId" => "record_row#{sfx}", "path" => table.records_path}
      }
    ]
  end

  # --- query controls (search / filters / pagination) ---

  # The `"query"` action wire contract: every control sends
  # `{"query": {"path": <the table's query path>}}` — the current query
  # state — plus the source `"component"` and either a literal page reset
  # (`"page" => 1`, Apply) or a relative page change (`"pageDelta" => -1 | 1`,
  # prev/next). The server validates everything against the declared
  # allowlist (`AshA2ui.QueryRunner`).
  defp query_components(_view, %{query: nil}, _sfx), do: []

  defp query_components(view, table, sfx) do
    query = table.query
    search = (query.search_fields != [] && [search_input(table, sfx)]) || []
    filters = Enum.map(query.filters, &filter_picker(view.resource, table, &1, sfx))

    controls = %{
      "id" => "query#{sfx}_controls",
      "component" => "Row",
      "children" => Enum.map(search ++ filters, & &1["id"]) ++ ["query#{sfx}_apply_button"]
    }

    [controls | search ++ filters] ++
      apply_button(table, sfx) ++ pagination_components(table, sfx)
  end

  defp search_input(table, sfx) do
    %{
      "id" => "query#{sfx}_search_input",
      "component" => "TextField",
      "label" => "Search",
      "value" => %{"path" => "#{table.query_path}/search"}
    }
  end

  defp filter_picker(resource, table, field, sfx) do
    %{
      "id" => "query#{sfx}_filter_#{field}",
      "component" => "ChoicePicker",
      "label" => humanize(field),
      "variant" => "mutuallyExclusive",
      "value" => %{"path" => "#{table.query_path}/filters/#{field}"},
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

  defp apply_button(table, sfx) do
    [
      query_button("query#{sfx}_apply", table, %{"page" => 1}),
      %{"id" => "query#{sfx}_apply_text", "component" => "Text", "text" => "Apply"}
    ]
  end

  defp pagination_components(table, sfx) do
    [
      %{
        "id" => "query#{sfx}_pagination",
        "component" => "Row",
        "children" => [
          "query#{sfx}_prev_button",
          "query#{sfx}_page_text",
          "query#{sfx}_next_button"
        ]
      },
      query_button("query#{sfx}_prev", table, %{"pageDelta" => -1}),
      %{"id" => "query#{sfx}_prev_text", "component" => "Text", "text" => "Previous"},
      %{
        "id" => "query#{sfx}_page_text",
        "component" => "Text",
        "text" => %{"path" => "#{table.query_path}/page"}
      },
      query_button("query#{sfx}_next", table, %{"pageDelta" => 1}),
      %{"id" => "query#{sfx}_next_text", "component" => "Text", "text" => "Next"}
    ]
  end

  defp query_button(id_prefix, table, context) do
    context =
      context
      |> Map.put("query", %{"path" => table.query_path})
      |> Map.put("component", to_string(table.name))

    %{
      "id" => "#{id_prefix}_button",
      "component" => "Button",
      "child" => "#{id_prefix}_text",
      "action" => %{"event" => %{"name" => "query", "context" => context}}
    }
  end

  # Write-action contexts carry the current /query (on multi-table surfaces:
  # the whole per-table state map) so success refreshes can re-read with the
  # client's active search/filters/sort/page.
  defp put_query_binding(context, view) do
    if Enum.any?(view.tables, & &1.query) do
      Map.put(context, "query", %{"path" => "/query"})
    else
      context
    end
  end

  defp table_descendants(view, table, sfx) do
    fields = table.component.fields
    cell_ids = Enum.map(fields, &"table_cell#{sfx}_#{&1}")
    action_button_ids = Enum.map(table.row_actions, &"row_action#{sfx}_#{&1}_button")

    row = %{
      "id" => "record_row#{sfx}",
      "component" => "Row",
      "children" => cell_ids ++ action_button_ids ++ ["row_select#{sfx}_button"]
    }

    cells = Enum.map(fields, &cell(view, &1, sfx))
    action_buttons = Enum.flat_map(table.row_actions, &row_action_button(view, table, &1, sfx))

    select_button = [
      %{
        "id" => "row_select#{sfx}_button",
        "component" => "Button",
        "child" => "row_select#{sfx}_text",
        "action" => %{
          "event" => %{
            "name" => "select_row",
            "context" => %{
              "recordId" => %{"path" => "id"},
              "component" => to_string(table.name)
            }
          }
        }
      },
      %{"id" => "row_select#{sfx}_text", "component" => "Text", "text" => "Select"}
    ]

    [row] ++ cells ++ action_buttons ++ select_button
  end

  defp cell(view, field_name, sfx) do
    field = view.fields[field_name]

    %{
      "id" => "table_cell#{sfx}_#{field_name}",
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

  defp row_action_button(view, table, action, sfx) do
    [
      %{
        "id" => "row_action#{sfx}_#{action}_button",
        "component" => "Button",
        "child" => "row_action#{sfx}_#{action}_text",
        "action" => %{
          "event" => %{
            "name" => "invoke",
            "context" =>
              put_query_binding(
                %{
                  "action" => to_string(action),
                  "recordId" => %{"path" => "id"},
                  "component" => to_string(table.name)
                },
                view
              )
          }
        }
      },
      %{
        "id" => "row_action#{sfx}_#{action}_text",
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

  # The initial data model carries the query state under "query": the single
  # table's state map, or (multi-table) an object keyed by table component
  # name covering every query-attached table. Callers that ran the queries
  # (AshA2ui.Info) pass the real state via `:query_state`; direct encoder
  # calls fall back to the declared defaults with counts derived from the
  # records at hand. Omitted entirely when no table declares a query.
  defp put_query_state(value, view, opts) do
    query_tables = Enum.filter(view.tables, & &1.query)

    cond do
      query_tables == [] ->
        value

      ResolvedView.multi_table?(view) ->
        states = Keyword.get(opts, :query_state) || %{}

        Map.put(
          value,
          "query",
          Map.new(query_tables, fn table ->
            rows = value["records"][to_string(table.name)] || []
            {to_string(table.name), Map.get(states, table.name) || default_state(table, rows)}
          end)
        )

      true ->
        state =
          Keyword.get(opts, :query_state) || default_state(hd(query_tables), value["records"])

        Map.put(value, "query", state)
    end
  end

  defp default_state(table, records) do
    AshA2ui.QueryRunner.state(
      table.query,
      AshA2ui.QueryRunner.default_params(table.query),
      length(records),
      false
    )
  end

  # --- record serialization ---

  defp serialize_record(view, table, record) do
    field_names =
      case table do
        %{component: %{fields: fields}} -> fields
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

  # A calculation/aggregate that slipped past `loads` must not leak an
  # inspect()-ed struct onto the wire.
  defp json_safe(%Ash.NotLoaded{}), do: nil
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
