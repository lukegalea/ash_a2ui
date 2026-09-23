defmodule AshA2ui.Combobox do
  @moduledoc """
  Host-side wiring for the shipped catalog's combobox enhancement of
  AshA2ui's search-picker composites.

  `priv/js/ash_a2ui_catalog.js` (the merged basic catalog) upgrades two
  kinds of emitted composites into a real typeahead combobox — search
  input, anchored overlay, keyboard navigation, a Clear chip — and
  non-searchable context pickers into a chip group. The enhancement is
  *structural*: its `detectPicker` keys on the extension's frozen id
  contract (see the Contexts and Details topic) — the `Card`/`Column`
  composites' `context_<name>_body` and `form_select_<field>` ids and
  their `_label`/`_selected`/`_options`/`_option_button`/
  `_search_input`/`_search_button`/`_clear_button` descendants. A
  composite that does not fully match degrades to the plain column
  rendering, so the wire format stays 100% basic catalog.

  This module mirrors that contract on the Elixir side: the ids and the
  data attributes a **host-side mount hook** needs to find and instrument
  a composite, without hand-writing the id vocabulary.

  ## The helper

      AshA2ui.Combobox.ids(context: "clinician")
      # => %{kind: :context, name: "clinician", body: "context_clinician_body",
      #      label: "context_clinician_label", selected: "context_clinician_selected",
      #      options: "context_clinician_options", option_button: "context_clinician_option_button",
      #      clear_button: "context_clinician_clear_button",
      #      search_input: nil, search_button: nil, options_path: "/options/clinician"}

      AshA2ui.Combobox.ids(field: "author_id", searchable: true)
      # => %{kind: :field, ..., body: "form_select_author_id", ..., clear_button: nil,
      #      search_input: "form_select_author_id_search_input",
      #      search_button: "form_select_author_id_search_button"}

  * a **context** picker is the Card > Column composite the encoder emits
    for a `context` entity (it always carries the Clear button; search
    controls exist when the context declares `option_search` — pass
    `searchable: true` to name them),
  * a **field** select is the searchable-select composite emitted for a
    relationship form field with `option_search` (no Clear button; always
    searched when present, so `searchable: true` names its controls).

  `data_attrs/1` returns the same contract as `data-*` attributes for the
  host element a mount hook hangs off:

      AshA2ui.Combobox.data_attrs(context: "clinician", searchable: true)
      # => %{
      #      "data-ash-a2ui-combobox" => "context",
      #      "data-ash-a2ui-combobox-name" => "clinician",
      #      "data-ash-a2ui-combobox-body-id" => "context_clinician_body",
      #      ...
      #    }

  ## The host-side mount hook

  The catalog's `<ash-a2ui-column>` element does the actual enhancement
  (it owns the shadow DOM); a host hook only *observes* or *targets* the
  composite — analytics, focus hand-off, a host-side "Add" affordance
  next to it. Sprinkle the data attributes on the host chrome (the
  surface container, a sidebar, ...) and read them in the hook:

      // assets/js/ash_a2ui_combobox_hook.js (host-side sketch)
      export const AshA2uiCombobox = {
        mounted() {
          const { ashA2uiCombobox: kind, ashA2uiComboboxName: name,
                  ashA2uiComboboxBodyId: bodyId } = this.el.dataset;
          if (!kind || !bodyId) return;
          // `document.getElementById(bodyId)` reaches the composite the
          // catalog renders; the remaining -id attributes name its
          // option list, selected chip, clear button, and search controls.
        },
      };

      // app.js
      liveSocket.addHook("AshA2uiCombobox", AshA2uiCombobox);

      <div id="clinic-sidebar" phx-hook="AshA2uiCombobox"
           {AshA2ui.Combobox.data_attrs(context: "clinician", searchable: true)}>
        ... the surface ...
      </div>

  (`data-ash-a2ui-combobox-*` reads back through the standard camelCase
  `dataset` conversion — `data-ash-a2ui-combobox-body-id` is
  `dataset.ashA2uiComboboxBodyId`.)
  """

  @name_format ~r/^[a-zA-Z][a-zA-Z0-9_]*$/

  @typedoc "The id vocabulary `detectPicker` matches, mirrored for hosts."
  @type ids :: %{
          required(:kind) => :context | :field,
          required(:name) => String.t(),
          required(:body) => String.t(),
          required(:label) => String.t(),
          required(:selected) => String.t(),
          required(:options) => String.t(),
          required(:option_button) => String.t(),
          required(:clear_button) => String.t() | nil,
          required(:search_input) => String.t() | nil,
          required(:search_button) => String.t() | nil,
          required(:options_path) => String.t()
        }

  @doc """
  The id vocabulary of the picker composite for one `context` name or one
  form `field` name (exactly one is required). `searchable: true` names
  the search input/button ids — present on the wire only when the
  context/field declares `option_search`.
  """
  @spec ids(keyword) :: ids()
  def ids(opts) do
    {kind, name, searchable} = target(opts)
    base = base_id(kind, name)

    searchable_ids =
      if searchable do
        %{search_input: "#{base}_search_input", search_button: "#{base}_search_button"}
      else
        %{search_input: nil, search_button: nil}
      end

    clear_button = (kind == :context && "#{base}_clear_button") || nil

    %{
      kind: kind,
      name: name,
      body: "#{base}_body",
      label: "#{base}_label",
      selected: "#{base}_selected",
      options: "#{base}_options",
      option_button: "#{base}_option_button",
      clear_button: clear_button,
      options_path: "/options/#{name}"
    }
    |> Map.merge(searchable_ids)
  end

  @doc """
  `ids/1` as `data-*` attributes (string keys, ready to spread onto a HEEx
  element) — the contract the host-side mount hook reads (see the
  moduledoc). Nil ids (the Clear button on a field select; the search
  controls when not searchable) are omitted.
  """
  @spec data_attrs(keyword) :: %{String.t() => String.t()}
  def data_attrs(opts) do
    ids = ids(opts)

    id_attrs =
      [:body, :label, :selected, :options, :option_button, :clear_button, :search_input, :search_button]
      |> Enum.flat_map(fn key ->
        case Map.fetch!(ids, key) do
          nil -> []
          value -> [{"data-ash-a2ui-combobox-#{key |> to_string() |> String.replace("_", "-")}-id", value}]
        end
      end)
      |> Map.new()

    %{
      "data-ash-a2ui-combobox" => (ids.kind == :context && "context") || "field",
      "data-ash-a2ui-combobox-name" => ids.name,
      "data-ash-a2ui-combobox-options-path" => ids.options_path
    }
    |> Map.merge(id_attrs)
  end

  defp target(opts) do
    context = Keyword.get(opts, :context)
    field = Keyword.get(opts, :field)
    searchable = Keyword.get(opts, :searchable, false)

    case {context, field} do
      {nil, nil} ->
        raise ArgumentError,
              "AshA2ui.Combobox: pass exactly one of :context or :field"

      {name, nil} ->
        {:context, validate_name!(:context, name), validate_searchable!(searchable)}

      {nil, name} ->
        {:field, validate_name!(:field, name), validate_searchable!(searchable)}

      {_both, _given} ->
        raise ArgumentError,
              "AshA2ui.Combobox: pass exactly one of :context or :field, got both"
    end
  end

  defp validate_name!(option, name) do
    unless is_binary(name) and name =~ @name_format do
      raise ArgumentError,
            "AshA2ui.Combobox: #{inspect(name)} is not a valid :#{option} name — " <>
              "names are strings of letters, digits and underscores, starting with a letter"
    end

    name
  end

  defp validate_searchable!(searchable) when is_boolean(searchable), do: searchable

  defp validate_searchable!(searchable) do
    raise ArgumentError, "AshA2ui.Combobox: :searchable must be a boolean, got: #{inspect(searchable)}"
  end

  # The composite base id of the frozen wire contract: context pickers
  # render under `context_<name>` (their structural anchor is the
  # `context_<name>_body` Column); searchable relationship selects under
  # `form_select_<field>`.
  defp base_id(:context, name), do: "context_#{name}"
  defp base_id(:field, name), do: "form_select_#{name}"
end
