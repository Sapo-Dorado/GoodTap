defmodule Goodtap.GameEngine.State do
  alias Goodtap.Catalog
  alias Goodtap.Decks

  @double_faced_layouts ["transform", "modal_dfc", "double_faced_token", "reversible_card"]

  @doc """
  Initialize full game state when both players have selected decks.
  Returns the game_state map ready to be stored in the Game record.
  """
  def initialize(host, opponent, host_deck_id, opponent_deck_id) do
    host_state = build_player_state(host, host_deck_id)
    opponent_state = build_player_state(opponent, opponent_deck_id)

    %{
      "host" => host_state,
      "opponent" => opponent_state
    }
  end

  defp build_player_state(user, deck_id) do
    card_ids = Decks.expand_deck_card_ids(deck_id)
    cards_by_id = Catalog.list_cards_by_ids(Enum.uniq(card_ids))
    card_map = Map.new(cards_by_id, &{&1.id, &1})

    instances =
      card_ids
      |> Enum.map(fn card_id ->
        card = Map.fetch!(card_map, card_id)
        build_card_instance(card)
      end)
      |> Enum.shuffle()

    {hand, deck} = Enum.split(instances, 7)

    %{
      "user_id" => user.id,
      "username" => user.username,
      "life" => 20,
      "trackers" => [],
      "deck_id" => deck_id,
      "zones" => %{
        "hand" => hand,
        "deck" => deck,
        "battlefield" => [],
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
      "tapped" => false
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
    "https://cards.scryfall.io/normal/back/0/a/0aeebaf5-8c7d-4636-9e82-8c27447861f7.jpg"
  end

  @doc """
  Determine the display image URL for a card given viewer perspective.
  """
  def card_display_url(card_instance, viewer_role, owner_role, zone) do
    cond do
      hidden_from_viewer?(viewer_role, owner_role, zone) ->
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
