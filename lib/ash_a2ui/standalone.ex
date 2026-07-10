defmodule AshA2ui.Standalone do
  @moduledoc """
  Author an `a2ui` block in a dedicated UI module instead of on the resource
  itself. Point it at the resource with the `for_resource` section option:

      defmodule MyApp.UI.PromotionsProviderUI do
        use AshA2ui.Standalone

        a2ui do
          for_resource MyApp.Promotions.PromotionsProvider

          component :table do
            fields [:name, :inserted_at]
          end
        end
      end

  Standalone modules can be passed anywhere a resource module is accepted by
  `AshA2ui.Info` / `AshA2ui.ResolvedView` / `AshA2ui.ActionHandler`.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshA2ui]],
    untyped_extensions?: true
end
