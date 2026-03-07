alias Goodtap.Repo
alias Goodtap.Catalog.CardPrinting

raw =
  case System.get_env("PRINTINGS_JSON_PATH") do
    nil ->
      IO.puts("Fetching unique-artwork cards from Scryfall...")
      headers = [{"User-Agent", "GoodTap/1.0"}, {"Accept", "application/json"}]
      {:ok, %{body: meta}} = Req.get("https://api.scryfall.com/bulk-data/unique-artwork", headers: headers)
      url = meta["download_uri"]
      IO.puts("Downloading #{url}...")
      {:ok, %{body: body}} = Req.get(url, headers: headers, receive_timeout: 300_000)
      Jason.encode!(body)

    path ->
      IO.puts("Loading #{path}...")
      File.read!(path)
  end

IO.puts("Parsing JSON...")
cards_data = Jason.decode!(raw)

IO.puts("Seeding #{length(cards_data)} printings...")

now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()

cards_data
|> Enum.chunk_every(500)
|> Enum.with_index(1)
|> Enum.each(fn {chunk, idx} ->
  entries =
    Enum.flat_map(chunk, fn card ->
      image_uris =
        card["image_uris"] ||
          get_in(card, ["card_faces", Access.at(0), "image_uris"]) ||
          %{}

      # Skip cards with no usable image
      if image_uris == %{} do
        []
      else
        [%{
          id: card["id"],
          card_name: card["name"] |> String.split("//") |> List.first() |> String.trim(),
          set_code: card["set"],
          collector_number: card["collector_number"],
          image_uris: image_uris,
          is_token: card["layout"] in ["token", "double_faced_token"],
          data: Map.take(card, ["set", "set_name", "collector_number", "rarity", "artist", "image_uris", "card_faces"]),
          inserted_at: now,
          updated_at: now
        }]
      end
    end)

  Repo.insert_all(CardPrinting, entries,
    on_conflict: {:replace, [:card_name, :set_code, :collector_number, :image_uris, :is_token, :data, :updated_at]},
    conflict_target: [:id]
  )

  IO.puts("  Chunk #{idx}/#{div(length(cards_data), 500) + 1} done")
end)

IO.puts("Done! Printings seeded successfully.")
