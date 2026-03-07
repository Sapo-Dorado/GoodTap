defmodule Goodtap.Decks.Importers.Plaintext do
  @moduledoc """
  Imports a deck from a plain text decklist in the standard MTG format:

      4 Lightning Bolt
      2 Snapcaster Mage (MH2) 123

      Sideboard:
      2 Negate

  Lines starting with a number followed by a card name are parsed.
  Optionally includes a set code and collector number: `(SET) number`.
  A "Sideboard" or "Sideboard:" line switches subsequent cards to the sideboard.
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

  # Matches lines like:
  #   4 Lightning Bolt
  #   4 Lightning Bolt (MH2) 123
  #   4 The Modern Age / Vector Glider (NEO) 66
  # Groups: qty, name, set_code (optional), collector_number (optional)
  @card_line ~r/^(\d+)[x\s]+([^(]+?)(?:\s+\(([A-Z0-9]+)\)\s+([\w\-]+))?\s*$/

  # Arena metadata lines to skip
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
              [_, qty_str, name | rest] ->
                qty = String.to_integer(qty_str)

                if qty == 0 do
                  {acc, board}
                else
                  {set_code, collector_number} =
                    case rest do
                      [set, num | _] when set != "" -> {String.downcase(set), num}
                      _ -> {nil, nil}
                    end

                  entry = %{
                    name: String.trim(name),
                    quantity: qty,
                    board: board,
                    set_code: set_code,
                    collector_number: collector_number
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
