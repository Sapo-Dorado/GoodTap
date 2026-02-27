defmodule Goodtap.Decks.Importers.Behaviour do
  @callback supports_url?(url :: String.t()) :: boolean()
  @callback import(url :: String.t()) ::
              {:ok, %{name: String.t(), cards: list(%{name: String.t(), quantity: integer()})}}
              | {:error, String.t()}
end
