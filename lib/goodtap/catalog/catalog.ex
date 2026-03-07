defmodule Goodtap.Catalog do
  import Ecto.Query, warn: false
  alias Goodtap.Repo
  alias Goodtap.Catalog.Card
  alias Goodtap.Catalog.CardPrinting

  def get_card!(id), do: Repo.get!(Card, id)

  def get_card(id), do: Repo.get(Card, id)

  def get_card_by_name(name) do
    Repo.get_by(Card, name: name)
  end

  def search_cards(query, limit \\ 20) do
    search = "%#{query}%"

    Card
    |> where([c], ilike(c.name, ^search))
    |> order_by([c], c.name)
    |> limit(^limit)
    |> Repo.all()
  end

  # Returns {results, total_count} for display "Showing X of Y"
  def search_cards_paged(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    token_only = Keyword.get(opts, :token_only, false)
    search = "%#{query}%"

    base =
      if token_only do
        Card |> where([c], c.is_token and ilike(c.name, ^search))
      else
        Card |> where([c], ilike(c.name, ^search))
      end

    total = Repo.aggregate(base, :count, :id)
    results = base |> order_by([c], c.name) |> limit(^limit) |> Repo.all()

    {results, total}
  end

  def search_tokens(query, limit \\ 20) do
    search = "%#{query}%"

    Card
    |> where([c], c.is_token and ilike(c.name, ^search))
    |> order_by([c], c.name)
    |> limit(^limit)
    |> Repo.all()
  end

  def list_cards_by_ids(ids) when is_list(ids) do
    Card
    |> where([c], c.id in ^ids)
    |> Repo.all()
  end

  def list_cards_by_names(names) when is_list(names) do
    Card
    |> where([c], c.name in ^names and not c.is_token)
    |> Repo.all()
  end

  def get_printing(id), do: Repo.get(CardPrinting, id)

  def get_printing_by_set(set_code, collector_number) do
    CardPrinting
    |> where([p], p.set_code == ^set_code and p.collector_number == ^collector_number)
    |> limit(1)
    |> Repo.one()
  end

  def get_printings_for_card(card_name) do
    CardPrinting
    |> where([p], p.card_name == ^card_name)
    |> order_by([p], [p.set_code, p.collector_number])
    |> Repo.all()
  end

  # Find a card by name for deck import.
  # Always searches by the front face name only (before any " //") since Scryfall
  # is inconsistent about whether it stores the full DFC name or just the front.
  # Falls back to a unique contains match if no exact hit.
  def find_card_for_deck(raw_name) do
    name = raw_name |> String.split("//") |> List.first() |> String.trim()

    # 1. Case-insensitive exact match on front face name
    exact =
      Card
      |> where([c], fragment("lower(?) = lower(?)", c.name, ^name) and not c.is_token)
      |> Repo.all()

    case exact do
      [card | _] ->
        card

      [] ->
        # 2. Unique contains match — only use if exactly one result
        search = "%#{name}%"

        case Card |> where([c], ilike(c.name, ^search) and not c.is_token) |> Repo.all() do
          [card] -> card
          _ -> nil
        end
    end
  end
end
