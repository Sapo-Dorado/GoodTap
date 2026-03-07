defmodule Goodtap.Catalog do
  import Ecto.Query, warn: false
  alias Goodtap.Repo
  alias Goodtap.Catalog.Card

  def get_card!(id), do: Repo.get!(Card, id)

  def get_card(id), do: Repo.get(Card, id)

  def get_card_by_name(name) do
    Card
    |> where([c], c.name == ^name and not c.is_token)
    |> limit(1)
    |> Repo.one()
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
  # filter: :all | :tokens_only | :no_tokens
  def search_cards_paged(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    filter = Keyword.get(opts, :filter, :all)
    search = "%#{query}%"

    base =
      case filter do
        :tokens_only -> Card |> where([c], c.is_token and ilike(c.name, ^search))
        :no_tokens -> Card |> where([c], not c.is_token and ilike(c.name, ^search))
        :all -> Card |> where([c], ilike(c.name, ^search))
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

  # Find a specific printing by its Scryfall ID within a card's printings array
  def get_printing(card_name, printing_id) when is_binary(card_name) and is_binary(printing_id) do
    case get_card_by_name(card_name) do
      nil -> nil
      card -> Enum.find(card.printings, &(&1["id"] == printing_id))
    end
  end

  def get_printing(nil, _), do: nil
  def get_printing(_, nil), do: nil

  # Return all printings for a card (already embedded on the card row)
  def get_printings_for_card(card_name) do
    case get_card_by_name(card_name) do
      nil -> []
      card -> card.printings
    end
  end

  # Find a card and resolve an optional printing for deck import.
  #
  # Name matching:
  #   1. Strip everything after "//" — decklists may include the back-face name but
  #      we only need the front face to search. Works for all formats.
  #   2. ILIKE contains search on non-token cards. Only accepts the result if exactly
  #      one card matches — avoids false positives on ambiguous partial names.
  #      DFC cards work naturally: "The Modern Age" matches "The Modern Age // Vector Glider".
  #
  # Printing resolution:
  #   If set_code + collector_number are provided (e.g. from "(RNA) 244" in the
  #   decklist), we look for a matching printing in card.printings. If found we store
  #   that printing_id on the deck_card so the correct art is shown. Falls back to nil
  #   (default art) if the printing isn't in our DB.
  #
  # Returns {card, printing_id} — printing_id may be nil.
  def find_card_for_deck(raw_name, set_code \\ nil, collector_number \\ nil) do
    # Step 1: take everything before the first "/" to handle both "Name / Back" and "Name // Back" formats
    name = raw_name |> String.split("/") |> List.first() |> String.trim()

    # Step 2: try exact case-insensitive match first. This handles cards like "Island"
    # and "Dispel" which would match multiple cards in a starts-with search.
    # Falls back to starts-with for partial names and DFC front-face names like
    # "The Modern Age" matching "The Modern Age // Vector Glider".
    card =
      case Card |> where([c], fragment("lower(?)", c.name) == fragment("lower(?)", ^name) and not c.is_token) |> Repo.all() do
        [card] -> card
        _ ->
          search = "#{name}%"
          case Card |> where([c], ilike(c.name, ^search) and not c.is_token) |> Repo.all() do
            [card] -> card
            _ -> nil
          end
      end

    case card do
      nil ->
        {nil, nil}

      card ->
        # Step 4: resolve printing from set+collector if provided
        printing_id =
          if set_code && collector_number do
            printing = Enum.find(card.printings, fn p ->
              p["set_code"] == set_code && p["collector_number"] == collector_number
            end)
            printing && printing["id"]
          end

        {card, printing_id}
    end
  end
end
