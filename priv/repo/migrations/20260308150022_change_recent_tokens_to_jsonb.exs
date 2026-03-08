defmodule Goodtap.Repo.Migrations.ChangeRecentTokensToJsonb do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :recent_tokens
      add :recent_tokens, {:array, :map}, default: [], null: false
    end
  end
end
