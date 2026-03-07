defmodule Goodtap.Catalog.CardPrinting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "card_printings" do
    field :card_name, :string
    field :set_code, :string
    field :collector_number, :string
    field :image_uris, :map
    field :is_token, :boolean, default: false
    field :data, :map
    timestamps()
  end

  def changeset(printing, attrs) do
    printing
    |> cast(attrs, [:id, :card_name, :set_code, :collector_number, :image_uris, :is_token, :data])
    |> validate_required([:id, :card_name, :set_code, :collector_number, :image_uris, :data])
  end
end
