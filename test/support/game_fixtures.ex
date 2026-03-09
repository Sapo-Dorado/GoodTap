defmodule Goodtap.GameFixtures do
  @moduledoc """
  Minimal in-memory game state builders for unit tests.
  No database access — pure map construction.
  """

  def card(attrs \\ %{}) do
    Map.merge(
      %{
        "instance_id" => Ecto.UUID.generate(),
        "card_id" => "test-card-id",
        "name" => "Test Card",
        "is_token" => false,
        "is_face_down" => false,
        "active_face" => 0,
        "is_double_faced" => false,
        "image_uris" => %{"front" => "https://example.com/front.jpg", "back" => nil},
        "counters" => [],
        "tapped" => false,
        "known" => %{"host" => false, "opponent" => false}
      },
      attrs
    )
  end

  def token(attrs \\ %{}) do
    card(Map.merge(%{"is_token" => true}, attrs))
  end

  def game_state(host_attrs \\ %{}, opponent_attrs \\ %{}) do
    %{
      "host" => player_state(host_attrs),
      "opponent" => player_state(opponent_attrs),
      "z_counter" => 0
    }
  end

  def player_state(attrs \\ %{}) do
    Map.merge(
      %{
        "user_id" => "host-user-id",
        "username" => "testuser",
        "life" => 20,
        "trackers" => [],
        "deck_id" => "deck-id",
        "top_revealed" => false,
        "zones" => %{
          "hand" => [],
          "deck" => [],
          "battlefield" => [],
          "graveyard" => [],
          "exile" => []
        }
      },
      attrs
    )
  end

  # Build a game state with N cards in a zone for the given player.
  def with_cards_in(state, player, zone, cards) do
    put_in(state, [player, "zones", zone], cards)
  end
end
