# AshA2ui.ActorPlug is the optional HTTP half of AshA2ui.Actor. The whole
# module is guarded so the protocol core compiles when Plug is absent
# (mirroring the NO_PHOENIX guard on the LiveView transport).
if Code.ensure_loaded?(Plug.Conn) do
  defmodule AshA2ui.ActorPlug do
    @moduledoc """
    `GET /a2ui/actor?id=<uuid>` switches the acting actor: the id is
    validated through `AshA2ui.Actor.load/1`, stored in the session, and the
    request redirects back to its referer. Every other request passes
    through untouched, so the plug can sit in the browser pipeline of any
    host using `AshA2ui.Actor`.

        pipeline :browser do
          # ... existing plugs ...
          plug AshA2ui.ActorPlug
        end
    """

    @behaviour Plug

    import Plug.Conn

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, _opts) do
      case conn.path_info do
        ["a2ui", "actor"] -> switch(conn)
        _ -> conn
      end
    end

    defp switch(%Plug.Conn{method: "GET"} = conn) do
      case AshA2ui.Actor.load(conn.query_params["id"] || "") do
        %AshA2ui.Actor{id: id} ->
          # A raw 302 rather than Phoenix.Controller.redirect/2: this module
          # must work in any Plug host, Phoenix or not. The session is
          # fetched here because the plug may run before the host's own
          # fetch_session (at the endpoint, not in a pipeline); fetch_session
          # is idempotent if a host already fetched it.
          conn
          |> fetch_session()
          |> put_session(AshA2ui.Actor.session_key(), id)
          |> put_resp_header("location", back(conn))
          |> send_resp(302, "")

        nil ->
          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(422, "unknown actor\n")
      end
    end

    defp switch(conn) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(405, "GET only\n")
    end

    # Sessions are written over HTTP, so the picker links here from wherever
    # the user is; land them back on that page. A referer-less request (curl,
    # a fresh tab) lands on the app root.
    defp back(conn) do
      case get_req_header(conn, "referer") do
        [referer | _] -> URI.parse(referer).path || "/"
        [] -> "/"
      end
    end
  end
end
