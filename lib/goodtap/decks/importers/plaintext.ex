defmodule Goodtap.Decks.Importers.Plaintext do
  @moduledoc """
  Imports a deck from a plain text decklist in the standard MTG format:

      4 Lightning Bolt
      2 Snapcaster Mage

      Sideboard:
      2 Negate

  Lines starting with a number followed by a card name are parsed.
  A "Sideboard" or "Sideboard:" line switches subsequent cards to the sideboard board.
  Empty lines are ignored.
  """

  def import(name, text) do
    cards = parse(text)

    if cards == [] do
      {:error, "No cards found. Make sure each line starts with a quantity and card name, e.g. \"4 Lightning Bolt\"."}
    else
      {:ok, %{name: name, cards: cards}}
    end
  end

  # Matches: "4 Lightning Bolt (CLB) 141" or "4 Lightning Bolt"
  # Captures qty and card name, stripping trailing "(SET) collector#"
  @card_line ~r/^(\d+)[x\s]+([^(]+?)(?:\s+\([A-Z0-9]+\)\s+[\w\-]+)?\s*$/

  # Arena metadata lines to skip: "About", "Deck", "Name <anything>", "Commander", "Companion"
  @skip_line ~r/^(About|Deck|Name\s|Commander$|Companion$)/i

  defp parse(text) do
    {cards, _board} =
      text
      |> String.split("\n")
      |> Enum.reduce({[], "main"}, fn line, {acc, board} ->
        line = String.trim(line)

        cond do
          line == "" ->
            {acc, board}

          String.match?(line, ~r/^sideboard\s*:?\s*$/i) ->
            {acc, "sideboard"}

          String.match?(line, ~r/^commander\s*:?\s*$/i) ->
            {acc, "commander"}

          String.match?(line, @skip_line) ->
            {acc, board}

          true ->
            case Regex.run(@card_line, line) do
              [_, qty_str, name] ->
                qty = String.to_integer(qty_str)
                if qty == 0 do
                  {acc, board}
                else
                  entry = %{
                    name: String.trim(name),
                    quantity: qty,
                    board: board
                  }
                  {[entry | acc], board}
                end

              _ ->
                {acc, board}
            end
        end
      end)

    Enum.reverse(cards)
  end
end
