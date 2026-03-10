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
        "known" => %{}
      },
      attrs
    )
  end

  def token(attrs \\ %{}) do
    card(Map.merge(%{"is_token" => true}, attrs))
  end

  # Builds a 2-player game state with "p1" and "p2" as player keys.
  def game_state(p1_attrs \\ %{}, p2_attrs \\ %{}) do
    %{
      "p1" => player_state(p1_attrs),
      "p2" => player_state(p2_attrs),
      "z_counter" => 0
    }
  end

  def player_state(attrs \\ %{}) do
    Map.merge(
      %{
        "user_id" => "test-user-id",
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
