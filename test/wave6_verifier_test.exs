defmodule AshA2ui.Wave6VerifierTest do
  @moduledoc """
  Compile-time failure tests for `AshA2ui.Verifiers.VerifyLayouts`, using
  the `capture_io(:stderr)` + regex pattern from the existing verifier
  suite.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  describe "group placement and shape" do
    test "a group on a :table component does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule GroupOnTable do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Promotion

              component :table do
                fields [:name, :slug]

                group :details do
                  fields [:name]
                end
              end
            end
          end
        end)

      assert result =~ ~r/component :table declares a group/
      assert result =~ ~r/only supported on :form components/
    end

    test "duplicate group names do not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule DuplicateGroupNames do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Promotion

              component :form do
                fields [:name, :slug]
                create_action :create

                group :details do
                  fields [:name]
                end

                group :details do
                  fields [:slug]
                end
              end
            end
          end
        end)

      assert result =~ ~r/duplicate group :details/
    end

    test "an empty group does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule EmptyGroup do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Promotion

              component :form do
                fields [:name]
                create_action :create

                group :details do
                  fields []
                end
              end
            end
          end
        end)

      assert result =~ ~r/group :details declares no fields/
    end

    test "a group referencing a field outside the form does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule GroupFieldOutsideForm do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Promotion

              component :form do
                fields [:name]
                create_action :create

                group :details do
                  fields [:name, :slug]
                end
              end
            end
          end
        end)

      assert result =~ ~r/group :details references field :slug/
      assert result =~ ~r/form component's \(declared or inferred\) fields list/
    end

    test "a field in two groups does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule FieldInTwoGroups do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Promotion

              component :form do
                fields [:name, :slug]
                create_action :create

                group :details do
                  fields [:name, :slug]
                end

                group :extras do
                  fields [:slug]
                end
              end
            end
          end
        end)

      assert result =~ ~r/field :slug belongs to more than one group/
    end
  end

  describe "row_layout placement and shape" do
    test "a row_layout on a :form component does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule RowLayoutOnForm do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Promotion

              component :form do
                fields [:name]
                create_action :create

                row_layout do
                  title :name
                end
              end
            end
          end
        end)

      assert result =~ ~r/component :form declares a row_layout/
      assert result =~ ~r/only supported on :table components/
    end

    test "a title outside the table's fields does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule TitleOutsideFields do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Promotion

              component :table do
                fields [:slug, :trial_days]

                row_layout do
                  title :name
                end
              end
            end
          end
        end)

      assert result =~ ~r/row_layout references field :name/
      assert result =~ ~r/table's fields/
    end

    test "a field referenced twice across title/badge/meta does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule DuplicateLayoutField do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Promotion

              component :table do
                fields [:name, :slug]

                row_layout do
                  title :name
                  meta [:name, :slug]
                end
              end
            end
          end
        end)

      assert result =~ ~r/row_layout references field :name more than once/
    end

    test "badge_text without a badge does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadgeTextWithoutBadge do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Promotion

              component :table do
                fields [:name, :is_active]

                row_layout do
                  title :name
                  badge_text true: "Active"
                end
              end
            end
          end
        end)

      assert result =~ ~r/badge_text without a badge/
    end

    test "non-string badge_text values do not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule NonStringBadgeText do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Promotion

              component :table do
                fields [:name, :is_active]

                row_layout do
                  title :name
                  badge :is_active
                  badge_text true: :active
                end
              end
            end
          end
        end)

      assert result =~ ~r/badge_text for true must be a string/
    end
  end
end
