defmodule Goodtap.GameEngine.StateTest do
  use ExUnit.Case, async: true

  alias Goodtap.GameEngine.State
  import Goodtap.GameFixtures

  describe "known_to?/2" do
    test "map format — true when role is true" do
      c = card(%{"known" => %{"host" => true, "opponent" => false}})
      assert State.known_to?(c, "host")
      refute State.known_to?(c, "opponent")
    end

    test "map format — false by default" do
      c = card(%{"known" => %{"host" => false, "opponent" => false}})
      refute State.known_to?(c, "host")
      refute State.known_to?(c, "opponent")
    end

    test "legacy boolean true — known to all" do
      c = card(%{"known" => true})
      assert State.known_to?(c, "host")
      assert State.known_to?(c, "opponent")
    end

    test "legacy boolean false — known to none" do
      c = card(%{"known" => false})
      refute State.known_to?(c, "host")
      refute State.known_to?(c, "opponent")
    end

    test "nil known — treated as false" do
      c = card(%{"known" => nil})
      refute State.known_to?(c, "host")
      refute State.known_to?(c, "opponent")
    end
  end

  describe "card_display_url/4" do
    @front_url "https://example.com/front.jpg"
    @back_url "https://example.com/back.jpg"

    def card_with_images(attrs \\ %{}) do
      card(Map.merge(%{"image_uris" => %{"front" => @front_url, "back" => @back_url}}, attrs))
    end

    test "owner sees front of their own hand card" do
      c = card_with_images(%{"known" => %{"host" => true, "opponent" => false}})
      assert State.card_display_url(c, "host", "host", "hand") == @front_url
    end

    test "opponent cannot see owner's hand card — shows card back" do
      c = card_with_images()
      assert State.card_display_url(c, "opponent", "host", "hand") == State.card_back_url()
    end

    test "face-down card shows back regardless of zone or knowledge" do
      c = card_with_images(%{"is_face_down" => true, "known" => %{"host" => true, "opponent" => true}})
      assert State.card_display_url(c, "host", "host", "battlefield") == State.card_back_url()
    end

    test "active_face 1 shows back image" do
      c = card_with_images(%{"active_face" => 1})
      assert State.card_display_url(c, "host", "host", "battlefield") == @back_url
    end

    test "active_face 1 with no back image falls back to card back" do
      c = card(Map.merge(%{"image_uris" => %{"front" => @front_url, "back" => nil}, "active_face" => 1}, %{}))
      assert State.card_display_url(c, "host", "host", "battlefield") == State.card_back_url()
    end

    test "battlefield card (face-up) shows front" do
      c = card_with_images(%{"known" => %{"host" => true, "opponent" => true}})
      assert State.card_display_url(c, "host", "host", "battlefield") == @front_url
      assert State.card_display_url(c, "opponent", "host", "battlefield") == @front_url
    end

    test "deck card not known to viewer shows back" do
      c = card_with_images(%{"known" => %{"host" => false, "opponent" => false}})
      assert State.card_display_url(c, "host", "host", "deck") == State.card_back_url()
    end

    test "deck card known to viewer (top_revealed) shows front" do
      c = card_with_images(%{"known" => %{"host" => true, "opponent" => true}})
      assert State.card_display_url(c, "host", "host", "deck") == @front_url
    end
  end
end
