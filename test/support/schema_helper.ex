defmodule AshA2ui.Test.SchemaHelper do
  @moduledoc """
  Loads the vendored A2UI JSON Schemas (priv/a2ui/v0_9_1 and priv/a2ui/v1_0)
  with `ex_json_schema` and exposes assertion helpers used by every
  payload-producing test.

  FROZEN CONTRACT — `assert_valid_server_message/1` and
  `assert_valid_client_message/1` are the assertion interface every parallel
  track codes against (they validate against the v0.9.1 schemas, unchanged).
  v1.0 validation is the additive second argument: pass `:v1_0` to any of the
  four public schema functions.

  Implementation notes (see also priv/a2ui/v0_9_1/NOTES.md and
  priv/a2ui/v1_0/NOTES.md):

    * The spec schemas declare JSON Schema draft 2020-12, but `ex_json_schema`
      implements draft-7. We rewrite `$schema` to draft-7; draft-2020-12-only
      keywords (`unevaluatedProperties`) are ignored, making validation
      slightly more permissive than the spec — fine for positive assertions.
      Constraints the draft-7 engine cannot check (e.g. v1.0's "no
      `returnType` on wire FunctionCalls", expressed via
      `unevaluatedProperties`) are covered by explicit conformance tests
      instead (see test/v1_0_conformance_test.exs).
    * Cross-file `$ref`s (absolute `https://a2ui.org/...` URLs and relative
      refs like `catalog.json#/...`) are resolved offline: relative refs are
      rewritten to absolute URLs under the version's base and
      `resolve_remote/1` (configured as the `:ex_json_schema`
      `:remote_schema_resolver`) serves them from the vendored files — v1.0
      URLs (containing `/v1_0/`) from priv/a2ui/v1_0, everything else from
      priv/a2ui/v0_9_1. `catalog.json` resolves to the version's basic
      catalog; the v1.0 `testing_catalog.json` (used by the vendored upstream
      conformance cases) resolves to priv/a2ui/v1_0/test/testing_catalog.json.
  """

  import ExUnit.Assertions

  @schema_dirs %{
    v0_9_1: Application.app_dir(:ash_a2ui, ["priv", "a2ui", "v0_9_1"]),
    v1_0: Application.app_dir(:ash_a2ui, ["priv", "a2ui", "v1_0"])
  }

  @ref_bases %{
    v0_9_1: "https://a2ui.org/specification/v0_9/",
    v1_0: "https://a2ui.org/specification/v1_0/"
  }

  @doc """
  Asserts that `message` (a map with string keys) is a valid A2UI
  server->client message for the given spec `version` (`:v0_9_1`, the
  default, or `:v1_0`). Returns `message`.
  """
  def assert_valid_server_message(message, version \\ :v0_9_1) do
    assert_valid(server_schema(version), message, version, "server->client")
  end

  @doc """
  Asserts that `message` (a map with string keys) is a valid A2UI
  client->server message for the given spec `version` (`:v0_9_1`, the
  default, or `:v1_0`). Returns `message`.
  """
  def assert_valid_client_message(message, version \\ :v0_9_1) do
    assert_valid(client_schema(version), message, version, "client->server")
  end

  @doc """
  Resolves a remote `$ref` URL to the corresponding vendored schema file.
  Configured in config/config.exs as the ex_json_schema remote resolver.
  """
  def resolve_remote(url) do
    path = URI.parse(url).path || ""
    version = if String.contains?(path, "v1_0"), do: :v1_0, else: :v0_9_1

    file =
      case Path.basename(path) do
        "catalog.json" -> catalog_alias() || Path.join(["catalogs", "basic", "catalog.json"])
        "testing_catalog.json" -> Path.join(["test", "testing_catalog.json"])
        basename -> basename
      end

    load_schema(version, file)
  end

  @doc "The resolved server->client message schema for `version`."
  def server_schema(version \\ :v0_9_1), do: resolved_schema(version, "server_to_client.json")

  @doc "The resolved client->server message schema for `version`."
  def client_schema(version \\ :v0_9_1), do: resolved_schema(version, "client_to_server.json")

  @doc """
  A resolved schema for any vendored file of `version` (path relative to the
  version's priv/a2ui directory), used by the v1.0 conformance suite to run
  the upstream spec test cases. `opts[:catalog]` aliases relative
  `catalog.json` refs to another vendored file (the upstream runner's
  temp-catalog mechanism), e.g. `catalog: "testing_catalog.json"`.
  """
  def resolved_schema(version, file, opts \\ []) do
    catalog = Keyword.get(opts, :catalog)
    key = {__MODULE__, version, file, catalog}

    case :persistent_term.get(key, nil) do
      nil ->
        schema = with_catalog_alias(catalog, fn -> resolve_schema(version, file) end)
        :persistent_term.put(key, schema)
        schema

      schema ->
        schema
    end
  end

  # ExJsonSchema resolves remote refs synchronously in the calling process,
  # so a process-scoped alias redirects every `catalog.json` ref — including
  # the transitive ones inside common_types.json — for the duration of one
  # schema resolution (the upstream runner's temp-catalog mechanism).
  defp with_catalog_alias(nil, fun), do: fun.()

  defp with_catalog_alias(catalog, fun) do
    file =
      case catalog do
        "testing_catalog.json" -> Path.join(["test", "testing_catalog.json"])
        other -> other
      end

    Process.put({__MODULE__, :catalog_alias}, file)

    try do
      fun.()
    after
      Process.delete({__MODULE__, :catalog_alias})
    end
  end

  defp catalog_alias, do: Process.get({__MODULE__, :catalog_alias})

  defp resolve_schema(version, file) do
    version
    |> load_schema(file)
    |> ExJsonSchema.Schema.resolve()
  end

  @doc """
  Validates (without asserting) `data` against a resolved schema; returns
  `:ok` or `{:error, errors}`.
  """
  def validate(schema, data), do: ExJsonSchema.Validator.validate(schema, data)

  defp assert_valid(schema, message, version, direction) do
    case ExJsonSchema.Validator.validate(schema, message) do
      :ok ->
        message

      {:error, errors} ->
        flunk("""
        Expected a valid A2UI #{spec_version(version)} #{direction} message, got validation errors:

        #{Enum.map_join(errors, "\n", fn {msg, path} -> "  #{path}: #{msg}" end)}

        Message:

        #{inspect(message, pretty: true)}
        """)
    end
  end

  defp spec_version(:v0_9_1), do: "v0.9.1"
  defp spec_version(:v1_0), do: "v1.0"

  defp load_schema(version, relative_path) do
    @schema_dirs
    |> Map.fetch!(version)
    |> Path.join(relative_path)
    |> File.read!()
    |> Jason.decode!()
    |> preprocess(Map.fetch!(@ref_bases, version))
  end

  # Downgrade the $schema declaration to draft-7 (the draft ex_json_schema
  # implements) and rewrite relative $refs to absolute spec URLs so the
  # remote resolver serves them from the vendored files.
  defp preprocess(%{} = map, base) do
    map
    |> Enum.map(fn
      {"$schema", _} -> {"$schema", "http://json-schema.org/draft-07/schema#"}
      {"$ref", ref} -> {"$ref", absolutize_ref(ref, base)}
      {key, value} -> {key, preprocess(value, base)}
    end)
    |> Map.new()
  end

  defp preprocess(list, base) when is_list(list), do: Enum.map(list, &preprocess(&1, base))
  defp preprocess(other, _base), do: other

  defp absolutize_ref("#" <> _ = ref, _base), do: ref
  defp absolutize_ref("http" <> _ = ref, _base), do: ref
  defp absolutize_ref(ref, base), do: base <> ref
end
