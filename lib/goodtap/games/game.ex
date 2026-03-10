defmodule Goodtap.Games.Game do
  use Ecto.Schema
  import Ecto.Changeset

  alias Goodtap.Accounts.User
  alias Goodtap.Games.GamePlayer

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :id

  schema "games" do
    field :status, :string, default: "waiting"
    field :game_state, :map
    field :max_players, :integer, default: 2

    belongs_to :host, User
    has_many :game_players, GamePlayer

    timestamps()
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [:id, :host_id, :status, :game_state, :max_players])
    |> validate_required([:id, :host_id, :status])
    |> validate_inclusion(:status, ["waiting", "setup", "active", "ended", "sideboarding"])
    |> validate_number(:max_players, greater_than_or_equal_to: 2, less_than_or_equal_to: 6)
    |> unique_constraint(:id, name: :games_pkey)
  end
end
