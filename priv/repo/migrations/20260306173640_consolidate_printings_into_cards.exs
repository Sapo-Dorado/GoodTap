defmodule Goodtap.Repo.Migrations.ConsolidatePrintingsIntoCards do
  use Ecto.Migration

  def change do
    # Add printings array to cards
    alter table(:cards) do
      add :printings, :jsonb, default: "[]", null: false
    end

    # Drop the now-redundant card_printings table
    # printing_id on deck_cards stays — it references a printing ID within card.printings
    drop table(:card_printings)
  end
end
