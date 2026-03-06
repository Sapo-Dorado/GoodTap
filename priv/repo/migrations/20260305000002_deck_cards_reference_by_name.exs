defmodule Goodtap.Repo.Migrations.DeckCardsReferenceByName do
  use Ecto.Migration

  def change do
    # Drop the FK constraint and rename the column to card_name
    drop constraint(:deck_cards, "deck_cards_card_id_fkey")
    drop unique_index(:deck_cards, [:deck_id, :card_id, :board])

    rename table(:deck_cards), :card_id, to: :card_name

    create unique_index(:deck_cards, [:deck_id, :card_name, :board])
  end
end
