defmodule GoodtapWeb.GameListLive do
  use GoodtapWeb, :live_view

  alias Goodtap.Games

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    games = Games.list_active_games_for_user(user.id)

    {:ok, assign(socket, games: games, page_title: "My Games")}
  end

  def handle_event("new_game", _params, socket) do
    user = socket.assigns.current_scope.user

    case Games.create_game(user) do
      {:ok, game} ->
        {:noreply, push_navigate(socket, to: ~p"/games/#{game.id}/setup")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create game")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold">My Games</h1>
        <button phx-click="new_game" class="btn btn-primary">
          + New Game
        </button>
      </div>

      <div :if={@games == []} class="text-center py-16 text-gray-400">
        <p class="text-lg">No active games.</p>
        <p class="text-sm mt-2">Start a new game to play with a friend!</p>
      </div>

      <div class="space-y-3">
        <%= for game <- @games do %>
          <div class="bg-gray-800 rounded-lg p-4 flex items-center justify-between">
            <div>
              <div class="font-medium">
                Game vs
                <%= cond do %>
                  <% game.host.id == @current_scope.user.id && game.opponent -> %>
                    {game.opponent.username}
                  <% game.host.id == @current_scope.user.id -> %>
                    <span class="text-yellow-400">Waiting for opponent...</span>
                  <% true -> %>
                    {game.host.username}
                <% end %>
              </div>
              <div class="text-sm text-gray-400 mt-1">
                Status: <span class="capitalize">{game.status}</span>
              </div>
            </div>
            <div>
              <%= if game.status in ["waiting", "setup"] do %>
                <.link navigate={~p"/games/#{game.id}/setup"} class="btn btn-sm btn-outline">
                  Setup
                </.link>
              <% else %>
                <.link navigate={~p"/games/#{game.id}/play"} class="btn btn-sm btn-primary">
                  Play
                </.link>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
