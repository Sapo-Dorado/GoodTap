defmodule Goodtap.Games.Game do
  use Ecto.Schema
  import Ecto.Changeset

  alias Goodtap.Accounts.User

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :id

  schema "games" do
    field :status, :string, default: "waiting"
    field :game_state, :map

    belongs_to :host, User
    belongs_to :opponent, User

    timestamps()
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [:id, :host_id, :opponent_id, :status, :game_state])
    |> validate_required([:id, :host_id, :status])
    |> validate_inclusion(:status, ["waiting", "setup", "active", "ended", "sideboarding"])
    |> unique_constraint(:id, name: :games_pkey)
  end
end
