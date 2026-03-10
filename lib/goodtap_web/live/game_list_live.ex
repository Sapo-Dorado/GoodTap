defmodule GoodtapWeb.GameListLive do
  use GoodtapWeb, :live_view

  alias Goodtap.Games

  @game_limit 10

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    games = Games.list_active_games_for_user(user.id)

    {:ok, assign(socket, games: games, page_title: "My Games", confirm_delete: nil)}
  end

  def handle_event("new_game", params, socket) do
    user = socket.assigns.current_scope.user
    games = socket.assigns.games
    max_players = String.to_integer(params["max_players"] || "2")

    if length(games) >= @game_limit do
      {:noreply, put_flash(socket, :error, "You can have at most #{@game_limit} active games.")}
    else
      case Games.create_game(user, max_players: max_players) do
        {:ok, game} ->
          {:noreply, push_navigate(socket, to: ~p"/games/#{game.id}/setup")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to create game")}
      end
    end
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, confirm_delete: id)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, confirm_delete: nil)}
  end

  def handle_event("delete_game", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    game = Games.get_game!(id)

    if Goodtap.Games.player_key_for(game, user.id) != nil do
      {:ok, _} = Games.delete_game(game)
      games = Enum.reject(socket.assigns.games, &(&1.id == id))
      {:noreply, assign(socket, games: games, confirm_delete: nil)}
    else
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold">My Games</h1>
        <%= if length(@games) >= 10 do %>
          <div
            style="cursor:not-allowed"
            onmouseenter="document.getElementById('new-game-tip').style.display='block'"
            onmouseleave="document.getElementById('new-game-tip').style.display='none'"
            onmousemove="(function(e){var t=document.getElementById('new-game-tip');t.style.left=(e.clientX-t.offsetWidth-10)+'px';t.style.top=(e.clientY+14)+'px';})(event)"
          >
            <button class="btn btn-primary opacity-50 cursor-not-allowed" disabled style="pointer-events:none">
              + New Game
            </button>
          </div>
          <div
            id="new-game-tip"
            style="display:none; position:fixed; z-index:9999; pointer-events:none;"
            class="bg-gray-800 border border-gray-600 rounded px-3 py-2 text-sm text-gray-300 whitespace-nowrap"
          >
            You can have at most 10 active games
          </div>
        <% else %>
          <form phx-submit="new_game" class="flex items-center gap-2">
            <select name="max_players" class="select select-sm bg-gray-700 border-gray-600">
              <option value="2">2 players</option>
              <option value="3">3 players</option>
              <option value="4">4 players</option>
              <option value="5">5 players</option>
              <option value="6">6 players</option>
            </select>
            <button type="submit" class="btn btn-primary">
              + New Game
            </button>
          </form>
        <% end %>
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
                <% others = Enum.reject(game.game_players, &(&1.user_id == @current_scope.user.id)) %>
                <%= cond do %>
                  <% others != [] -> %>
                    Game vs {Enum.map_join(others, ", ", & &1.user.username)}
                  <% true -> %>
                    <span class="text-yellow-400">Waiting for players... ({length(game.game_players)}/{game.max_players})</span>
                <% end %>
              </div>
              <div class="text-sm text-gray-400 mt-1">
                Status: <span class="capitalize">{game.status}</span>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <%= if game.status in ["waiting", "setup"] do %>
                <.link navigate={~p"/games/#{game.id}/setup"} class="btn btn-sm btn-outline">
                  Setup
                </.link>
              <% else %>
                <.link navigate={~p"/games/#{game.id}/play"} class="btn btn-sm btn-primary">
                  Play
                </.link>
              <% end %>
              <button
                phx-click="confirm_delete"
                phx-value-id={game.id}
                class="btn btn-sm btn-ghost text-red-400 hover:text-red-300"
                title="Delete game"
              >
                ✕
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Delete Confirmation Modal --%>
      <div
        :if={@confirm_delete}
        class="fixed inset-0 bg-black/70 flex items-center justify-center z-50"
      >
        <div class="bg-gray-800 rounded-xl p-6 w-full max-w-sm mx-4 shadow-2xl">
          <h2 class="text-lg font-bold mb-2">Delete Game?</h2>
          <p class="text-gray-400 text-sm mb-6">This will permanently delete the game for both players.</p>
          <div class="flex gap-3 justify-end">
            <button phx-click="cancel_delete" class="btn btn-ghost btn-sm">Cancel</button>
            <button
              phx-click="delete_game"
              phx-value-id={@confirm_delete}
              class="btn btn-error btn-sm"
            >
              Delete
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
