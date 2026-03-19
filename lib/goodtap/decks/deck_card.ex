defmodule Goodtap.Decks.DeckCard do
  use Ecto.Schema
  import Ecto.Changeset

  alias Goodtap.Decks.Deck

  schema "deck_cards" do
    field :oracle_id, :string
    field :printing_id, :string
    field :quantity, :integer, default: 1
    field :board, :string, default: "main"

    belongs_to :deck, Deck
  end

  def changeset(deck_card, attrs) do
    deck_card
    |> cast(attrs, [:deck_id, :oracle_id, :printing_id, :quantity, :board])
    |> validate_required([:deck_id, :oracle_id])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_inclusion(:board, ["main", "sideboard", "commander"])
  end
end
