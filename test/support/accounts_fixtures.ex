defmodule Goodtap.AccountsFixtures do
  alias Goodtap.Accounts

  def unique_username, do: "user#{System.unique_integer([:positive])}"

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{username: unique_username(), password: "hello world!"})
      |> Accounts.register_user()

    user
  end

  def override_token_authenticated_at(token, authenticated_at) do
    import Ecto.Query
    {1, nil} =
      Goodtap.Repo.update_all(
        from(t in Goodtap.Accounts.UserToken, where: t.token == ^token),
        set: [authenticated_at: authenticated_at]
      )
  end
end
