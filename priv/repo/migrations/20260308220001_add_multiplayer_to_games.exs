defmodule Goodtap.Repo.Migrations.AddMultiplayerToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :max_players, :integer, default: 2, null: false
      remove :opponent_id
    end

    drop_if_exists index(:games, [:opponent_id])

    create table(:game_players, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :game_id, references(:games, type: :string, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :player_key, :string, null: false
      timestamps(updated_at: false)
    end

    create index(:game_players, [:game_id])
    create index(:game_players, [:user_id])
    create unique_index(:game_players, [:game_id, :player_key])
    create unique_index(:game_players, [:game_id, :user_id])
  end
end
