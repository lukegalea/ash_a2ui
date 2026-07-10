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
    * `records_list` — `List` whose children are a template
      `{"componentId": "record_row", "path": "/records"}`; `record_row` is a
      `Row` of per-field `Text` cells (`table_cell_<field>`, bound to the
      template-relative path `<field>`, `format: :date` rendered through
      `formatDate`), one `Button` per row action
      (`row_action_<action>_button`: event `invoke`, context
      `{"action": "<name>", "recordId": {"path": "id"}}`) and a
      `row_select_button` (event `select_row`, context
      `{"recordId": {"path": "id"}}`)
    * `form` — `Column` of `form_input_<field>` + `form_error_<field>` pairs
      and a `form_submit_button` (event `submit_form`, context
      `{"values": {"path": "/form"}, "recordId": {"path": "/form/id"}}`).
      Inputs use the field's resolved widget (`TextField` / `CheckBox` /
      `ChoicePicker` / `DateTimeInput`), bind `value` to `/form/<field>`, and
      errors are `Text` (caption) bound to `/errors/<field>`
    * `status_text` — `Text` bound to `/ui/status`

  ## Data model

  The reserved-path value shape (see `topics/data-model-conventions`):

      %{
        "records" => [%{"id" => ..., "<field>" => ...}, ...],
        "form" => %{},
        "errors" => %{},
        "ui" => %{"status" => ""}
      }

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
          "components" => components(resolved_view)
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
             "ui" => %{"status" => ""}
           }}
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

  # --- component tree ---

  defp components(view) do
    table = Enum.find(view.components, &(&1.name == :table))
    form = Enum.find(view.components, &(&1.name == :form))

    table_components = (table && table_components(view, table)) || []
    form_components = (form && form_components(view, form)) || []

    root = %{
      "id" => "root",
      "component" => "Column",
      "children" => Enum.map(table_components ++ form_components, & &1["id"]) ++ ["status_text"]
    }

    status = %{
      "id" => "status_text",
      "component" => "Text",
      "text" => %{"path" => "/ui/status"}
    }

    [root | table_components ++ form_components ++ table_descendants(view, table)] ++
      form_descendants(view, form) ++ [status]
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
    action_buttons = Enum.flat_map(table.row_actions, &row_action_button/1)

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

  defp row_action_button(action) do
    [
      %{
        "id" => "row_action_#{action}_button",
        "component" => "Button",
        "child" => "row_action_#{action}_text",
        "action" => %{
          "event" => %{
            "name" => "invoke",
            "context" => %{
              "action" => to_string(action),
              "recordId" => %{"path" => "id"}
            }
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

  defp form_descendants(_view, nil), do: []

  defp form_descendants(view, form) do
    inputs = Enum.map(form.fields, &form_input(view, &1))
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
            "context" => %{
              "values" => %{"path" => "/form"},
              "recordId" => %{"path" => "/form/id"}
            }
          }
        }
      },
      %{"id" => "form_submit_text", "component" => "Text", "text" => "Save"}
    ]

    inputs ++ errors ++ submit
  end

  defp form_input(view, field_name) do
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
        |> Map.put("options", choice_options(view.resource, field_name))

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
    |> Map.new(fn name -> {to_string(name), record |> Map.get(name) |> json_safe()} end)
  end

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
