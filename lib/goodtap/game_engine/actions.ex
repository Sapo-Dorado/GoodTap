defmodule Goodtap.GameEngine.Actions do
  alias Goodtap.GameEngine.State

  # ─── Known Helpers ────────────────────────────────────────────────────────

  defp mark_known_to(card, role), do: put_in_known(card, role, true)
  defp clear_known_to(card, role), do: put_in_known(card, role, false)

  defp mark_known_to_both(card) do
    card
    |> mark_known_to("host")
    |> mark_known_to("opponent")
  end

  defp clear_known_to_both(card) do
    card
    |> clear_known_to("host")
    |> clear_known_to("opponent")
  end

  # If the player has "top_revealed" enabled, mark the current top deck card known to both.
  # Called after any action that changes the deck contents or order.
  defp maybe_reveal_deck_top(state, player) do
    if get_in(state, [player, "top_revealed"]) do
      case get_in(state, [player, "zones", "deck"]) do
        [top | rest] ->
          put_in(state, [player, "zones", "deck"], [mark_known_to_both(top) | rest])
        _ ->
          state
      end
    else
      state
    end
  end

  defp put_in_known(card, role, value) do
    known =
      case card["known"] do
        true -> %{"host" => true, "opponent" => true}
        false -> %{"host" => false, "opponent" => false}
        nil -> %{"host" => false, "opponent" => false}
        map when is_map(map) -> map
      end

    Map.put(card, "known", Map.put(known, role, value))
  end

  # ─── Tap ──────────────────────────────────────────────────────────────────

  def tap(state, player, instance_id) do
    update_in_zone(state, player, "battlefield", instance_id, fn card ->
      Map.update!(card, "tapped", &(!&1))
    end)
  end

  # ─── Move to Graveyard ────────────────────────────────────────────────────

  def move_to_graveyard(state, player, instance_id, source_zone) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      card = card |> reset_face() |> Map.put("tapped", false) |> reset_counters() |> mark_known_to_both()

      if card["is_token"] do
        {:ok, maybe_reveal_deck_top(state, player)}
      else
        {:ok, maybe_reveal_deck_top(prepend_to_zone(state, player, "graveyard", card), player)}
      end
    end
  end

  # ─── Move to Exile ────────────────────────────────────────────────────────

  def move_to_exile(state, player, instance_id, source_zone) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      card = card |> reset_face() |> Map.put("tapped", false) |> reset_counters() |> mark_known_to_both()

      if card["is_token"] do
        {:ok, maybe_reveal_deck_top(state, player)}
      else
        {:ok, maybe_reveal_deck_top(prepend_to_zone(state, player, "exile", card), player)}
      end
    end
  end

  def move_all_to_exile(state, player) do
    graveyard = get_in(state, [player, "zones", "graveyard"]) || []
    existing_exile = get_in(state, [player, "zones", "exile"]) || []
    {to_exile, _tokens} = Enum.split_with(graveyard, &(!&1["is_token"]))
    to_exile = Enum.map(to_exile, &(&1 |> reset_face() |> Map.put("tapped", false) |> reset_counters() |> mark_known_to_both()))
    state
    |> put_in([player, "zones", "graveyard"], [])
    |> put_in([player, "zones", "exile"], to_exile ++ existing_exile)
    |> then(&{:ok, &1})
  end

  # ─── Reorder Within Zone ──────────────────────────────────────────────────

  # Generic reorder for any list zone (hand, deck, graveyard, exile).
  # insert_index is the desired position *before* removal, so we adjust for
  # the gap left by removing the card.
  def reorder_in_zone(state, player, zone, instance_id, insert_index) do
    cards = get_in(state, [player, "zones", zone]) || []
    original_index = Enum.find_index(cards, fn c -> c["instance_id"] == instance_id end)

    with {:ok, {card, state}} <- remove_from_zone(state, player, zone, instance_id) do
      adjusted =
        if is_integer(original_index) && is_integer(insert_index) &&
             original_index < insert_index do
          insert_index - 1
        else
          insert_index
        end

      {:ok, insert_into_zone(state, player, zone, card, adjusted)}
    end
  end

  # ─── Move to Hand ─────────────────────────────────────────────────────────

  def move_to_hand(state, player, instance_id, source_zone, insert_index \\ nil) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      card = card |> Map.put("tapped", false) |> reset_counters() |> mark_known_to(player)

      if card["is_token"] do
        {:ok, maybe_reveal_deck_top(state, player)}
      else
        state =
          if is_integer(insert_index) do
            insert_into_zone(state, player, "hand", card, insert_index)
          else
            append_to_zone(state, player, "hand", card)
          end

        {:ok, maybe_reveal_deck_top(state, player)}
      end
    end
  end

  # ─── Move to Deck Top ────────────────────────────────────────────────────

  def move_to_deck(state, player, instance_id, source_zone, insert_index \\ nil) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      was_face_down = card["is_face_down"]
      card = card |> reset_face() |> Map.put("tapped", false) |> reset_counters()
      card = if was_face_down, do: card, else: mark_known_from_zone(card, source_zone)

      if card["is_token"] do
        {:ok, state}
      else
        state =
          if is_integer(insert_index) do
            insert_into_zone(state, player, "deck", card, insert_index)
          else
            prepend_to_zone(state, player, "deck", card)
          end

        {:ok, maybe_reveal_deck_top(state, player)}
      end
    end
  end

  def move_to_deck_bottom(state, player, instance_id, source_zone) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      was_face_down = card["is_face_down"]
      card = card |> reset_face() |> Map.put("tapped", false) |> reset_counters()
      card = if was_face_down, do: card, else: mark_known_from_zone(card, source_zone)

      if card["is_token"] do
        {:ok, state}
      else
        {:ok, maybe_reveal_deck_top(append_to_zone(state, player, "deck", card), player)}
      end
    end
  end

  # ─── Move to Battlefield ──────────────────────────────────────────────────

  def move_to_battlefield(state, player, instance_id, source_zone, x, y) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      {fx, fy} = nudge_if_occupied(state, player, x, y, nil)
      card =
        card
        |> Map.put("tapped", false)
        |> Map.put("x", fx)
        |> Map.put("y", fy)

      # Face-down cards retain existing known state (player keeps prior knowledge).
      # Face-up cards entering battlefield are visible to all.
      card = if card["is_face_down"], do: card, else: mark_known_to_both(card)

      {:ok, maybe_reveal_deck_top(append_to_zone(state, player, "battlefield", card), player)}
    end
  end

  def update_battlefield_position(state, player, instance_id, x, y) do
    {fx, fy} = nudge_if_occupied(state, player, x, y, instance_id)
    update_in_zone(state, player, "battlefield", instance_id, fn card ->
      card |> Map.put("x", fx) |> Map.put("y", fy)
    end)
  end

  # ─── Flip Card ────────────────────────────────────────────────────────────

  def flip_card(state, player, instance_id, zone) do
    update_in_zone(state, player, zone, instance_id, fn card ->
      if card["is_double_faced"] do
        Map.update!(card, "active_face", fn f -> if f == 0, do: 1, else: 0 end)
      else
        currently_face_down = card["is_face_down"]
        card = Map.update!(card, "is_face_down", &(!&1))
        # Only reveal knowledge when flipping face-up on the battlefield (public zone).
        # Flipping in hand is a private action and doesn't change visibility.
        if currently_face_down and zone == "battlefield", do: mark_known_to_both(card), else: card
      end
    end)
  end

  # ─── Draw Top Card to Destination ─────────────────────────────────────────

  # dest: "battlefield" | "battlefield_face_down" | "graveyard" | "exile"
  def draw_top_to(state, player, dest) do
    case get_in(state, [player, "zones", "deck"]) do
      [] -> {:ok, state}
      [card | rest] ->
        state = put_in(state, [player, "zones", "deck"], rest)

        state =
          case dest do
            "battlefield_face_down" ->
              {fx, fy} = nudge_if_occupied(state, player, 0.5, 0.5, nil)
              card = card |> Map.put("tapped", false) |> Map.put("is_face_down", true) |> Map.put("x", fx) |> Map.put("y", fy)
              update_in(state, [player, "zones", "battlefield"], &(&1 ++ [card]))

            "battlefield" ->
              {fx, fy} = nudge_if_occupied(state, player, 0.5, 0.5, nil)
              card = card |> Map.put("tapped", false) |> Map.put("is_face_down", false) |> Map.put("x", fx) |> Map.put("y", fy) |> mark_known_to_both()
              update_in(state, [player, "zones", "battlefield"], &(&1 ++ [card]))

            "graveyard" ->
              card = card |> reset_face() |> Map.put("tapped", false) |> reset_counters() |> mark_known_to_both()
              if card["is_token"], do: state, else: prepend_to_zone(state, player, "graveyard", card)

            "exile" ->
              card = card |> reset_face() |> Map.put("tapped", false) |> reset_counters() |> mark_known_to_both()
              if card["is_token"], do: state, else: prepend_to_zone(state, player, "exile", card)
          end

        {:ok, maybe_reveal_deck_top(state, player)}
    end
  end

  # ─── Draw Face-Down to Battlefield ────────────────────────────────────────

  def draw_face_down(state, player, x \\ 0.5, y \\ 0.5) do
    case get_in(state, [player, "zones", "deck"]) do
      [] -> {:ok, state}
      [card | rest] ->
        {fx, _} = nudge_if_occupied(state, player, x, y, nil)
        card =
          card
          |> Map.put("tapped", false)
          |> Map.put("is_face_down", true)
          |> Map.put("x", fx)
          |> Map.put("y", y)

        state =
          state
          |> put_in([player, "zones", "deck"], rest)
          |> update_in([player, "zones", "battlefield"], &(&1 ++ [card]))

        {:ok, state}
    end
  end

  # ─── Draw ─────────────────────────────────────────────────────────────────

  def draw(state, player, count) when count > 0 do
    deck = get_in(state, [player, "zones", "deck"])
    hand = get_in(state, [player, "zones", "hand"])
    top_revealed = get_in(state, [player, "top_revealed"]) || false

    # When top is revealed, each drawn card was publicly visible as it was drawn,
    # so all drawn cards are known to both players.
    drawn =
      deck
      |> Enum.take(count)
      |> Enum.map(fn card ->
        card = mark_known_to(card, player)
        if top_revealed, do: mark_known_to_both(card), else: card
      end)

    remaining = Enum.drop(deck, count)

    state =
      state
      |> put_in([player, "zones", "deck"], remaining)
      |> put_in([player, "zones", "hand"], hand ++ drawn)
      |> maybe_reveal_deck_top(player)

    {:ok, state}
  end

  def draw(state, _player, _count), do: {:ok, state}

  # ─── Shuffle ──────────────────────────────────────────────────────────────

  def shuffle(state, player) do
    state =
      update_in(state, [player, "zones", "deck"], fn deck ->
        deck
        |> Enum.map(&clear_known_to_both/1)
        |> Enum.shuffle()
      end)
      |> maybe_reveal_deck_top(player)

    {:ok, state}
  end

  # ─── Mulligan ─────────────────────────────────────────────────────────────

  def mulligan(state, player) do
    hand = get_in(state, [player, "zones", "hand"])
    deck = get_in(state, [player, "zones", "deck"])

    new_deck =
      (hand ++ deck)
      |> Enum.map(&clear_known_to_both/1)
      |> Enum.shuffle()

    {new_hand, new_deck} = Enum.split(new_deck, 7)

    state =
      state
      |> put_in([player, "zones", "hand"], new_hand)
      |> put_in([player, "zones", "deck"], new_deck)
      |> maybe_reveal_deck_top(player)

    {:ok, state}
  end

  # ─── Scry ─────────────────────────────────────────────────────────────────

  # Reveal top N cards (remove from deck top, return them for display).
  # When scrying more than 1 card, clear known state on all revealed cards —
  # the player sees them during scry but can't track individual positions afterward.
  # top_revealed does not change this — the new top is revealed after scry_resolve.
  def scry_reveal(state, player, count) do
    deck = get_in(state, [player, "zones", "deck"])
    top_cards = Enum.take(deck, count)
    top_cards = if count > 1, do: Enum.map(top_cards, &clear_known_to_both/1), else: top_cards
    remaining = Enum.drop(deck, count)
    state = put_in(state, [player, "zones", "deck"], remaining)
    {top_cards, state}
  end

  # Resolve scry - place cards based on decisions map %{instance_id => destination}
  def scry_resolve(state, player, decisions, scry_cards) do
    to_top = []
    to_bottom = []

    {state, to_top, to_bottom} =
      Enum.reduce(scry_cards, {state, to_top, to_bottom}, fn card, {st, tops, bottoms} ->
        dest = Map.get(decisions, card["instance_id"], "bottom")

        case dest do
          "top" ->
            {st, [mark_known_to(card, player) | tops], bottoms}

          "bottom" ->
            {st, tops, bottoms ++ [mark_known_to(card, player)]}

          "graveyard" ->
            {:ok, st} = move_to_graveyard_direct(st, player, card)
            {st, tops, bottoms}

          "exile" ->
            {:ok, st} = move_to_exile_direct(st, player, card)
            {st, tops, bottoms}

          _ ->
            {st, tops, bottoms ++ [card]}
        end
      end)

    deck = get_in(state, [player, "zones", "deck"])
    # to_top was built in reverse order (head prepend), reverse it
    new_deck = Enum.reverse(to_top) ++ deck ++ to_bottom
    state = put_in(state, [player, "zones", "deck"], new_deck)
    maybe_reveal_deck_top(state, player)
  end

  defp move_to_graveyard_direct(state, player, card) do
    card = card |> reset_face() |> mark_known_to_both()

    if card["is_token"] do
      {:ok, state}
    else
      {:ok, prepend_to_zone(state, player, "graveyard", card)}
    end
  end

  defp move_to_exile_direct(state, player, card) do
    card = card |> reset_face() |> mark_known_to_both()

    if card["is_token"] do
      {:ok, state}
    else
      {:ok, prepend_to_zone(state, player, "exile", card)}
    end
  end

  # ─── Toggle Top Revealed ─────────────────────────────────────────────────

  def toggle_top_revealed(state, player) do
    currently = get_in(state, [player, "top_revealed"]) || false
    state = put_in(state, [player, "top_revealed"], !currently)
    state = maybe_reveal_deck_top(state, player)
    {:ok, state}
  end

  # ─── Add Counter ─────────────────────────────────────────────────────────

  def add_counter(state, player, instance_id, counter_name) do
    update_in_zone(state, player, "battlefield", instance_id, fn card ->
      counters = card["counters"] || []
      new_counter = %{"name" => counter_name, "value" => 0}
      Map.put(card, "counters", counters ++ [new_counter])
    end)
  end

  def update_counter(state, player, instance_id, counter_index, delta) do
    update_in_zone(state, player, "battlefield", instance_id, fn card ->
      counters = card["counters"] || []

      updated =
        List.update_at(counters, counter_index, fn counter ->
          Map.update!(counter, "value", &(&1 + delta))
        end)

      Map.put(card, "counters", updated)
    end)
  end

  def remove_counter(state, player, instance_id, counter_index) do
    update_in_zone(state, player, "battlefield", instance_id, fn card ->
      counters = card["counters"] || []
      Map.put(card, "counters", List.delete_at(counters, counter_index))
    end)
  end

  # ─── Copy Card (token) ────────────────────────────────────────────────────

  def copy_card(state, player, instance_id) do
    case find_in_zone(state, player, "battlefield", instance_id) do
      nil ->
        {:error, "Card not found on battlefield"}

      original ->
        {fx, _} = nudge_if_occupied(state, player, original["x"], original["y"], nil)
        token =
          original
          |> Map.put("instance_id", Ecto.UUID.generate())
          |> Map.put("is_token", true)
          |> Map.put("x", fx)
          |> Map.put("y", original["y"])

        {:ok, append_to_zone(state, player, "battlefield", token)}
    end
  end

  # Copy a card from the opponent's battlefield onto the player's battlefield.
  def copy_opponent_card(state, player, instance_id) do
    opp = if player == "host", do: "opponent", else: "host"

    case find_in_zone(state, opp, "battlefield", instance_id) do
      nil -> {:ok, state}
      %{"is_face_down" => true} -> {:ok, state}
      original ->
        {fx, _} = nudge_if_occupied(state, player, original["x"], original["y"], nil)
        token =
          original
          |> Map.put("instance_id", Ecto.UUID.generate())
          |> Map.put("is_token", true)
          |> Map.put("x", fx)
          |> Map.put("y", original["y"])

        {:ok, append_to_zone(state, player, "battlefield", token)}
    end
  end

  # ─── Create Token ─────────────────────────────────────────────────────────

  def create_token(state, player, card, x, y) do
    token =
      card
      |> State.build_token_instance()
      |> Map.put("x", x)
      |> Map.put("y", y)
      |> Map.put("is_token", true)

    {:ok, append_to_zone(state, player, "battlefield", token)}
  end

  # ─── Life Total & Trackers ────────────────────────────────────────────────

  def adjust_life(state, player, delta) do
    state = update_in(state, [player, "life"], &(&1 + delta))
    {:ok, state}
  end

  def add_tracker(state, player, name) do
    state =
      update_in(state, [player, "trackers"], fn trackers ->
        trackers ++ [%{"name" => name, "value" => 0}]
      end)

    {:ok, state}
  end

  def adjust_tracker(state, player, tracker_index, delta) do
    state =
      update_in(state, [player, "trackers"], fn trackers ->
        List.update_at(trackers, tracker_index, fn t ->
          Map.update!(t, "value", &(&1 + delta))
        end)
      end)

    {:ok, state}
  end

  def remove_tracker(state, player, tracker_index) do
    state =
      update_in(state, [player, "trackers"], fn trackers ->
        List.delete_at(trackers, tracker_index)
      end)

    {:ok, state}
  end

  # ─── Untap All ────────────────────────────────────────────────────────────

  def untap_all(state, player) do
    state =
      update_in(state, [player, "zones", "battlefield"], fn cards ->
        Enum.map(cards, &Map.put(&1, "tapped", false))
      end)

    {:ok, state}
  end

  # ─── Private Helpers ─────────────────────────────────────────────────────

  # Nudge x right by 1% steps until no other card occupies the same rounded-percent
  # position, or the battlefield boundary (98%) is reached. Uses round() instead of
  # trunc() to avoid float drift (e.g. 57/100*100 = 56.999... -> trunc = 56 != 57).
  # Pass exclude_instance_id to ignore the card being moved.
  defp nudge_if_occupied(state, player, x, y, exclude_instance_id) do
    bf = get_in(state, [player, "zones", "battlefield"]) || []
    occupied =
      bf
      |> Enum.reject(fn c -> exclude_instance_id != nil and c["instance_id"] == exclude_instance_id end)
      |> MapSet.new(fn c -> {round((c["x"] || 0) * 100), round((c["y"] || 0) * 100)} end)
    ty = round(y * 100)
    start = round(x * 100)
    tx =
      Stream.iterate(start, &(&1 + 1))
      |> Enum.find(fn cx -> cx >= 95 or not MapSet.member?(occupied, {cx, ty}) end)
    # Store as integer percent / 100 so trunc(result * 100) == tx (no float drift).
    {tx / 100, ty / 100}
  end

  defp find_in_zone(state, player, zone, instance_id) do
    cards = get_in(state, [player, "zones", zone]) || []
    Enum.find(cards, fn c -> c["instance_id"] == instance_id end)
  end

  defp remove_from_zone(state, player, zone, instance_id) do
    cards = get_in(state, [player, "zones", zone]) || []

    case Enum.split_with(cards, fn c -> c["instance_id"] == instance_id end) do
      {[card], rest} ->
        state = put_in(state, [player, "zones", zone], rest)
        {:ok, {card, state}}

      _ ->
        {:error, "Card #{instance_id} not found in #{zone}"}
    end
  end

  defp update_in_zone(state, player, zone, instance_id, update_fn) do
    cards = get_in(state, [player, "zones", zone]) || []
    updated = Enum.map(cards, fn c ->
      if c["instance_id"] == instance_id, do: update_fn.(c), else: c
    end)
    state = put_in(state, [player, "zones", zone], updated)
    {:ok, state}
  end

  defp prepend_to_zone(state, player, zone, card) do
    update_in(state, [player, "zones", zone], fn cards -> [card | cards] end)
  end

  defp append_to_zone(state, player, zone, card) do
    update_in(state, [player, "zones", zone], fn cards -> cards ++ [card] end)
  end

  defp insert_into_zone(state, player, zone, card, index) do
    update_in(state, [player, "zones", zone], fn cards ->
      clamped = max(0, min(index, length(cards)))
      List.insert_at(cards, clamped, card)
    end)
  end

  defp reset_counters(card), do: Map.put(card, "counters", [])

  defp reset_face(card) do
    card
    |> Map.put("is_face_down", false)
    |> Map.put("active_face", 0)
  end

  # Mark a card as known to both when it was in a public zone (everyone saw it).
  # Hand is private so it only counts from battlefield/graveyard/exile.
  defp mark_known_from_zone(card, source_zone) when source_zone in ["battlefield", "graveyard", "exile"] do
    mark_known_to_both(card)
  end
  defp mark_known_from_zone(card, _source_zone), do: card

  # ─── Reveal / Hide Hand ───────────────────────────────────────────────────

  # Mark all given cards in player's hand as known to the opponent.
  def reveal_cards(state, player, instance_ids) do
    opp_role = if player == "host", do: "opponent", else: "host"

    state =
      update_in(state, [player, "zones", "hand"], fn hand ->
        Enum.map(hand, fn card ->
          if card["instance_id"] in instance_ids do
            mark_known_to(card, opp_role)
          else
            card
          end
        end)
      end)

    {:ok, state}
  end

  # Clear opponent knowledge for all cards in player's hand.
  def hide_hand(state, player) do
    opp_role = if player == "host", do: "opponent", else: "host"

    state =
      update_in(state, [player, "zones", "hand"], fn hand ->
        Enum.map(hand, &clear_known_to(&1, opp_role))
      end)

    {:ok, state}
  end
end
