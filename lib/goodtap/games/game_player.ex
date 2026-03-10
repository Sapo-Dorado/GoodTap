defmodule Goodtap.Games.GamePlayer do
  use Ecto.Schema
  import Ecto.Changeset

  alias Goodtap.Accounts.User
  alias Goodtap.Games.Game

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :id

  schema "game_players" do
    field :player_key, :string
    belongs_to :game, Game, type: :string
    belongs_to :user, User
    timestamps(updated_at: false)
  end

  def changeset(game_player, attrs) do
    game_player
    |> cast(attrs, [:game_id, :user_id, :player_key])
    |> validate_required([:game_id, :user_id, :player_key])
    |> unique_constraint([:game_id, :player_key])
    |> unique_constraint([:game_id, :user_id])
  end
end
