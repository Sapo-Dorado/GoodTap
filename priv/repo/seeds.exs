alias Goodtap.Repo
alias Goodtap.Catalog.Card

json_path = Path.join(__DIR__, "data/MTG_Cards.json")

IO.puts("Loading MTG_Cards.json...")
{:ok, raw} = File.read(json_path)
IO.puts("Parsing JSON...")
{:ok, cards_data} = Jason.decode(raw)

IO.puts("Seeding #{length(cards_data)} cards...")

now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()

cards_data
|> Enum.chunk_every(500)
|> Enum.with_index(1)
|> Enum.each(fn {chunk, idx} ->
  entries =
    Enum.map(chunk, fn card ->
      %{
        id: card["id"],
        name: card["name"],
        layout: card["layout"],
        data: card,
        inserted_at: now,
        updated_at: now
      }
    end)

  Repo.insert_all(Card, entries,
    on_conflict: {:replace, [:name, :layout, :data, :updated_at]},
    conflict_target: [:id]
  )

  IO.puts("  Chunk #{idx}/#{div(length(cards_data), 500) + 1} done")
end)

IO.puts("Done! Cards seeded successfully.")
