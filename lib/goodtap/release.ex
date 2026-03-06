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

  def update_cards do
    load_app()
    {:ok, _} = Application.ensure_all_started(:req)

    IO.puts("Fetching latest oracle cards from Scryfall...")
    headers = [{"User-Agent", "GoodTap/1.0"}, {"Accept", "application/json"}]
    {:ok, %{body: meta}} = Req.get("https://api.scryfall.com/bulk-data/oracle-cards", headers: headers)
    url = meta["download_uri"]
    IO.puts("Downloading #{url}...")
    {:ok, %{body: body}} = Req.get(url, headers: headers, receive_timeout: 120_000)

    IO.puts("Writing to #{@cards_json}...")
    File.write!(@cards_json, Jason.encode!(body))

    IO.puts("Truncating games and cards tables...")
    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Adapters.SQL.query!(repo, "TRUNCATE TABLE games, cards")
        end)
    end

    IO.puts("Reseeding...")
    seed(@cards_json)

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
