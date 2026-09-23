defmodule AshA2ui.ComboboxTest do
  @moduledoc """
  The Elixir-side mirror of `priv/js/ash_a2ui_catalog.js`'s
  `detectPicker` id contract: `ids/1` names exactly the composite ids the
  catalog's structural detection matches, and `data_attrs/1` emits the
  `data-ash-a2ui-combobox-*` attributes the documented host-side mount
  hook reads through `dataset` (camelCase). The JS file itself is the
  source of truth and is verified by hand there; these tests pin the
  Elixir half so the two sides cannot drift silently.
  """

  use ExUnit.Case, async: true

  describe "ids/1" do
    test "a context picker: the frozen context_<name> composite ids" do
      assert %{
               kind: :context,
               name: "clinician",
               body: "context_clinician_body",
               label: "context_clinician_label",
               selected: "context_clinician_selected",
               options: "context_clinician_options",
               option_button: "context_clinician_option_button",
               clear_button: "context_clinician_clear_button",
               search_input: nil,
               search_button: nil,
               options_path: "/options/clinician"
             } = AshA2ui.Combobox.ids(context: "clinician")
    end

    test "a searchable context picker also names the search controls" do
      assert %{
               body: "context_clinician_body",
               search_input: "context_clinician_search_input",
               search_button: "context_clinician_search_button"
             } = AshA2ui.Combobox.ids(context: "clinician", searchable: true)
    end

    test "a form field select: form_select_<field>, no clear button" do
      assert %{
               kind: :field,
               name: "author_id",
               body: "form_select_author_id_body",
               label: "form_select_author_id_label",
               selected: "form_select_author_id_selected",
               options: "form_select_author_id_options",
               option_button: "form_select_author_id_option_button",
               clear_button: nil,
               search_input: nil,
               search_button: nil,
               options_path: "/options/author_id"
             } = AshA2ui.Combobox.ids(field: "author_id")
    end

    test "a searchable field select names the search controls" do
      assert %{
               clear_button: nil,
               search_input: "form_select_author_id_search_input",
               search_button: "form_select_author_id_search_button"
             } = AshA2ui.Combobox.ids(field: "author_id", searchable: true)
    end

    test "exactly one of :context / :field is required" do
      assert_raise ArgumentError, ~r/exactly one of :context or :field/, fn ->
        AshA2ui.Combobox.ids([])
      end

      assert_raise ArgumentError, ~r/exactly one of :context or :field/, fn ->
        AshA2ui.Combobox.ids(context: "a", field: "b")
      end
    end

    test "names must match the spec name format" do
      assert_raise ArgumentError, ~r/not a valid :context name/, fn ->
        AshA2ui.Combobox.ids(context: "9lives")
      end

      assert_raise ArgumentError, ~r/not a valid :field name/, fn ->
        AshA2ui.Combobox.ids(field: "author id")
      end
    end

    test ":searchable must be a boolean" do
      assert_raise ArgumentError, ~r/:searchable must be a boolean/, fn ->
        AshA2ui.Combobox.ids(context: "clinician", searchable: "yes")
      end
    end
  end

  describe "data_attrs/1" do
    test "emits the data-ash-a2ui-combobox-* contract the mount hook reads" do
      assert %{
               "data-ash-a2ui-combobox" => "context",
               "data-ash-a2ui-combobox-name" => "clinician",
               "data-ash-a2ui-combobox-body-id" => "context_clinician_body",
               "data-ash-a2ui-combobox-label-id" => "context_clinician_label",
               "data-ash-a2ui-combobox-selected-id" => "context_clinician_selected",
               "data-ash-a2ui-combobox-options-id" => "context_clinician_options",
               "data-ash-a2ui-combobox-option-button-id" => "context_clinician_option_button",
               "data-ash-a2ui-combobox-clear-button-id" => "context_clinician_clear_button",
               "data-ash-a2ui-combobox-options-path" => "/options/clinician"
             } = AshA2ui.Combobox.data_attrs(context: "clinician")
    end

    test "nil ids are omitted; search ids kebab-case their source keys" do
      attrs = AshA2ui.Combobox.data_attrs(context: "clinician")
      refute Map.has_key?(attrs, "data-ash-a2ui-combobox-search-input-id")
      refute Map.has_key?(attrs, "data-ash-a2ui-combobox-search-button-id")

      assert %{
               "data-ash-a2ui-combobox" => "field",
               "data-ash-a2ui-combobox-search-input-id" => "form_select_referral_search_input",
               "data-ash-a2ui-combobox-search-button-id" => "form_select_referral_search_button"
             } = AshA2ui.Combobox.data_attrs(field: "referral", searchable: true)

      # a field select never carries the clear button
      refute Map.has_key?(
               AshA2ui.Combobox.data_attrs(field: "referral"),
               "data-ash-a2ui-combobox-clear-button-id"
             )
    end

    test "kebab-case attribute names map to the documented dataset keys" do
      attrs = AshA2ui.Combobox.data_attrs(field: "author_id", searchable: true)

      # The moduledoc's host hook reads `this.el.dataset` — pin the standard
      # kebab-case → camelCase conversion: data-ash-a2ui-combobox-body-id
      # reads back as dataset.ashA2uiComboboxBodyId.
      for {"data-" <> rest, _value} <- attrs do
        [first | tail] = String.split(rest, "-")
        dataset_key = Enum.join([first | Enum.map(tail, &String.capitalize/1)])
        assert dataset_key =~ ~r/^ashA2uiCombobox/
      end
    end
  end
end
