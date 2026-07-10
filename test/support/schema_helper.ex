defmodule AshA2ui.Test.SchemaHelper do
  @moduledoc """
  Loads the vendored A2UI v0.9.1 JSON Schemas (priv/a2ui/v0_9_1) with
  `ex_json_schema` and exposes assertion helpers used by every
  payload-producing test.

  FROZEN CONTRACT — `assert_valid_server_message/1` and
  `assert_valid_client_message/1` are the assertion interface every parallel
  track codes against.

  Implementation notes (see also priv/a2ui/v0_9_1/NOTES.md):

    * The spec schemas declare JSON Schema draft 2020-12, but `ex_json_schema`
      implements draft-7. We rewrite `$schema` to draft-7; draft-2020-12-only
      keywords (`unevaluatedProperties`) are ignored, making validation
      slightly more permissive than the spec — fine for positive assertions.
    * Cross-file `$ref`s (absolute `https://a2ui.org/...` URLs and relative
      refs like `catalog.json#/...`) are resolved offline: relative refs are
      rewritten to absolute URLs and `resolve_remote/1` (configured as the
      `:ex_json_schema` `:remote_schema_resolver`) serves them from the
      vendored files. `catalog.json` resolves to the basic catalog.
  """

  import ExUnit.Assertions

  @schema_dir Application.app_dir(:ash_a2ui, ["priv", "a2ui", "v0_9_1"])
  @ref_base "https://a2ui.org/specification/v0_9/"

  @doc """
  Asserts that `message` (a map with string keys) is a valid A2UI v0.9.1
  server->client message (`createSurface` / `updateComponents` /
  `updateDataModel` / `deleteSurface`). Returns `message`.
  """
  def assert_valid_server_message(message) do
    assert_valid(server_schema(), message, "server->client")
  end

  @doc """
  Asserts that `message` (a map with string keys) is a valid A2UI v0.9.1
  client->server message (`action` / `error` envelope). Returns `message`.
  """
  def assert_valid_client_message(message) do
    assert_valid(client_schema(), message, "client->server")
  end

  @doc """
  Resolves a remote `$ref` URL to the corresponding vendored schema file.
  Configured in config/config.exs as the ex_json_schema remote resolver.
  """
  def resolve_remote(url) do
    file =
      case Path.basename(URI.parse(url).path) do
        "catalog.json" -> Path.join(["catalogs", "basic", "catalog.json"])
        basename -> basename
      end

    load_schema(file)
  end

  @doc "The resolved server->client message schema."
  def server_schema, do: resolved_schema("server_to_client.json")

  @doc "The resolved client->server message schema."
  def client_schema, do: resolved_schema("client_to_server.json")

  defp assert_valid(schema, message, direction) do
    case ExJsonSchema.Validator.validate(schema, message) do
      :ok ->
        message

      {:error, errors} ->
        flunk("""
        Expected a valid A2UI v0.9.1 #{direction} message, got validation errors:

        #{Enum.map_join(errors, "\n", fn {msg, path} -> "  #{path}: #{msg}" end)}

        Message:

        #{inspect(message, pretty: true)}
        """)
    end
  end

  defp resolved_schema(file) do
    key = {__MODULE__, file}

    case :persistent_term.get(key, nil) do
      nil ->
        schema = file |> load_schema() |> ExJsonSchema.Schema.resolve()
        :persistent_term.put(key, schema)
        schema

      schema ->
        schema
    end
  end

  defp load_schema(relative_path) do
    @schema_dir
    |> Path.join(relative_path)
    |> File.read!()
    |> Jason.decode!()
    |> preprocess()
  end

  # Downgrade the $schema declaration to draft-7 (the draft ex_json_schema
  # implements) and rewrite relative $refs to absolute spec URLs so the
  # remote resolver serves them from the vendored files.
  defp preprocess(%{} = map) do
    map
    |> Enum.map(fn
      {"$schema", _} -> {"$schema", "http://json-schema.org/draft-07/schema#"}
      {"$ref", ref} -> {"$ref", absolutize_ref(ref)}
      {key, value} -> {key, preprocess(value)}
    end)
    |> Map.new()
  end

  defp preprocess(list) when is_list(list), do: Enum.map(list, &preprocess/1)
  defp preprocess(other), do: other

  defp absolutize_ref("#" <> _ = ref), do: ref
  defp absolutize_ref("http" <> _ = ref), do: ref
  defp absolutize_ref(ref), do: @ref_base <> ref
end
