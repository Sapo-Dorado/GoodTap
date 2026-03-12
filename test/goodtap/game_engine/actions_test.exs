defmodule Goodtap.GameEngine.ActionsTest do
  use ExUnit.Case, async: true

  alias Goodtap.GameEngine.Actions
  alias Goodtap.GameEngine.State
  import Goodtap.GameFixtures

  # ─── Helpers ──────────────────────────────────────────────────────────────

  defp cards_in(state, player, zone) do
    get_in(state, [player, "zones", zone]) || []
  end

  # In a 2-player game_state (p1/p2), "known to both" means both p1 and p2 know it.
  defp known_to_both?(card) do
    State.known_to?(card, "p1") and State.known_to?(card, "p2")
  end

  defp known_to_neither?(card) do
    not State.known_to?(card, "p1") and not State.known_to?(card, "p2")
  end

  # ─── Move to Graveyard ────────────────────────────────────────────────────

  describe "move_to_graveyard/4" do
    test "card becomes known to both players" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "hand", [c])
      {:ok, new_state} = Actions.move_to_graveyard(state, "p1", "c1", "hand")
      [moved] = cards_in(new_state, "p1", "graveyard")
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
      state = game_state() |> with_cards_in("p1", "battlefield", [c])
      {:ok, new_state} = Actions.move_to_graveyard(state, "p1", "c1", "battlefield")
      [moved] = cards_in(new_state, "p1", "graveyard")
      assert moved["tapped"] == false
      assert moved["is_face_down"] == false
      assert moved["active_face"] == 0
      assert moved["counters"] == []
    end

    test "token sent to graveyard disappears (not added to zone)" do
      t = token(%{"instance_id" => "t1"})
      state = game_state() |> with_cards_in("p1", "battlefield", [t])
      {:ok, new_state} = Actions.move_to_graveyard(state, "p1", "t1", "battlefield")
      assert cards_in(new_state, "p1", "graveyard") == []
      assert cards_in(new_state, "p1", "battlefield") == []
    end

    test "returns error when card not found" do
      state = game_state()
      assert {:error, _} = Actions.move_to_graveyard(state, "p1", "nonexistent", "hand")
    end
  end

  # ─── Move to Exile ────────────────────────────────────────────────────────

  describe "move_to_exile/4" do
    test "card becomes known to both players" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "hand", [c])
      {:ok, new_state} = Actions.move_to_exile(state, "p1", "c1", "hand")
      [moved] = cards_in(new_state, "p1", "exile")
      assert known_to_both?(moved)
    end

    test "resets face, tapped, and counters" do
      c = card(%{"instance_id" => "c1", "tapped" => true, "counters" => [%{"name" => "x", "value" => 1}]})
      state = game_state() |> with_cards_in("p1", "battlefield", [c])
      {:ok, new_state} = Actions.move_to_exile(state, "p1", "c1", "battlefield")
      [moved] = cards_in(new_state, "p1", "exile")
      assert moved["tapped"] == false
      assert moved["counters"] == []
    end

    test "token sent to exile disappears" do
      t = token(%{"instance_id" => "t1"})
      state = game_state() |> with_cards_in("p1", "battlefield", [t])
      {:ok, new_state} = Actions.move_to_exile(state, "p1", "t1", "battlefield")
      assert cards_in(new_state, "p1", "exile") == []
    end
  end

  # ─── Move to Hand ─────────────────────────────────────────────────────────

  describe "move_to_hand/4" do
    test "card becomes known to the moving player only" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "graveyard", [c])
      {:ok, new_state} = Actions.move_to_hand(state, "p1", "c1", "graveyard")
      [moved] = cards_in(new_state, "p1", "hand")
      assert State.known_to?(moved, "p1")
      refute State.known_to?(moved, "p2")
    end

    test "token sent to hand disappears" do
      t = token(%{"instance_id" => "t1"})
      state = game_state() |> with_cards_in("p1", "battlefield", [t])
      {:ok, new_state} = Actions.move_to_hand(state, "p1", "t1", "battlefield")
      assert cards_in(new_state, "p1", "hand") == []
    end
  end

  # ─── Move to Battlefield ──────────────────────────────────────────────────

  describe "move_to_battlefield/6" do
    test "face-up card becomes known to both players" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "hand", [c])
      {:ok, new_state} = Actions.move_to_battlefield(state, "p1", "c1", "hand", 0.5, 0.5)
      [moved] = cards_in(new_state, "p1", "battlefield")
      assert known_to_both?(moved)
    end

    test "face-down card does not change known state" do
      c = card(%{"instance_id" => "c1", "is_face_down" => true})
      state = game_state() |> with_cards_in("p1", "hand", [c])
      {:ok, new_state} = Actions.move_to_battlefield(state, "p1", "c1", "hand", 0.5, 0.5)
      [moved] = cards_in(new_state, "p1", "battlefield")
      assert known_to_neither?(moved)
    end

    test "card gets x, y, and z assigned" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "hand", [c])
      {:ok, new_state} = Actions.move_to_battlefield(state, "p1", "c1", "hand", 0.3, 0.7)
      [moved] = cards_in(new_state, "p1", "battlefield")
      assert moved["x"] == 0.3
      assert moved["y"] == 0.7
      assert is_integer(moved["z"]) and moved["z"] > 0
    end
  end

  # ─── Flip Card ────────────────────────────────────────────────────────────

  describe "flip_card/4" do
    test "flipping face-down card face-up on battlefield reveals it to both" do
      c = card(%{"instance_id" => "c1", "is_face_down" => true})
      state = game_state() |> with_cards_in("p1", "battlefield", [c])
      {:ok, new_state} = Actions.flip_card(state, "p1", "c1", "battlefield")
      [flipped] = cards_in(new_state, "p1", "battlefield")
      assert flipped["is_face_down"] == false
      assert known_to_both?(flipped)
    end

    test "flipping a card in hand does not change known state" do
      c = card(%{"instance_id" => "c1", "is_face_down" => true})
      state = game_state() |> with_cards_in("p1", "hand", [c])
      {:ok, new_state} = Actions.flip_card(state, "p1", "c1", "hand")
      [flipped] = cards_in(new_state, "p1", "hand")
      refute State.known_to?(flipped, "p2")
    end
  end

  # ─── Move to Deck ─────────────────────────────────────────────────────────

  describe "move_to_deck/4" do
    test "card from a public zone (graveyard) is known to both when returned to deck" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "graveyard", [c])
      {:ok, new_state} = Actions.move_to_deck(state, "p1", "c1", "graveyard")
      [on_top] = cards_in(new_state, "p1", "deck")
      assert known_to_both?(on_top)
    end

    test "card from hand is not newly revealed when moved to deck top" do
      c = card(%{"instance_id" => "c1", "known" => %{"p1" => true, "p2" => false}})
      state = game_state() |> with_cards_in("p1", "hand", [c])
      {:ok, new_state} = Actions.move_to_deck(state, "p1", "c1", "hand")
      [on_top] = cards_in(new_state, "p1", "deck")
      refute State.known_to?(on_top, "p2")
    end
  end

  # ─── Draw ─────────────────────────────────────────────────────────────────

  describe "draw/3" do
    test "drawn card is known to the drawing player only" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "deck", [c])
      {:ok, new_state} = Actions.draw(state, "p1", 1)
      [drawn] = cards_in(new_state, "p1", "hand")
      assert State.known_to?(drawn, "p1")
      refute State.known_to?(drawn, "p2")
    end

    test "drawing multiple cards makes each known to drawer only" do
      cards = for i <- 1..3, do: card(%{"instance_id" => "c#{i}"})
      state = game_state() |> with_cards_in("p1", "deck", cards)
      {:ok, new_state} = Actions.draw(state, "p1", 3)
      hand = cards_in(new_state, "p1", "hand")
      assert length(hand) == 3
      assert Enum.all?(hand, &State.known_to?(&1, "p1"))
      assert Enum.all?(hand, &(not State.known_to?(&1, "p2")))
    end

    test "drawing with top_revealed makes drawn card known to both" do
      c = card(%{"instance_id" => "c1"})
      state =
        game_state()
        |> with_cards_in("p1", "deck", [c])
        |> put_in(["p1", "top_revealed"], true)

      {:ok, new_state} = Actions.draw(state, "p1", 1)
      [drawn] = cards_in(new_state, "p1", "hand")
      assert known_to_both?(drawn)
    end
  end

  # ─── Draw Top To (pile hotkey behavior) ───────────────────────────────────

  describe "draw_top_to/3" do
    test "5 successive calls each move a different card — no clicks lost" do
      cards = for i <- 1..7, do: card(%{"instance_id" => "c#{i}", "name" => "Card #{i}"})
      state = game_state() |> with_cards_in("p1", "deck", cards)

      {:ok, s1} = Actions.draw_top_to(state, "p1", "hand")
      {:ok, s2} = Actions.draw_top_to(s1, "p1", "hand")
      {:ok, s3} = Actions.draw_top_to(s2, "p1", "hand")
      {:ok, s4} = Actions.draw_top_to(s3, "p1", "hand")
      {:ok, s5} = Actions.draw_top_to(s4, "p1", "hand")

      assert length(cards_in(s5, "p1", "hand")) == 5
      assert length(cards_in(s5, "p1", "deck")) == 2
      hand_ids = Enum.map(cards_in(s5, "p1", "hand"), & &1["instance_id"])
      assert length(hand_ids) == length(Enum.uniq(hand_ids))
    end

    test "draw_top_to graveyard — card becomes known to both" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "deck", [c])
      {:ok, new_state} = Actions.draw_top_to(state, "p1", "graveyard")
      [moved] = cards_in(new_state, "p1", "graveyard")
      assert known_to_both?(moved)
    end

    test "draw_top_to exile — card becomes known to both" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "deck", [c])
      {:ok, new_state} = Actions.draw_top_to(state, "p1", "exile")
      [moved] = cards_in(new_state, "p1", "exile")
      assert known_to_both?(moved)
    end

    test "draw_top_to battlefield — card becomes known to both" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "deck", [c])
      {:ok, new_state} = Actions.draw_top_to(state, "p1", "battlefield")
      [moved] = cards_in(new_state, "p1", "battlefield")
      assert known_to_both?(moved)
    end

    test "empty deck is a no-op" do
      state = game_state()
      {:ok, new_state} = Actions.draw_top_to(state, "p1", "hand")
      assert new_state == state
    end
  end

  # ─── Shuffle ──────────────────────────────────────────────────────────────

  describe "shuffle/2" do
    test "clears known state for all deck cards" do
      cards = for i <- 1..3 do
        card(%{"instance_id" => "c#{i}", "known" => %{"p1" => true, "p2" => true}})
      end
      state = game_state() |> with_cards_in("p1", "deck", cards)
      {:ok, new_state} = Actions.shuffle(state, "p1")
      deck = cards_in(new_state, "p1", "deck")
      assert Enum.all?(deck, &known_to_neither?/1)
    end
  end

  # ─── Mulligan ─────────────────────────────────────────────────────────────

  describe "mulligan/2" do
    test "redraws 7 cards into hand, leaves 3 in deck" do
      known_cards = for i <- 1..10 do
        card(%{"instance_id" => "c#{i}", "known" => %{"p1" => true, "p2" => true}})
      end
      state =
        game_state()
        |> with_cards_in("p1", "hand", Enum.take(known_cards, 3))
        |> with_cards_in("p1", "deck", Enum.drop(known_cards, 3))

      {:ok, new_state} = Actions.mulligan(state, "p1")
      assert length(cards_in(new_state, "p1", "hand")) == 7
      assert length(cards_in(new_state, "p1", "deck")) == 3
    end

    test "new hand cards are known to the drawing player" do
      cards = for i <- 1..10, do: card(%{"instance_id" => "c#{i}"})
      state =
        game_state()
        |> with_cards_in("p1", "hand", Enum.take(cards, 3))
        |> with_cards_in("p1", "deck", Enum.drop(cards, 3))

      {:ok, new_state} = Actions.mulligan(state, "p1")
      hand = cards_in(new_state, "p1", "hand")
      assert Enum.all?(hand, &State.known_to?(&1, "p1")), "each new hand card should be known to p1"
    end

    test "new hand cards are not known to the opponent" do
      cards = for i <- 1..10, do: card(%{"instance_id" => "c#{i}"})
      state =
        game_state()
        |> with_cards_in("p1", "hand", Enum.take(cards, 3))
        |> with_cards_in("p1", "deck", Enum.drop(cards, 3))

      {:ok, new_state} = Actions.mulligan(state, "p1")
      hand = cards_in(new_state, "p1", "hand")
      refute Enum.any?(hand, &State.known_to?(&1, "p2")), "no new hand card should be known to p2"
    end

    test "deck cards after mulligan are not known to either player" do
      cards = for i <- 1..10, do: card(%{"instance_id" => "c#{i}"})
      state =
        game_state()
        |> with_cards_in("p1", "hand", Enum.take(cards, 3))
        |> with_cards_in("p1", "deck", Enum.drop(cards, 3))

      {:ok, new_state} = Actions.mulligan(state, "p1")
      deck = cards_in(new_state, "p1", "deck")
      assert Enum.all?(deck, &known_to_neither?/1)
    end
  end

  # ─── Top Revealed ─────────────────────────────────────────────────────────

  describe "top_revealed behavior" do
    test "enabling top_revealed immediately marks top deck card known to both" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "deck", [c])
      {:ok, new_state} = Actions.toggle_top_revealed(state, "p1")
      [top] = cards_in(new_state, "p1", "deck")
      assert known_to_both?(top)
    end

    test "after drawing with top_revealed, new top is also known to both" do
      cards = [card(%{"instance_id" => "c1"}), card(%{"instance_id" => "c2"})]
      state =
        game_state()
        |> with_cards_in("p1", "deck", cards)
        |> put_in(["p1", "top_revealed"], true)

      {:ok, new_state} = Actions.draw(state, "p1", 1)
      [new_top] = cards_in(new_state, "p1", "deck")
      assert known_to_both?(new_top)
    end

    test "after shuffle with top_revealed, new top is known to both" do
      cards = for i <- 1..5, do: card(%{"instance_id" => "c#{i}"})
      state =
        game_state()
        |> with_cards_in("p1", "deck", cards)
        |> put_in(["p1", "top_revealed"], true)

      {:ok, new_state} = Actions.shuffle(state, "p1")
      [top | rest] = cards_in(new_state, "p1", "deck")
      assert known_to_both?(top)
      assert Enum.all?(rest, &known_to_neither?/1)
    end

    test "disabling top_revealed does not un-reveal the top card" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "deck", [c])

      {:ok, on_state} = Actions.toggle_top_revealed(state, "p1")
      [top] = cards_in(on_state, "p1", "deck")
      assert known_to_both?(top)

      {:ok, off_state} = Actions.toggle_top_revealed(on_state, "p1")
      [top2] = cards_in(off_state, "p1", "deck")
      assert known_to_both?(top2)
    end
  end

  # ─── Rapid pile moves (simulating server-side hotkey handling) ────────────

  describe "rapid pile hotkey moves — no clicks lost" do
    test "5 rapid moves from graveyard each act on a different card" do
      cards = for i <- 1..5, do: card(%{"instance_id" => "c#{i}"})
      state = game_state() |> with_cards_in("p1", "graveyard", cards)

      {:ok, s1} = Actions.move_to_hand(state, "p1", hd(get_in(state, ["p1", "zones", "graveyard"]))["instance_id"], "graveyard")
      {:ok, s2} = Actions.move_to_hand(s1, "p1", hd(get_in(s1, ["p1", "zones", "graveyard"]))["instance_id"], "graveyard")
      {:ok, s3} = Actions.move_to_hand(s2, "p1", hd(get_in(s2, ["p1", "zones", "graveyard"]))["instance_id"], "graveyard")
      {:ok, s4} = Actions.move_to_hand(s3, "p1", hd(get_in(s3, ["p1", "zones", "graveyard"]))["instance_id"], "graveyard")
      {:ok, s5} = Actions.move_to_hand(s4, "p1", hd(get_in(s4, ["p1", "zones", "graveyard"]))["instance_id"], "graveyard")

      assert length(get_in(s5, ["p1", "zones", "hand"])) == 5
      assert get_in(s5, ["p1", "zones", "graveyard"]) == []
      hand_ids = Enum.map(get_in(s5, ["p1", "zones", "hand"]), & &1["instance_id"])
      assert length(hand_ids) == length(Enum.uniq(hand_ids))
    end

    test "5 rapid moves from exile each act on a different card" do
      cards = for i <- 1..5, do: card(%{"instance_id" => "e#{i}"})
      state = game_state() |> with_cards_in("p1", "exile", cards)

      final = Enum.reduce(1..5, state, fn _, st ->
        top_id = hd(get_in(st, ["p1", "zones", "exile"]))["instance_id"]
        {:ok, new_st} = Actions.move_to_hand(st, "p1", top_id, "exile")
        new_st
      end)

      assert length(get_in(final, ["p1", "zones", "hand"])) == 5
      assert get_in(final, ["p1", "zones", "exile"]) == []
    end
  end

  # ─── Log message name visibility rules ────────────────────────────────────

  describe "log message card name visibility" do
    test "card moved to graveyard should show name (always public after move)" do
      c = card(%{"instance_id" => "c1", "name" => "Lightning Bolt"})
      state = game_state() |> with_cards_in("p1", "hand", [c])
      {:ok, new_state} = Actions.move_to_graveyard(state, "p1", "c1", "hand")
      [moved] = cards_in(new_state, "p1", "graveyard")
      assert known_to_both?(moved)
    end

    test "card drawn to hand should NOT show name (only known to drawer)" do
      c = card(%{"instance_id" => "c1", "name" => "Secret Card"})
      state = game_state() |> with_cards_in("p1", "deck", [c])
      {:ok, new_state} = Actions.draw(state, "p1", 1)
      [drawn] = cards_in(new_state, "p1", "hand")
      refute known_to_both?(drawn)
    end

    test "card from unknown deck to hand via draw_top_to — not known to both" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "deck", [c])
      {:ok, new_state} = Actions.draw_top_to(state, "p1", "hand")
      [drawn] = cards_in(new_state, "p1", "hand")
      assert State.known_to?(drawn, "p1")
      refute State.known_to?(drawn, "p2")
    end

    test "card already known to both moved to hand — still known to both" do
      c = card(%{"instance_id" => "c1", "name" => "Famous Card", "known" => %{"p1" => true, "p2" => true}})
      state = game_state() |> with_cards_in("p1", "battlefield", [c])
      {:ok, new_state} = Actions.move_to_hand(state, "p1", "c1", "battlefield")
      [moved] = cards_in(new_state, "p1", "hand")
      assert State.known_to?(moved, "p2")
    end
  end

  # ─── Copy Opponent Card ───────────────────────────────────────────────────

  describe "copy_opponent_card/4" do
    test "copies a face-up card from another player's battlefield" do
      c = card(%{"instance_id" => "opp1", "name" => "Dragon", "x" => 0.5, "y" => 0.3,
                 "known" => %{"p1" => true, "p2" => true}})
      state = game_state() |> with_cards_in("p2", "battlefield", [c])
      {:ok, new_state} = Actions.copy_opponent_card(state, "p1", "p2", "opp1")
      p1_bf = cards_in(new_state, "p1", "battlefield")
      assert length(p1_bf) == 1
      assert hd(p1_bf)["name"] == "Dragon"
      assert hd(p1_bf)["is_token"] == true
    end

    test "does not copy face-down cards" do
      c = card(%{"instance_id" => "opp1", "is_face_down" => true, "x" => 0.5, "y" => 0.3})
      state = game_state() |> with_cards_in("p2", "battlefield", [c])
      {:ok, new_state} = Actions.copy_opponent_card(state, "p1", "p2", "opp1")
      assert cards_in(new_state, "p1", "battlefield") == []
    end
  end

  # ─── Reveal / Hide Hand ───────────────────────────────────────────────────

  describe "reveal_cards/3" do
    test "marks specified hand cards as known to all other players" do
      c1 = card(%{"instance_id" => "c1"})
      c2 = card(%{"instance_id" => "c2"})
      state = game_state() |> with_cards_in("p1", "hand", [c1, c2])
      {:ok, new_state} = Actions.reveal_cards(state, "p1", ["c1"])
      hand = cards_in(new_state, "p1", "hand")
      revealed = Enum.find(hand, &(&1["instance_id"] == "c1"))
      hidden = Enum.find(hand, &(&1["instance_id"] == "c2"))
      assert State.known_to?(revealed, "p2")
      refute State.known_to?(hidden, "p2")
    end

    test "works with 3 players — reveals to all others" do
      c = card(%{"instance_id" => "c1"})
      state = %{
        "p1" => player_state() |> put_in(["zones", "hand"], [c]),
        "p2" => player_state(),
        "p3" => player_state(),
        "z_counter" => 0
      }
      {:ok, new_state} = Actions.reveal_cards(state, "p1", ["c1"])
      [revealed] = get_in(new_state, ["p1", "zones", "hand"])
      assert State.known_to?(revealed, "p2")
      assert State.known_to?(revealed, "p3")
      refute State.known_to?(revealed, "p1")
    end
  end

  describe "hide_hand/2" do
    test "clears knowledge of all other players for hand cards" do
      c = card(%{"instance_id" => "c1", "known" => %{"p1" => true, "p2" => true}})
      state = game_state() |> with_cards_in("p1", "hand", [c])
      {:ok, new_state} = Actions.hide_hand(state, "p1")
      [hidden] = cards_in(new_state, "p1", "hand")
      refute State.known_to?(hidden, "p2")
      # p1 still knows their own card
      assert State.known_to?(hidden, "p1")
    end
  end

  # ─── Z-index renumbering with N players ───────────────────────────────────

  describe "z-index renumbering" do
    test "next_z renumbers across all players when max is exceeded" do
      # Create state with z_counter near the max (15) across two players
      p1_cards = for i <- 1..8 do
        card(%{"instance_id" => "p1c#{i}", "x" => i / 10, "y" => 0.5, "z" => i})
      end
      p2_cards = for i <- 1..8 do
        card(%{"instance_id" => "p2c#{i}", "x" => i / 10, "y" => 0.5, "z" => i + 8})
      end

      state =
        game_state()
        |> with_cards_in("p1", "battlefield", p1_cards)
        |> with_cards_in("p2", "battlefield", p2_cards)
        |> Map.put("z_counter", 16)

      # Moving a card should trigger renumbering
      c = card(%{"instance_id" => "new"})
      state_with_new = put_in(state, ["p1", "zones", "hand"], [c])
      {:ok, new_state} = Actions.move_to_battlefield(state_with_new, "p1", "new", "hand", 0.5, 0.5)

      # All z values should be reasonable (renumbered from 1..N+1)
      all_z =
        (get_in(new_state, ["p1", "zones", "battlefield"]) ++
         get_in(new_state, ["p2", "zones", "battlefield"]))
        |> Enum.map(& &1["z"])

      assert Enum.all?(all_z, &(&1 > 0))
      assert Enum.max(all_z) <= 18  # at most 17 cards + 1
    end
  end

  # ─── on_battlefield field ─────────────────────────────────────────────────

  describe "move_to_player_battlefield/7" do
    test "sets on_battlefield when placing on opponent" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "hand", [c])

      {:ok, new_state} = Actions.move_to_player_battlefield(state, "p1", "p2", "c1", "hand", 0.3, 0.2)
      [placed] = cards_in(new_state, "p1", "battlefield")
      assert placed["on_battlefield"] == "p2"
      assert placed["x"] == 0.3
      assert placed["y"] == 0.2
    end

    test "card stays in source player's zone" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "hand", [c])

      {:ok, new_state} = Actions.move_to_player_battlefield(state, "p1", "p2", "c1", "hand", 0.3, 0.2)
      assert cards_in(new_state, "p2", "battlefield") == []
      assert length(cards_in(new_state, "p1", "battlefield")) == 1
    end

    test "placing on own side clears on_battlefield" do
      c = card(%{"instance_id" => "c1", "on_battlefield" => "p2"})
      state = game_state() |> with_cards_in("p1", "battlefield", [c])

      {:ok, new_state} = Actions.move_to_player_battlefield(state, "p1", "p1", "c1", "battlefield", 0.5, 0.8)
      [moved] = cards_in(new_state, "p1", "battlefield")
      refute Map.has_key?(moved, "on_battlefield")
    end

    test "card becomes known to all players" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "hand", [c])

      {:ok, new_state} = Actions.move_to_player_battlefield(state, "p1", "p2", "c1", "hand", 0.3, 0.2)
      [placed] = cards_in(new_state, "p1", "battlefield")
      assert State.known_to?(placed, "p1")
      assert State.known_to?(placed, "p2")
    end
  end

  describe "update_battlefield_position/6 with target_player" do
    test "nil target_player preserves existing on_battlefield" do
      c = card(%{"instance_id" => "c1", "on_battlefield" => "p2"})
      state = game_state() |> with_cards_in("p1", "battlefield", [c])

      {:ok, new_state} = Actions.update_battlefield_position(state, "p1", "c1", 0.4, 0.3)
      [moved] = cards_in(new_state, "p1", "battlefield")
      assert moved["on_battlefield"] == "p2"
    end

    test "target_player == player clears on_battlefield (drag back to own side)" do
      c = card(%{"instance_id" => "c1", "on_battlefield" => "p2"})
      state = game_state() |> with_cards_in("p1", "battlefield", [c])

      {:ok, new_state} = Actions.update_battlefield_position(state, "p1", "c1", 0.5, 0.8, "p1")
      [moved] = cards_in(new_state, "p1", "battlefield")
      refute Map.has_key?(moved, "on_battlefield")
    end

    test "target_player == opponent sets on_battlefield" do
      c = card(%{"instance_id" => "c1"})
      state = game_state() |> with_cards_in("p1", "battlefield", [c])

      {:ok, new_state} = Actions.update_battlefield_position(state, "p1", "c1", 0.3, 0.2, "p2")
      [moved] = cards_in(new_state, "p1", "battlefield")
      assert moved["on_battlefield"] == "p2"
    end
  end

  describe "move_to_battlefield/7 clears on_battlefield" do
    test "move to battlefield always clears on_battlefield" do
      c = card(%{"instance_id" => "c1", "on_battlefield" => "p2"})
      state = game_state() |> with_cards_in("p1", "hand", [c])

      {:ok, new_state} = Actions.move_to_battlefield(state, "p1", "c1", "hand", 0.5, 0.8)
      [moved] = cards_in(new_state, "p1", "battlefield")
      refute Map.has_key?(moved, "on_battlefield")
    end
  end
end
