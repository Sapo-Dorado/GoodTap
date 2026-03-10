defmodule GoodtapWeb.GameSetupLiveTest do
  use GoodtapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Goodtap.AccountsFixtures

  alias Goodtap.Games

  setup do
    host = user_fixture()
    guest = user_fixture()
    {:ok, game} = Games.create_game(host, max_players: 2)
    %{host: host, guest: guest, game: game}
  end

  test "existing player sees new player immediately when they join", %{conn: conn, host: host, guest: guest, game: game} do
    host_conn = log_in_user(conn, host)
    {:ok, host_view, _html} = live(host_conn, ~p"/games/#{game.id}/setup")

    assert render(host_view) =~ "1/2 joined"

    guest_conn = log_in_user(build_conn(), guest)
    {:ok, _guest_view, _html} = live(guest_conn, ~p"/games/#{game.id}/setup")

    # Host's view should update without a refresh
    assert render(host_view) =~ "2/2 joined"
  end

  test "waiting for player slots decrease as players join", %{conn: conn, host: host, guest: guest, game: game} do
    host_conn = log_in_user(conn, host)
    {:ok, host_view, _html} = live(host_conn, ~p"/games/#{game.id}/setup")

    assert render(host_view) =~ "Waiting for player"

    guest_conn = log_in_user(build_conn(), guest)
    {:ok, _guest_view, _html} = live(guest_conn, ~p"/games/#{game.id}/setup")

    refute render(host_view) =~ "Waiting for player"
  end

  test "guest sees themselves in the player list after joining", %{conn: conn, guest: guest, game: game} do
    guest_conn = log_in_user(conn, guest)
    {:ok, guest_view, _html} = live(guest_conn, ~p"/games/#{game.id}/setup")

    assert render(guest_view) =~ guest.username
  end
end
