defmodule GoodtapWeb.GameSetupLive do
  use GoodtapWeb, :live_view

  alias Goodtap.{Games, Decks}
  alias Goodtap.GameEngine.State, as: GameEngineState

  def mount(%{"id" => id}, _session, socket) do
    case Games.get_game(id) do
      nil -> {:ok, push_navigate(socket, to: ~p"/games")}
      game -> mount_game(game, socket)
    end
  end

  defp mount_game(game, socket) do
    user = socket.assigns.current_scope.user

    # Redirect if the game has started
    if game.status == "active" do
      {:ok, push_navigate(socket, to: ~p"/games/#{game.id}/play")}
    else
      game =
        cond do
          # Already a player — no action needed
          Games.player_key_for(game, user.id) != nil ->
            game

          # Room available — join
          length(game.game_players) < game.max_players ->
            case Games.join_game(game, user) do
              {:ok, updated, _key} ->
                Games.broadcast_game_update(updated)
                updated
              {:error, :full} ->
                game
              _ ->
                game
            end

          # Full — redirect
          true ->
            nil
        end

      if is_nil(game) do
        {:ok,
         socket
         |> put_flash(:error, "This game is full.")
         |> push_navigate(to: ~p"/games")}
      else
        Games.subscribe_to_game(game.id)
        decks = Decks.list_user_decks(user.id)
        my_role = Games.player_key_for(game, user.id)
        invite_url = GoodtapWeb.Endpoint.url() <> ~p"/games/join/#{game.id}"

        {:ok,
         assign(socket,
           game: game,
           my_role: my_role,
           decks: decks,
           invite_url: invite_url,
           page_title: "Game Setup",
           selected_deck_id: nil
         )}
      end
    end
  end

  def handle_info({:game_updated, game}, socket) do
    if game.status == "active" do
      {:noreply, push_navigate(socket, to: ~p"/games/#{game.id}/play")}
    else
      {:noreply, assign(socket, game: game)}
    end
  end

  def handle_info({:game_started, game}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/games/#{game.id}/play")}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  def handle_event("select_deck", %{"deck_id" => deck_id}, socket) do
    game = socket.assigns.game
    my_role = socket.assigns.my_role

    case Games.set_player_deck(game, my_role, deck_id) do
      {:ok, updated_game} ->
        updated_game = Games.get_game!(updated_game.id)
        Games.broadcast_game_update(updated_game)

        case Games.maybe_start_game(updated_game) do
          {:start, _} ->
            deck_ids = get_in(updated_game.game_state, ["deck_ids"]) || %{}
            players_with_keys = Enum.map(updated_game.game_players, &{&1.player_key, &1.user})
            game_state = GameEngineState.initialize(players_with_keys, deck_ids)

            {:ok, started_game} = Games.update_game_state(updated_game, game_state)
            {:ok, started_game} = Games.start_game(started_game)

            Games.broadcast_game_started(started_game)

            {:noreply, push_navigate(socket, to: ~p"/games/#{started_game.id}/play")}

          {:wait, _} ->
            {:noreply, assign(socket, game: updated_game, selected_deck_id: deck_id)}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to select deck")}
    end
  end

  defp deck_id_for(game, player_key) do
    get_in(game.game_state, ["deck_ids", player_key])
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold mb-8">Game Setup</h1>

      <%!-- Invite Section --%>
      <div class="bg-gray-800 rounded-xl p-6 mb-6">
        <h2 class="text-lg font-semibold mb-3">
          Invite Players ({length(@game.game_players)}/{@game.max_players} joined)
        </h2>
        <div class="flex gap-2">
          <input
            type="text"
            value={@invite_url}
            readonly
            class="input input-bordered flex-1 bg-gray-700 text-sm"
            id="invite-url-input"
          />
          <button
            id="copy-invite-btn"
            phx-hook="CopyToClipboard"
            data-copy-text={@invite_url}
            class="btn btn-outline btn-sm"
          >
            Copy
          </button>
        </div>
      </div>

      <%!-- Player Status --%>
      <div class="bg-gray-800 rounded-xl p-6 mb-6">
        <h2 class="text-lg font-semibold mb-4">Players</h2>

        <div class="space-y-3">
          <%= for gp <- Enum.sort_by(@game.game_players, & &1.player_key) do %>
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <div class="w-2 h-2 rounded-full bg-green-500"></div>
                <span>
                  {gp.user.username}
                  {if gp.player_key == "p1", do: " (Host)", else: ""}
                  {if gp.player_key == @my_role, do: " (You)", else: ""}
                </span>
              </div>
              <span class={if deck_id_for(@game, gp.player_key), do: "text-green-400", else: "text-yellow-400"}>
                {if deck_id_for(@game, gp.player_key), do: "Deck selected", else: "Choosing deck..."}
              </span>
            </div>
          <% end %>

          <%= for _i <- (length(@game.game_players) + 1)..@game.max_players do %>
            <div class="flex items-center gap-2 text-gray-500">
              <div class="w-2 h-2 rounded-full bg-gray-600"></div>
              <span>Waiting for player...</span>
            </div>
          <% end %>
        </div>

        <div
          :if={length(@game.game_players) == @game.max_players &&
            Enum.all?(@game.game_players, &deck_id_for(@game, &1.player_key))}
          class="mt-4 text-center text-green-400 font-medium"
        >
          Starting game...
        </div>
      </div>

      <%!-- Deck Selection --%>
      <div class="bg-gray-800 rounded-xl p-6">
        <h2 class="text-lg font-semibold mb-4">Select Your Deck</h2>

        <div :if={@decks == []} class="text-gray-400 text-sm">
          You have no decks.
          <.link navigate={~p"/decks"} class="text-purple-400 hover:underline">
            Import a deck first.
          </.link>
        </div>

        <div class="space-y-2">
          <%= for deck <- @decks do %>
            <button
              phx-click="select_deck"
              phx-value-deck_id={deck.id}
              class={[
                "w-full text-left p-3 rounded-lg border transition-colors",
                if(deck_id_for(@game, @my_role) == to_string(deck.id),
                  do: "border-purple-500 bg-purple-900/30",
                  else: "border-gray-600 hover:border-gray-400"
                )
              ]}
            >
              <div class="font-medium">{deck.name}</div>
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
