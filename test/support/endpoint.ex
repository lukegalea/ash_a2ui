# Minimal Phoenix test endpoint + router for LiveRenderer tests
# (Phoenix.LiveViewTest-ready). Guarded so the NO_PHOENIX CI job (which strips
# the Phoenix stack) still compiles test/support cleanly.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.Test.ErrorHTML do
    @moduledoc false

    def render(template, _assigns) do
      Phoenix.Controller.status_message_from_template(template)
    end
  end

  defmodule AshA2ui.Test.Router do
    @moduledoc false

    use Phoenix.Router
    # TODO Track 4: `import Phoenix.LiveView.Router` when adding live routes
    # (left out for now to keep the compile warning-free).

    pipeline :browser do
      plug(:accepts, ["html"])
      plug(:fetch_session)
    end

    scope "/" do
      pipe_through(:browser)

      # TODO Track 4: add live routes for LiveRenderer tests here, e.g.
      #   live "/kitchen-sink", AshA2ui.Test.KitchenSinkLive
    end
  end

  defmodule AshA2ui.Test.Endpoint do
    @moduledoc false

    use Phoenix.Endpoint, otp_app: :ash_a2ui

    @session_options [
      store: :cookie,
      key: "_ash_a2ui_test",
      signing_salt: "aaaaaaaaaaaaaaaa",
      same_site: "Lax"
    ]

    socket("/live", Phoenix.LiveView.Socket,
      websocket: [connect_info: [session: @session_options]]
    )

    plug(Plug.Session, @session_options)
    plug(AshA2ui.Test.Router)
  end
end
