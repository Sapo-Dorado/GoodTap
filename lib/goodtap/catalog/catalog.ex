defmodule Goodtap.Catalog do
  import Ecto.Query, warn: false
  alias Goodtap.Repo
  alias Goodtap.Catalog.Card

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

  def search_tokens(query, limit \\ 20) do
    search = "%#{query}%"

    Card
    |> where([c], c.layout == "token" and ilike(c.name, ^search))
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
