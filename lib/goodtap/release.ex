defmodule Goodtap.Release do
  @app :goodtap

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed(json_path \\ nil) do
    load_app()
    if json_path, do: System.put_env("SEEDS_JSON_PATH", json_path)

    # Req uses Finch under the hood; start it if not already running
    {:ok, _} = Application.ensure_all_started(:req)

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seeds = Application.app_dir(:goodtap, "priv/repo/seeds.exs")
          Code.eval_file(seeds)
        end)
    end
  end

  @cards_json "/var/lib/goodtap/MTG_Cards.json"
  @printings_json "/var/lib/goodtap/MTG_Printings.json"

  def force_reset do
    load_app()
    {:ok, _} = Application.ensure_all_started(:req)

    IO.puts("Truncating all tables...")
    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Adapters.SQL.query!(repo, "TRUNCATE TABLE deck_cards, decks, games, card_printings, cards")
        end)
    end

    update_cards()
  end

  def update_cards do
    load_app()
    {:ok, _} = Application.ensure_all_started(:req)

    headers = [{"User-Agent", "GoodTap/1.0"}, {"Accept", "application/json"}]

    # Download oracle cards
    IO.puts("Fetching latest oracle cards from Scryfall...")
    {:ok, %{body: meta}} = Req.get("https://api.scryfall.com/bulk-data/oracle-cards", headers: headers)
    url = meta["download_uri"]
    IO.puts("Downloading #{url}...")
    {:ok, %{body: body}} = Req.get(url, headers: headers, receive_timeout: 120_000)
    File.write!(@cards_json, Jason.encode!(body))

    # Download unique-artwork printings
    IO.puts("Fetching unique-artwork printings from Scryfall...")
    {:ok, %{body: meta}} = Req.get("https://api.scryfall.com/bulk-data/unique-artwork", headers: headers)
    url = meta["download_uri"]
    IO.puts("Downloading #{url}...")
    {:ok, %{body: body}} = Req.get(url, headers: headers, receive_timeout: 300_000)
    File.write!(@printings_json, Jason.encode!(body))

    IO.puts("Truncating games, cards, and printings tables...")
    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Adapters.SQL.query!(repo, "TRUNCATE TABLE games, card_printings, cards")
        end)
    end

    IO.puts("Seeding oracle cards...")
    seed(@cards_json)

    IO.puts("Seeding printings...")
    seed_printings(@printings_json)

    IO.puts("Done!")
  end

  def seed_printings(json_path \\ nil) do
    load_app()
    if json_path, do: System.put_env("PRINTINGS_JSON_PATH", json_path)
    {:ok, _} = Application.ensure_all_started(:req)

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seeds = Application.app_dir(:goodtap, "priv/repo/seeds_printings.exs")
          Code.eval_file(seeds)
        end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
