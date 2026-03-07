alias Goodtap.Repo
alias Goodtap.Catalog.Card

headers = [{"User-Agent", "GoodTap/1.0"}, {"Accept", "application/json"}]

# ── Unique-artwork printings ───────────────────────────────────────────────────
# One entry per unique artwork — contains full card data + image_uris.
# We group by card name: the first entry becomes the card row, all entries
# become the printings array.

artwork_raw =
  case System.get_env("ARTWORK_JSON_PATH") do
    nil ->
      IO.puts("Fetching unique-artwork bulk data URI from Scryfall...")
      {:ok, %{body: meta}} = Req.get("https://api.scryfall.com/bulk-data/unique-artwork", headers: headers)
      url = meta["download_uri"]
      IO.puts("Downloading #{url}...")
      {:ok, %{body: body}} = Req.get(url, headers: headers, receive_timeout: 300_000)
      Jason.encode!(body)

    path ->
      IO.puts("Loading unique-artwork from #{path}...")
      File.read!(path)
  end

IO.puts("Parsing unique-artwork JSON...")
artwork_cards = Jason.decode!(artwork_raw)

IO.puts("Grouping #{length(artwork_cards)} printings by card name...")

# Group all printings by name, preserving insertion order.
# The first printing for each name is used as the canonical card data.
cards_by_name =
  Enum.reduce(artwork_cards, %{}, fn card, acc ->
    # Skip art series cards — they are memorabilia collectibles, not playable cards
    if card["layout"] == "art_series" do
      acc
    else
    name = card["name"]
    printing = %{
      "id" => card["id"],
      "set_code" => card["set"],
      "collector_number" => card["collector_number"],
      "image_uris" => card["image_uris"] || get_in(card, ["card_faces", Access.at(0), "image_uris"])
    }

    case Map.get(acc, name) do
      nil -> Map.put(acc, name, {card, [printing]})
      {first, printings} -> Map.put(acc, name, {first, printings ++ [printing]})
    end
    end
  end)

# ── Seed cards table ──────────────────────────────────────────────────────────

entries_list = Map.values(cards_by_name)
IO.puts("Seeding #{length(entries_list)} cards...")

now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()

entries_list
|> Enum.chunk_every(500)
|> Enum.with_index(1)
|> Enum.each(fn {chunk, idx} ->
  entries =
    Enum.map(chunk, fn {card, printings} ->
      %{
        id: card["id"],
        name: card["name"],
        layout: card["layout"],
        is_token: card["layout"] in ["token", "double_faced_token"],
        data: card,
        printings: printings,
        inserted_at: now,
        updated_at: now
      }
    end)

  Repo.insert_all(Card, entries,
    on_conflict: {:replace, [:name, :layout, :is_token, :data, :printings, :updated_at]},
    conflict_target: [:id]
  )

  IO.puts("  Chunk #{idx}/#{div(length(entries_list), 500) + 1} done")
end)

IO.puts("Done! Cards seeded successfully.")
