defmodule GoodtapWeb.DeckListLive do
  use GoodtapWeb, :live_view

  alias Goodtap.Decks
  alias Goodtap.Catalog

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
       selected_deck: nil,
       # deck view mode: :list or :preview
       deck_view_mode: :list,
       # inline qty editing: deck_card_id -> true
       editing_qty: nil,
       # context menu for deck card: %{id, board, x, y} or nil
       deck_card_menu: nil,
       # which board we're adding a card to: "main" | "sideboard" | nil
       adding_to_board: nil
     )}
  end

  # ─── Import ───────────────────────────────────────────────────────────────

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

  # ─── Deck Selection ───────────────────────────────────────────────────────

  def handle_event("view_deck", %{"id" => id}, socket) do
    deck = Decks.get_deck_with_cards!(id)
    {:noreply, assign(socket, selected_deck: deck, deck_view_mode: :list, editing_qty: nil, deck_card_menu: nil)}
  end

  def handle_event("close_deck", _params, socket) do
    {:noreply, assign(socket, selected_deck: nil, deck_card_menu: nil, adding_to_board: nil)}
  end

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, deck_view_mode: String.to_existing_atom(mode))}
  end

  # ─── Delete Deck ──────────────────────────────────────────────────────────

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

  # ─── Inline Quantity Editing ──────────────────────────────────────────────

  def handle_event("start_edit_qty", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_qty: id)}
  end

  def handle_event("save_qty", %{"card_id" => id, "quantity" => qty_str}, socket) do
    case Integer.parse(qty_str) do
      {qty, _} when qty > 0 ->
        deck_card = Decks.get_deck_card!(id)
        {:ok, _} = Decks.update_deck_card_quantity(deck_card, qty)
        socket = reload_selected_deck(socket)
        {:noreply, assign(socket, editing_qty: nil)}

      _ ->
        {:noreply, assign(socket, editing_qty: nil)}
    end
  end

  def handle_event("cancel_edit_qty", _params, socket) do
    {:noreply, assign(socket, editing_qty: nil)}
  end

  # ─── Remove Card ──────────────────────────────────────────────────────────

  def handle_event("remove_card", %{"id" => id}, socket) do
    deck_card = Decks.get_deck_card!(id)
    {:ok, _} = Decks.remove_deck_card(deck_card)
    socket = reload_selected_deck(socket)
    {:noreply, socket}
  end

  # ─── Deck Card Context Menu ───────────────────────────────────────────────

  def handle_event("deck_card_menu", %{"id" => id, "board" => board}, socket) do
    # Toggle: close if already open for this card
    menu =
      if socket.assigns.deck_card_menu && socket.assigns.deck_card_menu.id == id do
        nil
      else
        %{id: id, board: board}
      end

    {:noreply, assign(socket, deck_card_menu: menu)}
  end

  def handle_event("close_deck_card_menu", _params, socket) do
    {:noreply, assign(socket, deck_card_menu: nil)}
  end

  def handle_event("move_card_board", %{"id" => id, "board" => board}, socket) do
    deck_card = Decks.get_deck_card!(id)
    {:ok, _} = Decks.move_deck_card_board(deck_card, board)
    socket = reload_selected_deck(socket)
    {:noreply, assign(socket, deck_card_menu: nil)}
  end

  def handle_event("set_commander", %{"id" => id}, socket) do
    deck = socket.assigns.selected_deck
    {:ok, _} = Decks.set_commander(deck.id, id)
    socket = reload_selected_deck(socket)
    {:noreply, assign(socket, deck_card_menu: nil)}
  end

  # ─── Add Card via CardSearchComponent ─────────────────────────────────────

  def handle_event("show_add_card", %{"board" => board}, socket) do
    {:noreply, assign(socket, adding_to_board: board, deck_card_menu: nil)}
  end

  def handle_event("close_add_card", _params, socket) do
    {:noreply, assign(socket, adding_to_board: nil)}
  end

  def handle_info({:deck_card_selected, %{"card_name" => card_name, "printing_id" => printing_id}}, socket) do
    deck = socket.assigns.selected_deck
    board = socket.assigns.adding_to_board || "main"

    {:ok, _} = Decks.add_card_to_deck(deck, card_name, printing_id, board)
    socket = reload_selected_deck(socket)
    {:noreply, assign(socket, adding_to_board: nil)}
  end

  # ─── Helpers ──────────────────────────────────────────────────────────────

  defp reload_selected_deck(socket) do
    case socket.assigns.selected_deck do
      nil -> socket
      deck -> assign(socket, selected_deck: Decks.get_deck_with_cards!(deck.id))
    end
  end

  defp group_by_board(deck_cards) do
    deck_cards
    |> Enum.group_by(& &1.board)
    |> Enum.sort_by(fn {board, _} ->
      case board do
        "commander" -> 0
        "main" -> 1
        "sideboard" -> 2
        _ -> 3
      end
    end)
  end

  defp card_image_url(card_name, printing_id) do
    cond do
      printing_id ->
        case Catalog.get_printing(printing_id) do
          nil -> nil
          p -> get_in(p.image_uris, ["normal"])
        end

      true ->
        case Catalog.get_card_by_name(card_name) do
          nil ->
            nil

          card ->
            get_in(card.data, ["image_uris", "normal"]) ||
              get_in(card.data, ["card_faces", Access.at(0), "image_uris", "normal"])
        end
    end
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
        <p class="text-sm mt-2">Import a deck to get started.</p>
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
          <%!-- Header --%>
          <div class="flex items-center justify-between p-4 border-b border-gray-700">
            <h2 class="text-lg font-bold truncate">{@selected_deck.name}</h2>
            <div class="flex items-center gap-2">
              <%!-- View mode toggle --%>
              <div class="flex rounded overflow-hidden border border-gray-600 text-xs">
                <button
                  phx-click="set_view_mode"
                  phx-value-mode="list"
                  class={["px-2 py-1", if(@deck_view_mode == :list, do: "bg-purple-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600")]}
                >
                  List
                </button>
                <button
                  phx-click="set_view_mode"
                  phx-value-mode="preview"
                  class={["px-2 py-1", if(@deck_view_mode == :preview, do: "bg-purple-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600")]}
                >
                  Preview
                </button>
              </div>
              <button phx-click="close_deck" class="btn btn-sm btn-ghost">✕</button>
            </div>
          </div>

          <%!-- Content --%>
          <div class="overflow-y-auto flex-1 p-4">
            <%= for {board, cards} <- group_by_board(@selected_deck.deck_cards) do %>
              <div class="mb-6">
                <div class="flex items-center justify-between mb-2">
                  <h3 class="text-xs font-semibold uppercase tracking-wider text-gray-400">
                    {board} ({Enum.sum(Enum.map(cards, & &1.quantity))})
                  </h3>
                  <button
                    phx-click="show_add_card"
                    phx-value-board={board}
                    class="text-xs text-purple-400 hover:text-purple-300"
                  >
                    + Add card
                  </button>
                </div>

                <%= if @deck_view_mode == :list do %>
                  <div class="space-y-1">
                    <%= for dc <- Enum.sort_by(cards, & &1.card_name) do %>
                      <div class="flex items-center gap-2 text-sm group">
                        <%!-- Quantity: click to edit inline --%>
                        <%= if @editing_qty == dc.id do %>
                          <form
                            phx-submit="save_qty"
                            class="flex items-center"
                          >
                            <input type="hidden" name="card_id" value={dc.id} />
                            <input
                              type="number"
                              name="quantity"
                              value={dc.quantity}
                              min="1"
                              max="99"
                              class="w-12 text-center bg-gray-700 border border-purple-500 rounded text-xs py-0.5 focus:outline-none"
                              autofocus
                              phx-blur="cancel_edit_qty"
                            />
                          </form>
                        <% else %>
                          <button
                            phx-click="start_edit_qty"
                            phx-value-id={dc.id}
                            class="text-gray-400 w-8 text-right shrink-0 hover:text-white tabular-nums"
                            title="Click to edit quantity"
                          >
                            {dc.quantity}x
                          </button>
                        <% end %>

                        <%!-- Card name with context menu toggle --%>
                        <div class="flex-1 relative">
                          <span
                            class="text-white cursor-pointer hover:text-purple-300"
                            phx-click="deck_card_menu"
                            phx-value-id={dc.id}
                            phx-value-board={dc.board}
                          >{dc.card_name}</span>
                          <%!-- Inline dropdown --%>
                          <%= if @deck_card_menu && @deck_card_menu.id == dc.id do %>
                            <div class="absolute left-0 top-full mt-1 z-10 bg-gray-800 border border-gray-600 rounded shadow-xl py-1 text-sm min-w-[160px]">
                              <%= if @deck_card_menu.board != "main" do %>
                                <button
                                  phx-click="move_card_board"
                                  phx-value-id={dc.id}
                                  phx-value-board="main"
                                  class="w-full text-left px-4 py-2 hover:bg-gray-700"
                                >
                                  Move to Main Deck
                                </button>
                              <% end %>
                              <%= if @deck_card_menu.board != "sideboard" do %>
                                <button
                                  phx-click="move_card_board"
                                  phx-value-id={dc.id}
                                  phx-value-board="sideboard"
                                  class="w-full text-left px-4 py-2 hover:bg-gray-700"
                                >
                                  Move to Sideboard
                                </button>
                              <% end %>
                              <%= if @deck_card_menu.board != "commander" do %>
                                <button
                                  phx-click="set_commander"
                                  phx-value-id={dc.id}
                                  class="w-full text-left px-4 py-2 hover:bg-gray-700 text-yellow-400"
                                >
                                  Set as Commander
                                </button>
                              <% end %>
                              <button
                                phx-click="remove_card"
                                phx-value-id={dc.id}
                                class="w-full text-left px-4 py-2 hover:bg-gray-700 text-red-400"
                              >
                                Remove
                              </button>
                            </div>
                          <% end %>
                        </div>

                        <%!-- Remove button --%>
                        <button
                          phx-click="remove_card"
                          phx-value-id={dc.id}
                          class="text-gray-600 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity ml-auto shrink-0"
                          title="Remove"
                        >
                          ×
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <%!-- Preview mode --%>
                  <div class="flex flex-wrap gap-2">
                    <%= for dc <- Enum.sort_by(cards, & &1.card_name) do %>
                      <% img = card_image_url(dc.card_name, dc.printing_id) %>
                      <div class="flex flex-col items-center gap-1 relative group">
                        <div class="relative">
                          <img
                            src={img || "/images/CardBack.png"}
                            class="h-24 w-auto rounded shadow"
                            title={dc.card_name}
                          />
                          <span class="absolute bottom-1 right-1 bg-black/70 text-white text-xs rounded px-1">
                            {dc.quantity}x
                          </span>
                        </div>
                        <button
                          phx-click="remove_card"
                          phx-value-id={dc.id}
                          class="text-gray-500 hover:text-red-400 text-xs opacity-0 group-hover:opacity-100 transition-opacity"
                        >
                          Remove
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Add Card Modal --%>
      <div
        :if={@adding_to_board}
        class="fixed inset-0 bg-black/80 flex items-center justify-center z-[70]"
      >
        <div class="bg-gray-800 rounded-xl p-6 w-full max-w-lg mx-4">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-xl font-bold">Add Card to {String.capitalize(@adding_to_board || "")}</h2>
            <button phx-click="close_add_card" class="text-gray-400 hover:text-white text-2xl leading-none">&times;</button>
          </div>
          <.live_component
            module={GoodtapWeb.CardSearchComponent}
            id={"add-card-#{@adding_to_board}"}
            token_only={false}
            on_select={:deck_card_selected}
          />
        </div>
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
