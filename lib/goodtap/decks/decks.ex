defmodule Goodtap.Decks do
  import Ecto.Query, warn: false
  alias Goodtap.Repo
  alias Goodtap.Decks.{Deck, DeckCard}
  alias Goodtap.Decks.Importers.Plaintext

  def list_user_decks(user_id) do
    Deck
    |> where([d], d.user_id == ^user_id)
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  def get_deck!(id), do: Repo.get!(Deck, id)

  def get_deck_with_cards!(id) do
    Deck
    |> Repo.get!(id)
    |> Repo.preload(:deck_cards)
  end

  defp insert_deck_cards(deck, card_list) do
    Enum.each(card_list, fn %{name: name, quantity: qty, board: board} ->
      %DeckCard{}
      |> DeckCard.changeset(%{
        deck_id: deck.id,
        card_name: name,
        quantity: qty,
        board: board
      })
      |> Repo.insert(on_conflict: :replace_all, conflict_target: [:deck_id, :card_name, :board])
    end)
  end

  def create_deck_from_text(user, name, text) do
    with {:ok, %{name: deck_name, cards: card_list}} <- Plaintext.import(name, text) do
      Repo.transact(fn ->
        with {:ok, deck} <-
               %Deck{}
               |> Deck.changeset(%{name: deck_name, user_id: user.id})
               |> Repo.insert() do
          insert_deck_cards(deck, card_list)
          {:ok, Repo.preload(deck, :deck_cards)}
        end
      end)
    end
  end

  def create_deck(user, attrs) do
    %Deck{}
    |> Deck.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  def update_deck(deck, attrs) do
    deck
    |> Deck.changeset(attrs)
    |> Repo.update()
  end

  def delete_deck(deck) do
    Repo.delete(deck)
  end

  # Returns a flat list of card names repeated by quantity (for shuffling into deck)
  def expand_deck_card_names(deck_id) do
    DeckCard
    |> where([dc], dc.deck_id == ^deck_id and dc.board == "main")
    |> select([dc], {dc.card_name, dc.quantity})
    |> Repo.all()
    |> Enum.flat_map(fn {name, qty} -> List.duplicate(name, qty) end)
  end
end
