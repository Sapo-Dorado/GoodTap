defmodule Goodtap.Repo.Migrations.AddRecentCountersToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :recent_counters, {:array, :map}, default: []
    end
  end
end
