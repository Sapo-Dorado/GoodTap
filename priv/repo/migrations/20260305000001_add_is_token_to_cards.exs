defmodule Goodtap.Repo.Migrations.AddIsTokenToCards do
  use Ecto.Migration

  def change do
    alter table(:cards) do
      add :is_token, :boolean, null: false, default: false
    end

    create index(:cards, [:is_token])
  end
end
