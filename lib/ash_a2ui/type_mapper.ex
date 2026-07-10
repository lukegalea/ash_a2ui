defmodule AshA2ui.TypeMapper do
  @moduledoc """
  Maps Ash types to default widget atoms: string -> `:text_field`, boolean ->
  `:check_box`, atom with `one_of` constraints -> `:choice_picker`,
  date/datetime -> `:date_time_input`. Numeric types map to `:text_field`
  (the numeric keyboard hint is applied by the encoder). Unknown types fall
  back to `:text_field`.

  The widget atom -> catalog component name mapping (`:text_field` ->
  `"TextField"`, ...) lives in the encoder (`AshA2ui.Encoder.V0_9_1`).
  """

  @text_field_types [Ash.Type.String, Ash.Type.CiString] ++
                      [Ash.Type.Integer, Ash.Type.Decimal, Ash.Type.Float]

  @date_time_types [
    Ash.Type.Date,
    Ash.Type.UtcDatetime,
    Ash.Type.UtcDatetimeUsec,
    Ash.Type.NaiveDatetime
  ]

  @doc """
  Returns the default widget atom for the given Ash type (a type module or a
  builtin alias like `:string`) and its constraints.
  """
  @spec widget_for(ash_type :: module | atom, constraints :: keyword) :: atom
  def widget_for(ash_type, constraints \\ []) do
    ash_type
    |> Ash.Type.get_type()
    |> do_widget_for(constraints)
  end

  defp do_widget_for(type, _constraints) when type in @text_field_types, do: :text_field
  defp do_widget_for(Ash.Type.Boolean, _constraints), do: :check_box
  defp do_widget_for(type, _constraints) when type in @date_time_types, do: :date_time_input

  defp do_widget_for(Ash.Type.Atom, constraints) do
    if Keyword.keyword?(constraints) && constraints[:one_of] do
      :choice_picker
    else
      :text_field
    end
  end

  defp do_widget_for(_type, _constraints), do: :text_field
end
