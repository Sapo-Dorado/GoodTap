defmodule GoodtapWeb.DeckListLive do
  use GoodtapWeb, :live_view

  alias Goodtap.Decks

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    decks = Decks.list_user_decks(user.id)

    {:ok,
     assign(socket,
       decks: decks,
       page_title: "My Decks",
       show_import_modal: false,
       import_name: "",
       import_text: "",
       import_error: nil,
       importing: false,
       selected_deck: nil
     )}
  end

  def handle_event("show_import", _params, socket) do
    {:noreply, assign(socket, show_import_modal: true, import_name: "", import_text: "", import_error: nil)}
  end

  def handle_event("hide_import", _params, socket) do
    {:noreply, assign(socket, show_import_modal: false)}
  end

  def handle_event("import_deck", %{"name" => name, "decklist" => text}, socket) do
    user = socket.assigns.current_scope.user
    socket = assign(socket, importing: true, import_error: nil)

    case Decks.create_deck_from_text(user, String.trim(name), String.trim(text)) do
      {:ok, deck} ->
        decks = [deck | socket.assigns.decks]

        {:noreply,
         socket
         |> assign(decks: decks, show_import_modal: false, importing: false)
         |> put_flash(:info, "Deck \"#{deck.name}\" imported successfully!")}

      {:error, reason} ->
        {:noreply, assign(socket, import_error: reason, importing: false)}
    end
  end

  def handle_event("view_deck", %{"id" => id}, socket) do
    deck = Decks.get_deck_with_cards!(id)
    {:noreply, assign(socket, selected_deck: deck)}
  end

  def handle_event("close_deck", _params, socket) do
    {:noreply, assign(socket, selected_deck: nil)}
  end

  def handle_event("delete_deck", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    deck = Decks.get_deck!(id)

    if deck.user_id == user.id do
      {:ok, _} = Decks.delete_deck(deck)
      decks = Enum.reject(socket.assigns.decks, &(&1.id == deck.id))

      socket =
        if socket.assigns.selected_deck && socket.assigns.selected_deck.id == deck.id do
          assign(socket, selected_deck: nil)
        else
          socket
        end

      {:noreply, assign(socket, decks: decks)}
    else
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  defp group_by_board(deck_cards) do
    deck_cards
    |> Enum.group_by(& &1.board)
    |> Enum.sort_by(fn {board, _} ->
      case board do
        "main" -> 0
        "sideboard" -> 1
        _ -> 2
      end
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold">My Decks</h1>
        <button phx-click="show_import" class="btn btn-primary">
          + Import Deck
        </button>
      </div>

      <div :if={@decks == []} class="text-center py-16 text-gray-400">
        <p class="text-lg">No decks yet.</p>
        <p class="text-sm mt-2">Import a deck from Moxfield to get started.</p>
      </div>

      <div class="space-y-3">
        <%= for deck <- @decks do %>
          <div class="bg-gray-800 rounded-lg p-4 flex items-center justify-between">
            <div
              class="flex-1 cursor-pointer hover:text-white transition-colors"
              phx-click="view_deck"
              phx-value-id={deck.id}
            >
              <div class="font-medium">{deck.name}</div>
              <div :if={deck.source_url} class="text-sm text-gray-400 mt-1 truncate max-w-md">
                {deck.source_url}
              </div>
            </div>
            <button
              phx-click="delete_deck"
              phx-value-id={deck.id}
              data-confirm="Delete this deck?"
              class="btn btn-sm btn-ghost text-red-400 hover:text-red-300 ml-4 shrink-0"
            >
              Delete
            </button>
          </div>
        <% end %>
      </div>

      <%!-- Deck Detail Panel --%>
      <div
        :if={@selected_deck}
        class="fixed inset-0 bg-black/60 z-40"
        phx-click="close_deck"
      />
      <div class={[
        "fixed top-0 right-0 h-full w-full max-w-md bg-gray-900 shadow-2xl z-50 flex flex-col transition-transform duration-300",
        if(@selected_deck, do: "translate-x-0", else: "translate-x-full")
      ]}>
        <%= if @selected_deck do %>
          <div class="flex items-center justify-between p-4 border-b border-gray-700">
            <h2 class="text-lg font-bold truncate">{@selected_deck.name}</h2>
            <button phx-click="close_deck" class="btn btn-sm btn-ghost">✕</button>
          </div>

          <div class="overflow-y-auto flex-1 p-4">
            <%= for {board, cards} <- group_by_board(@selected_deck.deck_cards) do %>
              <div class="mb-6">
                <h3 class="text-xs font-semibold uppercase tracking-wider text-gray-400 mb-2">
                  {board} ({Enum.sum(Enum.map(cards, & &1.quantity))})
                </h3>
                <div class="space-y-1">
                  <%= for dc <- Enum.sort_by(cards, & &1.card_name) do %>
                    <div class="flex items-center gap-2 text-sm">
                      <span class="text-gray-400 w-5 text-right shrink-0">{dc.quantity}x</span>
                      <span class="text-white">{dc.card_name}</span>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Import Modal --%>
      <div
        :if={@show_import_modal}
        class="fixed inset-0 bg-black/70 flex items-center justify-center z-50"
      >
        <div class="bg-gray-800 rounded-xl p-6 w-full max-w-lg mx-4 shadow-2xl">
          <h2 class="text-xl font-bold mb-4">Import Deck</h2>

          <form phx-submit="import_deck">
            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-300 mb-1">
                Deck Name
              </label>
              <input
                type="text"
                name="name"
                value={@import_name}
                placeholder="My Deck"
                class="input input-bordered w-full bg-gray-700 text-white placeholder-gray-400"
                required
                autofocus
              />
            </div>

            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-300 mb-1">
                Decklist
              </label>
              <textarea
                name="decklist"
                rows="12"
                placeholder={"4 Lightning Bolt\n2 Snapcaster Mage\n...\n\nSideboard\n2 Negate"}
                class="textarea textarea-bordered w-full bg-gray-700 text-white placeholder-gray-400 font-mono text-sm"
                required
              >{@import_text}</textarea>
              <p class="text-xs text-gray-500 mt-1">
                One card per line: <span class="font-mono">4 Lightning Bolt</span>. Add a "Sideboard" line to separate sideboard cards.
              </p>
              <div :if={@import_error} class="text-red-400 text-sm mt-2">
                {@import_error}
              </div>
            </div>

            <div class="flex gap-3 justify-end">
              <button type="button" phx-click="hide_import" class="btn btn-ghost">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary" disabled={@importing}>
                {if @importing, do: "Importing...", else: "Import"}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
