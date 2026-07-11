defmodule AshA2ui.Wave5ResolvedViewTest do
  @moduledoc """
  Resolution tests for Wave 5: searchable relationship selects
  (`option_search`) and nested relationship forms (`nested_form` +
  `Ash.Changeset.ManagedRelationshipHelpers`-driven mode inference).
  """

  use ExUnit.Case, async: true

  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.{Tag, Ticket, TicketNote, TicketSearchUI}

  describe "searchable selects" do
    test "option_search lands on the resolved select as search_fields" do
      view = ResolvedView.resolve(TicketSearchUI)

      assert %{author_id: select} = view.selects
      assert select.search_fields == [:name, :email]
      assert select.destination == AshA2ui.Test.Author
      assert select.option_label == :name
    end

    test "selects without option_search resolve with empty search_fields" do
      view = ResolvedView.resolve(Ticket)

      assert view.selects[:author_id].search_fields == []
    end
  end

  describe "nested form mode inference" do
    test "direct_control infers create_inline with declared fields" do
      view = ResolvedView.resolve(Ticket)

      assert %{mode: :create_inline, fields: [:body, :rating]} = view.nested_forms[:notes]
      assert view.nested_forms[:notes].relationship == :notes
      assert view.nested_forms[:notes].destination == TicketNote
      assert view.nested_forms[:notes].label == "Notes"
    end

    test "append_and_remove infers pick_existing with resolved option config" do
      view = ResolvedView.resolve(Ticket)

      nested = view.nested_forms[:tags]
      assert nested.mode == :pick_existing
      assert nested.fields == []
      assert nested.destination == Tag
      assert nested.option_label == :name
      assert nested.option_value == :id
      assert nested.option_sort == :name
      assert nested.search_fields == []
    end

    test "nested_form option_search resolves as picker search_fields" do
      view = ResolvedView.resolve(TicketSearchUI)

      assert view.nested_forms[:tags].search_fields == [:name]
    end

    test "create_inline fields default to the destination create accepts minus the FK" do
      defmodule InferredNestedFieldsUI do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.Ticket
          surface_id "tickets_inferred"

          component :form do
            fields [:subject]
            create_action :create
            update_action :update

            nested_form :notes do
            end
          end
        end
      end

      view = ResolvedView.resolve(InferredNestedFieldsUI)

      assert Enum.sort(view.nested_forms[:notes].fields) == [:body, :rating]
      refute :ticket_id in view.nested_forms[:notes].fields
    end
  end

  describe "option_sources/1, select_state/1, form_loads/1" do
    test "option_sources unifies selects and pick_existing nested forms" do
      sources = TicketSearchUI |> ResolvedView.resolve() |> ResolvedView.option_sources()

      assert sources[:author_id].kind == :select
      assert sources[:tags].kind == :nested_form
      assert sources[:tags].destination == Tag
      refute Map.has_key?(sources, :notes)
    end

    test "select_state covers searchable selects and pick_existing pickers" do
      state = TicketSearchUI |> ResolvedView.resolve() |> ResolvedView.select_state()

      assert state["author_id"] == %{"search" => "", "label" => ""}
      assert state["tags"] == %{"search" => "", "picked" => []}
      refute Map.has_key?(state, "notes")
    end

    test "select_state is empty for surfaces without wave-5 features" do
      assert AshA2ui.Test.Post |> ResolvedView.resolve() |> ResolvedView.select_state() == %{}
    end

    test "form_loads covers searchable-select and nested-form relationships" do
      loads = TicketSearchUI |> ResolvedView.resolve() |> ResolvedView.form_loads()

      assert Enum.sort(loads) == [:author, :tags]

      assert Ticket |> ResolvedView.resolve() |> ResolvedView.form_loads() |> Enum.sort() ==
               [:notes, :tags]
    end
  end
end
