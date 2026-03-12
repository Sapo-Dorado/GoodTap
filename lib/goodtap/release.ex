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

  def force_reset do
    load_app()
    {:ok, _} = Application.ensure_all_started(:req)

    IO.puts("Truncating all tables...")
    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Adapters.SQL.query!(repo, "TRUNCATE TABLE deck_cards, decks, game_players, games, cards")
        end)
    end

    update_cards()
  end

  def update_cards do
    load_app()
    {:ok, _} = Application.ensure_all_started(:req)

    IO.puts("Truncating games and cards tables...")
    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Adapters.SQL.query!(repo, "TRUNCATE TABLE game_players, games, cards")
        end)
    end

    IO.puts("Seeding cards...")
    seed()

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
