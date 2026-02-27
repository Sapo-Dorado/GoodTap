defmodule Goodtap.Repo do
  use Ecto.Repo,
    otp_app: :goodtap,
    adapter: Ecto.Adapters.Postgres
end
