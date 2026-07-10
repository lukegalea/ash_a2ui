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
