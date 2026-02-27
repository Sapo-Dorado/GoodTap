defmodule GoodtapWeb.GameJoinLive do
  use GoodtapWeb, :live_view

  alias Goodtap.Games

  def mount(%{"token" => token}, _session, socket) do
    case Games.get_game(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Game not found or invite link is invalid.")
         |> push_navigate(to: ~p"/games")}

      game ->
        {:ok, push_navigate(socket, to: ~p"/games/#{game.id}/setup")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center min-h-screen">
      <p class="text-gray-400">Joining game...</p>
    </div>
    """
  end
end
