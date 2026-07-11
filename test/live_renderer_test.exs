# The whole file is Phoenix-only: under NO_PHOENIX the LiveRenderer, the test
# endpoint and the fixture LiveViews (test/support/live_renderer_live_views.ex)
# don't exist, so nothing here should even compile.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.LiveRendererTest do
    # async: false — the stub listener lives in global app env and the tests
    # share the app-wide test endpoint/PubSub.
    use ExUnit.Case, async: false

    import Phoenix.ConnTest
    import Phoenix.LiveViewTest

    alias AshA2ui.Test.LiveRendererFixtures, as: Fixtures
    alias AshA2ui.Test.{MinimalUI, SchemaHelper}

    @endpoint AshA2ui.Test.Endpoint

    setup do
      Application.put_env(:ash_a2ui, :live_renderer_test_listener, self())

      on_exit(fn ->
        Application.delete_env(:ash_a2ui, :live_renderer_test_listener)
      end)

      [conn: Plug.Test.init_test_session(build_conn(), %{})]
    end

    describe "mount" do
      test "connected mount pushes schema-valid a2ui:messages", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/stubbed")

        assert_push_event(view, "a2ui:messages", %{messages: messages})

        assert length(messages) == 3
        Enum.each(messages, &SchemaHelper.assert_valid_server_message/1)

        assert [
                 %{"createSurface" => _},
                 %{"updateComponents" => _},
                 %{"updateDataModel" => _}
               ] = messages
      end

      test "static render outputs the hook container without building the surface", %{conn: conn} do
        conn = get(conn, "/live-renderer/stubbed")
        html = html_response(conn, 200)

        assert html =~ ~s(id="ash-a2ui-surface")
        assert html =~ ~s(phx-hook="AshA2ui")
        assert html =~ ~s(phx-update="ignore")

        # surface_fn must not run on the static (disconnected) render
        refute_receive {:surface_fn, _, _}, 100
      end

      test "actor_fn and tenant_fn results are passed to surface_fn", %{conn: conn} do
        {:ok, _view, _html} = live(conn, "/live-renderer/stubbed")

        assert_receive {:surface_fn, MinimalUI, opts}
        assert opts[:actor] == :stub_actor
        assert opts[:tenant] == :stub_tenant
      end

      test "assigns ui/actor/tenant on the socket for introspection", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/stubbed")

        assigns = :sys.get_state(view.pid).socket.assigns
        assert assigns.ash_a2ui_ui == MinimalUI
        assert assigns.ash_a2ui_actor == :stub_actor
        assert assigns.ash_a2ui_tenant == :stub_tenant
      end
    end

    describe "a2ui:action round-trip" do
      test "routes the envelope through action_fn and pushes the ok messages", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/stubbed")
        envelope = Fixtures.action_envelope()
        SchemaHelper.assert_valid_client_message(envelope)

        render_hook(view, "a2ui:action", envelope)

        assert_receive {:action_fn, MinimalUI, ^envelope, opts}
        assert opts[:actor] == :stub_actor
        assert opts[:tenant] == :stub_tenant

        assert_push_event(view, "a2ui:messages", %{
          messages:
            [_, %{"updateDataModel" => %{"path" => "/ui/status", "value" => "saved"}}] = messages
        })

        Enum.each(messages, &SchemaHelper.assert_valid_server_message/1)
      end

      test "an error tuple from action_fn also pushes its messages", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/stubbed")
        envelope = Fixtures.action_envelope("invoke", %{"fail" => true})

        render_hook(view, "a2ui:action", envelope)

        assert_receive {:action_fn, MinimalUI, ^envelope, _opts}

        assert_push_event(view, "a2ui:messages", %{
          messages: [%{"updateDataModel" => %{"path" => "/errors/name"}} | _] = messages
        })

        Enum.each(messages, &SchemaHelper.assert_valid_server_message/1)
      end
    end

    describe "PubSub live refresh" do
      test "a notification broadcast triggers a debounced data-model push", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/pubsub")
        assert_push_event(view, "a2ui:messages", %{messages: _initial})

        notification = %Ash.Notifier.Notification{resource: AshA2ui.Test.Minimal}

        Phoenix.PubSub.broadcast(
          AshA2ui.Test.PubSub,
          "ash_a2ui_test:providers",
          notification
        )

        assert_receive {:data_model_fn, MinimalUI, _opts}, 1_000

        assert_push_event(view, "a2ui:messages", %{messages: [message]}, 1_000)
        SchemaHelper.assert_valid_server_message(message)
        assert %{"updateDataModel" => %{"path" => "/records"}} = message
      end

      test "arbitrary broadcast payloads on subscribed topics also trigger a refresh", %{
        conn: conn
      } do
        {:ok, view, _html} = live(conn, "/live-renderer/pubsub")
        assert_push_event(view, "a2ui:messages", %{messages: _initial})

        Phoenix.PubSub.broadcast(
          AshA2ui.Test.PubSub,
          "ash_a2ui_test:providers",
          %{topic: "ash_a2ui_test:providers", event: "create", payload: %{}}
        )

        assert_receive {:data_model_fn, MinimalUI, _opts}, 1_000
        assert_push_event(view, "a2ui:messages", %{messages: [_message]}, 1_000)
      end

      test "rapid notifications coalesce into a single refresh", %{conn: conn} do
        {:ok, _view, _html} = live(conn, "/live-renderer/pubsub")

        for _ <- 1..5 do
          Phoenix.PubSub.broadcast(
            AshA2ui.Test.PubSub,
            "ash_a2ui_test:providers",
            %Ash.Notifier.Notification{resource: AshA2ui.Test.Minimal}
          )
        end

        assert_receive {:data_model_fn, MinimalUI, _opts}, 1_000
        refute_receive {:data_model_fn, _, _}, 300
      end

      test "handle_info messages are ignored when pubsub is not configured", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/stubbed")

        send(view.pid, %Ash.Notifier.Notification{resource: AshA2ui.Test.Minimal})
        send(view.pid, :unrelated)

        refute_receive {:data_model_fn, _, _}, 400
      end
    end

    describe "integration with real defaults" do
      test "mount with default surface_fn pushes schema-valid messages", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/defaults")

        assert_push_event(view, "a2ui:messages", %{messages: messages})
        assert messages != []
        Enum.each(messages, &SchemaHelper.assert_valid_server_message/1)
      end

      test "a query action round-trips through the LiveView transport", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/query")
        assert_push_event(view, "a2ui:messages", %{messages: _initial})

        envelope = %{
          "version" => "v0.9.1",
          "action" => %{
            "name" => "query",
            "surfaceId" => "paginated",
            "sourceComponentId" => "query_apply_button",
            "timestamp" => "2026-07-10T12:00:00Z",
            "context" => %{"query" => %{"search" => "nothing matches this"}, "page" => 1}
          }
        }

        SchemaHelper.assert_valid_client_message(envelope)
        render_hook(view, "a2ui:action", envelope)

        assert_push_event(view, "a2ui:messages", %{messages: messages})
        Enum.each(messages, &SchemaHelper.assert_valid_server_message/1)

        assert [
                 %{"updateDataModel" => %{"path" => "/records", "value" => []}},
                 %{"updateDataModel" => %{"path" => "/query", "value" => query_state}}
               ] = messages

        assert %{"search" => "nothing matches this", "page" => 1, "hasMore" => false} =
                 query_state
      end

      test "a PubSub refresh re-runs the client's last query state, not the defaults", %{
        conn: conn
      } do
        {:ok, view, _html} = live(conn, "/live-renderer/query-pubsub")
        assert_push_event(view, "a2ui:messages", %{messages: _initial})

        envelope = %{
          "version" => "v0.9.1",
          "action" => %{
            "name" => "query",
            "surfaceId" => "paginated",
            "sourceComponentId" => "query_apply_button",
            "timestamp" => "2026-07-10T12:00:00Z",
            "context" => %{"query" => %{"search" => "needle"}, "page" => 1}
          }
        }

        render_hook(view, "a2ui:action", envelope)
        assert_push_event(view, "a2ui:messages", %{messages: [_records, _query]})

        Phoenix.PubSub.broadcast(
          AshA2ui.Test.PubSub,
          "ash_a2ui_test:paginated",
          %Ash.Notifier.Notification{resource: AshA2ui.Test.Paginated}
        )

        assert_push_event(
          view,
          "a2ui:messages",
          %{messages: [%{"updateDataModel" => %{"path" => "/", "value" => value}}]},
          1_000
        )

        # Without query-state tracking the refresh would rebuild with the
        # declared defaults and push "search" => "".
        assert %{"search" => "needle", "page" => 1} = value["query"]
      end
    end
  end
end
