defmodule Goodtap.Decks.Importers.Registry do
  @importers [Goodtap.Decks.Importers.Moxfield]

  def find_importer(url) do
    Enum.find(@importers, fn mod -> mod.supports_url?(url) end)
  end
end
