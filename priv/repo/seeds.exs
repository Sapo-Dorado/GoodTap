alias Goodtap.Repo
alias Goodtap.Catalog.Card

headers = [{"User-Agent", "GoodTap/1.0"}, {"Accept", "application/json"}]

# ── Default-cards bulk data ────────────────────────────────────────────────────
# One entry per printing of every card. We group by oracle_id to build one card
# row per unique card, with all its printings embedded. Each printing retains
# is_default and released_at so we can compute the default printing per card.

cards_path =
  case System.get_env("ARTWORK_JSON_PATH") do
    nil ->
      IO.puts("Fetching default-cards bulk data URI from Scryfall...")

      {:ok, %{body: meta}} =
        Req.get("https://api.scryfall.com/bulk-data/default-cards", headers: headers)

      url = meta["download_uri"]
      tmp = System.tmp_dir!() |> Path.join("mtg_default_cards.json")
      IO.puts("Downloading #{url} to #{tmp}...")
      {:ok, _} = Req.get(url, headers: headers, receive_timeout: 600_000, into: File.stream!(tmp))
      tmp

    path ->
      IO.puts("Loading default-cards from #{path}...")
      path
  end

IO.puts("Parsing default-cards JSON...")
artwork_cards = cards_path |> File.read!() |> Jason.decode!()

IO.puts("Grouping #{length(artwork_cards)} printings by oracle_id...")

non_default_frame_effects = MapSet.new(["showcase", "extendedart", "etched"])
valid_border_colors = MapSet.new(["black", "white", "silver"])

is_default_printing = fn card ->
  frame_effects = Map.get(card, "frame_effects", [])
  border_color = Map.get(card, "border_color", "black")

  card["promo"] != true &&
    card["booster"] != false &&
    card["full_art"] != true &&
    card["textless"] != true &&
    Enum.empty?(Enum.filter(frame_effects, &MapSet.member?(non_default_frame_effects, &1))) &&
    MapSet.member?(valid_border_colors, border_color)
end

# Group printings by oracle_id. The first printing encountered for each oracle_id
# is used as the canonical card data row. All printings (including it) are stored
# in the printings array with is_default and released_at for default resolution.
cards_by_oracle =
  Enum.reduce(artwork_cards, %{}, fn card, acc ->
    # Skip art series and reversible cards — memorabilia/collector variants,
    # not independently playable (reversible cards are duplicates of normal cards)
    if card["layout"] in ["art_series", "reversible_card"] do
      acc
    else
      key = card["oracle_id"] || card["id"]

      printing = %{
        "id" => card["id"],
        "set_code" => card["set"],
        "collector_number" => card["collector_number"],
        "is_default" => is_default_printing.(card),
        "released_at" => card["released_at"],
        "image_uris" =>
          card["image_uris"] || get_in(card, ["card_faces", Access.at(0), "image_uris"])
      }

      case Map.get(acc, key) do
        nil -> Map.put(acc, key, {card, [printing]})
        {first, printings} -> Map.put(acc, key, {first, printings ++ [printing]})
      end
    end
  end)

# ── Seed cards table ──────────────────────────────────────────────────────────

entries_list = Map.values(cards_by_oracle)
IO.puts("Seeding #{length(entries_list)} cards...")

now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()

entries_list
|> Enum.chunk_every(500)
|> Enum.with_index(1)
|> Enum.each(fn {chunk, idx} ->
  entries =
    Enum.map(chunk, fn {card, printings} ->
      # Default printing: most recent printing where is_default is true.
      # Falls back to most recent printing overall if none are marked default.
      default_printing_id =
        Enum.filter(printings, & &1["is_default"])
        |> Enum.max_by(& &1["released_at"], fn -> nil end) ||
          Enum.max_by(printings, & &1["released_at"], fn -> nil end)

      %{
        id: card["id"],
        name: card["name"],
        oracle_id: card["oracle_id"] || card["id"],
        layout: card["layout"],
        is_token: card["layout"] in ["token", "double_faced_token"],
        data: card,
        printings: printings,
        default_printing_id: default_printing_id && default_printing_id["id"],
        inserted_at: now,
        updated_at: now
      }
    end)

  Repo.insert_all(Card, entries,
    on_conflict:
      {:replace,
       [:name, :oracle_id, :layout, :is_token, :data, :printings, :default_printing_id, :updated_at]},
    conflict_target: [:id]
  )

  IO.puts("  Chunk #{idx}/#{div(length(entries_list), 500) + 1} done")
end)

IO.puts("Done! Cards seeded successfully.")
