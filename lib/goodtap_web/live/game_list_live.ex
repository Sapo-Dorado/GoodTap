defmodule GoodtapWeb.GameListLive do
  use GoodtapWeb, :live_view

  alias Goodtap.Games

  @game_limit 10

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    games = Games.list_active_games_for_user(user.id)

    {:ok, assign(socket, games: games, page_title: "My Games", confirm_delete: nil)}
  end

  def handle_event("new_game", _params, socket) do
    user = socket.assigns.current_scope.user
    games = socket.assigns.games

    if length(games) >= @game_limit do
      {:noreply, put_flash(socket, :error, "You can have at most #{@game_limit} active games.")}
    else
      case Games.create_game(user) do
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

    if game.host_id == user.id || game.opponent_id == user.id do
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
          <div class="relative group">
            <button class="btn btn-primary btn-disabled opacity-50 cursor-not-allowed" disabled>
              + New Game
            </button>
            <div class="absolute right-0 top-full mt-1 bg-gray-800 border border-gray-600 rounded px-3 py-2 text-sm text-gray-300 whitespace-nowrap opacity-0 group-hover:opacity-100 pointer-events-none z-10">
              Maximum 10 games reached
            </div>
          </div>
        <% else %>
          <button phx-click="new_game" class="btn btn-primary">
            + New Game
          </button>
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
