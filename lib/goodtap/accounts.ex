defmodule Goodtap.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Goodtap.Repo

  alias Goodtap.Accounts.{User, UserToken}

  ## Database getters

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  def change_user_registration(user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, validate_unique: false)
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def get_user_by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    user = Repo.get_by(User, username: username)
    if User.valid_password?(user, password), do: user
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.
  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.
  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  @doc """
  Prepends a counter entry to the user's recent_counters list, keeping only the 5 most recent.
  Deduplicates by name + has_quantity so the same counter isn't listed twice.
  """
  def add_recent_counter(user, name, has_quantity) do
    entry = %{"name" => name, "has_quantity" => has_quantity}

    updated =
      [entry | Enum.reject(user.recent_counters, &(&1["name"] == name && &1["has_quantity"] == has_quantity))]
      |> Enum.take(5)

    user
    |> Ecto.Changeset.change(recent_counters: updated)
    |> Repo.update!()
  end

  @doc """
  Prepends a token entry to the user's recent_tokens list, keeping only the 8 most recent.
  Deduplicates by oracle_id.
  """
  def add_recent_token(user, card, printing_id \\ nil) do
    entry = %{"oracle_id" => card.oracle_id, "name" => card.name, "printing_id" => printing_id}

    updated =
      [entry | Enum.reject(user.recent_tokens, &(&1["oracle_id"] == entry["oracle_id"]))]
      |> Enum.take(8)

    user
    |> Ecto.Changeset.change(recent_tokens: updated)
    |> Repo.update!()
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
