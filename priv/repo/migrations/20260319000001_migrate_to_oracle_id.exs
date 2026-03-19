defmodule Goodtap.Repo.Migrations.MigrateToOracleId do
  use Ecto.Migration

  def change do
    # Add oracle_id to cards table
    alter table(:cards) do
      add :oracle_id, :string
    end

    create index(:cards, [:oracle_id])

    # Change deck_cards: rename card_name → oracle_id
    # Drop old unique index first
    drop_if_exists unique_index(:deck_cards, [:deck_id, :card_name, :board])

    rename table(:deck_cards), :card_name, to: :oracle_id

    create unique_index(:deck_cards, [:deck_id, :oracle_id, :board])
  end
end
