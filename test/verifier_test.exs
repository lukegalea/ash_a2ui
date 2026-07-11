defmodule AshA2ui.VerifierTest do
  @moduledoc """
  Compile-time failure tests for `AshA2ui.Verifiers.VerifyFields` and
  `AshA2ui.Verifiers.VerifyActions`, using the `capture_io(:stderr)` + regex
  pattern from ash_state_machine (Spark converts verifier `DslError`s into
  stderr warnings at compile time).
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  describe "VerifyFields" do
    test "unknown table field does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule UnknownTableField do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              component :table do
                fields [:name, :nope]
              end
            end
          end
        end)

      assert result =~ ~r/component :table references unknown field :nope/
      assert result =~ ~r/public attribute, calculation, or aggregate/
    end

    test "private attribute referenced as a field does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule PrivateAttributeField do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
              attribute :secret, :string
            end

            actions do
              defaults [:read]
            end

            a2ui do
              component :table do
                fields [:name, :secret]
              end
            end
          end
        end)

      assert result =~ ~r/component :table references unknown field :secret/
    end

    test "field override with an unknown name does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule UnknownFieldOverride do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              component :table do
                fields [:name]
              end

              field :nonexistent do
                label "Ghost"
              end
            end
          end
        end)

      assert result =~ ~r/field :nonexistent/
      assert result =~ ~r/public attribute, calculation, or aggregate/
    end

    test "form field outside the action's accepts does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule FormFieldNotAccepted do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
              attribute :email, :string, public?: true
            end

            actions do
              defaults [:read]

              create :create do
                primary? true
                accept [:name]
              end
            end

            a2ui do
              component :form do
                fields [:name, :email]
                create_action :create
              end
            end
          end
        end)

      assert result =~ ~r/component :form field :email is not accepted/
    end

    test "form fields may come from action arguments" do
      result =
        capture_io(:stderr, fn ->
          defmodule FormFieldFromArgument do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]

              create :create do
                primary? true
                accept [:name]
                argument :invite_code, :string
              end
            end

            a2ui do
              component :form do
                fields [:name]
                create_action :create
              end

              field :name do
                label "Name"
              end
            end
          end
        end)

      refute result =~ ~r/is not accepted/
      refute result =~ ~r/unknown field/
    end
  end

  describe "VerifyActions" do
    test "missing read_action does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule MissingReadAction do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              component :table do
                fields [:name]
                read_action :nonexistent
              end
            end
          end
        end)

      assert result =~ ~r/read_action :nonexistent does not exist/
    end

    test "read_action of the wrong type does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule WrongReadActionType do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read, create: :*]
            end

            a2ui do
              component :table do
                fields [:name]
                read_action :create
              end
            end
          end
        end)

      assert result =~ ~r/read_action :create must be of type :read/
      assert result =~ ~r/:create/
    end

    test "create_action of the wrong type does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule WrongCreateActionType do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read, create: :*]
            end

            a2ui do
              component :form do
                fields [:name]
                create_action :read
              end
            end
          end
        end)

      assert result =~ ~r/create_action :read must be of type :create/
    end

    test "missing update_action does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule MissingUpdateAction do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read, create: :*]
            end

            a2ui do
              component :form do
                fields [:name]
                create_action :create
                update_action :nonexistent
              end
            end
          end
        end)

      assert result =~ ~r/update_action :nonexistent does not exist/
    end

    test "row_action that does not exist does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule MissingRowAction do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              component :table do
                fields [:name]
                row_actions [:vanish]
              end
            end
          end
        end)

      assert result =~ ~r/row action :vanish does not exist/
    end

    test "row_actions accept any action type, including destroy and generic actions" do
      result =
        capture_io(:stderr, fn ->
          defmodule AnyTypeRowActions do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read, :destroy, create: :*, update: :*]

              action :ping, :string do
                run fn _input, _context -> {:ok, "pong"} end
              end
            end

            a2ui do
              component :table do
                fields [:name]
                read_action :read
                row_actions [:update, :destroy, :ping]
              end
            end
          end
        end)

      refute result =~ ~r/row action/
      refute result =~ ~r/does not exist/
    end
  end

  defmodule CompositeDest do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      validate_domain_inclusion?: false,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      attribute :tenant_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
      attribute :code, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  describe "VerifyRelationships (form selects)" do
    test "relationship naming a nonexistent relationship does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule UnknownRelationship do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              component :table do
                fields [:name]
              end

              field :name do
                relationship(:nope)
              end
            end
          end
        end)

      assert result =~ ~r/relationship :nope does not exist/
    end

    test "option_label that is not a public destination attribute does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadOptionLabel do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshA2ui.Test.Author, public?: true
            end

            actions do
              defaults [:read]

              create :create do
                primary? true
                accept [:title, :author_id]
              end
            end

            a2ui do
              component :form do
                fields [:title, :author_id]
                create_action :create
              end

              field :author_id do
                option_label(:bogus)
              end
            end
          end
        end)

      assert result =~ ~r/option_label :bogus/
      assert result =~ ~r/public attribute/
    end

    test "option_* options on a field without a relationship do not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule OptionWithoutRelationship do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              component :table do
                fields [:name]
              end

              field :name do
                option_label(:name)
              end
            end
          end
        end)

      assert result =~ ~r/option_label/
      assert result =~ ~r/relationship/
    end

    test "composite destination primary key without option_value does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule CompositePkSelect do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :dest, AshA2ui.VerifierTest.CompositeDest,
                public?: true,
                destination_attribute: :tenant_id
            end

            actions do
              defaults [:read]

              create :create do
                primary? true
                accept [:title, :dest_id]
              end
            end

            a2ui do
              component :form do
                fields [:title, :dest_id]
                create_action :create
              end
            end
          end
        end)

      assert result =~ ~r/composite primary key/
      assert result =~ ~r/option_value/
    end
  end

  describe "VerifyRelationships (source columns)" do
    test "source whose first step is not a relationship does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadSourceStep do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              component :table do
                fields [:title, :author_email]
              end

              field :author_email do
                source [:nope, :email]
              end
            end
          end
        end)

      assert result =~ ~r/source .*:nope/
      assert result =~ ~r/relationship/
    end

    test "source with a non-attribute terminal step does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadSourceTerminal do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshA2ui.Test.Author, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              component :table do
                fields [:title, :author_bogus]
              end

              field :author_bogus do
                source [:author, :bogus]
              end
            end
          end
        end)

      assert result =~ ~r/source .*:bogus/
      assert result =~ ~r/public attribute/
    end

    test "a source field listed in a form component does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule SourceFieldInForm do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshA2ui.Test.Author, public?: true
            end

            actions do
              defaults [:read, create: :*]
            end

            a2ui do
              component :form do
                fields [:title, :author_email]
                create_action :create
              end

              field :author_email do
                source [:author, :email]
              end
            end
          end
        end)

      assert result =~ ~r/source field :author_email/
      assert result =~ ~r/form/
    end

    test "a source field listed in a query's sortable does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule SortableSourceField do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshA2ui.Test.Author, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                sortable [:title, :author_email]
              end

              component :table do
                fields [:title, :author_email]
                query :default
              end

              field :author_email do
                source [:author, :email]
              end
            end
          end
        end)

      assert result =~ ~r/:author_email/
      assert result =~ ~r/not sortable/
    end

    test "a valid inferred select plus source column compiles cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule CleanRelationships do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshA2ui.Test.Author, public?: true
            end

            actions do
              defaults [:read]

              create :create do
                primary? true
                accept [:title, :author_id]
              end
            end

            a2ui do
              component :table do
                fields [:title, :author_name]
              end

              component :form do
                fields [:title, :author_id]
                create_action :create
              end

              field :author_name do
                source [:author, :name]
              end
            end
          end
        end)

      refute result =~ ~r/does not exist/
      refute result =~ ~r/unknown field/
      refute result =~ ~r/source/
    end
  end

  describe "standalone modules" do
    test "verifiers check fields against for_resource" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadStandalone do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Minimal

              component :table do
                fields [:name, :bogus]
              end
            end
          end
        end)

      assert result =~ ~r/component :table references unknown field :bogus/
    end

    test "verifiers check actions against for_resource" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadStandaloneAction do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Minimal

              component :table do
                fields [:name]
                row_actions [:missing_action]
              end
            end
          end
        end)

      assert result =~ ~r/row action :missing_action does not exist/
    end
  end
end
