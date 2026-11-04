defmodule AshA2ui.L10n do
  @moduledoc """
  Message templates for the text ash_a2ui writes for a reader: feedback,
  status lines and chrome built from parts (`"Exported %{filename} (%{count}
  rows)."`).

  A template's `%{key}` placeholders are filled from a keyword list of
  bindings, the way Gettext interpolates. Each placeholder is replaced
  once, in a single pass, so a value that itself contains `%{...}` is never
  interpolated again. A placeholder with no binding is left as written.
  """

  @placeholder ~r/%\{(\w+)\}/

  @typedoc "A translator built from the localization options, or `nil` for none."
  @type t :: nil

  @doc """
  Translates `msgid` with `l10n` and fills its placeholders from `bindings`.
  Without a translator (`nil`) the msgid is only interpolated.
  """
  @spec t(t, String.t(), keyword) :: String.t()
  def t(l10n, msgid, bindings \\ [])
  def t(nil, msgid, bindings) when is_binary(msgid), do: interpolate(msgid, bindings)

  @doc """
  Fills `template`'s `%{key}` placeholders from `bindings`.

      iex> AshA2ui.L10n.interpolate("Updated %{field}.", field: "Name")
      "Updated Name."

      iex> AshA2ui.L10n.interpolate("%{a} and %{b}", a: "%{b}", b: "x")
      "%{b} and x"
  """
  @spec interpolate(String.t(), keyword | map) :: String.t()
  def interpolate(template, bindings) when bindings == [] or bindings == %{}, do: template

  def interpolate(template, bindings) when is_binary(template) do
    values = Map.new(bindings, fn {key, value} -> {to_string(key), value} end)

    Regex.replace(@placeholder, template, fn whole, key ->
      case Map.fetch(values, key) do
        {:ok, value} -> to_string(value)
        :error -> whole
      end
    end)
  end
end
