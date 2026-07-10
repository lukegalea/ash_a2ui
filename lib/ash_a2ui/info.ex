defmodule AshA2ui.Info do
  @moduledoc """
  Introspection for the `AshA2ui` extension, plus the public payload-building
  API.

  FROZEN CONTRACT — the signatures of `build_surface/2`, `build_data_model/2`,
  `resource!/1`, `components/1` and `fields/1` are the interface every parallel
  track codes against; do not change outside an integration commit.
  """

  use Spark.InfoGenerator, extension: AshA2ui, sections: [:a2ui]

  @doc """
  The `component` entities declared in the `a2ui` section.
  """
  @spec components(module) :: [AshA2ui.Component.t()]
  def components(resource_or_ui_module) do
    resource_or_ui_module
    |> Spark.Dsl.Extension.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Component))
  end

  @doc """
  The `field` entities declared in the `a2ui` section.
  """
  @spec fields(module) :: [AshA2ui.Field.t()]
  def fields(resource_or_ui_module) do
    resource_or_ui_module
    |> Spark.Dsl.Extension.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Field))
  end

  @doc """
  Resolves the Ash resource behind `resource_or_ui_module`: the module's
  `for_resource` option if set (standalone UI modules), otherwise the module
  itself (which must be an `Ash.Resource`).
  """
  @spec resource!(module) :: module
  def resource!(resource_or_ui_module) do
    case a2ui_for_resource(resource_or_ui_module) do
      {:ok, resource} ->
        resource

      :error ->
        if Ash.Resource.Info.resource?(resource_or_ui_module) do
          resource_or_ui_module
        else
          raise ArgumentError,
                "#{inspect(resource_or_ui_module)} is not an Ash resource and has no " <>
                  "`for_resource` configured in its `a2ui` section"
        end
    end
  end

  @doc """
  Builds the ordered A2UI v0.9.1 server->client message list for the surface:
  `createSurface` -> `updateComponents` -> `updateDataModel`.

  ## Options

    * `:actor` — the actor used to load records (`authorize?: true`).
    * `:tenant` — the tenant used to load records.
  """
  @spec build_surface(module, keyword) :: [map]
  def build_surface(resource_or_ui_module, opts \\ []) do
    resolved_view = AshA2ui.ResolvedView.resolve(resource_or_ui_module, opts)

    # TODO Track 2: load records via the resource's read action with
    # actor/tenant from opts and authorize?: true (through the generated
    # `render_a2ui` action once Track 1 lands it).
    records = []

    AshA2ui.Encoder.V0_9_1.encode_surface(resolved_view, records, opts)
  end

  @doc """
  Builds a data-only refresh: the `updateDataModel` message for the surface,
  used for PubSub-driven live refreshes.

  Takes the same options as `build_surface/2`.
  """
  @spec build_data_model(module, keyword) :: map
  def build_data_model(resource_or_ui_module, opts \\ []) do
    resolved_view = AshA2ui.ResolvedView.resolve(resource_or_ui_module, opts)

    # TODO Track 2: load records (see build_surface/2).
    records = []

    AshA2ui.Encoder.V0_9_1.encode_data_model(resolved_view, records, opts)
  end
end
