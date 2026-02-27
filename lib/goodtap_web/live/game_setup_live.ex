defmodule GoodtapWeb.GameSetupLive do
  use GoodtapWeb, :live_view

  alias Goodtap.{Games, Decks}
  alias Goodtap.GameEngine.State, as: GameEngineState

  def mount(%{"id" => id}, _session, socket) do
    game = Games.get_game!(id)
    user = socket.assigns.current_scope.user

    # Redirect if the game has started
    if game.status == "active" do
      {:ok, push_navigate(socket, to: ~p"/games/#{game.id}/play")}
    else
      # Join game if user is not host and game is waiting
      game =
        cond do
          game.host_id == user.id ->
            game

          is_nil(game.opponent_id) && game.status == "waiting" ->
            {:ok, updated} = Games.join_game(game, user)
            Games.broadcast_game_update(updated)
            updated

          game.opponent_id == user.id ->
            game

          true ->
            game
        end

      Games.subscribe_to_game(game.id)
      decks = Decks.list_user_decks(user.id)

      my_role = if game.host_id == user.id, do: :host, else: :opponent

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
    user = socket.assigns.current_scope.user
    game = socket.assigns.game

    result =
      if game.host_id == user.id do
        Games.set_host_deck(game, deck_id)
      else
        Games.set_opponent_deck(game, deck_id)
      end

    case result do
      {:ok, updated_game} ->
        Games.broadcast_game_update(updated_game)

        # Check if both players are ready to start
        case Games.maybe_start_game(updated_game) do
          {:start, _game} ->
            # Initialize full game state and start
            state_data = updated_game.game_state || %{}
            host_deck_id = state_data["host_deck_id"]
            opponent_deck_id = state_data["opponent_deck_id"]

            host = updated_game.host
            opponent = updated_game.opponent

            game_state =
              GameEngineState.initialize(host, opponent, host_deck_id, opponent_deck_id)

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

  defp my_deck_id(game, my_role) do
    state = game.game_state || %{}

    case my_role do
      :host -> state["host_deck_id"]
      :opponent -> state["opponent_deck_id"]
    end
  end

  defp opponent_deck_id(game, my_role) do
    state = game.game_state || %{}

    case my_role do
      :host -> state["opponent_deck_id"]
      :opponent -> state["host_deck_id"]
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold mb-8">Game Setup</h1>

      <%!-- Invite Section --%>
      <div class="bg-gray-800 rounded-xl p-6 mb-6">
        <h2 class="text-lg font-semibold mb-3">Invite Your Opponent</h2>
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
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <div class="w-2 h-2 rounded-full bg-green-500"></div>
              <span>{@game.host.username} (Host)</span>
            </div>
            <span class={if my_deck_id(@game, :host), do: "text-green-400", else: "text-yellow-400"}>
              {if my_deck_id(@game, :host), do: "Deck selected", else: "Choosing deck..."}
            </span>
          </div>

          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <div class={[
                "w-2 h-2 rounded-full",
                if(@game.opponent, do: "bg-green-500", else: "bg-gray-500")
              ]}>
              </div>
              <span>
                {if @game.opponent, do: @game.opponent.username, else: "Waiting for opponent..."}
              </span>
            </div>
            <span :if={@game.opponent} class={
              if my_deck_id(@game, :opponent), do: "text-green-400", else: "text-yellow-400"
            }>
              {if my_deck_id(@game, :opponent), do: "Deck selected", else: "Choosing deck..."}
            </span>
          </div>
        </div>

        <div
          :if={@game.opponent && my_deck_id(@game, :host) && my_deck_id(@game, :opponent)}
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
                if(my_deck_id(@game, @my_role) == to_string(deck.id),
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
