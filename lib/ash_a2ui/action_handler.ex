defmodule AshA2ui.ActionHandler do
  @moduledoc """
  Consumes A2UI client->server `action` envelope messages and invokes the
  corresponding Ash actions (actor-aware, `authorize?: true`).

  FROZEN CONTRACT — the `handle/3` signature is the interface every parallel
  track codes against; do not change outside an integration commit.

  TODO Track 3: implement. Currently raises.
  """

  @doc """
  Handles an A2UI client `action` envelope (a decoded map matching the
  vendored `client_to_server.json` schema, i.e.
  `%{"version" => _, "action" => %{"name" => ..., "surfaceId" => ...,
  "sourceComponentId" => ..., "timestamp" => ..., "context" => %{...}}}`).

  Supported `action.name` values (v0): `"submit_form"`, `"select_row"`,
  `"invoke"`.

  Returns `{:ok, messages}` with follow-up server->client messages (e.g. an
  `updateDataModel` refresh) or `{:error, messages}` where the messages carry
  validation errors on the reserved `/errors/<field>` and `/ui/status`
  data-model paths.

  ## Options

    * `:actor` — the actor for the Ash action invocation.
    * `:tenant` — the tenant for the Ash action invocation.
  """
  @spec handle(module, action_message :: map, opts :: keyword) ::
          {:ok, [map]} | {:error, [map]}
  def handle(_resource_or_ui_module, _action_message, _opts \\ []) do
    # TODO Track 3: parse the envelope, map action.name to the Ash action,
    # invoke with actor/tenant, map validation errors to /errors/<field> and
    # /ui/status updateDataModel payloads.
    raise "TODO Track 3: AshA2ui.ActionHandler.handle/3 is not implemented yet"
  end
end
