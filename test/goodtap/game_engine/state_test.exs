defmodule Goodtap.GameEngine.StateTest do
  use ExUnit.Case, async: true

  alias Goodtap.GameEngine.State
  import Goodtap.GameFixtures

  describe "known_to?/2" do
    test "map format — true when role is true" do
      c = card(%{"known" => %{"p1" => true, "p2" => false}})
      assert State.known_to?(c, "p1")
      refute State.known_to?(c, "p2")
    end

    test "map format — false by default" do
      c = card(%{"known" => %{"p1" => false, "p2" => false}})
      refute State.known_to?(c, "p1")
      refute State.known_to?(c, "p2")
    end

    test "empty map — unknown to any role" do
      c = card(%{"known" => %{}})
      refute State.known_to?(c, "p1")
      refute State.known_to?(c, "p2")
    end

    test "nil known — treated as false" do
      c = card(%{"known" => nil})
      refute State.known_to?(c, "p1")
      refute State.known_to?(c, "p2")
    end
  end

  describe "all_player_keys/1" do
    test "returns sorted player keys" do
      state = game_state()
      assert State.all_player_keys(state) == ["p1", "p2"]
    end

    test "returns keys for N players" do
      state = %{
        "p1" => player_state(),
        "p2" => player_state(),
        "p3" => player_state(),
        "z_counter" => 0
      }
      assert State.all_player_keys(state) == ["p1", "p2", "p3"]
    end

    test "ignores non-player keys" do
      state = game_state() |> Map.put("die_roll", %{}) |> Map.put("log", [])
      assert State.all_player_keys(state) == ["p1", "p2"]
    end
  end

  describe "card_display_url/4" do
    @front_url "https://example.com/front.jpg"
    @back_url "https://example.com/back.jpg"

    def card_with_images(attrs \\ %{}) do
      card(Map.merge(%{"image_uris" => %{"front" => @front_url, "back" => @back_url}}, attrs))
    end

    test "owner sees front of their own hand card" do
      c = card_with_images(%{"known" => %{"p1" => true, "p2" => false}})
      assert State.card_display_url(c, "p1", "p1", "hand") == @front_url
    end

    test "opponent cannot see owner's hand card — shows card back" do
      c = card_with_images()
      assert State.card_display_url(c, "p2", "p1", "hand") == State.card_back_url()
    end

    test "face-down card shows back regardless of zone or knowledge" do
      c = card_with_images(%{"is_face_down" => true, "known" => %{"p1" => true, "p2" => true}})
      assert State.card_display_url(c, "p1", "p1", "battlefield") == State.card_back_url()
    end

    test "active_face 1 shows back image" do
      c = card_with_images(%{"active_face" => 1})
      assert State.card_display_url(c, "p1", "p1", "battlefield") == @back_url
    end

    test "active_face 1 with no back image falls back to card back" do
      c = card(Map.merge(%{"image_uris" => %{"front" => @front_url, "back" => nil}, "active_face" => 1}, %{}))
      assert State.card_display_url(c, "p1", "p1", "battlefield") == State.card_back_url()
    end

    test "battlefield card (face-up) shows front" do
      c = card_with_images(%{"known" => %{"p1" => true, "p2" => true}})
      assert State.card_display_url(c, "p1", "p1", "battlefield") == @front_url
      assert State.card_display_url(c, "p2", "p1", "battlefield") == @front_url
    end

    test "deck card not known to viewer shows back" do
      c = card_with_images(%{"known" => %{"p1" => false, "p2" => false}})
      assert State.card_display_url(c, "p1", "p1", "deck") == State.card_back_url()
    end

    test "deck card known to viewer (top_revealed) shows front" do
      c = card_with_images(%{"known" => %{"p1" => true, "p2" => true}})
      assert State.card_display_url(c, "p1", "p1", "deck") == @front_url
    end
  end

  describe "starting_life/1" do
    test "2-player game starts with 20 life" do
      assert State.starting_life(2) == 20
    end

    test "3-player game starts with 40 life" do
      assert State.starting_life(3) == 40
    end

    test "4-player game starts with 40 life" do
      assert State.starting_life(4) == 40
    end
  end
end
