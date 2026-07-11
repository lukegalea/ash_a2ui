defmodule AshA2ui.Wave5VerifierTest do
  @moduledoc """
  Compile-time failure tests for the Wave 5 verifier additions: the
  `option_search` checks in `AshA2ui.Verifiers.VerifyRelationships` and the
  new `AshA2ui.Verifiers.VerifyNestedForms`, using the `capture_io(:stderr)`
  + regex pattern from the existing verifier suite.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  describe "VerifyRelationships option_search" do
    test "non-string option_search entry does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule NonStringOptionSearch do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Post

              component :form do
                fields [:title, :author_id]
              end

              field :author_id do
                option_search [:id]
              end
            end
          end
        end)

      assert result =~ ~r/option_search entry :id on field :author_id/
      assert result =~ ~r/string-typed/
    end

    test "unknown option_search entry does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule UnknownOptionSearch do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Post

              component :form do
                fields [:title, :author_id]
              end

              field :author_id do
                option_search [:nope]
              end
            end
          end
        end)

      assert result =~ ~r/option_search entry :nope on field :author_id/
      assert result =~ ~r/public\s+attribute of AshA2ui\.Test\.Author/
    end

    test "option_search on a field without a relationship does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule OrphanOptionSearch do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Post

              component :form do
                fields [:title]
              end

              field :title do
                option_search [:name]
              end
            end
          end
        end)

      assert result =~ ~r/option_search is set on field :title, which has no relationship/
    end
  end

  describe "VerifyNestedForms" do
    test "argument without a manage_relationship change does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule NoManageChange do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Post

              component :form do
                fields [:title]

                nested_form :comments do
                end
              end
            end
          end
        end)

      assert result =~ ~r/nested_form :comments requires a manage_relationship change/
      assert result =~ ~r/consuming argument :comments/
    end

    test "nested_form outside a :form component does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule NestedFormOnTable do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Ticket

              component :table do
                fields [:subject]

                nested_form :notes do
                end
              end
            end
          end
        end)

      assert result =~ ~r/nested_form :notes is declared inside the :table component/
      assert result =~ ~r/only render inside :form components/
    end

    test "update-only manage_relationship does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule UpdateOnlyResource do
            @moduledoc false
            use Ash.Resource,
              domain: AshA2ui.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              validate_domain_inclusion?: false,
              extensions: [AshA2ui]

            ets do
              private? true
            end

            attributes do
              uuid_primary_key :id
              attribute :subject, :string, public?: true
            end

            relationships do
              has_many :notes, AshA2ui.Test.TicketNote,
                public?: true,
                destination_attribute: :ticket_id
            end

            actions do
              defaults [:read]

              create :create do
                primary? true
                accept [:subject]
                argument :notes, {:array, :map}, allow_nil?: true
                change manage_relationship(:notes, on_no_match: :ignore, on_match: :update)
              end
            end

            a2ui do
              component :form do
                fields [:subject]

                nested_form :notes do
                end
              end
            end
          end
        end)

      assert result =~ ~r/allows neither lookups \(on_lookup\) nor creates/
      assert result =~ ~r/no v1\s+rendering/
    end

    test "inconsistent modes across create and update actions do not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule InconsistentModes do
            @moduledoc false
            use Ash.Resource,
              domain: AshA2ui.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              validate_domain_inclusion?: false,
              extensions: [AshA2ui]

            ets do
              private? true
            end

            attributes do
              uuid_primary_key :id
              attribute :subject, :string, public?: true
            end

            relationships do
              has_many :notes, AshA2ui.Test.TicketNote,
                public?: true,
                destination_attribute: :ticket_id
            end

            actions do
              defaults [:read]

              create :create do
                primary? true
                accept [:subject]
                argument :notes, {:array, :map}, allow_nil?: true
                change manage_relationship(:notes, type: :direct_control)
              end

              update :update do
                primary? true
                require_atomic? false
                accept [:subject]
                argument :notes, {:array, :uuid}, allow_nil?: true
                change manage_relationship(:notes, type: :append_and_remove)
              end
            end

            a2ui do
              component :form do
                fields [:subject]

                nested_form :notes do
                end
              end
            end
          end
        end)

      assert result =~ ~r/infers different interaction modes across/
    end

    test "unknown create_inline field does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule UnknownNestedField do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Ticket

              component :form do
                fields [:subject]
                create_action :create
                update_action :update

                nested_form :notes do
                  fields [:body, :nope]
                end
              end
            end
          end
        end)

      assert result =~ ~r/nested_form :notes field :nope must be a public\s+writable attribute/
    end

    test "non-string nested option_search entry does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule NonStringNestedSearch do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Ticket

              component :form do
                fields [:subject]
                create_action :create
                update_action :update

                nested_form :tags do
                  option_search [:ticket_id]
                end
              end
            end
          end
        end)

      assert result =~ ~r/option_search entry :ticket_id on nested_form :tags/
    end

    test "sound nested forms compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule SoundNestedForms do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Ticket
              surface_id "sound_nested"

              component :form do
                fields [:subject, :author_id]
                create_action :create
                update_action :update

                nested_form :notes do
                  fields [:body, :rating]
                end

                nested_form :tags do
                  option_search [:name]
                end
              end

              field :author_id do
                option_search [:name, :email]
              end
            end
          end
        end)

      refute result =~ ~r/nested_form/
      refute result =~ ~r/option_search/
    end
  end
end
