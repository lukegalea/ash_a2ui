defmodule AshA2ui.Canvas.Registry do
  @moduledoc """
  The host-configured catalogue of what the canvas knows to exist.

  A registry is a module implementing this behaviour. `domains/0` returns
  the compile-known Ash domain modules the canvas may traverse — this is the
  entire discovery surface (`CANVAS-SEC-005`): what the registry does not
  list does not exist, and no resolver path ever widens it. The optional
  `label/1` callback lets a host override display labels; it receives
  `:application`, a domain module, a resource module, or a record struct,
  and returning `nil` (or not implementing the callback) falls back to the
  library's humanized defaults.

  The library ships `Canvas.Test.Registry` over the test-support fixtures;
  hosts implement their own.
  """

  @doc """
  The domain modules the canvas may traverse. Compile-known modules only —
  the resolver matches client refs against these as strings and never
  converts input into module names.
  """
  @callback domains() :: [module()]

  @doc """
  Optional display-label override. Receives `:application`, a domain
  module, a resource module, or a record struct; `nil` falls back to the
  library default.
  """
  @callback label(target :: :application | module() | struct()) :: String.t() | nil

  @optional_callbacks [label: 1]

  @doc false
  # The registry's domain list, with a fail-loud check: a registry that does
  # not implement the behaviour is a configuration error, not an empty
  # canvas.
  def domains(registry) do
    if Code.ensure_loaded?(registry) and function_exported?(registry, :domains, 0) do
      registry.domains()
    else
      raise ArgumentError,
            "#{inspect(registry)} is not an AshA2ui.Canvas.Registry: it does not implement domains/0"
    end
  end

  @doc false
  # The registry's label for `target`, or nil when the host provides no
  # override.
  def label(registry, target) do
    if Code.ensure_loaded?(registry) and function_exported?(registry, :label, 1) do
      registry.label(target)
    else
      nil
    end
  end

  @doc false
  # The application id used for the root node and `application:` refs:
  # derived from the registry module's own (compile-known) name, so it is
  # stable and never client-influenced.
  def application_id(registry) do
    short =
      registry
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    "application:" <> short
  end
end
