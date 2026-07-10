defmodule AshA2ui.TypeMapper do
  @moduledoc """
  Maps Ash types to default widgets (string -> `:text_field`, boolean ->
  `:check_box`, enum -> `:choice_picker`, datetime -> `:date_time_input`, ...).

  TODO Track 2: implement. Currently raises.
  """

  @doc """
  Returns the default widget atom for the given Ash type module.
  """
  @spec widget_for(ash_type :: module) :: atom
  def widget_for(_ash_type) do
    # TODO Track 2: map Ash types (incl. constraints, e.g. atom one_of ->
    # :choice_picker) to widget atoms.
    raise "TODO Track 2: AshA2ui.TypeMapper.widget_for/1 is not implemented yet"
  end
end
