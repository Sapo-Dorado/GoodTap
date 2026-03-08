defmodule Goodtap.Repo.Migrations.AddRecentTokensToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :recent_tokens, {:array, :string}, default: [], null: false
    end
  end
end
