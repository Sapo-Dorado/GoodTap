defmodule Goodtap.GameEngine.State do
  alias Goodtap.Catalog
  alias Goodtap.Decks

  @double_faced_layouts ["transform", "modal_dfc", "double_faced_token", "reversible_card"]

  @doc """
  Initialize full game state when both players have selected decks.
  Returns the game_state map ready to be stored in the Game record.
  """
  def initialize(host, opponent, host_deck_id, opponent_deck_id, opts \\ []) do
    host_state = build_player_state(host, host_deck_id, "host")
    opponent_state = build_player_state(opponent, opponent_deck_id, "opponent")
    build_game_state(host_state, opponent_state, opts)
  end

  @doc """
  Initialize game state with explicit card name lists (used for sideboard restarts
  so the underlying deck in the DB is never modified).
  card_specs is %{"host" => {card_names, commander_name, deck_id}, "opponent" => ...}
  """
  def initialize_with_card_lists(host, opponent, card_specs, opts \\ []) do
    host_state = build_player_state_from_names(host, card_specs["host"], "host")
    opponent_state = build_player_state_from_names(opponent, card_specs["opponent"], "opponent")
    build_game_state(host_state, opponent_state, opts)
  end

  defp build_game_state(host_state, opponent_state, opts) do
    base = %{"host" => host_state, "opponent" => opponent_state}

    if Keyword.get(opts, :roll_die, true) do
      host_dice = Enum.map(1..2, fn _ -> :rand.uniform(6) end)
      opponent_dice = Enum.map(1..2, fn _ -> :rand.uniform(6) end)
      host_total = Enum.sum(host_dice)
      opp_total = Enum.sum(opponent_dice)
      host_name = get_in(base, ["host", "username"]) || "host"
      opp_name = get_in(base, ["opponent", "username"]) || "opponent"
      t = System.system_time(:second)
      log = [
        %{"t" => t, "p" => "opponent", "u" => opp_name, "m" => "rolled a #{opp_total}"},
        %{"t" => t, "p" => "host", "u" => host_name, "m" => "rolled a #{host_total}"}
      ]
      base
      |> Map.put("die_roll", %{
        "host" => host_total,
        "host_dice" => host_dice,
        "opponent" => opp_total,
        "opponent_dice" => opponent_dice
      })
      |> Map.put("log", log)
    else
      base
    end
  end

  defp build_player_state_from_names(user, {card_names, commander_names, deck_id}, role) do
    commander_names = List.wrap(commander_names)
    all_names = Enum.uniq(card_names ++ commander_names)
    cards = Catalog.list_cards_by_names(all_names)
    card_map = Map.new(cards, &{&1.name, &1})

    instances =
      card_names
      |> Enum.flat_map(fn name ->
        case Map.fetch(card_map, name) do
          {:ok, card} -> [build_card_instance(card)]
          :error ->
            require Logger
            Logger.warning("Card not found in catalog, skipping: #{inspect(name)}")
            []
        end
      end)
      |> Enum.shuffle()

    {hand_raw, deck} = Enum.split(instances, 7)
    hand = Enum.map(hand_raw, &Map.put(&1, "known", %{"host" => role == "host", "opponent" => role == "opponent"}))

    battlefield =
      commander_names
      |> Enum.with_index()
      |> Enum.flat_map(fn {name, i} ->
        case Map.fetch(card_map, name) do
          {:ok, card} ->
            [build_card_instance(card) |> Map.put("x", 0.3 + i * 0.1) |> Map.put("y", 0.5)]
          :error ->
            require Logger
            Logger.warning("Starts-in-play card not found in catalog: #{inspect(name)}")
            []
        end
      end)

    %{
      "user_id" => user.id,
      "username" => user.username,
      "life" => 20,
      "trackers" => [],
      "deck_id" => deck_id,
      "zones" => %{
        "hand" => hand,
        "deck" => deck,
        "battlefield" => battlefield,
        "graveyard" => [],
        "exile" => []
      }
    }
  end

  defp build_player_state(user, deck_id, role) do
    deck_entries = Decks.expand_deck_card_names(deck_id)
    commander_entries = Decks.get_commanders(deck_id)
    commander_tuples = Enum.flat_map(commander_entries, fn dc ->
      List.duplicate({dc.card_name, dc.printing_id}, dc.quantity)
    end)

    all_names = Enum.uniq(Enum.map(deck_entries, &elem(&1, 0)) ++ Enum.map(commander_tuples, &elem(&1, 0)))
    cards = Catalog.list_cards_by_names(all_names)
    card_map = Map.new(cards, &{&1.name, &1})

    instances =
      deck_entries
      |> Enum.flat_map(fn {name, printing_id} ->
        case Map.fetch(card_map, name) do
          {:ok, card} -> [build_card_instance(card, printing_id)]
          :error ->
            require Logger
            Logger.warning("Card not found in catalog, skipping: #{inspect(name)}")
            []
        end
      end)
      |> Enum.shuffle()

    {hand_raw, deck} = Enum.split(instances, 7)
    hand = Enum.map(hand_raw, &Map.put(&1, "known", %{"host" => role == "host", "opponent" => role == "opponent"}))

    # Place all starts-in-play cards on battlefield
    battlefield =
      commander_tuples
      |> Enum.with_index()
      |> Enum.flat_map(fn {{name, printing_id}, i} ->
        case Map.fetch(card_map, name) do
          {:ok, card} ->
            [build_card_instance(card, printing_id) |> Map.put("x", 0.3 + i * 0.1) |> Map.put("y", 0.5)]
          :error ->
            require Logger
            Logger.warning("Starts-in-play card not found in catalog: #{inspect(name)}")
            []
        end
      end)

    %{
      "user_id" => user.id,
      "username" => user.username,
      "life" => 20,
      "trackers" => [],
      "deck_id" => deck_id,
      "zones" => %{
        "hand" => hand,
        "deck" => deck,
        "battlefield" => battlefield,
        "graveyard" => [],
        "exile" => []
      }
    }
  end

  def build_card_instance(card, printing_id \\ nil) do
    is_dfc = card.layout in @double_faced_layouts
    resolved_printing_id = printing_id || card.default_printing_id
    image_uris = printing_image_uris(card, resolved_printing_id) || extract_image_uris(card.data)

    %{
      "instance_id" => Ecto.UUID.generate(),
      "card_id" => card.id,
      "name" => card.name,
      "is_token" => card.layout == "token",
      "is_face_down" => false,
      "active_face" => 0,
      "is_double_faced" => is_dfc,
      "image_uris" => image_uris,
      "counters" => [],
      "tapped" => false,
      "known" => %{"host" => false, "opponent" => false}
    }
  end

  def build_token_instance(card, printing_id \\ nil) do
    card
    |> build_card_instance(printing_id)
    |> Map.put("is_token", true)
    |> Map.put("instance_id", Ecto.UUID.generate())
  end

  defp printing_image_uris(_card, nil), do: nil
  defp printing_image_uris(card, printing_id) do
    case Enum.find(card.printings, &(&1["id"] == printing_id)) do
      nil -> nil
      printing ->
        # Printing stores front image_uris; for DFC, get back from card.data
        front = get_in(printing, ["image_uris", "normal"])
        back = get_in(card.data, ["card_faces", Access.at(1), "image_uris", "normal"])
        %{"front" => front, "back" => back}
    end
  end

  defp extract_image_uris(card_data) do
    cond do
      Map.has_key?(card_data, "image_uris") ->
        %{
          "front" => get_in(card_data, ["image_uris", "normal"]),
          "back" => nil
        }

      match?(%{"card_faces" => [_, _ | _]}, card_data) ->
        [face0, face1 | _] = card_data["card_faces"]

        %{
          "front" => get_in(face0, ["image_uris", "normal"]),
          "back" => get_in(face1, ["image_uris", "normal"])
        }

      true ->
        %{"front" => nil, "back" => nil}
    end
  end

  @doc """
  Returns the card back URL used for face-down or hidden cards.
  """
  def card_back_url do
    "/images/CardBack.png"
  end

  @doc """
  Returns true if the card is known to the given role.
  Handles both the old boolean format and the new per-player map format.
  """
  def known_to?(card, role) do
    case card["known"] do
      true -> true
      false -> false
      nil -> false
      map when is_map(map) -> map[role] == true
    end
  end

  @doc """
  Determine the display image URL for a card given viewer perspective.
  """
  def card_display_url(card_instance, viewer_role, owner_role, zone) do
    cond do
      hidden_from_viewer?(viewer_role, owner_role, zone) ->
        card_back_url()

      zone == "deck" and not known_to?(card_instance, viewer_role) ->
        card_back_url()

      card_instance["is_face_down"] ->
        card_back_url()

      card_instance["active_face"] == 1 ->
        card_instance["image_uris"]["back"] || card_back_url()

      true ->
        card_instance["image_uris"]["front"] || card_back_url()
    end
  end

  defp hidden_from_viewer?(viewer_role, owner_role, zone) do
    viewer_role != owner_role and zone == "hand"
  end
end
