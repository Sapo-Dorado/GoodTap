defmodule Goodtap.GameEngine.Actions do
  alias Goodtap.GameEngine.State

  # ─── Known Helpers ────────────────────────────────────────────────────────

  defp mark_known_to(card, role), do: put_in_known(card, role, true)
  defp clear_known_to(card, role), do: put_in_known(card, role, false)

  defp mark_known_to_all(card, player_keys) do
    Enum.reduce(player_keys, card, &mark_known_to(&2, &1))
  end

  defp clear_known_to_all(card, player_keys) do
    Enum.reduce(player_keys, card, &clear_known_to(&2, &1))
  end

  # Convenience wrappers that derive player keys from state
  defp mark_known_to_both(card, state), do: mark_known_to_all(card, State.all_player_keys(state))
  defp clear_known_to_both(card, state), do: clear_known_to_all(card, State.all_player_keys(state))

  # If the player has "top_revealed" enabled, mark the current top deck card known to all.
  # Called after any action that changes the deck contents or order.
  defp maybe_reveal_deck_top(state, player) do
    if get_in(state, [player, "top_revealed"]) do
      case get_in(state, [player, "zones", "deck"]) do
        [top | rest] ->
          put_in(state, [player, "zones", "deck"], [mark_known_to_both(top, state) | rest])
        _ ->
          state
      end
    else
      state
    end
  end

  defp put_in_known(card, role, value) do
    known = if is_map(card["known"]), do: card["known"], else: %{}
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
      card = card |> reset_face() |> Map.put("tapped", false) |> reset_counters() |> mark_known_to_both(state)

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
      card = card |> reset_face() |> Map.put("tapped", false) |> reset_counters() |> mark_known_to_both(state)

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
    to_exile = Enum.map(to_exile, &(&1 |> reset_face() |> Map.put("tapped", false) |> reset_counters() |> mark_known_to_both(state)))
    state
    |> put_in([player, "zones", "graveyard"], [])
    |> put_in([player, "zones", "exile"], to_exile ++ existing_exile)
    |> then(&{:ok, &1})
  end

  # ─── Reorder Within Zone ──────────────────────────────────────────────────

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
      card = card |> reset_face() |> Map.put("tapped", false) |> reset_counters() |> mark_known_to(player)

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
      card = if was_face_down, do: card, else: mark_known_from_zone(card, source_zone, state)

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
      card = if was_face_down, do: card, else: mark_known_from_zone(card, source_zone, state)

      if card["is_token"] do
        {:ok, state}
      else
        {:ok, maybe_reveal_deck_top(append_to_zone(state, player, "deck", card), player)}
      end
    end
  end

  # ─── Move to Battlefield ──────────────────────────────────────────────────

  def move_to_battlefield(state, player, instance_id, source_zone, x, y, nudge \\ true) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      {fx, fy} = if nudge, do: nudge_if_occupied(state, player, x, y, nil), else: {x, y}
      {state, z} = next_z(state)
      card =
        card
        |> Map.put("tapped", false)
        |> Map.put("x", fx)
        |> Map.put("y", fy)
        |> Map.put("z", z)
        |> Map.delete("on_battlefield")

      card = if card["is_face_down"], do: card, else: mark_known_to_both(card, state)

      {:ok, maybe_reveal_deck_top(append_to_zone(state, player, "battlefield", card), player)}
    end
  end

  # Move a card to the battlefield, visually associating it with target_player's side.
  # The card stays in source_player's zone; on_battlefield is set to target_player.
  # When target_player == source_player, behaves like move_to_battlefield (own side).
  def move_to_player_battlefield(state, source_player, target_player, instance_id, source_zone, x, y) do
    with {:ok, {card, state}} <- remove_from_zone(state, source_player, source_zone, instance_id) do
      {state, z} = next_z(state)
      card =
        card
        |> Map.put("tapped", false)
        |> Map.put("x", x)
        |> Map.put("y", y)
        |> Map.put("z", z)
        |> then(fn c -> if c["is_face_down"], do: c, else: mark_known_to_both(c, state) end)
        |> then(fn c ->
          if target_player == source_player,
            do: Map.delete(c, "on_battlefield"),
            else: Map.put(c, "on_battlefield", target_player)
        end)

      {:ok, append_to_zone(state, source_player, "battlefield", card)}
    end
  end

  def update_battlefield_position(state, player, instance_id, x, y, target_player \\ nil) do
    {state, z} = next_z(state)
    update_in_zone(state, player, "battlefield", instance_id, fn card ->
      card
      |> Map.put("x", x)
      |> Map.put("y", y)
      |> Map.put("z", z)
      |> then(fn c ->
        cond do
          target_player == nil -> c
          target_player == player -> Map.delete(c, "on_battlefield")
          true -> Map.put(c, "on_battlefield", target_player)
        end
      end)
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
        if currently_face_down and zone == "battlefield", do: mark_known_to_both(card, state), else: card
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
              {state, z} = next_z(state)
              card = card |> Map.put("tapped", false) |> Map.put("is_face_down", true) |> Map.put("x", fx) |> Map.put("y", fy) |> Map.put("z", z)
              update_in(state, [player, "zones", "battlefield"], &(&1 ++ [card]))

            "battlefield" ->
              {fx, fy} = nudge_if_occupied(state, player, 0.5, 0.5, nil)
              {state, z} = next_z(state)
              card = card |> Map.put("tapped", false) |> Map.put("is_face_down", false) |> Map.put("x", fx) |> Map.put("y", fy) |> Map.put("z", z) |> mark_known_to_both(state)
              update_in(state, [player, "zones", "battlefield"], &(&1 ++ [card]))

            "graveyard" ->
              card = card |> reset_face() |> Map.put("tapped", false) |> reset_counters() |> mark_known_to_both(state)
              if card["is_token"], do: state, else: prepend_to_zone(state, player, "graveyard", card)

            "exile" ->
              card = card |> reset_face() |> Map.put("tapped", false) |> reset_counters() |> mark_known_to_both(state)
              if card["is_token"], do: state, else: prepend_to_zone(state, player, "exile", card)

            "hand" ->
              card = card |> reset_face() |> Map.put("tapped", false) |> mark_known_to(player)
              append_to_zone(state, player, "hand", card)
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
        if top_revealed, do: mark_known_to_both(card, state), else: card
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
        |> Enum.map(&clear_known_to_both(&1, state))
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
      |> Enum.map(&clear_known_to_both(&1, state))
      |> Enum.shuffle()

    {new_hand, new_deck} = Enum.split(new_deck, 7)
    new_hand = Enum.map(new_hand, &mark_known_to(&1, player))

    state =
      state
      |> put_in([player, "zones", "hand"], new_hand)
      |> put_in([player, "zones", "deck"], new_deck)
      |> maybe_reveal_deck_top(player)

    {:ok, state}
  end

  # ─── Scry ─────────────────────────────────────────────────────────────────

  # Reveal top N cards (remove from deck top, return them for display).
  def scry_reveal(state, player, count) do
    deck = get_in(state, [player, "zones", "deck"])
    top_cards = Enum.take(deck, count)
    top_cards = if count > 1, do: Enum.map(top_cards, &clear_known_to_both(&1, state)), else: top_cards
    top_cards = Enum.map(top_cards, &mark_known_to(&1, player))
    remaining = Enum.drop(deck, count)
    state = put_in(state, [player, "zones", "deck"], remaining)
    {top_cards, state}
  end

  # Resolve scry - place cards based on decisions map %{instance_id => destination}.
  # decision_order is the list of instance_ids in the order they were clicked.
  # Cards sent to top are ordered so that the first-clicked is deepest and
  # the last-clicked is on top of the deck. Bottom cards use the same order.
  def scry_resolve(state, player, decisions, scry_cards, decision_order) do
    card_by_id = Map.new(scry_cards, &{&1["instance_id"], &1})

    # Process in click order so position reflects user intent
    {state, to_top, to_bottom} =
      Enum.reduce(decision_order, {state, [], []}, fn id, {st, tops, bottoms} ->
        card = card_by_id[id]
        dest = Map.get(decisions, id, "bottom")

        case dest do
          "top" ->
            {st, tops ++ [mark_known_to(card, player)], bottoms}

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
    # First-clicked top card is deepest (leftmost), last-clicked is on top
    new_deck = Enum.reverse(to_top) ++ deck ++ to_bottom
    state = put_in(state, [player, "zones", "deck"], new_deck)
    maybe_reveal_deck_top(state, player)
  end

  defp move_to_graveyard_direct(state, player, card) do
    card = card |> reset_face() |> mark_known_to_both(state)

    if card["is_token"] do
      {:ok, state}
    else
      {:ok, prepend_to_zone(state, player, "graveyard", card)}
    end
  end

  defp move_to_exile_direct(state, player, card) do
    card = card |> reset_face() |> mark_known_to_both(state)

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

  def add_counter(state, player, instance_id, counter_name, has_quantity \\ true) do
    update_in_zone(state, player, "battlefield", instance_id, fn card ->
      counters = card["counters"] || []
      new_counter =
        if has_quantity,
          do: %{"name" => counter_name, "value" => 0, "has_quantity" => true},
          else: %{"name" => counter_name, "has_quantity" => false}
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
        {state, z} = next_z(state)
        token =
          original
          |> Map.put("instance_id", Ecto.UUID.generate())
          |> Map.put("is_token", true)
          |> Map.put("x", fx)
          |> Map.put("y", original["y"])
          |> Map.put("z", z)

        {:ok, append_to_zone(state, player, "battlefield", token)}
    end
  end

  # Copy a card from a source player's battlefield onto the current player's battlefield.
  def copy_opponent_card(state, player, source_player, instance_id) do
    case find_in_zone(state, source_player, "battlefield", instance_id) do
      nil -> {:ok, state}
      %{"is_face_down" => true} -> {:ok, state}
      original ->
        {fx, _} = nudge_if_occupied(state, player, original["x"], original["y"], nil)
        {state, z} = next_z(state)
        token =
          original
          |> Map.put("instance_id", Ecto.UUID.generate())
          |> Map.put("is_token", true)
          |> Map.put("x", fx)
          |> Map.put("y", original["y"])
          |> Map.put("z", z)

        {:ok, append_to_zone(state, player, "battlefield", token)}
    end
  end

  # ─── Create Token ─────────────────────────────────────────────────────────

  def create_token(state, player, card, x, y, printing_id \\ nil) do
    {fx, fy} = nudge_if_occupied(state, player, x, y, nil)
    {state, z} = next_z(state)
    token =
      card
      |> State.build_token_instance(printing_id)
      |> Map.put("x", fx)
      |> Map.put("y", fy)
      |> Map.put("z", z)
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

  # ─── Reveal / Hide Hand ───────────────────────────────────────────────────

  # Mark all given cards in player's hand as known to all other players.
  def reveal_cards(state, player, instance_ids) do
    other_players = other_player_keys(state, player)

    state =
      update_in(state, [player, "zones", "hand"], fn hand ->
        Enum.map(hand, fn card ->
          if card["instance_id"] in instance_ids do
            mark_known_to_all(card, other_players)
          else
            card
          end
        end)
      end)

    {:ok, state}
  end

  # Clear all other players' knowledge for cards in player's hand.
  def hide_hand(state, player) do
    other_players = other_player_keys(state, player)

    state =
      update_in(state, [player, "zones", "hand"], fn hand ->
        Enum.map(hand, &clear_known_to_all(&1, other_players))
      end)

    {:ok, state}
  end

  # ─── Private Helpers ─────────────────────────────────────────────────────

  @max_card_z 15

  defp next_z(state) do
    next = (state["z_counter"] || 0) + 1

    if next > @max_card_z do
      # Renumber all battlefield cards across all players by their current z order,
      # then assign the next available z value.
      all_cards =
        State.all_player_keys(state)
        |> Enum.flat_map(fn role ->
          (get_in(state, [role, "zones", "battlefield"]) || [])
          |> Enum.map(&{role, &1})
        end)
        |> Enum.sort_by(fn {_role, c} -> c["z"] || 0 end)

      {state, _} =
        Enum.reduce(all_cards, {state, 1}, fn {role, card}, {st, i} ->
          updated =
            (get_in(st, [role, "zones", "battlefield"]) || [])
            |> Enum.map(fn c ->
              if c["instance_id"] == card["instance_id"], do: Map.put(c, "z", i), else: c
            end)

          {put_in(st, [role, "zones", "battlefield"], updated), i + 1}
        end)

      z = length(all_cards) + 1
      {Map.put(state, "z_counter", z), z}
    else
      {Map.put(state, "z_counter", next), next}
    end
  end

  # Returns all player keys in state except the given one.
  defp other_player_keys(state, player_key) do
    State.all_player_keys(state) |> Enum.reject(&(&1 == player_key))
  end

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

  # Mark a card as known to all when it was in a public zone.
  defp mark_known_from_zone(card, source_zone, state) when source_zone in ["battlefield", "graveyard", "exile"] do
    mark_known_to_both(card, state)
  end
  defp mark_known_from_zone(card, _source_zone, _state), do: card
end
