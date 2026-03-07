defmodule Goodtap.Games do
  import Ecto.Query, warn: false
  alias Goodtap.Repo
  alias Goodtap.Games.Game

  def list_active_games_for_user(user_id) do
    Game
    |> where([g], g.status != "ended")
    |> where([g], g.host_id == ^user_id or g.opponent_id == ^user_id)
    |> order_by([g], desc: g.inserted_at)
    |> preload([:host, :opponent])
    |> Repo.all()
  end

  def get_game!(id), do: Repo.get!(Game, id) |> Repo.preload([:host, :opponent])

  def get_game(id) do
    case Repo.get(Game, id) do
      nil -> nil
      game -> Repo.preload(game, [:host, :opponent])
    end
  end

  def create_game(host) do
    id = generate_id()

    %Game{}
    |> Game.changeset(%{
      id: id,
      host_id: host.id,
      status: "waiting",
      game_state: %{"host_deck_id" => nil, "opponent_deck_id" => nil}
    })
    |> Repo.insert()
  end

  def join_game(game, opponent) do
    game
    |> Game.changeset(%{opponent_id: opponent.id, status: "setup"})
    |> Repo.update()
  end

  def set_host_deck(game, deck_id) do
    new_state = Map.put(game.game_state || %{}, "host_deck_id", deck_id)

    game
    |> Game.changeset(%{game_state: new_state})
    |> Repo.update()
  end

  def set_opponent_deck(game, deck_id) do
    new_state = Map.put(game.game_state || %{}, "opponent_deck_id", deck_id)

    game
    |> Game.changeset(%{game_state: new_state})
    |> Repo.update()
  end

  def update_game_state(game, new_state) do
    game
    |> Game.changeset(%{game_state: new_state})
    |> Repo.update()
  end

  def start_game(game) do
    game
    |> Game.changeset(%{status: "active"})
    |> Repo.update()
  end

  def end_game(game) do
    Repo.delete(game)
  end

  def delete_game(game) do
    Repo.delete(game)
  end

  # Begin sideboarding phase: store current state in game_state for restart
  def start_sideboarding(game) do
    new_state =
      (game.game_state || %{})
      |> Map.put("sideboard_ready", %{"host" => false, "opponent" => false})

    game
    |> Game.changeset(%{game_state: new_state, status: "sideboarding"})
    |> Repo.update()
  end

  # Mark a player as ready and store their resolved card list (from in-memory sideboard edits).
  # card_spec is {card_names, commander_name, deck_id}.
  # Reloads from DB first to avoid overwriting the other player's data.
  def submit_sideboard_with_card_list(game, player_role, {card_names, commander_name, deck_id}) do
    fresh = get_game!(game.id)
    state = fresh.game_state || %{}
    ready = Map.get(state, "sideboard_ready", %{})
    card_lists = Map.get(state, "sideboard_card_lists", %{})

    new_state =
      state
      |> Map.put("sideboard_ready", Map.put(ready, player_role, true))
      |> Map.put("sideboard_card_lists", Map.put(card_lists, player_role, %{
        "card_names" => card_names,
        "commander_name" => commander_name,
        "deck_id" => deck_id
      }))

    fresh
    |> Game.changeset(%{game_state: new_state})
    |> Repo.update()
  end

  def both_sideboard_ready?(game) do
    ready = get_in(game.game_state, ["sideboard_ready"]) || %{}
    Map.get(ready, "host") == true && Map.get(ready, "opponent") == true
  end

  def maybe_start_game(game) do
    state = game.game_state || %{}
    host_deck = state["host_deck_id"]
    opponent_deck = state["opponent_deck_id"]

    if host_deck && opponent_deck && game.opponent_id do
      {:start, game}
    else
      {:wait, game}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  def broadcast_game_update(game) do
    Phoenix.PubSub.broadcast(Goodtap.PubSub, "game:#{game.id}", {:game_updated, game})
  end

  def broadcast_game_started(game) do
    Phoenix.PubSub.broadcast(Goodtap.PubSub, "game:#{game.id}", {:game_started, game})
  end

  def broadcast_game_state(game_id, game_state) do
    Phoenix.PubSub.broadcast(
      Goodtap.PubSub,
      "game:#{game_id}",
      {:game_state_updated, game_state}
    )
  end

  def broadcast_game_ended(game_id) do
    Phoenix.PubSub.broadcast(Goodtap.PubSub, "game:#{game_id}", :game_ended)
  end

  def broadcast_sideboarding_started(game) do
    Phoenix.PubSub.broadcast(Goodtap.PubSub, "game:#{game.id}", {:sideboarding_started, game})
  end

  def broadcast_game_restarted(game) do
    Phoenix.PubSub.broadcast(Goodtap.PubSub, "game:#{game.id}", {:game_restarted, game})
  end

  def subscribe_to_game(game_id) do
    Phoenix.PubSub.subscribe(Goodtap.PubSub, "game:#{game_id}")
  end
end
