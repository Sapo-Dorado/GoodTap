defmodule Goodtap.Repo.Migrations.CreateCards do
  use Ecto.Migration

  def change do
    create table(:cards, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :layout, :string
      add :data, :map, null: false
      timestamps()
    end

    create index(:cards, [:name])
    create index(:cards, [:layout])
  end
end
