defmodule AshA2ui.Verifiers.VerifyExport do
  @moduledoc """
  Verifies at compile time that `export` blocks (CSV file export) are sound:

    * only `:table` and `:report` components may declare an `export` block,
    * every declared column of a `:report` export is one of the report's
      `fields`,
    * every declared column of a `:table` export is one of the table's
      `fields` or a public attribute, calculation or aggregate of the table's
      resource (a related table's own resource). A column the table does
      not show is loaded for the export query only.

  Column checks degrade gracefully when they cannot be decided at
  verification time: a report or table without declared `fields`, or a
  table whose resource cannot be resolved (a standalone UI module without
  a compilable `for_resource`), is checked against what is known — a
  table's declared `fields` alone in the latter case.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info, as: ResourceInfo
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    components =
      dsl_state
      |> Verifier.get_entities([:a2ui])
      |> Enum.filter(&is_struct(&1, AshA2ui.Component))

    components
    |> Enum.filter(& &1.export)
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case verify_component(component, dsl_state, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_component(component, dsl_state, module) do
    key = AshA2ui.Component.key(component)

    with :ok <- verify_kind(component, key, module) do
      verify_columns(component, key, table_resource(component, dsl_state), module)
    end
  end

  defp verify_kind(%{name: kind}, _key, _module) when kind in [:table, :report], do: :ok

  defp verify_kind(_component, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :export],
       message:
         "component #{inspect(key)} cannot declare an export block: CSV export is only " <>
           "supported on :table and :report components"
     )}
  end

  defp verify_columns(%{export: %{columns: nil}}, _key, _resource, _module), do: :ok
  defp verify_columns(%{fields: nil}, _key, nil, _module), do: :ok

  defp verify_columns(component, key, resource, module) do
    case Enum.find(component.export.columns, &(not exportable?(component, resource, &1))) do
      nil -> :ok
      unknown -> {:error, unknown_column(component, key, resource, unknown, module)}
    end
  end

  defp exportable?(component, resource, column) do
    column in (component.fields || []) or
      (not is_nil(resource) and resource_column?(resource, column))
  end

  # A readable value of the record: a public attribute, calculation or
  # aggregate (not a relationship, which has no CSV cell).
  defp resource_column?(resource, column) do
    not is_nil(
      ResourceInfo.public_attribute(resource, column) ||
        ResourceInfo.public_calculation(resource, column) ||
        ResourceInfo.public_aggregate(resource, column)
    )
  end

  defp unknown_column(component, key, nil, column, module) do
    DslError.exception(
      module: module,
      path: [:a2ui, :component, key, :export, :columns],
      message:
        "export column #{inspect(column)} is not one of component #{inspect(key)}'s " <>
          "fields #{inspect(component.fields)}"
    )
  end

  defp unknown_column(component, key, resource, column, module) do
    fields = if component.fields, do: "fields #{inspect(component.fields)} nor ", else: ""

    DslError.exception(
      module: module,
      path: [:a2ui, :component, key, :export, :columns],
      message:
        "export column #{inspect(column)} is not one of component #{inspect(key)}'s " <>
          fields <>
          "a public attribute, calculation or aggregate of #{inspect(resource_name(resource))}"
    )
  end

  # The resource a table export's extra columns are checked against: the
  # table's own resource (a related table's `resource`), or the surface's.
  # nil for reports (their rows are maps, not records) and when the
  # resource cannot be resolved at verification time.
  defp table_resource(%{name: :table, resource: resource}, _dsl_state)
       when not is_nil(resource),
       do: loaded_resource(resource)

  defp table_resource(%{name: :table}, dsl_state) do
    case Verifier.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if Ash.Resource.Dsl in Verifier.get_persisted(dsl_state, :extensions, []),
          do: dsl_state

      resource ->
        loaded_resource(resource)
    end
  end

  defp table_resource(_component, _dsl_state), do: nil

  defp loaded_resource(resource) do
    if Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource), do: resource
  end

  defp resource_name(resource) when is_atom(resource), do: resource
  defp resource_name(dsl_state), do: Verifier.get_persisted(dsl_state, :module)
end
