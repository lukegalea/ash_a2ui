# The whole file is Phoenix-only: under NO_PHOENIX the presence wrapper,
# the test presence module and the fixture LiveView don't exist, so nothing
# here should even compile.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.PresenceTest do
    @moduledoc """
    The presence contract: per-surface topic tracking keyed by (label +
    stable key), the list/untrack/subscribe helpers over a real
    `Phoenix.Presence` module, the PubSub-driven refresh contract end to
    end through the test endpoint (`mount_surface` + `handle_broadcast` +
    `PresenceBar`), and the nav active-state helper.
    """

    use ExUnit.Case, async: false

    import Phoenix.ConnTest
    import Phoenix.LiveViewTest

    @endpoint AshA2ui.Test.Endpoint
    @presence AshA2ui.Test.Presence

    describe "topic/1" do
      test "the surface id namespaces the topic (grouped by surface)" do
        assert AshA2ui.Presence.topic("consult-1") == "a2ui:surface:consult-1"
      end
    end

    describe "track / list / untrack" do
      test "one row per stable key with its label, sorted by key" do
        visitor("tracked-surface", "user-grace", "Grace Hopper")
        visitor("tracked-surface", "user-ada", "Ada Lovelace")

        assert [
                 %{key: "user-ada", label: "Ada Lovelace"},
                 %{key: "user-grace", label: "Grace Hopper"}
               ] = AshA2ui.Presence.list(@presence, "tracked-surface")
      end

      test "presences are grouped by surface: another surface sees nobody" do
        visitor("surface-a", "user-ada", "Ada Lovelace")

        assert [] = AshA2ui.Presence.list(@presence, "surface-b")
      end

      test "untrack removes the visitor before process death" do
        # ada tracks from THIS process, so untrack (which targets the
        # calling process) finds it; grace rides a spawned visitor
        AshA2ui.Presence.track(@presence, "untracked-surface", "user-ada", "Ada Lovelace")
        visitor("untracked-surface", "user-grace", "Grace Hopper")

        AshA2ui.Presence.untrack(@presence, "untracked-surface", "user-ada")

        assert [%{key: "user-grace"}] = AshA2ui.Presence.list(@presence, "untracked-surface")
      end

      test "extra metadata rides along; label wins over the key when metas lack it" do
        visitor("meta-surface", "user-ada", "Ada Lovelace", %{"role" => "vet"})

        assert [%{key: "user-ada", label: "Ada Lovelace"}] =
                 AshA2ui.Presence.list(@presence, "meta-surface")
      end
    end

    describe "subscribe/2 + the refresh contract" do
      test "a subscriber receives the presence broadcasts for its surface" do
        AshA2ui.Presence.subscribe(@presence, "broadcast-surface")

        visitor("broadcast-surface", "user-ada", "Ada Lovelace")

        assert_receive %Phoenix.Socket.Broadcast{
                         topic: "a2ui:surface:broadcast-surface",
                         event: "presence_diff"
                       },
                       1_000
      end
    end

    describe "surface LiveView wiring (through the test endpoint)" do
      setup do
        [conn: build_conn()]
      end

      test "mount_surface tracks the visitor, seeds the bar, and renders the nav", %{conn: conn} do
        {:ok, view, html} = live(conn, "/presence?surface=wired&key=user-ada&label=Ada")

        # the visitor's own avatar (initials + aria-label), seeded by the
        # connected mount's list
        html = await_avatar(view, html, ~s(title="Ada"))

        assert html =~ ~s(aria-label="Ada is viewing this surface")
        assert html =~ ~s(aria-label="People viewing this surface")

        # the nav contract: the current page's link carries aria-current,
        # the other doesn't
        assert html =~ ~s(<a href="/presence" aria-current="page">)
        assert html =~ ~s(<a href="/presence/patients">)
      end

      test "a second visitor arrives on every connected viewer via PubSub", %{conn: conn} do
        {:ok, view_ada, _html} = live(conn, "/presence?surface=shared&key=user-ada&label=Ada")

        {:ok, _view_grace, html_grace} =
          live(conn, "/presence?surface=shared&key=user-grace&label=Grace")

        # the late joiner's mount seeded both rows
        assert html_grace =~ ~s(title="Ada")
        assert html_grace =~ ~s(title="Grace")

        # and the first viewer refreshed from the presence_diff broadcast
        html_ada = render(view_ada)
        assert html_ada =~ ~s(title="Ada")
        await_avatar(view_ada, html_ada, ~s(title="Grace"))
      end

      test "the +N overflow chip collapses the stack beyond max_visible", %{conn: conn} do
        visitor("overflow-surface", "user-a", "Ann")
        visitor("overflow-surface", "user-b", "Bob")
        visitor("overflow-surface", "user-c", "Cleo")

        {:ok, view, html} =
          live(conn, "/presence?surface=overflow-surface&key=user-d&label=Dave")

        # four presences against max_visible 3: Dave + the +1 chip
        html = await_avatar(view, html, ~s(title="Dave"))

        assert html =~ "+1"
        assert html =~ ~s(aria-label="1 more people viewing this surface")
      end

      test "leaving is reflected on the other viewers", %{conn: conn} do
        {:ok, view_ada, _html} = live(conn, "/presence?surface=leaving&key=user-ada&label=Ada")

        {:ok, view_grace, _html} =
          live(conn, "/presence?surface=leaving&key=user-grace&label=Grace")

        assert render(view_grace) =~ ~s(title="Ada")

        # the grace LiveView process dies -> presence untracks via DOWN ->
        # ada's view refreshes on the presence_diff broadcast
        GenServer.stop(view_grace.pid)

        html_ada = await_absent(view_ada, render(view_ada), ~s(title="Grace"))
        assert html_ada =~ ~s(title="Ada")
      end
    end

    describe "PresenceBar rendering" do
      test "initials circles, per-avatar aria labels, and the overflow chip" do
        html =
          render_component(&AshA2ui.PresenceBar.bar/1, %{
            presences: [
              %{key: "u1", label: "Ada Lovelace"},
              %{key: "u2", label: "Grace Hopper"},
              %{key: "u3", label: "Alan"}
            ],
            max_visible: 2
          })

        assert html =~ ~s(aria-label="People viewing this surface")
        assert html =~ "AL"
        assert html =~ ~s(aria-label="Ada Lovelace is viewing this surface")
        assert html =~ "GH"
        refute html =~ ~s(aria-label="Alan is viewing this surface")
        assert html =~ "+1"
        assert html =~ ~s(aria-label="1 more people viewing this surface")
      end

      test "an empty surface renders the labelled, avatar-less stack" do
        html = render_component(&AshA2ui.PresenceBar.bar/1, %{presences: []})

        assert html =~ ~s(aria-label="People viewing this surface")
        refute html =~ "title="
      end

      test "initials: first letter of the first two words, uppercased" do
        assert AshA2ui.PresenceBar.initials("Ada Lovelace") == "AL"
        assert AshA2ui.PresenceBar.initials("grace") == "G"
        assert AshA2ui.PresenceBar.initials("ada  lovelace-hopper") == "AL"
        assert AshA2ui.PresenceBar.initials("") == "?"
        assert AshA2ui.PresenceBar.initials("   ") == "?"
      end
    end

    describe "nav_current_attrs/2" do
      test "aria-current=page only for the rendered path" do
        assert %{"aria-current" => "page"} =
                 AshA2ui.PresenceBar.nav_current_attrs("/clinic/schedule", "/clinic/schedule")

        assert %{"aria-current" => nil} =
                 AshA2ui.PresenceBar.nav_current_attrs("/clinic/schedule", "/clinic/patients")
      end
    end

    # --- helpers -------------------------------------------------------------

    # A live visitor tracked under (surface, key): a linked process that
    # tracks itself and lives until the test process exits.
    defp visitor(surface_id, key, label, metadata \\ %{}) do
      parent = self()

      spawn_link(fn ->
        AshA2ui.Presence.track(@presence, surface_id, key, label, metadata)
        send(parent, {:tracked, key})

        receive do
          :stop -> :ok
        end
      end)

      assert_receive {:tracked, ^key}, 1_000
    end

    # Polls a LiveView render until the expected markup lands (the
    # presence_diff round trip is async).
    defp await_avatar(view, html, markup, attempts \\ 50)

    defp await_avatar(_view, html, _markup, 0), do: html

    defp await_avatar(view, html, markup, attempts) do
      if html =~ markup do
        html
      else
        Process.sleep(10)
        await_avatar(view, render(view), markup, attempts - 1)
      end
    end

    defp await_absent(view, html, markup, attempts \\ 50)

    defp await_absent(_view, _html, markup, 0), do: flunk("expected #{markup} to disappear")

    defp await_absent(view, html, markup, attempts) do
      if html =~ markup do
        Process.sleep(10)
        await_absent(view, render(view), markup, attempts - 1)
      else
        html
      end
    end
  end
end
