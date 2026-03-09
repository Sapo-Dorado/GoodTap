defmodule Goodtap.GameEngine.ActionsTest do
  use ExUnit.Case, async: true

  alias Goodtap.GameEngine.Actions
  alias Goodtap.GameEngine.State
  import Goodtap.GameFixtures

  # ─── Helpers ──────────────────────────────────────────────────────────────

  defp cards_in(state, player, zone) do
    get_in(state, [player, "zones", zone]) || []
  end

  defp known_to_both?(card) do
    State.known_to?(card, "host") and State.known_to?(card, "opponent")
  end

  defp known_to_neither?(card) do
    not State.known_to?(card, "host") and not State.known_to?(card, "opponent")
  end

  # ─── Move to Graveyard ────────────────────────────────────────────────────

  describe "move_to_graveyard/4" do
    test "card becomes known to both players" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("host", "hand", [c])
      {:ok, new_state} = Actions.move_to_graveyard(state, "host", "c1", "hand")
      [moved] = cards_in(new_state, "host", "graveyard")
      assert known_to_both?(moved)
    end

    test "resets tapped, face-down, and counters" do
      c = card(%{
        "instance_id" => "c1",
        "tapped" => true,
        "is_face_down" => true,
        "active_face" => 1,
        "counters" => [%{"name" => "+1/+1", "value" => 3}]
      })
      state = game_state() |> with_cards_in("host", "battlefield", [c])
      {:ok, new_state} = Actions.move_to_graveyard(state, "host", "c1", "battlefield")
      [moved] = cards_in(new_state, "host", "graveyard")
      assert moved["tapped"] == false
      assert moved["is_face_down"] == false
      assert moved["active_face"] == 0
      assert moved["counters"] == []
    end

    test "token sent to graveyard disappears (not added to zone)" do
      t = token(%{"instance_id" => "t1"})
      state = game_state() |> with_cards_in("host", "battlefield", [t])
      {:ok, new_state} = Actions.move_to_graveyard(state, "host", "t1", "battlefield")
      assert cards_in(new_state, "host", "graveyard") == []
      assert cards_in(new_state, "host", "battlefield") == []
    end

    test "returns error when card not found" do
      state = game_state()
      assert {:error, _} = Actions.move_to_graveyard(state, "host", "nonexistent", "hand")
    end
  end

  # ─── Move to Exile ────────────────────────────────────────────────────────

  describe "move_to_exile/4" do
    test "card becomes known to both players" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("host", "hand", [c])
      {:ok, new_state} = Actions.move_to_exile(state, "host", "c1", "hand")
      [moved] = cards_in(new_state, "host", "exile")
      assert known_to_both?(moved)
    end

    test "resets face, tapped, and counters" do
      c = card(%{"instance_id" => "c1", "tapped" => true, "counters" => [%{"name" => "x", "value" => 1}]})
      state = game_state() |> with_cards_in("host", "battlefield", [c])
      {:ok, new_state} = Actions.move_to_exile(state, "host", "c1", "battlefield")
      [moved] = cards_in(new_state, "host", "exile")
      assert moved["tapped"] == false
      assert moved["counters"] == []
    end

    test "token sent to exile disappears" do
      t = token(%{"instance_id" => "t1"})
      state = game_state() |> with_cards_in("host", "battlefield", [t])
      {:ok, new_state} = Actions.move_to_exile(state, "host", "t1", "battlefield")
      assert cards_in(new_state, "host", "exile") == []
    end
  end

  # ─── Move to Hand ─────────────────────────────────────────────────────────

  describe "move_to_hand/4" do
    test "card becomes known to the moving player only" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("host", "graveyard", [c])
      {:ok, new_state} = Actions.move_to_hand(state, "host", "c1", "graveyard")
      [moved] = cards_in(new_state, "host", "hand")
      assert State.known_to?(moved, "host")
      refute State.known_to?(moved, "opponent")
    end

    test "token sent to hand disappears" do
      t = token(%{"instance_id" => "t1"})
      state = game_state() |> with_cards_in("host", "battlefield", [t])
      {:ok, new_state} = Actions.move_to_hand(state, "host", "t1", "battlefield")
      assert cards_in(new_state, "host", "hand") == []
    end
  end

  # ─── Move to Battlefield ──────────────────────────────────────────────────

  describe "move_to_battlefield/6" do
    test "face-up card becomes known to both players" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("host", "hand", [c])
      {:ok, new_state} = Actions.move_to_battlefield(state, "host", "c1", "hand", 0.5, 0.5)
      [moved] = cards_in(new_state, "host", "battlefield")
      assert known_to_both?(moved)
    end

    test "face-down card does not change known state" do
      # Card unknown to both before move
      c = card(%{"instance_id" => "c1", "is_face_down" => true})
      state = game_state() |> with_cards_in("host", "hand", [c])
      {:ok, new_state} = Actions.move_to_battlefield(state, "host", "c1", "hand", 0.5, 0.5)
      [moved] = cards_in(new_state, "host", "battlefield")
      assert known_to_neither?(moved)
    end

    test "card gets x, y, and z assigned" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("host", "hand", [c])
      {:ok, new_state} = Actions.move_to_battlefield(state, "host", "c1", "hand", 0.3, 0.7)
      [moved] = cards_in(new_state, "host", "battlefield")
      assert moved["x"] == 0.3
      assert moved["y"] == 0.7
      assert is_integer(moved["z"]) and moved["z"] > 0
    end
  end

  # ─── Flip Card ────────────────────────────────────────────────────────────

  describe "flip_card/4" do
    test "flipping face-down card face-up on battlefield reveals it to both" do
      c = card(%{"instance_id" => "c1", "is_face_down" => true})
      state = game_state() |> with_cards_in("host", "battlefield", [c])
      {:ok, new_state} = Actions.flip_card(state, "host", "c1", "battlefield")
      [flipped] = cards_in(new_state, "host", "battlefield")
      assert flipped["is_face_down"] == false
      assert known_to_both?(flipped)
    end

    test "flipping a card in hand does not change known state" do
      c = card(%{"instance_id" => "c1", "is_face_down" => true})
      state = game_state() |> with_cards_in("host", "hand", [c])
      {:ok, new_state} = Actions.flip_card(state, "host", "c1", "hand")
      [flipped] = cards_in(new_state, "host", "hand")
      # Still unknown to opponent — hand flip is private
      refute State.known_to?(flipped, "opponent")
    end
  end

  # ─── Move to Deck ─────────────────────────────────────────────────────────

  describe "move_to_deck/4" do
    test "card from a public zone (graveyard) is known to both when returned to deck" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("host", "graveyard", [c])
      {:ok, new_state} = Actions.move_to_deck(state, "host", "c1", "graveyard")
      [on_top] = cards_in(new_state, "host", "deck")
      assert known_to_both?(on_top)
    end

    test "card from hand is not newly revealed when moved to deck top" do
      # Card only known to host (was drawn)
      c = card(%{"instance_id" => "c1", "known" => %{"host" => true, "opponent" => false}})
      state = game_state() |> with_cards_in("host", "hand", [c])
      {:ok, new_state} = Actions.move_to_deck(state, "host", "c1", "hand")
      [on_top] = cards_in(new_state, "host", "deck")
      refute State.known_to?(on_top, "opponent")
    end
  end

  # ─── Draw ─────────────────────────────────────────────────────────────────

  describe "draw/3" do
    test "drawn card is known to the drawing player only" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("host", "deck", [c])
      {:ok, new_state} = Actions.draw(state, "host", 1)
      [drawn] = cards_in(new_state, "host", "hand")
      assert State.known_to?(drawn, "host")
      refute State.known_to?(drawn, "opponent")
    end

    test "drawing multiple cards makes each known to drawer only" do
      cards = for i <- 1..3, do: card(%{"instance_id" => "c#{i}"})
      state = game_state() |> with_cards_in("host", "deck", cards)
      {:ok, new_state} = Actions.draw(state, "host", 3)
      hand = cards_in(new_state, "host", "hand")
      assert length(hand) == 3
      assert Enum.all?(hand, &State.known_to?(&1, "host"))
      assert Enum.all?(hand, &(not State.known_to?(&1, "opponent")))
    end

    test "drawing with top_revealed makes drawn card known to both" do
      c = card(%{"instance_id" => "c1"})
      state =
        game_state()
        |> with_cards_in("host", "deck", [c])
        |> put_in(["host", "top_revealed"], true)

      {:ok, new_state} = Actions.draw(state, "host", 1)
      [drawn] = cards_in(new_state, "host", "hand")
      assert known_to_both?(drawn)
    end
  end

  # ─── Draw Top To (pile hotkey behavior) ───────────────────────────────────

  describe "draw_top_to/3" do
    test "5 successive calls each move a different card — no clicks lost" do
      cards = for i <- 1..7, do: card(%{"instance_id" => "c#{i}", "name" => "Card #{i}"})
      state = game_state() |> with_cards_in("host", "deck", cards)

      {:ok, s1} = Actions.draw_top_to(state, "host", "hand")
      {:ok, s2} = Actions.draw_top_to(s1, "host", "hand")
      {:ok, s3} = Actions.draw_top_to(s2, "host", "hand")
      {:ok, s4} = Actions.draw_top_to(s3, "host", "hand")
      {:ok, s5} = Actions.draw_top_to(s4, "host", "hand")

      assert length(cards_in(s5, "host", "hand")) == 5
      assert length(cards_in(s5, "host", "deck")) == 2
      # All moved cards are distinct
      hand_ids = Enum.map(cards_in(s5, "host", "hand"), & &1["instance_id"])
      assert length(hand_ids) == length(Enum.uniq(hand_ids))
    end

    test "draw_top_to graveyard — card becomes known to both" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("host", "deck", [c])
      {:ok, new_state} = Actions.draw_top_to(state, "host", "graveyard")
      [moved] = cards_in(new_state, "host", "graveyard")
      assert known_to_both?(moved)
    end

    test "draw_top_to exile — card becomes known to both" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("host", "deck", [c])
      {:ok, new_state} = Actions.draw_top_to(state, "host", "exile")
      [moved] = cards_in(new_state, "host", "exile")
      assert known_to_both?(moved)
    end

    test "draw_top_to battlefield — card becomes known to both" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("host", "deck", [c])
      {:ok, new_state} = Actions.draw_top_to(state, "host", "battlefield")
      [moved] = cards_in(new_state, "host", "battlefield")
      assert known_to_both?(moved)
    end

    test "empty deck is a no-op" do
      state = game_state()
      {:ok, new_state} = Actions.draw_top_to(state, "host", "hand")
      assert new_state == state
    end
  end

  # ─── Shuffle ──────────────────────────────────────────────────────────────

  describe "shuffle/2" do
    test "clears known state for all deck cards" do
      cards = for i <- 1..3 do
        card(%{"instance_id" => "c#{i}", "known" => %{"host" => true, "opponent" => true}})
      end
      state = game_state() |> with_cards_in("host", "deck", cards)
      {:ok, new_state} = Actions.shuffle(state, "host")
      deck = cards_in(new_state, "host", "deck")
      assert Enum.all?(deck, &known_to_neither?/1)
    end
  end

  # ─── Mulligan ─────────────────────────────────────────────────────────────

  describe "mulligan/2" do
    test "clears known state for all cards, redraws 7" do
      known_cards = for i <- 1..10 do
        card(%{"instance_id" => "c#{i}", "known" => %{"host" => true, "opponent" => true}})
      end
      state =
        game_state()
        |> with_cards_in("host", "hand", Enum.take(known_cards, 3))
        |> with_cards_in("host", "deck", Enum.drop(known_cards, 3))

      {:ok, new_state} = Actions.mulligan(state, "host")
      hand = cards_in(new_state, "host", "hand")
      deck = cards_in(new_state, "host", "deck")
      assert length(hand) == 7
      assert length(deck) == 3
      assert Enum.all?(hand ++ deck, &known_to_neither?/1)
    end
  end

  # ─── Top Revealed ─────────────────────────────────────────────────────────

  describe "top_revealed behavior" do
    test "enabling top_revealed immediately marks top deck card known to both" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("host", "deck", [c])
      {:ok, new_state} = Actions.toggle_top_revealed(state, "host")
      [top] = cards_in(new_state, "host", "deck")
      assert known_to_both?(top)
    end

    test "after drawing with top_revealed, new top is also known to both" do
      cards = [card(%{"instance_id" => "c1"}), card(%{"instance_id" => "c2"})]
      state =
        game_state()
        |> with_cards_in("host", "deck", cards)
        |> put_in(["host", "top_revealed"], true)

      {:ok, new_state} = Actions.draw(state, "host", 1)
      [new_top] = cards_in(new_state, "host", "deck")
      assert known_to_both?(new_top)
    end

    test "after shuffle with top_revealed, new top is known to both" do
      cards = for i <- 1..5, do: card(%{"instance_id" => "c#{i}"})
      state =
        game_state()
        |> with_cards_in("host", "deck", cards)
        |> put_in(["host", "top_revealed"], true)

      {:ok, new_state} = Actions.shuffle(state, "host")
      [top | rest] = cards_in(new_state, "host", "deck")
      assert known_to_both?(top)
      # Only top is revealed, not rest
      assert Enum.all?(rest, &known_to_neither?/1)
    end

    test "disabling top_revealed does not un-reveal the top card" do
      c = card(%{"instance_id" => "c1"})
      # Start with top_revealed off (default)
      state = game_state() |> with_cards_in("host", "deck", [c])

      # Toggle on — top card should become known to both
      {:ok, on_state} = Actions.toggle_top_revealed(state, "host")
      [top] = cards_in(on_state, "host", "deck")
      assert known_to_both?(top)

      # Toggle off — known state is not cleared, card stays revealed
      {:ok, off_state} = Actions.toggle_top_revealed(on_state, "host")
      [top2] = cards_in(off_state, "host", "deck")
      assert known_to_both?(top2)
    end
  end

  # ─── Rapid pile moves (simulating server-side hotkey handling) ────────────

  describe "rapid pile hotkey moves — no clicks lost" do
    test "5 rapid moves from graveyard each act on a different card" do
      cards = for i <- 1..5, do: card(%{"instance_id" => "c#{i}"})
      state = game_state() |> with_cards_in("host", "graveyard", cards)

      # Simulate server resolving 5 hotkey events, each using resolve_pile_id logic
      # (always top of graveyard)
      {:ok, s1} = Actions.move_to_hand(state, "host", hd(get_in(state, ["host", "zones", "graveyard"]))["instance_id"], "graveyard")
      {:ok, s2} = Actions.move_to_hand(s1, "host", hd(get_in(s1, ["host", "zones", "graveyard"]))["instance_id"], "graveyard")
      {:ok, s3} = Actions.move_to_hand(s2, "host", hd(get_in(s2, ["host", "zones", "graveyard"]))["instance_id"], "graveyard")
      {:ok, s4} = Actions.move_to_hand(s3, "host", hd(get_in(s3, ["host", "zones", "graveyard"]))["instance_id"], "graveyard")
      {:ok, s5} = Actions.move_to_hand(s4, "host", hd(get_in(s4, ["host", "zones", "graveyard"]))["instance_id"], "graveyard")

      assert length(get_in(s5, ["host", "zones", "hand"])) == 5
      assert get_in(s5, ["host", "zones", "graveyard"]) == []
      hand_ids = Enum.map(get_in(s5, ["host", "zones", "hand"]), & &1["instance_id"])
      assert length(hand_ids) == length(Enum.uniq(hand_ids))
    end

    test "5 rapid moves from exile each act on a different card" do
      cards = for i <- 1..5, do: card(%{"instance_id" => "e#{i}"})
      state = game_state() |> with_cards_in("host", "exile", cards)

      final = Enum.reduce(1..5, state, fn _, st ->
        top_id = hd(get_in(st, ["host", "zones", "exile"]))["instance_id"]
        {:ok, new_st} = Actions.move_to_hand(st, "host", top_id, "exile")
        new_st
      end)

      assert length(get_in(final, ["host", "zones", "hand"])) == 5
      assert get_in(final, ["host", "zones", "exile"]) == []
    end
  end

  # ─── Log message name visibility rules ────────────────────────────────────

  describe "log message card name visibility" do
    test "card moved to graveyard should show name (always public after move)" do
      c = card(%{"instance_id" => "c1", "name" => "Lightning Bolt"})
      state = game_state() |> with_cards_in("host", "hand", [c])
      {:ok, new_state} = Actions.move_to_graveyard(state, "host", "c1", "hand")
      [moved] = cards_in(new_state, "host", "graveyard")
      # After move to GY, card is known to both — name should be shown in log
      assert known_to_both?(moved)
    end

    test "card drawn to hand should NOT show name (only known to drawer)" do
      c = card(%{"instance_id" => "c1", "name" => "Secret Card"})
      state = game_state() |> with_cards_in("host", "deck", [c])
      {:ok, new_state} = Actions.draw(state, "host", 1)
      [drawn] = cards_in(new_state, "host", "hand")
      # Not known to both — should not show name in opponent's log
      refute known_to_both?(drawn)
    end

    test "card from unknown deck to hand via draw_top_to — not known to both" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("host", "deck", [c])
      {:ok, new_state} = Actions.draw_top_to(state, "host", "hand")
      [drawn] = cards_in(new_state, "host", "hand")
      # Known to host only — log should say "a card"
      assert State.known_to?(drawn, "host")
      refute State.known_to?(drawn, "opponent")
    end

    test "card already known to both moved to hand — still known to both (ok to show name)" do
      # A card that was on battlefield (known to both) goes to hand
      c = card(%{"instance_id" => "c1", "name" => "Famous Card", "known" => %{"host" => true, "opponent" => true}})
      state = game_state() |> with_cards_in("host", "battlefield", [c])
      {:ok, new_state} = Actions.move_to_hand(state, "host", "c1", "battlefield")
      [moved] = cards_in(new_state, "host", "hand")
      # move_to_hand marks known to player, but opponent knowledge was already true
      # The card is still known to opponent from before — so name is ok to show
      assert State.known_to?(moved, "opponent")
    end
  end
end
