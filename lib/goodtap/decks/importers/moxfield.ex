defmodule Goodtap.Decks.Importers.Moxfield do
  @behaviour Goodtap.Decks.Importers.Behaviour

  @base_url "https://api2.moxfield.com/v3/decks/all"

  @impl true
  def supports_url?(url) do
    String.contains?(url, "moxfield.com/decks/")
  end

  @impl true
  def import(url) do
    with {:ok, deck_id} <- extract_deck_id(url),
         {:ok, data} <- fetch_deck(deck_id) do
      cards = parse_cards(data)
      {:ok, %{name: data["name"] || "Imported Deck", cards: cards}}
    end
  end

  defp extract_deck_id(url) do
    case Regex.run(~r{moxfield\.com/decks/([a-zA-Z0-9_\-]+)}, url) do
      [_, id] -> {:ok, id}
      _ -> {:error, "Could not extract deck ID from URL"}
    end
  end

  defp fetch_deck(deck_id) do
    url = "#{@base_url}/#{deck_id}"

    case Req.get(url, headers: [{"User-Agent", "Goodtap/1.0"}]) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, "Failed to parse Moxfield response"}
        end

      {:ok, %{status: status}} ->
        {:error, "Moxfield API returned status #{status}"}

      {:error, reason} ->
        {:error, "Failed to connect to Moxfield: #{inspect(reason)}"}
    end
  end

  defp parse_cards(data) do
    boards = ["mainboard", "sideboard", "commanders"]

    Enum.flat_map(boards, fn board_key ->
      board_name =
        case board_key do
          "mainboard" -> "main"
          "sideboard" -> "sideboard"
          "commanders" -> "commander"
        end

      case data[board_key] do
        nil ->
          []

        board_data when is_map(board_data) ->
          Enum.flat_map(board_data, fn {_key, entry} ->
            name = get_in(entry, ["card", "name"]) || entry["name"]
            quantity = entry["quantity"] || 1

            if name do
              [%{name: name, quantity: quantity, board: board_name}]
            else
              []
            end
          end)
      end
    end)
  end
end
