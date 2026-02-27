defmodule GoodtapWeb.PageController do
  use GoodtapWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
      redirect(conn, to: ~p"/games")
    else
      render(conn, :home)
    end
  end
end
