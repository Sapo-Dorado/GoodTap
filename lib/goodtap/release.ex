defmodule Goodtap.Release do
  @app :goodtap

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed(artwork_path \\ nil) do
    load_app()
    if artwork_path, do: System.put_env("ARTWORK_JSON_PATH", artwork_path)

    {:ok, _} = Application.ensure_all_started(:req)

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seeds = Application.app_dir(:goodtap, "priv/repo/seeds.exs")
          Code.eval_file(seeds)
        end)
    end
  end

  @artwork_json "/var/lib/goodtap/MTG_Artwork.json"

  def force_reset do
    load_app()
    {:ok, _} = Application.ensure_all_started(:req)

    IO.puts("Truncating all tables...")
    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Adapters.SQL.query!(repo, "TRUNCATE TABLE deck_cards, decks, games, cards")
        end)
    end

    update_cards()
  end

  def update_cards do
    load_app()
    {:ok, _} = Application.ensure_all_started(:req)

    headers = [{"User-Agent", "GoodTap/1.0"}, {"Accept", "application/json"}]

    IO.puts("Fetching unique-artwork bulk data URI from Scryfall...")
    {:ok, %{body: meta}} = Req.get("https://api.scryfall.com/bulk-data/unique-artwork", headers: headers)
    url = meta["download_uri"]
    IO.puts("Downloading #{url}...")
    {:ok, %{body: body}} = Req.get(url, headers: headers, receive_timeout: 300_000)
    File.write!(@artwork_json, Jason.encode!(body))

    IO.puts("Truncating games and cards tables...")
    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Adapters.SQL.query!(repo, "TRUNCATE TABLE games, cards")
        end)
    end

    IO.puts("Seeding cards with printings...")
    seed(@artwork_json)

    IO.puts("Done!")
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
