defmodule Goodtap.Repo.Migrations.CreateCardPrintings do
  use Ecto.Migration

  def change do
    create table(:card_printings, primary_key: false) do
      add :id, :string, primary_key: true
      add :card_name, :string, null: false
      add :set_code, :string, null: false
      add :collector_number, :string, null: false
      add :image_uris, :map, null: false
      add :is_token, :boolean, null: false, default: false
      add :data, :map, null: false
      timestamps()
    end

    create index(:card_printings, [:card_name])
    create index(:card_printings, [:set_code, :collector_number])
  end
end
