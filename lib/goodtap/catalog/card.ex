defmodule Goodtap.Catalog.Card do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @derive {Jason.Encoder, only: [:id, :name, :oracle_id, :layout, :data]}

  schema "cards" do
    field :name, :string
    field :oracle_id, :string
    field :layout, :string
    field :is_token, :boolean, default: false
    field :data, :map
    field :printings, {:array, :map}, default: []
    field :default_printing_id, :string
    timestamps()
  end

  def changeset(card, attrs) do
    card
    |> cast(attrs, [:id, :name, :oracle_id, :layout, :is_token, :data, :printings])
    |> validate_required([:id, :name, :data])
  end
end
