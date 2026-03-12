defmodule Goodtap.Decks.Deck do
  use Ecto.Schema
  import Ecto.Changeset

  alias Goodtap.Accounts.User
  alias Goodtap.Decks.DeckCard

  schema "decks" do
    field :name, :string
    field :source_url, :string

    belongs_to :user, User
    has_many :deck_cards, DeckCard

    timestamps()
  end

  def changeset(deck, attrs) do
    deck
    |> cast(attrs, [:name, :source_url, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, max: 100)
    |> unique_constraint(:name, name: :decks_user_id_name_index, message: "you already have a deck with that name")
  end
end
