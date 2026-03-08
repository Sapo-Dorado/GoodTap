defmodule Goodtap.Repo.Migrations.AddDefaultPrintingIdToCards do
  use Ecto.Migration

  def change do
    alter table(:cards) do
      add :default_printing_id, :string, null: true
    end
  end
end
