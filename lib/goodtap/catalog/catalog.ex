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

  # Find a card by name, also searching card_faces for DFC front face names
  def find_card_for_deck(name) do
    case Repo.get_by(Card, name: name, is_token: false) do
      nil ->
        Card
        |> where([c], fragment("lower(?) = lower(?)", c.name, ^name) and not c.is_token)
        |> limit(1)
        |> Repo.one()

      card ->
        card
    end
  end
end
