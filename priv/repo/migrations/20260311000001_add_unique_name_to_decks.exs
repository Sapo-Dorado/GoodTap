defmodule Goodtap.Repo.Migrations.AddUniqueNameToDecks do
  use Ecto.Migration

  def change do
    create unique_index(:decks, [:user_id, :name])
  end
end
