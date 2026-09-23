# The whole file is Phoenix-only: under NO_PHOENIX the picker LiveView, the
# test endpoint and the shared live_session route don't exist, so nothing
# here should even compile.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.ActorPickerLiveTest do
    @moduledoc """
    The picker's mounting contract: it works standalone (its own
    live_session) and in-session (a shared live_session carrying
    `on_mount AshA2ui.Actor`), reads only the session for its current-actor
    highlight, streams the roster from the async read (skeleton pills until
    it lands), and coexists with the on_mount assigns on the same socket.
    """

    use ExUnit.Case, async: false

    import Phoenix.ConnTest
    import Phoenix.LiveViewTest

    alias AshA2ui.Test.ActorRoster

    @endpoint AshA2ui.Test.Endpoint

    setup do
      previous = Application.get_env(:ash_a2ui, :actor)

      on_exit(fn -> Application.put_env(:ash_a2ui, :actor, previous) end)

      Application.put_env(:ash_a2ui, :actor, resource: ActorRoster, label: :name)

      # The roster table is shared (public ETS) — start every test empty.
      Enum.each(Ash.read!(ActorRoster, authorize?: false), &Ash.destroy!(&1))

      [conn: Plug.Test.init_test_session(build_conn(), %{})]
    end

    defp roster(name) do
      ActorRoster
      |> Ash.Changeset.for_create(:create, %{name: name})
      |> Ash.create!()
    end

    defp with_session_actor(conn, id) do
      Plug.Test.init_test_session(conn, %{AshA2ui.Actor.session_key() => id})
    end

    # The roster lands via the mount's async task; drain deterministically.
    defp await_stream(view, content, attempts \\ 50)

    defp await_stream(_view, _content, 0), do: flunk("the roster stream never landed")

    defp await_stream(view, content, attempts) do
      html = render(view)

      if html =~ content do
        html
      else
        Process.sleep(10)
        await_stream(view, content, attempts - 1)
      end
    end

    test "in-session mounting: shared live_session with on_mount renders the picker", %{
      conn: conn
    } do
      ada = roster("Ada")
      roster("Grace")

      {:ok, view, html} = live(with_session_actor(conn, ada.id), "/acting-as/shared")

      # the mount render: chrome + skeleton pills before the async roster
      # read lands
      assert html =~ "Acting as"
      assert html =~ "actor-skeleton-1"

      # drained: the streamed roster replaces the skeleton, and the session
      # actor's link is the current one
      html = await_stream(view, "Grace")
      refute html =~ "actor-skeleton-1"
      assert html =~ ~s(aria-current="true")

      # on_mount compatibility: the hook's assigns and the picker's assigns
      # share the socket without conflict
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.a2ui_actor && assigns.a2ui_actor.id == ada.id
      assert assigns.a2ui_actor_label == "Ada"
      assert assigns.current_id == ada.id
      assert assigns.actors_loaded? == true
    end

    test "in-session mounting with an unknown session id degrades to no current actor", %{
      conn: conn
    } do
      roster("Ada")

      unknown = "00000000-0000-0000-0000-000000000099"
      {:ok, view, _html} = live(with_session_actor(conn, unknown), "/acting-as/shared")

      html = await_stream(view, "Ada")
      refute html =~ ~s(aria-current="true")

      assigns = :sys.get_state(view.pid).socket.assigns
      refute assigns.a2ui_actor
      # the raw session id stays for the picker's aria comparison
      assert assigns.current_id == unknown
    end

    test "standalone-session mounting still works (its own live_session)", %{conn: conn} do
      ada = roster("Ada")

      {:ok, view, html} = live(with_session_actor(conn, ada.id), "/acting-as")

      assert html =~ "Acting as"
      html = await_stream(view, "Ada")
      assert html =~ ~s(aria-current="true")

      assigns = :sys.get_state(view.pid).socket.assigns
      # no on_mount configured for the standalone route: no hook assigns,
      # the picker works from the session alone
      assert assigns.current_id == ada.id
      refute Map.has_key?(assigns, :a2ui_actor)
    end

    test "the picker works without host actor configuration", %{conn: conn} do
      Application.put_env(:ash_a2ui, :actor, nil)

      {:ok, _view, html} = live(conn, "/acting-as/shared")
      assert html =~ "Acting as"
    end
  end
end
