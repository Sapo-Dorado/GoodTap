defmodule Goodtap.Decks.DeckCard do
  use Ecto.Schema
  import Ecto.Changeset

  alias Goodtap.Decks.Deck
  alias Goodtap.Catalog.Card

  schema "deck_cards" do
    field :quantity, :integer, default: 1
    field :board, :string, default: "main"

    belongs_to :deck, Deck
    belongs_to :card, Card, type: :string
  end

  def changeset(deck_card, attrs) do
    deck_card
    |> cast(attrs, [:deck_id, :card_id, :quantity, :board])
    |> validate_required([:deck_id, :card_id])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_inclusion(:board, ["main", "sideboard", "commander"])
  end
end
