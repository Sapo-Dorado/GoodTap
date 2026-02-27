defmodule Goodtap.Catalog.Card do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @derive {Jason.Encoder, only: [:id, :name, :layout, :data]}

  schema "cards" do
    field :name, :string
    field :layout, :string
    field :data, :map
    timestamps()
  end

  def changeset(card, attrs) do
    card
    |> cast(attrs, [:id, :name, :layout, :data])
    |> validate_required([:id, :name, :data])
  end
end
