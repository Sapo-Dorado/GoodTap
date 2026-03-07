defmodule Goodtap.Repo.Migrations.AddPrintingIdToDeckCards do
  use Ecto.Migration

  def change do
    alter table(:deck_cards) do
      add :printing_id, :string, null: true
    end
  end
end
