defmodule AshA2ui.Label do
  @moduledoc """
  The one place a display label is derived from a name.

  Every heading, column, field, action, context, group, step and choice
  label that the DSL does not declare is the humanized name: underscores
  become spaces and the first letter is capitalized (`:due_date` →
  `"Due date"`). Declared labels are used as written.
  """

  @doc """
  The humanized form of an atom or string name: underscores to spaces, the
  first letter capitalized and the rest downcased (`String.capitalize/1`).

      iex> AshA2ui.Label.humanize(:due_date)
      "Due date"
  """
  @spec humanize(atom | String.t()) :: String.t()
  def humanize(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  @doc """
  The humanized short name of a resource module (`MyApp.BulkTask` →
  `"Bulk task"`).

      iex> AshA2ui.Label.resource_name(MyApp.BulkTask)
      "Bulk task"
  """
  @spec resource_name(module) :: String.t()
  def resource_name(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> humanize()
  end

  @doc """
  A name with underscores as spaces and its case kept, for authoring tools
  that show a DSL key as words (`"option_label"` → `"option label"`).

      iex> AshA2ui.Label.words("option_label")
      "option label"
  """
  @spec words(String.t()) :: String.t()
  def words(name) when is_binary(name), do: String.replace(name, "_", " ")
end
