defmodule Goodtap.Games do
  import Ecto.Query, warn: false
  alias Goodtap.Repo
  alias Goodtap.Games.{Game, GamePlayer}

  def list_active_games_for_user(user_id) do
    Game
    |> join(:inner, [g], gp in GamePlayer, on: gp.game_id == g.id)
    |> where([g, gp], gp.user_id == ^user_id)
    |> where([g], g.status != "ended")
    |> order_by([g], desc: g.inserted_at)
    |> preload([:host, game_players: :user])
    |> Repo.all()
  end

  def get_game!(id) do
    Repo.get!(Game, id) |> Repo.preload([:host, game_players: :user])
  end

  def get_game(id) do
    case Repo.get(Game, id) do
      nil -> nil
      game -> Repo.preload(game, [:host, game_players: :user])
    end
  end

  def create_game(host, opts \\ []) do
    max_players = Keyword.get(opts, :max_players, 2)
    id = generate_id()

    Repo.transaction(fn ->
      game =
        %Game{}
        |> Game.changeset(%{
          id: id,
          host_id: host.id,
          status: "waiting",
          max_players: max_players,
          game_state: %{"deck_ids" => %{"p1" => nil}}
        })
        |> Repo.insert!()

      %GamePlayer{}
      |> GamePlayer.changeset(%{game_id: id, user_id: host.id, player_key: "p1"})
      |> Repo.insert!()

      Repo.preload(game, [:host, game_players: :user])
    end)
  end

  # Adds a user to the game as the next available player key.
  # Returns {:ok, game, player_key} or {:error, :full} if the game is at capacity.
  def join_game(game, user) do
    existing_keys =
      game.game_players
      |> Enum.map(& &1.player_key)
      |> MapSet.new()

    # Already joined?
    if Enum.any?(game.game_players, &(&1.user_id == user.id)) do
      player_key = Enum.find(game.game_players, &(&1.user_id == user.id)).player_key
      {:ok, game, player_key}
    else
      next_key =
        1..game.max_players
        |> Enum.map(&"p#{&1}")
        |> Enum.find(&(&1 not in existing_keys))

      if next_key do
        Repo.transaction(fn ->
          %GamePlayer{}
          |> GamePlayer.changeset(%{game_id: game.id, user_id: user.id, player_key: next_key})
          |> Repo.insert!()

          new_deck_ids = Map.put(get_in(game.game_state, ["deck_ids"]) || %{}, next_key, nil)
          new_state = Map.put(game.game_state || %{}, "deck_ids", new_deck_ids)

          updated =
            game
            |> Game.changeset(%{game_state: new_state, status: "setup"})
            |> Repo.update!()
            |> Repo.preload([:host, game_players: :user])

          {updated, next_key}
        end)
        |> case do
          {:ok, {game, key}} -> {:ok, game, key}
          {:error, reason} -> {:error, reason}
        end
      else
        {:error, :full}
      end
    end
  end

  def set_player_deck(game, player_key, deck_id) do
    existing = get_in(game.game_state, ["deck_ids"]) || %{}
    new_state = Map.put(game.game_state, "deck_ids", Map.put(existing, player_key, deck_id))

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

  # Returns {:start, game} when all players have selected decks, {:wait, game} otherwise.
  def maybe_start_game(game) do
    deck_ids = get_in(game.game_state, ["deck_ids"]) || %{}
    player_keys = Enum.map(game.game_players, & &1.player_key)
    all_have_decks = length(player_keys) == game.max_players &&
      Enum.all?(player_keys, &(Map.get(deck_ids, &1) != nil))

    if all_have_decks do
      {:start, game}
    else
      {:wait, game}
    end
  end

  # Begin sideboarding phase: reset sideboard_ready for all players.
  def start_sideboarding(game) do
    player_keys = Enum.map(game.game_players, & &1.player_key)
    sideboard_ready = Map.new(player_keys, &{&1, false})

    new_state =
      (game.game_state || %{})
      |> Map.put("sideboard_ready", sideboard_ready)

    game
    |> Game.changeset(%{game_state: new_state, status: "sideboarding"})
    |> Repo.update()
  end

  # Mark a player as ready with their resolved card list.
  def submit_sideboard_with_card_list(game, player_key, {card_names, commander_names, deck_id}) do
    fresh = get_game!(game.id)
    state = fresh.game_state || %{}
    ready = Map.get(state, "sideboard_ready", %{})
    card_lists = Map.get(state, "sideboard_card_lists", %{})

    new_state =
      state
      |> Map.put("sideboard_ready", Map.put(ready, player_key, true))
      |> Map.put("sideboard_card_lists", Map.put(card_lists, player_key, %{
        "card_names" => card_names,
        "commander_names" => commander_names,
        "deck_id" => deck_id
      }))

    fresh
    |> Game.changeset(%{game_state: new_state})
    |> Repo.update()
  end

  def all_sideboard_ready?(game) do
    ready = get_in(game.game_state, ["sideboard_ready"]) || %{}
    player_keys = Enum.map(game.game_players, & &1.player_key)
    length(player_keys) > 0 && Enum.all?(player_keys, &(Map.get(ready, &1) == true))
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

  def broadcast_target_card(game_id, instance_id) do
    Phoenix.PubSub.broadcast(Goodtap.PubSub, "game:#{game_id}", {:target_card, instance_id})
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

  # Helper: return the player_key for a given user in this game, or nil.
  def player_key_for(game, user_id) do
    case Enum.find(game.game_players, &(&1.user_id == user_id)) do
      nil -> nil
      gp -> gp.player_key
    end
  end

  # Helper: return all player keys in join order.
  def player_keys(game) do
    game.game_players
    |> Enum.sort_by(& &1.player_key)
    |> Enum.map(& &1.player_key)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end
end
