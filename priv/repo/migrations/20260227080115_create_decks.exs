defmodule Goodtap.Repo.Migrations.CreateDecks do
  use Ecto.Migration

  def change do
    create table(:decks) do
      add :name, :string, null: false
      add :source_url, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false
      timestamps()
    end

    create index(:decks, [:user_id])

    create table(:deck_cards) do
      add :deck_id, references(:decks, on_delete: :delete_all), null: false
      add :card_id, references(:cards, type: :string, on_delete: :restrict), null: false
      add :quantity, :integer, default: 1, null: false
      add :board, :string, default: "main", null: false
    end

    create index(:deck_cards, [:deck_id])
    create unique_index(:deck_cards, [:deck_id, :card_id, :board])
  end
end
