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
      omitted when the query has no `search_fields`), a preset `ChoicePicker`
      (`query_preset_picker`, bound to `/query/preset`, only when the query
      declares presets — options are the preset names, preceded by an
      `"All"`/`""` option unless a `default_preset` is declared), one
      `ChoicePicker` per declared filter (`query_filter_<name>`, bound to
      `/query/filters/<name>`, with an `"All"` option first) and a
      `query_apply_button` (event `query`, context
      `{"query": {"path": "/query"}, "page": 1}` — the page-1 reset)
    * `records_list` — `List` whose children are a template
      `{"componentId": "record_row", "path": "/records"}`; `record_row` is a
      `Card` wrapping `record_row_content`, a `Row` of per-field labeled
      cells — each `table_cell_<field>` is a `Row` of a caption `Text`
      (`table_cell_<field>_label`, the humanized field name) and a value
      `Text` (`table_cell_<field>_value`, bound to the template-relative
      path `<field>`, `format: :date` rendered through `formatDate`) —
      one `Button` per row action
      (`row_action_<action>_button`: event `invoke`, context
      `{"action": "<name>", "recordId": {"path": "id"}}`) and — only on
      surfaces with a `:form` component — a `row_select_button` (event
      `select_row`, context `{"recordId": {"path": "id"}}`; `select_row`
      populates `/form`, so formless surfaces omit the button rather than
      render a control with no visible effect). Tables declaring a `row_layout`
      swap the card's content for a header + metadata-grid structure —
      see the Layout topic and `card_row_components/4`

  ## Row-action prompts (prompt_fields)

  A row action whose `action` entity declares `prompt_fields` renders as a
  `Modal` (`row_action_<action>_modal`) instead of a bare button: the row
  slot holds the Modal, whose `trigger` is the usual
  `row_action_<action>_button` — now dispatching event `prompt` with context
  `{"action": "<name>", "recordId": {"path": "id"}, "component": "<table>"}`
  so the server pre-fills `/prompt/values/<action>` — and whose `content` is
  `row_action_<action>_prompt`, a `Column` of a title `Text`, one `TextField`
  per prompt field (bound to the absolute `/prompt/values/<action>/<field>`
  path; template-relative paths cannot reach the shared prompt state), a
  per-field error `Text` (bound to `/errors/<field>`) and a confirm `Button`
  (`row_action_<action>_confirm_button`: event `invoke`, context carrying
  `"values": {"path": "/prompt/values/<action>"}` alongside the usual
  `"action"`/`"recordId"`/`"component"`). Modal open/close is client-side
  (the v0.9.1 protocol has no server-controlled open state); the server
  contract is only the `prompt` pre-fill and the `invoke` values.

  ## Conditional row actions (visible_when)

  A row action whose `action` entity declares `visible_when` conditions is
  wrapped in `row_action_<action>_slot` — a `List` templated over the
  row-relative `_visible_<action>` path (`[%{"id" => id}]` when visible,
  `[]` when hidden, computed server-side; see `AshA2ui.Conditions`).
  Renderers supporting nested templates render zero or one button per row;
  rows also carry `"_actions"` (the visible action names) for renderers that
  don't. Rendering is best-effort — enforcement lives in
  `AshA2ui.ActionHandler`, which re-evaluates the conditions on every
  invoke.
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

  Surfaces with prompt-enabled row actions additionally carry `"prompt"` —
  `%{"values" => %{"<action>" => %{"<field>" => ""}}}` — and rows of tables
  with `visible_when` row actions gain the `"_actions"` /
  `"_visible_<action>"` keys (see the sections above).

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
             "form" => ResolvedView.initial_form(resolved_view),
             "errors" => %{},
             "options" => options_data(resolved_view, opts),
             "ui" => %{"status" => "", "action_result" => %{}, "action_result_text" => ""}
           }
           |> put_query_state(resolved_view, opts)
           |> put_prompt_state(resolved_view)
           |> put_select_state(resolved_view)
           |> put_context_data(resolved_view, opts)}
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

  # Options for relationship selects and pick_existing nested forms are
  # loaded by the caller (`AshA2ui.Info`) and passed via `opts[:options]` as
  # `%{name => [%{"label" => _, "value" => _}]}`. Direct encoder calls
  # without the option fall back to empty option lists per source.
  defp select_options(view, opts) do
    context_defaults =
      for {name, %{picker: true}} <- view.contexts, into: %{}, do: {name, []}

    defaults =
      view
      |> ResolvedView.option_sources()
      |> Map.new(fn {name, _source} -> {name, []} end)
      |> Map.merge(context_defaults)

    Map.merge(defaults, Keyword.get(opts, :options) || %{})
  end

  # The reserved /select state (searchable-select search text + selected
  # label, pick_existing search text + picked value). Omitted entirely on
  # surfaces without wave-5 relationship inputs (frozen shape unchanged).
  defp put_select_state(value, view) do
    case ResolvedView.select_state(view) do
      state when state == %{} -> value
      state -> Map.put(value, "select", state)
    end
  end

  # The `/options/<field>` data-model mirror of the inline ChoicePicker
  # options (string keys, same list shape).
  defp options_data(view, opts) do
    view
    |> select_options(opts)
    |> Map.new(fn {name, options} -> {to_string(name), options} end)
  end

  # The reserved /context and /detail state (see AshA2ui.ContextRunner):
  # the caller-resolved values when given (AshA2ui.Info passes them after
  # loading under the carried :context_state), the empty initial shapes
  # otherwise. Omitted entirely on context-less surfaces (frozen shape
  # unchanged).
  defp put_context_data(value, view, opts) do
    if ResolvedView.contexts?(view) do
      value
      |> Map.put(
        "context",
        Keyword.get(opts, :context_values) || ResolvedView.context_state(view)
      )
      |> put_detail_data(view, opts)
    else
      value
    end
  end

  defp put_detail_data(value, view, opts) do
    case ResolvedView.detail_state(view) do
      state when state == %{} ->
        value

      state ->
        resolved =
          Map.new(
            Keyword.get(opts, :detail_values) || %{},
            fn {name, detail_value} -> {to_string(name), detail_value} end
          )

        Map.put(value, "detail", Map.merge(state, resolved))
    end
  end

  # --- component tree ---

  # Multi-table id scheme: single-table surfaces keep the frozen unsuffixed
  # ids ("records_list", "table_cell_<field>", "query_apply_button", ...);
  # multi-table surfaces infix the table component name right after the id's
  # leading noun ("records_list_<name>", "table_cell_<name>_<field>",
  # "query_<name>_apply_button", ...) — see the sfx/1-using call sites.
  defp components(view, options) do
    form = Enum.find(view.components, &(&1.name == :form))

    context_sections =
      Enum.flat_map(view.context_order, &context_picker_components(view, view.contexts[&1]))

    table_sections =
      Enum.flat_map(view.tables, fn table ->
        sfx = table_suffix(view, table)

        table_components(view, table, sfx) ++
          query_components(view, table, sfx) ++
          table_descendants(view, table, sfx)
      end)

    detail_sections = Enum.flat_map(view.details, &detail_components(view, &1))

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

    [root | context_sections ++ table_sections ++ detail_sections ++ form_components] ++
      form_descendants(view, form, options) ++ [status | action_result_components()]
  end

  defp table_suffix(view, table) do
    if ResolvedView.multi_table?(view), do: "_#{table.name}", else: ""
  end

  # Root order: context pickers (in declaration order), then per
  # table/detail component (in declaration order) its section — a table's
  # heading, query controls, list, pagination; a detail's column — then
  # form, status, action-result panel; each section present only when
  # declared. Surfaces without contexts/details keep the frozen pre-context
  # root order.
  defp root_children(view, form) do
    context_children =
      for name <- view.context_order, view.contexts[name].picker, do: "context_#{name}"

    component_children = Enum.flat_map(view.components, &component_root_children(view, &1))

    context_children ++
      component_children ++ ((form && ["form"]) || []) ++ ["status_text", "action_result_panel"]
  end

  defp component_root_children(view, %{name: :table} = component) do
    table = Enum.find(view.tables, &(&1.component == component))
    sfx = table_suffix(view, table)

    ["table_heading#{sfx}"] ++
      ((table.query && ["query#{sfx}_controls"]) || []) ++
      ["records_list#{sfx}"] ++
      ((table.query && ["query#{sfx}_pagination"]) || [])
  end

  defp component_root_children(_view, %{name: :detail} = component),
    do: ["detail_#{AshA2ui.Component.key(component)}"]

  defp component_root_children(_view, _form), do: []

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
  # multi-table section is headed by its humanized component name — except
  # the expanded tables of a dynamic table set, which are headed by their
  # section record's label (see AshA2ui.Sections).
  defp table_components(view, table, sfx) do
    heading =
      case Map.get(table, :section) do
        %{label: label} ->
          label

        _not_a_section ->
          if ResolvedView.multi_table?(view),
            do: humanize(table.name),
            else: humanize_resource(view.resource)
      end

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
    presets = (query.presets != [] && [preset_picker(query, table, sfx)]) || []
    filters = Enum.map(query.filters, &filter_picker(view.resource, table, &1, sfx))
    ranges = Enum.flat_map(query.range_filters, &range_inputs(table, &1, sfx))

    # Query controls render as a Card (`query<sfx>_controls`, the id root
    # children reference) over a `_body` Row — section chrome on every
    # renderer, same shape as form groups and the context/detail sections.
    card = %{
      "id" => "query#{sfx}_controls",
      "component" => "Card",
      "child" => "query#{sfx}_controls_body"
    }

    controls = %{
      "id" => "query#{sfx}_controls_body",
      "component" => "Row",
      "children" =>
        Enum.map(search ++ presets ++ filters ++ ranges, & &1["id"]) ++
          ["query#{sfx}_apply_button"]
    }

    [card, controls | search ++ presets ++ filters ++ ranges] ++
      apply_button(view, table, sfx) ++ pagination_components(view, table, sfx)
  end

  defp search_input(table, sfx) do
    %{
      "id" => "query#{sfx}_search_input",
      "component" => "TextField",
      "label" => "Search",
      "value" => %{"path" => "#{table.query_path}/search"}
    }
  end

  # The preset picker sends only the preset NAME over the wire — the
  # predicates live server-side. With a default_preset the option set is
  # closed (no "" escape back to the unscoped base read); without one an
  # "All" option ("" = no preset) comes first, mirroring the filter pickers.
  defp preset_picker(query, table, sfx) do
    preset_options =
      Enum.map(query.presets, &%{"label" => humanize(&1.name), "value" => to_string(&1.name)})

    options =
      if query.default_preset do
        preset_options
      else
        [%{"label" => "All", "value" => ""} | preset_options]
      end

    %{
      "id" => "query#{sfx}_preset_picker",
      "component" => "ChoicePicker",
      "label" => "View",
      "variant" => "mutuallyExclusive",
      "value" => %{"path" => "#{table.query_path}/preset"},
      "options" => options
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

  # Each range_filters field emits a from/to TextField pair bound to the
  # frozen /query/ranges/<field>/from|to paths; the shared Apply button
  # submits them with the rest of the query state.
  defp range_inputs(table, field, sfx) do
    Enum.map(["from", "to"], fn side ->
      %{
        "id" => "query#{sfx}_range_#{field}_#{side}",
        "component" => "TextField",
        "label" => "#{humanize(field)} #{side}",
        "value" => %{"path" => "#{table.query_path}/ranges/#{field}/#{side}"}
      }
    end)
  end

  defp apply_button(view, table, sfx) do
    [
      query_button("query#{sfx}_apply", table, %{"page" => 1}, view),
      %{"id" => "query#{sfx}_apply_text", "component" => "Text", "text" => "Apply"}
    ]
  end

  defp pagination_components(view, table, sfx) do
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
      query_button("query#{sfx}_prev", table, %{"pageDelta" => -1}, view),
      %{"id" => "query#{sfx}_prev_text", "component" => "Text", "text" => "Previous"},
      %{
        "id" => "query#{sfx}_page_text",
        "component" => "Text",
        "text" => %{"path" => "#{table.query_path}/page"}
      },
      query_button("query#{sfx}_next", table, %{"pageDelta" => 1}, view),
      %{"id" => "query#{sfx}_next_text", "component" => "Text", "text" => "Next"}
    ]
  end

  defp query_button(id_prefix, table, context, view) do
    context =
      context
      |> Map.put("query", %{"path" => table.query_path})
      |> Map.put("component", to_string(table.name))
      |> put_contexts_binding(view)

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

  # Action contexts on context-enabled surfaces carry the current /context
  # map, so server reads (refreshes, query, context cascades) run under the
  # client's active selections. Context-less surfaces are unchanged (frozen
  # contract).
  defp put_contexts_binding(context, view) do
    if ResolvedView.contexts?(view) do
      Map.put(context, "contexts", %{"path" => "/context"})
    else
      context
    end
  end

  defp table_descendants(view, table, sfx) do
    {action_ids, action_components} =
      table.row_actions
      |> Enum.map(&row_action_components(view, table, &1, sfx))
      |> Enum.unzip()

    # The context-select button (master/detail hook) rides along with the
    # row-action anchors in either layout, as does the row-select button —
    # but the latter only on surfaces with a form: select_row exists solely
    # to populate /form, so a formless surface would render a dead button.
    {context_select_ids, context_select_components} = context_select_button(view, table, sfx)

    select_components =
      if Enum.any?(view.components, &(&1.name == :form)), do: select_button(table, sfx), else: []

    action_ids =
      action_ids ++ context_select_ids ++ Enum.map(Enum.take(select_components, 1), & &1["id"])

    row_components =
      case table.component.row_layout do
        nil -> flat_row_components(view, table, action_ids, sfx)
        layout -> card_row_components(view, layout, action_ids, sfx)
      end

    row_components ++
      List.flatten(action_components) ++ context_select_components ++ select_components
  end

  # Each record renders as a Card (chrome themed via --a2ui-card-*)
  # wrapping the actual Row of labeled cells; the List template still points
  # at record_row, so this stays invisible to the data model and actions.
  defp flat_row_components(view, table, action_ids, sfx) do
    fields = table.component.fields
    cell_ids = Enum.map(fields, &"table_cell#{sfx}_#{&1}")

    card = %{
      "id" => "record_row#{sfx}",
      "component" => "Card",
      "child" => "record_row#{sfx}_content"
    }

    row = %{
      "id" => "record_row#{sfx}_content",
      "component" => "Row",
      "children" => cell_ids ++ action_ids
    }

    [card, row | Enum.flat_map(fields, &cell(view, &1, sfx))]
  end

  # Card-style rows (row_layout): the templated record_row becomes a Card
  # whose Column body holds a header Row — the title Text (weight 1) and a
  # right-hand Row of the badge Text (when declared) plus the row's action
  # anchors and select button — above the meta grid (see grid_components/4:
  # Rows of equal-weight Columns, each a caption label over the bound value).
  defp card_row_components(view, layout, action_ids, sfx) do
    base = "record_row#{sfx}"

    badge =
      if layout.badge do
        [
          %{
            "id" => "#{base}_badge",
            "component" => "Text",
            "text" => %{"path" => "_badge_#{layout.badge}"},
            "variant" => "caption"
          }
        ]
      else
        []
      end

    {meta_row_ids, meta_components} =
      grid_components("#{base}_meta", layout.columns, layout.meta, fn field ->
        {["#{base}_meta_label_#{field}", "#{base}_meta_value_#{field}"],
         [
           %{
             "id" => "#{base}_meta_label_#{field}",
             "component" => "Text",
             "text" => view.fields[field].label,
             "variant" => "caption"
           },
           %{
             "id" => "#{base}_meta_value_#{field}",
             "component" => "Text",
             "text" => cell_text(view.fields[field])
           }
         ]}
      end)

    [
      %{"id" => base, "component" => "Card", "child" => "#{base}_body"},
      %{
        "id" => "#{base}_body",
        "component" => "Column",
        "children" => ["#{base}_header" | meta_row_ids]
      },
      %{
        "id" => "#{base}_header",
        "component" => "Row",
        "justify" => "spaceBetween",
        "align" => "center",
        "children" => ["#{base}_title", "#{base}_header_right"]
      },
      %{
        "id" => "#{base}_title",
        "component" => "Text",
        "text" => cell_text(view.fields[layout.title]),
        "variant" => "h4",
        "weight" => 1
      },
      %{
        "id" => "#{base}_header_right",
        "component" => "Row",
        "align" => "center",
        "children" => Enum.map(badge, & &1["id"]) ++ action_ids
      }
    ] ++ badge ++ meta_components
  end

  # An N-column grid: items chunked into Rows of `columns` equal-weight cell
  # Columns (each holding the ids `cell_fun` returns for its item), the last
  # row padded with empty spacer Columns so cells stay aligned.
  defp grid_components(base, columns, items, cell_fun) do
    items
    |> Enum.chunk_every(columns)
    |> Enum.with_index()
    |> Enum.map(fn {row_items, index} ->
      cells =
        Enum.map(row_items, fn item ->
          {children, components} = cell_fun.(item)

          {"#{base}_cell_#{item}",
           [
             %{
               "id" => "#{base}_cell_#{item}",
               "component" => "Column",
               "weight" => 1,
               "children" => children
             }
             | components
           ]}
        end)

      spacers =
        for spacer <- length(row_items)..(columns - 1)//1 do
          {"#{base}_spacer_#{index}_#{spacer}",
           [
             %{
               "id" => "#{base}_spacer_#{index}_#{spacer}",
               "component" => "Column",
               "weight" => 1,
               "children" => []
             }
           ]}
        end

      {cell_ids, cell_components} = Enum.unzip(cells ++ spacers)

      {"#{base}_row_#{index}",
       [
         %{
           "id" => "#{base}_row_#{index}",
           "component" => "Row",
           "children" => cell_ids
         }
         | List.flatten(cell_components)
       ]}
    end)
    |> Enum.unzip()
    |> then(fn {row_ids, components} -> {row_ids, List.flatten(components)} end)
  end

  # Only emitted on surfaces with a :form component — select_row's single
  # purpose is populating /form for editing, so a formless surface gets no
  # Select button (see table_descendants/3).
  defp select_button(table, sfx) do
    [
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
  end

  # A table with `select_context` gets a per-row Button dispatching
  # `context_select` for the named context with the row's id — the
  # master/detail hook: the row's record becomes the context's selection,
  # cascading like a picker selection would.
  defp context_select_button(_view, %{select_context: nil}, _sfx), do: {[], []}

  defp context_select_button(view, table, sfx) do
    name = table.select_context
    base = "row_context#{sfx}_button"

    components = [
      %{
        "id" => base,
        "component" => "Button",
        "child" => "row_context#{sfx}_text",
        "action" => %{
          "event" => %{
            "name" => "context_select",
            "context" =>
              %{
                "context" => to_string(name),
                "value" => %{"path" => "id"}
              }
              |> put_query_binding(view)
              |> put_contexts_binding(view)
          }
        }
      },
      %{
        "id" => "row_context#{sfx}_text",
        "component" => "Text",
        "text" => "View #{String.downcase(humanize(name))}"
      }
    ]

    {[base], components}
  end

  # A cell is a labeled pair: a caption Text with the humanized field name
  # and a body Text bound to the field value — so generated rows read
  # "Name: Fido" instead of a bare value soup.
  defp cell(view, field_name, sfx) do
    field = view.fields[field_name]
    base = "table_cell#{sfx}_#{field_name}"

    [
      %{
        "id" => base,
        "component" => "Row",
        "children" => ["#{base}_label", "#{base}_value"]
      },
      %{
        "id" => "#{base}_label",
        "component" => "Text",
        "text" => humanize(field_name),
        "variant" => "caption"
      },
      %{
        "id" => "#{base}_value",
        "component" => "Text",
        "text" => cell_text(field)
      }
    ]
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

  # One row action's components plus the id placed in the row's children:
  # a plain invoke Button by default; a Modal (trigger button + prompt
  # content) when the action declares prompt_fields; either wrapped in a
  # visibility slot (a List templated over the row-relative
  # `_visible_<action>` path) when the action declares visible_when.
  defp row_action_components(view, table, action, sfx) do
    setting = Map.get(view.actions, action)
    prompt? = match?(%{prompt_fields: [_ | _]}, setting)
    conditional? = match?(%{visible_when: [_ | _]}, setting)
    base = "row_action#{sfx}_#{action}"

    inner_id = if prompt?, do: "#{base}_modal", else: "#{base}_button"
    anchor_id = if conditional?, do: "#{base}_slot", else: inner_id

    button =
      if prompt? do
        prompt_trigger_button(table, action, base) ++
          prompt_components(view, table, action, base, setting)
      else
        invoke_button(view, table, action, base)
      end

    slot = if conditional?, do: [visibility_slot(base, inner_id, action)], else: []

    {anchor_id, button ++ slot}
  end

  defp invoke_button(view, table, action, base) do
    [
      %{
        "id" => "#{base}_button",
        "component" => "Button",
        "child" => "#{base}_text",
        "action" => %{
          "event" => %{
            "name" => "invoke",
            "context" =>
              %{
                "action" => to_string(action),
                "recordId" => %{"path" => "id"},
                "component" => to_string(table.name)
              }
              |> put_query_binding(view)
              |> put_contexts_binding(view)
          }
        }
      },
      %{
        "id" => "#{base}_text",
        "component" => "Text",
        "text" => humanize(action)
      }
    ]
  end

  # The Modal's trigger: opening is client-side (interacting with the
  # trigger), while the `prompt` event lets the server pre-fill
  # /prompt/values/<action> and clear stale /errors.
  defp prompt_trigger_button(table, action, base) do
    [
      %{
        "id" => "#{base}_button",
        "component" => "Button",
        "child" => "#{base}_text",
        "action" => %{
          "event" => %{
            "name" => "prompt",
            "context" => %{
              "action" => to_string(action),
              "recordId" => %{"path" => "id"},
              "component" => to_string(table.name)
            }
          }
        }
      },
      %{
        "id" => "#{base}_text",
        "component" => "Text",
        "text" => humanize(action)
      }
    ]
  end

  # The Modal and its content: a title, one TextField per prompt field bound
  # to the absolute /prompt/values/<action>/<field> path (template-relative
  # paths cannot reach the shared prompt state), a per-field error Text, and
  # the confirm Button whose invoke context carries the "values" binding.
  defp prompt_components(view, table, action, base, setting) do
    title = setting.prompt_title || humanize(action)

    field_children =
      Enum.flat_map(setting.prompt_fields, fn field ->
        ["#{base}_prompt_input_#{field}", "#{base}_prompt_error_#{field}"]
      end)

    inputs =
      Enum.map(setting.prompt_fields, fn field ->
        %{
          "id" => "#{base}_prompt_input_#{field}",
          "component" => "TextField",
          "label" => prompt_label(view, field),
          "value" => %{"path" => "/prompt/values/#{action}/#{field}"}
        }
      end)

    errors =
      Enum.map(setting.prompt_fields, fn field ->
        %{
          "id" => "#{base}_prompt_error_#{field}",
          "component" => "Text",
          "text" => %{"path" => "/errors/#{field}"},
          "variant" => "caption"
        }
      end)

    [
      %{
        "id" => "#{base}_modal",
        "component" => "Modal",
        "trigger" => "#{base}_button",
        "content" => "#{base}_prompt"
      },
      %{
        "id" => "#{base}_prompt",
        "component" => "Column",
        "children" => ["#{base}_prompt_title" | field_children] ++ ["#{base}_confirm_button"]
      },
      %{
        "id" => "#{base}_prompt_title",
        "component" => "Text",
        "text" => title,
        "variant" => "h3"
      }
    ] ++
      inputs ++
      errors ++
      [
        %{
          "id" => "#{base}_confirm_button",
          "component" => "Button",
          "variant" => "primary",
          "child" => "#{base}_confirm_text",
          "action" => %{
            "event" => %{
              "name" => "invoke",
              "context" =>
                %{
                  "action" => to_string(action),
                  "recordId" => %{"path" => "id"},
                  "component" => to_string(table.name),
                  "values" => %{"path" => "/prompt/values/#{action}"}
                }
                |> put_query_binding(view)
                |> put_contexts_binding(view)
            }
          }
        },
        %{"id" => "#{base}_confirm_text", "component" => "Text", "text" => "Confirm"}
      ]
  end

  defp prompt_label(view, field) do
    case view.fields[field] do
      %{label: label} when is_binary(label) -> label
      _undeclared -> humanize(field)
    end
  end

  # Zero-or-one nested template: `_visible_<action>` on the row is either
  # [] or [%{"id" => id}], so the slot renders the action only when the
  # server computed it visible (and the item's "id" keeps the
  # template-relative recordId binding working).
  defp visibility_slot(base, inner_id, action) do
    %{
      "id" => "#{base}_slot",
      "component" => "List",
      "children" => %{"componentId" => inner_id, "path" => "_visible_#{action}"}
    }
  end

  defp form_components(view, form) do
    field_children = form_field_children(view, form)
    nested_children = Enum.map(form.nested_forms, &"nested_#{&1.name}")
    children = field_children ++ nested_children ++ ["form_submit_button"]

    [%{"id" => "form", "component" => "Column", "children" => children}] ++
      group_components(view, form)
  end

  defp field_anchor_ids(view, field) do
    anchor =
      if searchable_select?(view, field),
        do: "form_select_#{field}",
        else: "form_input_#{field}"

    [anchor, "form_error_#{field}"]
  end

  # The ordering contract with groups: walking the form's effective field
  # order, an ungrouped field renders its input/error pair in place, and a
  # group renders (whole, in the group's own field order) at the position of
  # its first member — later members are already covered by the group.
  defp form_field_children(view, %{groups: []} = form) do
    Enum.flat_map(form.fields, &field_anchor_ids(view, &1))
  end

  defp form_field_children(view, form) do
    form.fields
    |> Enum.flat_map_reduce(MapSet.new(), fn field, seen ->
      case Enum.find(form.groups, &(field in &1.fields)) do
        nil -> {field_anchor_ids(view, field), seen}
        %{name: name} -> group_anchor(name, seen)
      end
    end)
    |> elem(0)
  end

  # The group anchor appears once — at its first member's position.
  defp group_anchor(name, seen) do
    if MapSet.member?(seen, name) do
      {[], seen}
    else
      {["form_group_#{name}"], MapSet.put(seen, name)}
    end
  end

  # One Card-wrapped section per group: a heading Text (h3) over the fields.
  # Single-column groups hold the input/error pairs directly; multi-column
  # groups lay them out in the shared grid shape (see grid_components/4).
  defp group_components(view, form) do
    Enum.flat_map(form.groups, &group_section(view, &1))
  end

  defp group_section(view, group) do
    base = "form_group_#{group.name}"
    {grid_children, grid_components} = group_grid(view, group, base)

    [
      %{"id" => base, "component" => "Card", "child" => "#{base}_body"},
      %{
        "id" => "#{base}_body",
        "component" => "Column",
        "children" => ["#{base}_heading" | grid_children]
      },
      %{
        "id" => "#{base}_heading",
        "component" => "Text",
        "text" => group.label,
        "variant" => "h3"
      }
    ] ++ grid_components
  end

  defp group_grid(view, %{columns: 1} = group, _base) do
    {Enum.flat_map(group.fields, &field_anchor_ids(view, &1)), []}
  end

  defp group_grid(view, group, base) do
    grid_components(base, group.columns, group.fields, fn field ->
      {field_anchor_ids(view, field), []}
    end)
  end

  defp searchable_select?(view, field_name) do
    match?(%{search_fields: [_ | _]}, view.selects[field_name])
  end

  defp form_descendants(_view, nil, _options), do: []

  defp form_descendants(view, form, options) do
    inputs =
      Enum.map(form.fields, fn field ->
        if searchable_select?(view, field) do
          searchable_select_components(view, field)
        else
          form_input(view, field, options)
        end
      end)

    nested =
      Enum.flat_map(form.nested_forms, fn entity ->
        nested_form_components(view, view.nested_forms[entity.name], options)
      end)

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
              %{
                "values" => %{"path" => "/form"},
                "recordId" => %{"path" => "/form/id"}
              }
              |> put_query_binding(view)
              |> put_contexts_binding(view)
          }
        }
      },
      %{"id" => "form_submit_text", "component" => "Text", "text" => "Save"}
    ]

    List.flatten(inputs) ++ nested ++ errors ++ submit
  end

  # --- searchable selects ---

  # A relationship select with `option_search` renders as a composite instead
  # of a static ChoicePicker: the current selection's label (bound to
  # /select/<field>/label), a search TextField (bound to
  # /select/<field>/search) with a Button dispatching `option_search`, and a
  # result List templated over /options/<field> whose per-option Button
  # dispatches `option_select` with the template-relative option "value".
  # Selection round-trips through the server, which validates the value
  # against the destination (authorized read) and writes /form/<field> plus
  # the resolved label — labels never come from the client.
  defp searchable_select_components(view, field_name) do
    base = "form_select_#{field_name}"
    field = view.fields[field_name]

    [
      %{
        "id" => base,
        "component" => "Column",
        "children" => [
          "#{base}_label",
          "#{base}_selected",
          "#{base}_controls",
          "#{base}_options"
        ]
      },
      %{"id" => "#{base}_label", "component" => "Text", "text" => field.label, "variant" => "h4"},
      %{
        "id" => "#{base}_selected",
        "component" => "Text",
        "text" => %{"path" => "/select/#{field_name}/label"}
      },
      %{
        "id" => "#{base}_controls",
        "component" => "Row",
        "children" => ["#{base}_search_input", "#{base}_search_button"]
      }
    ] ++
      search_controls(base, to_string(field_name)) ++
      option_list(base, "/options/#{field_name}", %{
        "name" => "option_select",
        "context" => %{
          "field" => to_string(field_name),
          "value" => %{"path" => "value"}
        }
      })
  end

  # The shared search input + button pair: the button's `option_search`
  # context carries the current search text via a data binding and the
  # select/picker name as "field".
  defp search_controls(base, name) do
    [
      %{
        "id" => "#{base}_search_input",
        "component" => "TextField",
        "label" => "Search",
        "value" => %{"path" => "/select/#{name}/search"}
      },
      %{
        "id" => "#{base}_search_button",
        "component" => "Button",
        "child" => "#{base}_search_text",
        "action" => %{
          "event" => %{
            "name" => "option_search",
            "context" => %{
              "field" => name,
              "search" => %{"path" => "/select/#{name}/search"}
            }
          }
        }
      },
      %{"id" => "#{base}_search_text", "component" => "Text", "text" => "Search"}
    ]
  end

  # The option result List: templated over the options path, one Button per
  # option whose child Text binds the template-relative "label" and whose
  # event context carries the template-relative "value".
  defp option_list(base, options_path, event) do
    [
      %{
        "id" => "#{base}_options",
        "component" => "List",
        "children" => %{"componentId" => "#{base}_option_button", "path" => options_path}
      },
      %{
        "id" => "#{base}_option_button",
        "component" => "Button",
        "variant" => "borderless",
        "child" => "#{base}_option_text",
        "action" => %{"event" => event}
      },
      %{
        "id" => "#{base}_option_text",
        "component" => "Text",
        "text" => %{"path" => "label"}
      }
    ]
  end

  # --- contexts and details ---

  # A picker context renders as a surface-level composite mirroring the
  # searchable-select pattern: a Card (`context_<name>`, the root child)
  # over a `_body` Column holding a label, the current selection (bound to
  # /context/<name>/label) with a Clear button (`context_clear`), a search
  # TextField (bound to /context/<name>/search) with a Button dispatching
  # `context_search` when the context declares option_search, and a result
  # List templated over /options/<name> whose per-option Button dispatches
  # `context_select` with the template-relative option "value". Every
  # context action carries the current /context map (and /query state on
  # query-enabled surfaces) so the server cascades under the client's
  # active state. Pickerless contexts (`picker false`) emit nothing — they
  # are selected through a table's `select_context` button.
  defp context_picker_components(_view, %{picker: false}), do: []

  defp context_picker_components(view, context) do
    base = "context_#{context.name}"
    name = to_string(context.name)
    searchable? = context.search_fields != []

    # The section renders as a Card (keeping the frozen `context_<name>` id
    # root children reference) over a `_body` Column holding the composite —
    # card chrome for every renderer; enhanced catalogs (see
    # priv/js/ash_a2ui_catalog.js) upgrade the body to a combobox.
    card = %{
      "id" => base,
      "component" => "Card",
      "child" => "#{base}_body"
    }

    section = %{
      "id" => "#{base}_body",
      "component" => "Column",
      "children" =>
        ["#{base}_label", "#{base}_selected_row"] ++
          ((searchable? && ["#{base}_controls"]) || []) ++ ["#{base}_options"]
    }

    header = [
      card,
      section,
      %{
        "id" => "#{base}_label",
        "component" => "Text",
        "text" => context.label,
        "variant" => "h3"
      },
      %{
        "id" => "#{base}_selected_row",
        "component" => "Row",
        "children" => ["#{base}_selected", "#{base}_clear_button"]
      },
      %{
        "id" => "#{base}_selected",
        "component" => "Text",
        "text" => %{"path" => "/context/#{name}/label"}
      },
      %{
        "id" => "#{base}_clear_button",
        "component" => "Button",
        "variant" => "borderless",
        "child" => "#{base}_clear_text",
        "action" => %{
          "event" => %{
            "name" => "context_clear",
            "context" =>
              %{"context" => name}
              |> put_query_binding(view)
              |> put_contexts_binding(view)
          }
        }
      },
      %{"id" => "#{base}_clear_text", "component" => "Text", "text" => "Clear"}
    ]

    controls =
      if searchable? do
        [
          %{
            "id" => "#{base}_controls",
            "component" => "Row",
            "children" => ["#{base}_search_input", "#{base}_search_button"]
          },
          %{
            "id" => "#{base}_search_input",
            "component" => "TextField",
            "label" => "Search",
            "value" => %{"path" => "/context/#{name}/search"}
          },
          %{
            "id" => "#{base}_search_button",
            "component" => "Button",
            "child" => "#{base}_search_text",
            "action" => %{
              "event" => %{
                "name" => "context_search",
                "context" =>
                  %{
                    "context" => name,
                    "search" => %{"path" => "/context/#{name}/search"}
                  }
                  |> put_contexts_binding(view)
              }
            }
          },
          %{"id" => "#{base}_search_text", "component" => "Text", "text" => "Search"}
        ]
      else
        []
      end

    options =
      option_list(base, "/options/#{name}", %{
        "name" => "context_select",
        "context" =>
          %{
            "context" => name,
            "value" => %{"path" => "value"}
          }
          |> put_query_binding(view)
          |> put_contexts_binding(view)
      })

    header ++ controls ++ options
  end

  # A :detail component renders its context's selected record: a heading
  # and one label/value Row per field, each value Text bound to the
  # absolute /detail/<context>/<field> path (an unselected context renders
  # empty values — the server writes %{}).
  defp detail_components(view, detail) do
    base = "detail_#{detail.name}"

    field_rows =
      Enum.flat_map(detail.fields, fn field ->
        [
          %{
            "id" => "#{base}_field_#{field}",
            "component" => "Row",
            "children" => ["#{base}_label_#{field}", "#{base}_value_#{field}"]
          },
          %{
            "id" => "#{base}_label_#{field}",
            "component" => "Text",
            "text" => detail_field_label(view, field),
            "variant" => "h5"
          },
          %{
            "id" => "#{base}_value_#{field}",
            "component" => "Text",
            "text" => %{"path" => "/detail/#{detail.context}/#{field}"}
          }
        ]
      end)

    [
      %{
        "id" => base,
        "component" => "Card",
        "child" => "#{base}_body"
      },
      %{
        "id" => "#{base}_body",
        "component" => "Column",
        "children" => ["#{base}_heading" | Enum.map(detail.fields, &"#{base}_field_#{&1}")]
      },
      %{
        "id" => "#{base}_heading",
        "component" => "Text",
        "text" => humanize(detail.name),
        "variant" => "h3"
      }
      | field_rows
    ]
  end

  defp detail_field_label(view, field) do
    case view.fields[field] do
      %{label: label} when is_binary(label) -> label
      _undeclared -> humanize(field)
    end
  end

  # --- nested forms ---

  # One nested-form section per `nested_form` entity: a heading, the current
  # rows (a List templated over /form/<argument> — every row map carries the
  # server-generated "_row" key the remove button's context binds), and the
  # mode-specific add mechanism. All row mutations round-trip through the
  # stateless `nested_add` / `nested_remove` actions, whose contexts carry
  # the current rows via a {"path": "/form/<argument>"} binding; the server
  # rewrites the array wholesale.
  defp nested_form_components(view, nested, options) do
    base = "nested_#{nested.argument}"

    header = [
      %{
        "id" => "#{base}_heading",
        "component" => "Text",
        "text" => nested.label,
        "variant" => "h3"
      }
    ]

    case nested.mode do
      :create_inline ->
        [nested_section(base, ["#{base}_heading", "#{base}_rows", "#{base}_add_button"])] ++
          header ++
          nested_rows(base, nested, create_inline_row(view, nested, base)) ++
          nested_add_button(base, nested, %{
            "argument" => to_string(nested.argument),
            "rows" => %{"path" => "/form/#{nested.argument}"}
          })

      :pick_existing ->
        picker = pick_existing_picker(view, nested, base, options)

        [nested_section(base, ["#{base}_heading", "#{base}_rows" | picker.children])] ++
          header ++ nested_rows(base, nested, pick_existing_row(base)) ++ picker.components
    end
  end

  defp nested_section(base, children) do
    %{"id" => base, "component" => "Column", "children" => children}
  end

  defp nested_rows(base, nested, {row_children, row_components}) do
    [
      %{
        "id" => "#{base}_rows",
        "component" => "List",
        "children" => %{"componentId" => "#{base}_row", "path" => "/form/#{nested.argument}"}
      },
      %{"id" => "#{base}_row", "component" => "Row", "children" => row_children}
    ] ++ row_components ++ nested_remove_button(base, nested)
  end

  # create_inline rows: one widget-mapped input per nested field bound to the
  # template-relative field path (conforming renderers resolve it to the
  # index-addressed /form/<argument>/<index>/<field> for two-way binding),
  # plus a per-field error Text bound to the row's "_error_<field>" mirror.
  defp create_inline_row(_view, nested, base) do
    children =
      Enum.flat_map(nested.fields, fn field ->
        ["#{base}_input_#{field}", "#{base}_row_error_#{field}"]
      end) ++ ["#{base}_remove_button"]

    inputs = Enum.map(nested.fields, &nested_input(nested, base, &1))

    errors =
      Enum.map(nested.fields, fn field ->
        %{
          "id" => "#{base}_row_error_#{field}",
          "component" => "Text",
          "text" => %{"path" => "_error_#{field}"},
          "variant" => "caption"
        }
      end)

    {children, inputs ++ errors}
  end

  defp pick_existing_row(base) do
    {
      ["#{base}_row_label", "#{base}_remove_button"],
      [
        %{
          "id" => "#{base}_row_label",
          "component" => "Text",
          "text" => %{"path" => "label"}
        }
      ]
    }
  end

  # The pick_existing add mechanism: with option_search a search input +
  # result List whose option Buttons dispatch `nested_add` directly with the
  # template-relative option "value"; without one a ChoicePicker of the
  # loaded options (inline, limit-capped — the v0.9.1 constraint) bound to
  # /select/<argument>/picked plus an Add button carrying that binding.
  defp pick_existing_picker(_view, %{search_fields: [_ | _]} = nested, base, _options) do
    name = to_string(nested.argument)

    %{
      children: ["#{base}_controls", "#{base}_options"],
      components:
        [
          %{
            "id" => "#{base}_controls",
            "component" => "Row",
            "children" => ["#{base}_search_input", "#{base}_search_button"]
          }
        ] ++
          search_controls(base, name) ++
          option_list(base, "/options/#{nested.argument}", %{
            "name" => "nested_add",
            "context" => %{
              "argument" => name,
              "value" => %{"path" => "value"},
              "rows" => %{"path" => "/form/#{nested.argument}"}
            }
          })
    }
  end

  defp pick_existing_picker(_view, nested, base, options) do
    picker = %{
      "id" => "#{base}_picker",
      "component" => "ChoicePicker",
      "label" => "Add",
      "variant" => "mutuallyExclusive",
      "value" => %{"path" => "/select/#{nested.argument}/picked"},
      "options" => Map.fetch!(options, nested.argument)
    }

    %{
      children: ["#{base}_picker", "#{base}_add_button"],
      components:
        [picker] ++
          nested_add_button(base, nested, %{
            "argument" => to_string(nested.argument),
            "value" => %{"path" => "/select/#{nested.argument}/picked"},
            "rows" => %{"path" => "/form/#{nested.argument}"}
          })
    }
  end

  defp nested_add_button(base, _nested, context) do
    [
      %{
        "id" => "#{base}_add_button",
        "component" => "Button",
        "child" => "#{base}_add_text",
        "action" => %{"event" => %{"name" => "nested_add", "context" => context}}
      },
      %{"id" => "#{base}_add_text", "component" => "Text", "text" => "Add"}
    ]
  end

  defp nested_remove_button(base, nested) do
    [
      %{
        "id" => "#{base}_remove_button",
        "component" => "Button",
        "child" => "#{base}_remove_text",
        "action" => %{
          "event" => %{
            "name" => "nested_remove",
            "context" => %{
              "argument" => to_string(nested.argument),
              "row" => %{"path" => "_row"},
              "rows" => %{"path" => "/form/#{nested.argument}"}
            }
          }
        }
      },
      %{"id" => "#{base}_remove_text", "component" => "Text", "text" => "Remove"}
    ]
  end

  # Nested inputs widget-map against the *destination* resource's attribute
  # types (the parent surface's field entities don't apply inside rows).
  defp nested_input(nested, base, field) do
    binding = %{"path" => to_string(field)}
    label = humanize(field)
    id = "#{base}_input_#{field}"
    base_props = %{"id" => id, "label" => label, "value" => binding}

    type = attribute_type(nested.destination, field)
    constraints = attribute_constraints(nested.destination, field)

    case AshA2ui.TypeMapper.widget_for(type || Ash.Type.String, constraints) do
      :check_box ->
        Map.put(base_props, "component", "CheckBox")

      :choice_picker ->
        base_props
        |> Map.put("component", "ChoicePicker")
        |> Map.put("variant", "mutuallyExclusive")
        |> Map.put("options", choice_options(nested.destination, field))

      :date_time_input ->
        base_props
        |> Map.put("component", "DateTimeInput")
        |> Map.put("enableDate", true)
        |> Map.put("enableTime", not date_only?(nested.destination, field))

      _text_field ->
        text_field = Map.put(base_props, "component", "TextField")

        if numeric?(nested.destination, field) do
          Map.put(text_field, "variant", "number")
        else
          text_field
        end
    end
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
    type = attribute_type(resource, field_name)

    if AshA2ui.TypeMapper.enum_type?(type) do
      Enum.map(type.values(), &%{"label" => enum_label(type, &1), "value" => to_string(&1)})
    else
      resource
      |> attribute_constraints(field_name)
      |> Keyword.get(:one_of, [])
      |> Enum.map(&%{"label" => humanize(&1), "value" => to_string(&1)})
    end
  end

  # `Ash.Type.Enum.label/1` is nil unless the enum declared explicit labels.
  defp enum_label(type, value) do
    case type.label(value) do
      nil -> humanize(value)
      label -> to_string(label)
    end
  end

  defp numeric?(resource, field_name),
    do: attribute_type(resource, field_name) in @numeric_types

  defp date_only?(resource, field_name),
    do: attribute_type(resource, field_name) == Ash.Type.Date

  # Filterable fields may be attributes or (expression-backed) calculations;
  # both carry a type + constraints for picker options and variants.
  defp attribute_type(resource, field_name) do
    case ResourceInfo.attribute(resource, field_name) ||
           ResourceInfo.calculation(resource, field_name) do
      %{type: type} -> Ash.Type.get_type(type)
      nil -> nil
    end
  end

  defp attribute_constraints(resource, field_name) do
    case ResourceInfo.attribute(resource, field_name) ||
           ResourceInfo.calculation(resource, field_name) do
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

  # The reserved /prompt state: one empty values map per prompt-enabled row
  # action, so the Modal inputs always have a bindable path. Omitted
  # entirely on surfaces without prompts (frozen shape unchanged).
  defp put_prompt_state(value, view) do
    prompt_values =
      for {name, %{prompt_fields: [_ | _] = fields}} <- view.actions, into: %{} do
        {to_string(name), Map.new(fields, &{to_string(&1), ""})}
      end

    if prompt_values == %{} do
      value
    else
      Map.put(value, "prompt", %{"values" => prompt_values})
    end
  end

  # --- record serialization ---

  defp serialize_record(view, table, record) do
    field_names =
      case table do
        %{component: %{fields: fields}} -> fields
        nil -> view.fields |> Map.values() |> Enum.reject(& &1.hidden) |> Enum.map(& &1.name)
      end

    row =
      [:id | field_names]
      |> Enum.uniq()
      |> Map.new(fn name -> {to_string(name), field_value(view, record, name)} end)

    row
    |> Map.merge((table && AshA2ui.Conditions.row_visibility(view, table, record)) || %{})
    |> Map.merge(AshA2ui.RowLayout.badge_data(table && table.component.row_layout, record))
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
  defp json_safe(%Ash.CiString{} = ci), do: to_string(ci)
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
