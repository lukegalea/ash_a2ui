defmodule AshA2ui.Wave4DslTest do
  @moduledoc """
  Compile-time verifier tests for the Wave 4 DSL additions: relationship-path
  `search_fields`, `preset` entities + `default_preset`, `prompt_fields`, and
  `visible_when`.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  defp define(body) do
    capture_io(:stderr, fn ->
      Module.create(
        Module.concat(__MODULE__, :"Fixture#{System.unique_integer([:positive])}"),
        body,
        Macro.Env.location(__ENV__)
      )
    end)
  end

  describe "relationship-path search_fields" do
    test "a valid path compiles cleanly" do
      result =
        define(
          quote do
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
                search_fields [:title, [:author, :email]]
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end
        )

      assert result == ""
    end

    test "a path through a private/unknown relationship is rejected" do
      result =
        define(
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                search_fields [[:ghost, :email]]
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end
        )

      assert result =~ ~r/search_fields path \[:ghost, :email\] is invalid/
      assert result =~ ~r/step :ghost is not a public relationship/
    end

    test "a path to a non-string terminal attribute is rejected" do
      result =
        define(
          quote do
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
                search_fields [[:author, :id]]
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end
        )

      assert result =~ ~r/must be a string-typed attribute/
    end
  end

  describe "presets" do
    test "a preset with neither filter nor read_action is rejected" do
      result =
        define(
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                preset :broken do
                end
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end
        )

      assert result =~ ~r/declare either filter or read_action/
    end

    test "a preset with both filter and read_action is rejected" do
      result =
        define(
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                preset :broken do
                  filter title: "x"
                  read_action :read
                end
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end
        )

      assert result =~ ~r/mutually exclusive/
    end

    test "a preset filter on an unknown key is rejected" do
      result =
        define(
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                preset :broken do
                  filter ghost: "x"
                end
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end
        )

      assert result =~ ~r/filter key :ghost must be a public attribute/
    end

    test "a preset read_action must be a read" do
      result =
        define(
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read, :destroy]
            end

            a2ui do
              query :default do
                preset :broken do
                  read_action :destroy
                end
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end
        )

      assert result =~ ~r/read_action :destroy must be of type :read/
    end

    test "default_preset must name a declared preset" do
      result =
        define(
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                default_preset :ghost

                preset :real do
                  filter title: "x"
                end
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end
        )

      assert result =~ ~r/default_preset :ghost does not name a declared preset/
    end
  end

  describe "prompt_fields" do
    test "a prompt field must be an argument or accept of the action" do
      result =
        define(
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]

              update :touch do
                accept []
              end
            end

            a2ui do
              component :table do
                fields [:title]
                row_actions [:touch]
              end

              action :touch do
                prompt_fields [:ghost]
              end
            end
          end
        )

      assert result =~ ~r/prompt field :ghost is neither an argument nor an accepted attribute/
    end

    test "prompt_fields on a non-row action is rejected" do
      result =
        define(
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read, create: :*, update: :*]
            end

            a2ui do
              component :table do
                fields [:title]
              end

              component :form do
                fields [:title]
                create_action :create
                update_action :update
              end

              action :update do
                prompt_fields [:title]
              end
            end
          end
        )

      assert result =~ ~r/prompt_fields only applies to row actions/
    end
  end

  describe "visible_when" do
    test "keys must be public attributes or expression calculations" do
      result =
        define(
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            calculations do
              calculate :shout, :string, AshA2ui.Test.Article.ShoutTitle, public?: true
            end

            actions do
              defaults [:read, :destroy]
            end

            a2ui do
              component :table do
                fields [:title]
                row_actions [:destroy]
              end

              action :destroy do
                visible_when shout: "LOUD"
              end
            end
          end
        )

      assert result =~
               ~r/visible_when key :shout .* must be a public attribute or an expression-backed/
    end

    test "values must cast to the field's type" do
      result =
        define(
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true

              attribute :state, :atom,
                public?: true,
                constraints: [one_of: [:new, :done]]
            end

            actions do
              defaults [:read, :destroy]
            end

            a2ui do
              component :table do
                fields [:title]
                row_actions [:destroy]
              end

              action :destroy do
                visible_when state: :bogus
              end
            end
          end
        )

      assert result =~ ~r/visible_when value :bogus for :state .* does not cast/
    end
  end
end
