defmodule Goodtap.GameEngine.State do
  alias Goodtap.Catalog
  alias Goodtap.Decks

  @double_faced_layouts ["transform", "modal_dfc", "double_faced_token", "reversible_card"]

  @doc """
  Initialize full game state when both players have selected decks.
  Returns the game_state map ready to be stored in the Game record.
  """
  def initialize(host, opponent, host_deck_id, opponent_deck_id, opts \\ []) do
    host_state = build_player_state(host, host_deck_id)
    opponent_state = build_player_state(opponent, opponent_deck_id)

    base = %{"host" => host_state, "opponent" => opponent_state}

    if Keyword.get(opts, :roll_die, true) do
      host_roll = Enum.sum(Enum.map(1..2, fn _ -> :rand.uniform(6) end))
      opponent_roll = Enum.sum(Enum.map(1..2, fn _ -> :rand.uniform(6) end))
      Map.put(base, "die_roll", %{"host" => host_roll, "opponent" => opponent_roll})
    else
      base
    end
  end

  defp build_player_state(user, deck_id) do
    card_names = Decks.expand_deck_card_names(deck_id)
    commander_entry = Decks.get_commander(deck_id)

    all_names = if commander_entry, do: [commander_entry.card_name | card_names], else: card_names
    cards = Catalog.list_cards_by_names(Enum.uniq(all_names))
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

    {hand, deck} = Enum.split(instances, 7)

    # Place commander on battlefield at a fixed initial position
    battlefield =
      if commander_entry do
        case Map.fetch(card_map, commander_entry.card_name) do
          {:ok, card} ->
            commander_instance =
              build_card_instance(card)
              |> Map.put("x", 0.5)
              |> Map.put("y", 0.5)

            [commander_instance]

          :error ->
            require Logger
            Logger.warning("Commander not found in catalog: #{inspect(commander_entry.card_name)}")
            []
        end
      else
        []
      end

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

  def build_card_instance(card) do
    is_dfc = card.layout in @double_faced_layouts

    %{
      "instance_id" => Ecto.UUID.generate(),
      "card_id" => card.id,
      "name" => card.name,
      "is_token" => card.layout == "token",
      "is_face_down" => false,
      "active_face" => 0,
      "is_double_faced" => is_dfc,
      "image_uris" => extract_image_uris(card.data),
      "counters" => [],
      "tapped" => false,
      "known" => false
    }
  end

  def build_token_instance(card) do
    card
    |> build_card_instance()
    |> Map.put("is_token", true)
    |> Map.put("instance_id", Ecto.UUID.generate())
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
  Determine the display image URL for a card given viewer perspective.
  """
  def card_display_url(card_instance, viewer_role, owner_role, zone) do
    cond do
      hidden_from_viewer?(viewer_role, owner_role, zone) ->
        card_back_url()

      zone == "deck" and card_instance["known"] != true ->
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
    viewer_role != owner_role and zone in ["hand", "deck"]
  end
end
