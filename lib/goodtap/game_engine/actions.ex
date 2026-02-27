defmodule Goodtap.GameEngine.Actions do
  alias Goodtap.GameEngine.State

  @max_counters 3

  # ─── Tap ──────────────────────────────────────────────────────────────────

  def tap(state, player, instance_id) do
    update_in_zone(state, player, "battlefield", instance_id, fn card ->
      Map.update!(card, "tapped", &(!&1))
    end)
  end

  # ─── Move to Graveyard ────────────────────────────────────────────────────

  def move_to_graveyard(state, player, instance_id, source_zone) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      card = card |> reset_face() |> Map.put("tapped", false)

      if card["is_token"] do
        {:ok, state}
      else
        {:ok, prepend_to_zone(state, player, "graveyard", card)}
      end
    end
  end

  # ─── Move to Exile ────────────────────────────────────────────────────────

  def move_to_exile(state, player, instance_id, source_zone) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      card = card |> reset_face() |> Map.put("tapped", false)

      if card["is_token"] do
        {:ok, state}
      else
        {:ok, prepend_to_zone(state, player, "exile", card)}
      end
    end
  end

  # ─── Move to Hand ─────────────────────────────────────────────────────────

  def move_to_hand(state, player, instance_id, source_zone) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      card = Map.put(card, "tapped", false)

      if card["is_token"] do
        {:ok, state}
      else
        {:ok, append_to_zone(state, player, "hand", card)}
      end
    end
  end

  # ─── Move to Deck Top ────────────────────────────────────────────────────

  def move_to_deck_top(state, player, instance_id, source_zone) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      card = card |> reset_face() |> Map.put("tapped", false)

      if card["is_token"] do
        {:ok, state}
      else
        {:ok, prepend_to_zone(state, player, "deck", card)}
      end
    end
  end

  def move_to_deck_bottom(state, player, instance_id, source_zone) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      card = card |> reset_face() |> Map.put("tapped", false)

      if card["is_token"] do
        {:ok, state}
      else
        {:ok, append_to_zone(state, player, "deck", card)}
      end
    end
  end

  # ─── Move to Battlefield ──────────────────────────────────────────────────

  def move_to_battlefield(state, player, instance_id, source_zone, x, y) do
    with {:ok, {card, state}} <- remove_from_zone(state, player, source_zone, instance_id) do
      card =
        card
        |> Map.put("tapped", false)
        |> Map.put("x", x)
        |> Map.put("y", y)

      {:ok, append_to_zone(state, player, "battlefield", card)}
    end
  end

  def update_battlefield_position(state, player, instance_id, x, y) do
    update_in_zone(state, player, "battlefield", instance_id, fn card ->
      card |> Map.put("x", x) |> Map.put("y", y)
    end)
  end

  # ─── Flip Card ────────────────────────────────────────────────────────────

  def flip_card(state, player, instance_id, zone) do
    update_in_zone(state, player, zone, instance_id, fn card ->
      if card["is_double_faced"] do
        Map.update!(card, "active_face", fn f -> if f == 0, do: 1, else: 0 end)
      else
        Map.update!(card, "is_face_down", &(!&1))
      end
    end)
  end

  # ─── Draw ─────────────────────────────────────────────────────────────────

  def draw(state, player, count) when count > 0 do
    deck = get_in(state, [player, "zones", "deck"])
    hand = get_in(state, [player, "zones", "hand"])
    drawn = Enum.take(deck, count)
    remaining = Enum.drop(deck, count)

    state =
      state
      |> put_in([player, "zones", "deck"], remaining)
      |> put_in([player, "zones", "hand"], hand ++ drawn)

    {:ok, state}
  end

  def draw(state, _player, _count), do: {:ok, state}

  # ─── Shuffle ──────────────────────────────────────────────────────────────

  def shuffle(state, player) do
    state = update_in(state, [player, "zones", "deck"], &Enum.shuffle/1)
    {:ok, state}
  end

  # ─── Scry ─────────────────────────────────────────────────────────────────

  # Reveal top N cards (remove from deck top, return them for display)
  def scry_reveal(state, player, count) do
    deck = get_in(state, [player, "zones", "deck"])
    top_cards = Enum.take(deck, count)
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
            {st, [card | tops], bottoms}

          "bottom" ->
            {st, tops, bottoms ++ [card]}

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
    state
  end

  defp move_to_graveyard_direct(state, player, card) do
    card = reset_face(card)

    if card["is_token"] do
      {:ok, state}
    else
      {:ok, prepend_to_zone(state, player, "graveyard", card)}
    end
  end

  defp move_to_exile_direct(state, player, card) do
    card = reset_face(card)

    if card["is_token"] do
      {:ok, state}
    else
      {:ok, prepend_to_zone(state, player, "exile", card)}
    end
  end

  # ─── Add Counter ─────────────────────────────────────────────────────────

  def add_counter(state, player, instance_id, counter_name) do
    update_in_zone(state, player, "battlefield", instance_id, fn card ->
      counters = card["counters"] || []

      if length(counters) >= @max_counters do
        card
      else
        new_counter = %{"name" => counter_name, "value" => 0}
        Map.put(card, "counters", counters ++ [new_counter])
      end
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
        token =
          original
          |> Map.put("instance_id", Ecto.UUID.generate())
          |> Map.put("is_token", true)
          |> Map.put("x", min(original["x"] + 0.05, 0.95))
          |> Map.put("y", min(original["y"] + 0.05, 0.95))

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

  defp reset_face(card) do
    card
    |> Map.put("is_face_down", false)
    |> Map.put("active_face", 0)
  end
end
