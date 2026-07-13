defmodule AshA2ui.AgUi do
  @moduledoc """
  AG-UI transport adjacency: emit AshA2ui surfaces over the
  [AG-UI protocol](https://docs.ag-ui.com) so AG-UI clients (CopilotKit,
  or anything speaking the protocol) can render and drive them.

  An **AG-UI server** is an HTTP endpoint that accepts a `POST` with a
  `RunAgentInput` JSON body and streams typed JSON events back — by default
  as Server-Sent Events (`Content-Type: text/event-stream`, one
  `data: <json>\\n\\n` frame per event). This module provides everything the
  protocol layer needs and **nothing transport-framework specific**: plain
  map event builders, SSE frame encoding, `RunAgentInput` decoding, and the
  A2UI↔AG-UI bindings (surfaces out, client actions in). It depends only on
  `Jason` — no Phoenix, no Plug — so it is always compiled; the HTTP
  endpoint itself is a handful of lines in the host (see the
  [External Transports](external-transports.html) topic for a complete
  Phoenix example).

  ## The event vocabulary

  A run streams, in order:

    1. `run_started/2`
    2. any number of content events — `text_message_*` (assistant tokens),
       `tool_call_*` (tool activity), `surface_activity/2` (A2UI surfaces),
       `custom/2`
    3. exactly one `run_finished/3` or `run_error/2`

  ## How A2UI rides AG-UI

  There is no first-class A2UI event in AG-UI. The interoperable binding —
  established by `@ag-ui/a2ui-middleware` and consumed by CopilotKit's
  `createA2UIMessageRenderer` — is an `ACTIVITY_SNAPSHOT` event with
  `activityType: "a2ui-surface"` whose `content` wraps the ordinary A2UI
  server→client message list under the `"a2ui_operations"` key:

      messages = AshA2ui.Info.build_surface(MyApp.UI.TicketUI,
        actor: admin, spec_version: "0.9.1")

      AshA2ui.AgUi.surface_activity("surface-tickets", messages)

  Snapshots **replace** by `messageId`: re-emitting the same `messageId`
  with an updated operations list updates the rendered surface in place
  (that is how action follow-ups and data refreshes reach the client —
  append the handler's `updateDataModel` messages and re-emit).

  > #### Pin the wire version to your renderer {: .warning}
  >
  > CopilotKit's shipped A2UI renderer processes **v0.9** messages (its
  > `MessageProcessor` comes from `@a2ui/web_core/v0_9`; it has no v1.0
  > runtime). When targeting it, build surfaces with
  > `spec_version: "0.9.1"` — the per-resolve override exists precisely so
  > a transport can pin the wire version without touching surface DSLs.

  Client → server, an A2UI user action arrives as the `a2uiAction` key of
  the next run's `forwardedProps` (the CopilotKit action bridge sets it,
  runs the agent once, then clears it). `decode_action/1` converts that
  payload into the client envelope `AshA2ui.ActionHandler.handle/3` and
  `AshA2ui.Dynamic.handle_action/3` consume.

  ## Authentication contract (read this)

  AG-UI has **no authentication story of its own** — the endpoint is an
  ordinary HTTP route in your application, and resolving the actor is the
  host's job, exactly as with `AshA2ui.LiveRenderer` and the plain JSON
  transport:

    * Gate the route with your session/token auth (router pipelines, plugs).
    * Derive the actor from the **authenticated session** — never from the
      request body. `RunAgentInput` is client-controlled; nothing in it is
      trustworthy identity.
    * Pass that actor to every `build_surface`/`build_data_model`/
      `ActionHandler.handle`/`Dynamic.handle_action` call. AshA2ui always
      runs Ash calls with `authorize?: true`; do not weaken that on a
      network-facing transport.
    * Anything you key across runs (per-thread surface state) must be scoped
      to the authenticated actor, not just the client-supplied `threadId`.
  """

  @a2ui_activity_type "a2ui-surface"
  @a2ui_operations_key "a2ui_operations"

  # ---------------------------------------------------------------------------
  # Server -> client events
  # ---------------------------------------------------------------------------

  @doc """
  The `RUN_STARTED` event opening a run. Echo the `threadId`/`runId` from
  the `RunAgentInput` that started the run.
  """
  @spec run_started(String.t(), String.t()) :: map
  def run_started(thread_id, run_id) do
    %{"type" => "RUN_STARTED", "threadId" => thread_id, "runId" => run_id}
  end

  @doc """
  The `RUN_FINISHED` event closing a successful run.

  ## Options

    * `:result` — optional result payload for the run.
  """
  @spec run_finished(String.t(), String.t(), keyword) :: map
  def run_finished(thread_id, run_id, opts \\ []) do
    %{"type" => "RUN_FINISHED", "threadId" => thread_id, "runId" => run_id}
    |> put_optional("result", Keyword.get(opts, :result))
  end

  @doc """
  The `RUN_ERROR` event terminating a failed run.

  ## Options

    * `:code` — optional machine-readable error code.
  """
  @spec run_error(String.t(), keyword) :: map
  def run_error(message, opts \\ []) do
    %{"type" => "RUN_ERROR", "message" => message}
    |> put_optional("code", Keyword.get(opts, :code))
  end

  @doc """
  The `TEXT_MESSAGE_START` event opening a streamed text message.

  ## Options

    * `:role` — the sender role, default `"assistant"`.
  """
  @spec text_message_start(String.t(), keyword) :: map
  def text_message_start(message_id, opts \\ []) do
    %{
      "type" => "TEXT_MESSAGE_START",
      "messageId" => message_id,
      "role" => Keyword.get(opts, :role, "assistant")
    }
  end

  @doc """
  A `TEXT_MESSAGE_CONTENT` token delta. The spec requires a **non-empty**
  delta; empty chunks raise (filter them out before calling).
  """
  @spec text_message_content(String.t(), String.t()) :: map
  def text_message_content(message_id, delta) do
    if delta == "" do
      raise ArgumentError, "TEXT_MESSAGE_CONTENT delta must be non-empty"
    end

    %{"type" => "TEXT_MESSAGE_CONTENT", "messageId" => message_id, "delta" => delta}
  end

  @doc "The `TEXT_MESSAGE_END` event closing a streamed text message."
  @spec text_message_end(String.t()) :: map
  def text_message_end(message_id) do
    %{"type" => "TEXT_MESSAGE_END", "messageId" => message_id}
  end

  @doc """
  The `TOOL_CALL_START` event announcing a tool invocation.

  ## Options

    * `:parent_message_id` — the assistant message this call belongs to.
  """
  @spec tool_call_start(String.t(), String.t(), keyword) :: map
  def tool_call_start(tool_call_id, tool_call_name, opts \\ []) do
    %{
      "type" => "TOOL_CALL_START",
      "toolCallId" => tool_call_id,
      "toolCallName" => tool_call_name
    }
    |> put_optional("parentMessageId", Keyword.get(opts, :parent_message_id))
  end

  @doc "A `TOOL_CALL_ARGS` event carrying a JSON fragment of the call's arguments."
  @spec tool_call_args(String.t(), String.t()) :: map
  def tool_call_args(tool_call_id, delta) do
    %{"type" => "TOOL_CALL_ARGS", "toolCallId" => tool_call_id, "delta" => delta}
  end

  @doc "The `TOOL_CALL_END` event closing a tool call's argument stream."
  @spec tool_call_end(String.t()) :: map
  def tool_call_end(tool_call_id) do
    %{"type" => "TOOL_CALL_END", "toolCallId" => tool_call_id}
  end

  @doc """
  The `TOOL_CALL_RESULT` event delivering a tool's output. `content` must
  be a string (JSON-encode structured results yourself).
  """
  @spec tool_call_result(String.t(), String.t(), String.t()) :: map
  def tool_call_result(message_id, tool_call_id, content) when is_binary(content) do
    %{
      "type" => "TOOL_CALL_RESULT",
      "messageId" => message_id,
      "toolCallId" => tool_call_id,
      "content" => content,
      "role" => "tool"
    }
  end

  @doc """
  The `ACTIVITY_SNAPSHOT` event carrying an A2UI surface: `activityType`
  `"#{@a2ui_activity_type}"`, with the surface's ordinary A2UI
  server→client message list wrapped under `content.#{@a2ui_operations_key}`
  — the binding CopilotKit's A2UI renderer consumes.

  `messages` is exactly what `AshA2ui.Info.build_surface/2` /
  `AshA2ui.Dynamic.build_surface/2` return. Keep the `message_id` **stable
  per surface** and re-emit with an extended message list to update the
  rendered surface in place (`"replace" => true` snapshot semantics).
  """
  @spec surface_activity(String.t(), [map]) :: map
  def surface_activity(message_id, messages) when is_list(messages) do
    %{
      "type" => "ACTIVITY_SNAPSHOT",
      "messageId" => message_id,
      "activityType" => @a2ui_activity_type,
      "content" => %{@a2ui_operations_key => messages},
      "replace" => true
    }
  end

  @doc "A `CUSTOM` extension event (`name` + arbitrary `value`)."
  @spec custom(String.t(), term) :: map
  def custom(name, value) do
    %{"type" => "CUSTOM", "name" => name, "value" => value}
  end

  @doc false
  def a2ui_activity_type, do: @a2ui_activity_type

  @doc false
  def a2ui_operations_key, do: @a2ui_operations_key

  # ---------------------------------------------------------------------------
  # SSE encoding
  # ---------------------------------------------------------------------------

  @doc """
  Encodes one event map as an SSE frame (`"data: <json>\\n\\n"` iodata) —
  the AG-UI default transport encoding. Send frames on a chunked response
  with `Content-Type: text/event-stream`.
  """
  @spec encode_sse(map) :: iodata
  def encode_sse(event) when is_map(event) do
    ["data: ", Jason.encode_to_iodata!(event), "\n\n"]
  end

  # ---------------------------------------------------------------------------
  # Client -> server
  # ---------------------------------------------------------------------------

  @doc """
  Decodes a `RunAgentInput` request body (already JSON-decoded) into a
  normalized map:

    * `:thread_id` / `:run_id` — the run identifiers to echo in lifecycle
      events (missing ones default to `""`; reject those requests if your
      endpoint requires real ids).
    * `:messages` — the conversation as `%{role: atom, content: binary}`
      maps, oldest first. Only `:user`, `:assistant`, `:system`, and
      `:developer` roles with non-empty string content are kept — tool,
      activity, and reasoning messages are transport bookkeeping, not chat
      history for your agent loop.
    * `:a2ui_action` — the raw `forwardedProps.a2uiAction` payload when the
      run was triggered by an A2UI user action (see `decode_action/1`),
      else `nil`.
    * `:forwarded_props` — the full `forwardedProps` map (`%{}` when absent).

  Everything is treated as untrusted client input: unknown roles and
  malformed entries are dropped, never raised on.
  """
  @spec decode_run_input(map) :: %{
          thread_id: String.t(),
          run_id: String.t(),
          messages: [%{role: atom, content: String.t()}],
          a2ui_action: map | nil,
          forwarded_props: map
        }
  def decode_run_input(body) when is_map(body) do
    forwarded_props =
      case body["forwardedProps"] do
        props when is_map(props) -> props
        _other -> %{}
      end

    %{
      thread_id: string_or_default(body["threadId"], ""),
      run_id: string_or_default(body["runId"], ""),
      messages: decode_messages(body["messages"]),
      a2ui_action:
        case forwarded_props["a2uiAction"] do
          action when is_map(action) -> action
          _other -> nil
        end,
      forwarded_props: forwarded_props
    }
  end

  @chat_roles %{
    "user" => :user,
    "assistant" => :assistant,
    "system" => :system,
    "developer" => :developer
  }

  defp decode_messages(messages) when is_list(messages) do
    for %{"role" => role, "content" => content} <- messages,
        chat_role = @chat_roles[role],
        chat_role != nil,
        is_binary(content) and content != "" do
      %{role: chat_role, content: content}
    end
  end

  defp decode_messages(_other), do: []

  @doc """
  Decodes an A2UI client action received over AG-UI into the v0.9.1 client
  envelope `AshA2ui.ActionHandler.handle/3` and
  `AshA2ui.Dynamic.handle_action/3` accept.

  Accepts the shapes the ecosystem produces:

    * the CopilotKit action-bridge payload —
      `%{"userAction" => %{"name" => ..., "surfaceId" => ..., ...}}`
      (what `forwardedProps.a2uiAction` carries),
    * a bare user-action map (`%{"name" => ..., ...}`),
    * an already-enveloped A2UI action (`%{"action" => %{...}}`) — passed
      through normalized.

  Only the spec's action keys (`name`, `surfaceId`, `sourceComponentId`,
  `timestamp`, `context`) are kept; renderer extras (e.g.
  `dataContextPath`) are dropped, and keys the spec requires but renderers
  may omit are filled with spec-valid defaults (`""` component/surface ids,
  a current UTC timestamp, an empty context) so the produced envelope
  always validates against the vendored v0.9.1 client schema. Returns
  `{:ok, envelope}` or `:error` for anything without a usable action name.
  """
  @spec decode_action(map) :: {:ok, map} | :error
  def decode_action(%{"userAction" => user_action}) when is_map(user_action) do
    decode_action(user_action)
  end

  def decode_action(%{"action" => action}) when is_map(action) do
    decode_action(action)
  end

  def decode_action(%{"name" => name} = action) when is_binary(name) and name != "" do
    inner = %{
      "name" => name,
      "surfaceId" => string_or_default(action["surfaceId"], ""),
      "sourceComponentId" => string_or_default(action["sourceComponentId"], ""),
      "timestamp" =>
        string_or_default(action["timestamp"], DateTime.to_iso8601(DateTime.utc_now())),
      "context" =>
        case action["context"] do
          context when is_map(context) -> context
          _other -> %{}
        end
    }

    {:ok, %{"version" => "v0.9.1", "action" => inner}}
  end

  def decode_action(_other), do: :error

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp string_or_default(value, _default) when is_binary(value), do: value
  defp string_or_default(_value, default), do: default
end
