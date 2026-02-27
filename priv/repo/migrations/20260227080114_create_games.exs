defmodule Goodtap.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :string, primary_key: true
      add :host_id, references(:users, on_delete: :delete_all), null: false
      add :opponent_id, references(:users, on_delete: :nilify_all)
      add :status, :string, default: "waiting", null: false
      add :game_state, :map
      timestamps()
    end
    create index(:games, [:host_id])
    create index(:games, [:opponent_id])
    create index(:games, [:status])
  end
end
