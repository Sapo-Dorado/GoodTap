defmodule GoodtapWeb.Hotkeys do
  # ─── Key Bindings ─────────────────────────────────────────────────────────
  # Each action maps to the key string sent by the JS keydown handler.
  # Lowercase letters = plain key. Uppercase letters = shift held.
  # "space" = spacebar.
  #
  # JS normalisation: e.key === " " → "space"; otherwise e.key as-is (so
  # shift+l arrives as "L", shift+u as "U", etc.).

  @keys %{
    shuffle:              "s",
    draw_one:             "d",
    untap_all:            "u",
    move_to_graveyard:    "g",
    move_to_exile:        "e",
    move_to_deck_top:     "l",
    move_to_deck_bottom:  "L",
    move_to_hand:         "h",
    move_to_battlefield:  "b",
    copy_card:            "x",
    flip_card:            "f",
    tap:                  "t",
    add_counter:          "c",
    create_token:         "w",
    new_turn:             "n",
    draw:                 "1-9",
    draw_face_down:       "p",
    target_card:          "o"
  }

  def key_for(action), do: @keys[action]

  # Keys that move a card out of its current zone — used to drive optimistic
  # hide in JS. Rendered into the DOM as data-move-keys so JS never hardcodes them.
  @move_actions [:move_to_graveyard, :move_to_exile, :move_to_deck_top,
                 :move_to_deck_bottom, :move_to_hand, :move_to_battlefield]
  def move_keys_csv do
    @move_actions |> Enum.map(&@keys[&1]) |> Enum.reject(&is_nil/1) |> Enum.join(",")
  end

  def display_for(:draw), do: "1–9"
  def display_for(action) do
    case @keys[action] do
      nil -> nil
      key ->
        cond do
          key == "space" -> "Space"
          String.upcase(key) == key and byte_size(key) == 1 -> "⇧#{String.upcase(key)}"
          true -> String.upcase(key)
        end
    end
  end

  # ─── Valid Actions Per Zone ────────────────────────────────────────────────

  def valid_actions_for("hand") do
    [:move_to_graveyard, :move_to_exile, :move_to_deck_top, :move_to_deck_bottom,
     :move_to_battlefield, :flip_card, :reveal_card]
  end

  def valid_actions_for("battlefield") do
    [:tap, :move_to_graveyard, :move_to_exile, :move_to_deck_top, :move_to_deck_bottom,
     :move_to_hand, :flip_card, :add_counter, :copy_card, :target_card]
  end

  def valid_actions_for_opponent_battlefield do
    [:copy_opponent_card, :target_card]
  end

  def valid_actions_for("deck") do
    [:draw, :shuffle, :scry, :find_card, :draw_top_to, :toggle_top_revealed]
  end

  def valid_actions_for("deck_top") do
    [:draw, :shuffle, :scry, :draw_top_to, :toggle_top_revealed]
  end

  def valid_actions_for("graveyard") do
    [:move_to_exile, :move_to_hand, :move_to_deck_top, :move_to_deck_bottom,
     :move_to_battlefield, :move_all_to_exile]
  end

  def valid_actions_for("exile") do
    [:move_to_graveyard, :move_to_hand, :move_to_deck_top, :move_to_deck_bottom,
     :move_to_battlefield]
  end

  def valid_actions_for(_), do: []

  # ─── Labels ───────────────────────────────────────────────────────────────

  def action_label(:tap), do: "Tap / Untap"
  def action_label(:move_all_to_exile), do: "Move All to Exile"
  def action_label(:move_to_graveyard), do: "Move to Graveyard"
  def action_label(:move_to_exile), do: "Move to Exile"
  def action_label(:move_to_hand), do: "Move to Hand"
  def action_label(:move_to_deck_top), do: "Move to Top of Library"
  def action_label(:move_to_deck_bottom), do: "Move to Bottom of Library"
  def action_label(:move_to_battlefield), do: "Move to Battlefield"
  def action_label(:flip_card), do: "Flip Card"
  def action_label(:draw), do: "Draw"
  def action_label(:new_turn), do: "Untap All & Draw"
  def action_label(:draw_one), do: "Draw 1"
  def action_label(:shuffle), do: "Shuffle"
  def action_label(:scry), do: "Scry"
  def action_label(:add_counter), do: "Add Counter"
  def action_label(:copy_card), do: "Copy Card"
  def action_label(:create_token), do: "Create Token"
  def action_label(:untap_all), do: "Untap All"
  def action_label(:draw_face_down), do: "Draw Face-Down to Battlefield"
  def action_label(:draw_top_to), do: "Draw Top Card to..."
  def action_label(:find_card), do: "Find Card"
  def action_label(:mulligan), do: "Mulligan"
  def action_label(:reveal_hand), do: "Reveal Hand"
  def action_label(:hide_hand), do: "Hide Hand"
  def action_label(:reveal_card), do: "Reveal to Opponent"
  def action_label(:copy_opponent_card), do: "Copy Card"
  def action_label(:target_card), do: "Target"
  def action_label(:toggle_top_revealed), do: "Keep Top Revealed"
  def action_label(other), do: to_string(other)
end
