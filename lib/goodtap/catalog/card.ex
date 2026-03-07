defmodule Goodtap.Catalog.Card do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @derive {Jason.Encoder, only: [:id, :name, :layout, :data]}

  schema "cards" do
    field :name, :string
    field :layout, :string
    field :is_token, :boolean, default: false
    field :data, :map
    field :printings, {:array, :map}, default: []
    timestamps()
  end

  def changeset(card, attrs) do
    card
    |> cast(attrs, [:id, :name, :layout, :is_token, :data, :printings])
    |> validate_required([:id, :name, :data])
  end
end
