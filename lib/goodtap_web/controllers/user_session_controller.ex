defmodule GoodtapWeb.UserSessionController do
  use GoodtapWeb, :controller

  alias Goodtap.Accounts
  alias GoodtapWeb.UserAuth

  def new(conn, _params) do
    form = Phoenix.Component.to_form(%{}, as: "user")
    render(conn, :new, form: form)
  end

  def create(conn, %{"user" => %{"username" => username, "password" => password} = user_params}) do
    if user = Accounts.get_user_by_username_and_password(username, password) do
      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, user_params)
    else
      form = Phoenix.Component.to_form(user_params, as: "user")

      conn
      |> put_flash(:error, "Invalid username or password")
      |> render(:new, form: form)
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
