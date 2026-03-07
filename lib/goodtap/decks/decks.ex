defmodule Goodtap.Decks do
  import Ecto.Query, warn: false
  alias Goodtap.Repo
  alias Goodtap.Decks.{Deck, DeckCard}
  alias Goodtap.Decks.Importers.Plaintext
  alias Goodtap.Catalog

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

  # Returns a list of card names that could not be found in the catalog.
  defp insert_deck_cards(deck, card_list) do
    card_lookup = Catalog.find_cards_for_deck(card_list)

    {not_found, to_insert} =
      Enum.reduce(card_list, {[], []}, fn entry, {nf, ins} ->
        case Map.get(card_lookup, entry.name) do
          {nil, _} -> {[entry.name | nf], ins}
          {card, printing_id} ->
            row = %{
              deck_id: deck.id,
              card_name: card.name,
              printing_id: printing_id,
              quantity: entry.quantity,
              board: entry.board
            }
            {nf, [row | ins]}
        end
      end)

    Repo.insert_all(DeckCard, to_insert,
      on_conflict: :replace_all,
      conflict_target: [:deck_id, :card_name, :board]
    )

    not_found |> Enum.reverse()
  end

  def create_deck_from_text(user, name, text) do
    with {:ok, %{name: deck_name, cards: card_list}} <- Plaintext.import(name, text) do
      case Repo.transact(fn ->
        with {:ok, deck} <-
               %Deck{}
               |> Deck.changeset(%{name: deck_name, user_id: user.id})
               |> Repo.insert() do
          not_found = insert_deck_cards(deck, card_list)
          {:ok, {Repo.preload(deck, :deck_cards), not_found}}
        end
      end) do
        {:ok, {deck, not_found}} -> {:ok, deck, not_found}
        {:error, reason} -> {:error, reason}
      end
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

  def add_card_to_deck(deck, card_name, printing_id \\ nil, board \\ "main") do
    %DeckCard{}
    |> DeckCard.changeset(%{deck_id: deck.id, card_name: card_name, printing_id: printing_id, quantity: 1, board: board})
    |> Repo.insert(
      on_conflict: [inc: [quantity: 1]],
      conflict_target: [:deck_id, :card_name, :board]
    )
  end

  def update_deck_card_printing(deck_card, printing_id) do
    deck_card
    |> DeckCard.changeset(%{printing_id: printing_id})
    |> Repo.update()
  end

  def update_deck_card_quantity(deck_card, quantity) when quantity > 0 do
    deck_card
    |> DeckCard.changeset(%{quantity: quantity})
    |> Repo.update()
  end

  def remove_deck_card(deck_card) do
    Repo.delete(deck_card)
  end

  def move_deck_card_board(deck_card, board) do
    existing =
      Repo.get_by(DeckCard,
        deck_id: deck_card.deck_id,
        card_name: deck_card.card_name,
        board: board
      )

    if existing do
      # Merge quantities into the target board entry, delete source
      Repo.update_all(
        from(dc in DeckCard, where: dc.id == ^existing.id),
        inc: [quantity: deck_card.quantity]
      )
      Repo.delete(deck_card)
    else
      deck_card
      |> DeckCard.changeset(%{board: board})
      |> Repo.update()
    end
  end

  # Move a single copy of a card to another board (for sideboarding one at a time)
  def move_one_to_board(deck_card, board) do
    Repo.transact(fn ->
      existing = Repo.get_by(DeckCard, deck_id: deck_card.deck_id, card_name: deck_card.card_name, board: board)

      if deck_card.quantity <= 1 do
        # Move the whole entry
        if existing do
          Repo.update_all(from(dc in DeckCard, where: dc.id == ^existing.id), inc: [quantity: 1])
          Repo.delete!(deck_card)
        else
          deck_card |> DeckCard.changeset(%{board: board}) |> Repo.update!()
        end
      else
        # Decrement source, increment or create target
        deck_card |> DeckCard.changeset(%{quantity: deck_card.quantity - 1}) |> Repo.update!()
        if existing do
          Repo.update_all(from(dc in DeckCard, where: dc.id == ^existing.id), inc: [quantity: 1])
        else
          %DeckCard{}
          |> DeckCard.changeset(%{deck_id: deck_card.deck_id, card_name: deck_card.card_name, printing_id: deck_card.printing_id, quantity: 1, board: board})
          |> Repo.insert!()
        end
      end

      {:ok, :done}
    end)
  end

  def get_deck_card!(id), do: Repo.get!(DeckCard, id)

  # Returns a flat list of card names repeated by quantity (for shuffling into deck)
  def expand_deck_card_names(deck_id) do
    DeckCard
    |> where([dc], dc.deck_id == ^deck_id and dc.board == "main")
    |> select([dc], {dc.card_name, dc.quantity})
    |> Repo.all()
    |> Enum.flat_map(fn {name, qty} -> List.duplicate(name, qty) end)
  end

  # Apply a list of sideboard swaps: [{deck_card_id, qty, to_board}]
  def apply_sideboard_swaps(swaps) do
    Repo.transact(fn ->
      Enum.each(swaps, fn {deck_card_id, qty, to_board} ->
        dc = Repo.get!(DeckCard, deck_card_id)
        from_board = dc.board

        cond do
          qty <= 0 -> :ok
          qty >= dc.quantity ->
            # Move all to target board
            existing = Repo.get_by(DeckCard, deck_id: dc.deck_id, card_name: dc.card_name, board: to_board)

            if existing do
              Repo.update_all(
                from(d in DeckCard, where: d.id == ^existing.id),
                inc: [quantity: dc.quantity]
              )
              Repo.delete(dc)
            else
              dc |> DeckCard.changeset(%{board: to_board}) |> Repo.update!()
            end

          true ->
            # Move partial qty: reduce source, add to target
            dc |> DeckCard.changeset(%{quantity: dc.quantity - qty}) |> Repo.update!()
            existing = Repo.get_by(DeckCard, deck_id: dc.deck_id, card_name: dc.card_name, board: to_board)

            if existing do
              Repo.update_all(
                from(d in DeckCard, where: d.id == ^existing.id),
                inc: [quantity: qty]
              )
            else
              %DeckCard{}
              |> DeckCard.changeset(%{
                deck_id: dc.deck_id,
                card_name: dc.card_name,
                printing_id: dc.printing_id,
                quantity: qty,
                board: to_board
              })
              |> Repo.insert!()
            end
        end

        _ = from_board  # suppress unused warning
      end)

      {:ok, :done}
    end)
  end

  # Returns all starts-in-play cards for a deck
  def get_commanders(deck_id) do
    DeckCard
    |> where([dc], dc.deck_id == ^deck_id and dc.board == "commander")
    |> Repo.all()
  end

  # Move a card to the starts-in-play board
  def set_commander(deck_id, deck_card_id) do
    deck_card = Repo.get!(DeckCard, deck_card_id)
    move_deck_card_board(deck_card, "commander")
  end
end
