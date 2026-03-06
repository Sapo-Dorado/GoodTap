defmodule GoodtapWeb.Hotkeys do
  @hotkeys %{
    tap: "space",
    move_to_graveyard: "d",
    move_to_exile: "s",
    move_to_deck_top: "t",
    move_to_deck_bottom: "y",
    flip_card: "f",
    draw: "1-9",
    shuffle: "v",
    add_counter: "u",
    copy_card: "k",
    create_token: "w",
    untap_all: "x",
    draw_one: "c",
    draw_face_down: "p"
  }

  def key_for(action), do: @hotkeys[action]

  def display_for(:tap), do: "Space"
  def display_for(:draw), do: "1–9"
  def display_for(action) do
    key = @hotkeys[action]
    if key, do: String.upcase(key), else: nil
  end

  def valid_actions_for("hand") do
    [:move_to_graveyard, :move_to_exile, :move_to_deck_top, :move_to_deck_bottom, :flip_card]
  end

  def valid_actions_for("battlefield") do
    [:tap, :move_to_graveyard, :move_to_exile, :move_to_deck_top, :move_to_deck_bottom, :flip_card, :add_counter, :copy_card]
  end

  def valid_actions_for("deck") do
    [:draw, :shuffle, :scry, :find_card, :draw_face_down]
  end

  def valid_actions_for("deck_top") do
    [:draw, :move_to_graveyard, :move_to_exile, :shuffle, :scry, :draw_face_down]
  end

  def valid_actions_for("graveyard") do
    [:move_to_exile, :move_to_hand, :move_to_deck_top, :move_to_deck_bottom]
  end

  def valid_actions_for("exile") do
    [:move_to_graveyard, :move_to_hand, :move_to_deck_top, :move_to_deck_bottom]
  end

  def valid_actions_for(_), do: []

  def action_label(:tap), do: "Tap / Untap"
  def action_label(:move_to_graveyard), do: "Move to Graveyard"
  def action_label(:move_to_exile), do: "Move to Exile"
  def action_label(:move_to_hand), do: "Move to Hand"
  def action_label(:move_to_deck_top), do: "Move to Top of Deck"
  def action_label(:move_to_deck_bottom), do: "Move to Bottom of Deck"
  def action_label(:flip_card), do: "Flip Card"
  def action_label(:draw), do: "Draw"
  def action_label(:shuffle), do: "Shuffle"
  def action_label(:scry), do: "Scry"
  def action_label(:add_counter), do: "Add Counter"
  def action_label(:copy_card), do: "Copy Card"
  def action_label(:create_token), do: "Create Token"
  def action_label(:untap_all), do: "Untap All"
  def action_label(:draw_one), do: "Draw 1"
  def action_label(:draw_face_down), do: "Draw Face-Down to Battlefield"
  def action_label(:find_card), do: "Find Card"
  def action_label(:mulligan), do: "Mulligan"
  def action_label(other), do: to_string(other)
end
