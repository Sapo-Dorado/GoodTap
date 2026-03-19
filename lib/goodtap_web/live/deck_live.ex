defmodule GoodtapWeb.DeckLive do
  use GoodtapWeb, :live_view

  alias Goodtap.Decks
  alias Goodtap.Catalog

  def mount(%{"username" => username, "name" => name}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Decks.get_deck_with_cards_by_slug(username, name) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/")}

      deck when deck.user_id != user.id ->
        {:ok, push_navigate(socket, to: ~p"/decks")}

      deck ->
      not_found = get_in(socket.assigns, [:flash, "not_found_cards"]) || []

      {:ok,
       assign(socket,
         deck: deck,
         card_map: load_card_map(deck),
         page_title: deck.name,
         deck_view_mode: :list,
         editing_qty: nil,
         deck_card_menu: nil,
         adding_to_board: nil,
         selected_printings: %{},
         not_found_cards: not_found
       )}
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
        {:noreply, socket |> reload_deck() |> assign(editing_qty: nil)}
      _ ->
        {:noreply, assign(socket, editing_qty: nil)}
    end
  end

  def handle_event("cancel_edit_qty", _params, socket) do
    {:noreply, assign(socket, editing_qty: nil)}
  end

  def handle_event("save_qty_blur", %{"value" => qty_str, "id" => id}, socket) do
    case Integer.parse(qty_str) do
      {qty, _} when qty > 0 ->
        deck_card = Decks.get_deck_card!(id)
        {:ok, _} = Decks.update_deck_card_quantity(deck_card, qty)
        {:noreply, socket |> reload_deck() |> assign(editing_qty: nil)}
      _ ->
        {:noreply, assign(socket, editing_qty: nil)}
    end
  end

  # ─── Remove Card ──────────────────────────────────────────────────────────

  def handle_event("remove_card", %{"id" => id}, socket) do
    deck_card = Decks.get_deck_card!(id)
    {:ok, _} = Decks.remove_deck_card(deck_card)
    {:noreply, reload_deck(socket)}
  end

  # ─── Deck Card Context Menu ───────────────────────────────────────────────

  def handle_event("deck_card_menu", %{"id" => id, "board" => board}, socket) do
    id = to_string(id)
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
    {:noreply, socket |> reload_deck() |> assign(deck_card_menu: nil)}
  end

  def handle_event("set_commander", %{"id" => id}, socket) do
    {:ok, _} = Decks.set_commander(socket.assigns.deck.id, id)
    {:noreply, socket |> reload_deck() |> assign(deck_card_menu: nil)}
  end

  # ─── View Mode ────────────────────────────────────────────────────────────

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, deck_view_mode: String.to_existing_atom(mode))}
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("select_printing", %{"deck_card_id" => id, "printing_id" => printing_id}, socket) do
    {:ok, _} = Decks.update_deck_card_printing(Decks.get_deck_card!(id), printing_id)
    {:noreply, reload_deck(socket)}
  end

  # ─── Add Card ─────────────────────────────────────────────────────────────

  def handle_event("show_add_card", %{"board" => board}, socket) do
    {:noreply, assign(socket, adding_to_board: board, deck_card_menu: nil)}
  end

  def handle_event("close_add_card", _params, socket) do
    {:noreply, assign(socket, adding_to_board: nil)}
  end

  def handle_info({:deck_card_selected, %{"oracle_id" => oracle_id, "printing_id" => printing_id}}, socket) do
    board = socket.assigns.adding_to_board || "main"
    {:ok, _} = Decks.add_card_to_deck(socket.assigns.deck, oracle_id, printing_id, board)
    {:noreply, socket |> reload_deck() |> assign(adding_to_board: nil)}
  end

  # ─── Helpers ──────────────────────────────────────────────────────────────

  defp reload_deck(socket) do
    deck = Decks.get_deck_with_cards!(socket.assigns.deck.id)
    socket |> assign(deck: deck, card_map: load_card_map(deck))
  end

  defp load_card_map(deck) do
    oracle_ids = Enum.map(deck.deck_cards, & &1.oracle_id) |> Enum.uniq()
    Catalog.list_cards_by_oracle_ids(oracle_ids) |> Map.new(&{&1.oracle_id, &1})
  end

  defp board_label("commander"), do: "Starts in Play"
  defp board_label(board), do: String.capitalize(board)

  defp group_by_board(deck_cards) do
    deck_cards
    |> Enum.group_by(& &1.board)
    |> Map.put_new("main", [])
    |> Enum.sort_by(fn {board, _} ->
      case board do
        "commander" -> 0
        "main" -> 1
        "sideboard" -> 2
        _ -> 3
      end
    end)
  end

  defp card_image_url_from_card(nil, _printing_id), do: nil
  defp card_image_url_from_card(card, printing_id) do
    printing = if printing_id, do: Enum.find(card.printings, &(&1["id"] == printing_id))
    cond do
      printing -> get_in(printing, ["image_uris", "normal"])
      true ->
        get_in(card.data, ["image_uris", "normal"]) ||
          get_in(card.data, ["card_faces", Access.at(0), "image_uris", "normal"])
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <%!-- Header --%>
      <div class="flex items-center gap-4 mb-6">
        <.link navigate={~p"/decks"} class="text-gray-400 hover:text-white">← Back</.link>
        <h1 class="text-2xl font-bold flex-1">{@deck.name}</h1>
        <div class="flex rounded overflow-hidden border border-gray-600 text-xs">
          <button
            phx-click="set_view_mode"
            phx-value-mode="list"
            class={["px-3 py-1.5", if(@deck_view_mode == :list, do: "bg-purple-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600")]}
          >List</button>
          <button
            phx-click="set_view_mode"
            phx-value-mode="preview"
            class={["px-3 py-1.5", if(@deck_view_mode == :preview, do: "bg-purple-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600")]}
          >Preview</button>
        </div>
      </div>

      <%!-- Deck content --%>
      <div id="deck-card-menu-hook" phx-hook="DeckCardMenu">
      <%= for {board, cards} <- group_by_board(@deck.deck_cards) do %>
        <div class="mb-6">
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-gray-400">
              {board_label(board)} ({Enum.sum(Enum.map(cards, & &1.quantity))})
            </h3>
            <button phx-click="show_add_card" phx-value-board={board} class="text-xs text-purple-400 hover:text-purple-300">
              + Add card
            </button>
          </div>

          <%= if @deck_view_mode == :list do %>
            <div class="space-y-1">
              <%= for dc <- Enum.sort_by(cards, fn dc -> (Map.get(@card_map, dc.oracle_id) || %{}) |> Map.get(:name, "") end) do %>
                <div class="flex items-center gap-2 text-sm group">
                  <%= if @editing_qty == to_string(dc.id) do %>
                    <form phx-submit="save_qty" class="flex items-center">
                      <input type="hidden" name="card_id" value={dc.id} />
                      <input
                        type="number"
                        name="quantity"
                        value={dc.quantity}
                        min="1"
                        max="99"
                        class="w-12 text-center bg-gray-700 border border-purple-500 rounded text-xs py-0.5 focus:outline-none"
                        autofocus
                        phx-blur="save_qty_blur"
                        phx-value-id={dc.id}
                      />
                    </form>
                  <% else %>
                    <button
                      phx-click="start_edit_qty"
                      phx-value-id={dc.id}
                      class="text-gray-400 w-8 text-right shrink-0 hover:text-white tabular-nums"
                    >{dc.quantity}x</button>
                  <% end %>

                  <div class="relative">
                    <span
                      class="text-white cursor-context-menu hover:text-purple-300"
                      data-deck-card-id={dc.id}
                      data-deck-card-board={dc.board}
                    >{(Map.get(@card_map, dc.oracle_id) || %{name: dc.oracle_id}).name}</span>
                    <button
                      phx-click="remove_card"
                      phx-value-id={dc.id}
                      class="text-gray-500 hover:text-red-400 shrink-0 ml-1"
                    >×</button>
                    <%= if @deck_card_menu && @deck_card_menu.id == to_string(dc.id) do %>
                      <div class="absolute left-0 top-full mt-1 z-10 bg-gray-800 border border-gray-600 rounded shadow-xl py-1 text-sm min-w-[160px]" phx-click-away="close_deck_card_menu">
                        <%= if @deck_card_menu.board != "main" do %>
                          <button phx-click="move_card_board" phx-value-id={dc.id} phx-value-board="main" class="w-full text-left px-4 py-2 hover:bg-gray-700">Move to Main Deck</button>
                        <% end %>
                        <%= if @deck_card_menu.board != "sideboard" do %>
                          <button phx-click="move_card_board" phx-value-id={dc.id} phx-value-board="sideboard" class="w-full text-left px-4 py-2 hover:bg-gray-700">Move to Sideboard</button>
                        <% end %>
                        <%= if @deck_card_menu.board != "commander" do %>
                          <button phx-click="set_commander" phx-value-id={dc.id} class="w-full text-left px-4 py-2 hover:bg-gray-700 text-yellow-400">Set as Starts in Play</button>
                        <% end %>
                        <button phx-click="remove_card" phx-value-id={dc.id} class="w-full text-left px-4 py-2 hover:bg-gray-700 text-red-400">Remove</button>
                      </div>
                    <% end %>
                  </div>

                </div>
              <% end %>
            </div>
          <% else %>
            <div class="flex flex-wrap gap-3">
              <%= for dc <- Enum.sort_by(cards, fn dc -> (Map.get(@card_map, dc.oracle_id) || %{}) |> Map.get(:name, "") end) do %>
                <% card = Map.get(@card_map, dc.oracle_id) %>
                <% img = card_image_url_from_card(card, dc.printing_id) %>
                <div class="flex flex-col items-center gap-1 relative group w-24">
                  <div class="relative w-full">
                    <img
                      src={img || "/images/CardBack.png"}
                      class="w-full h-auto rounded shadow cursor-context-menu"
                      title={(card && card.name) || dc.oracle_id}
                      data-deck-card-id={dc.id}
                      data-deck-card-board={dc.board}
                    />
                    <%= if @deck_card_menu && @deck_card_menu.id == to_string(dc.id) do %>
                      <div class="absolute left-0 top-full mt-1 z-10 bg-gray-800 border border-gray-600 rounded shadow-xl py-1 text-sm min-w-[160px]" phx-click-away="close_deck_card_menu">
                        <%= if @deck_card_menu.board != "main" do %>
                          <button phx-click="move_card_board" phx-value-id={dc.id} phx-value-board="main" class="w-full text-left px-4 py-2 hover:bg-gray-700">Move to Main Deck</button>
                        <% end %>
                        <%= if @deck_card_menu.board != "sideboard" do %>
                          <button phx-click="move_card_board" phx-value-id={dc.id} phx-value-board="sideboard" class="w-full text-left px-4 py-2 hover:bg-gray-700">Move to Sideboard</button>
                        <% end %>
                        <%= if @deck_card_menu.board != "commander" do %>
                          <button phx-click="set_commander" phx-value-id={dc.id} class="w-full text-left px-4 py-2 hover:bg-gray-700 text-yellow-400">Set as Starts in Play</button>
                        <% end %>
                        <button phx-click="remove_card" phx-value-id={dc.id} class="w-full text-left px-4 py-2 hover:bg-gray-700 text-red-400">Remove</button>
                      </div>
                    <% end %>
                  </div>
                  <div class="flex items-center gap-1 w-full">
                    <%= if @editing_qty == to_string(dc.id) do %>
                      <form phx-submit="save_qty" class="flex items-center">
                        <input type="hidden" name="card_id" value={dc.id} />
                        <input
                          type="number"
                          name="quantity"
                          value={dc.quantity}
                          min="1"
                          max="99"
                          class="w-10 text-center bg-gray-700 border border-purple-500 rounded text-xs py-0.5 focus:outline-none shrink-0"
                          autofocus
                          phx-blur="save_qty_blur"
                        />
                      </form>
                    <% else %>
                      <button
                        phx-click="start_edit_qty"
                        phx-value-id={dc.id}
                        class="text-xs text-gray-400 hover:text-white shrink-0"
                      >{dc.quantity}x</button>
                    <% end %>
                    <span class="text-xs text-gray-300 truncate">{(Map.get(@card_map, dc.oracle_id) || %{name: dc.oracle_id}).name}</span>
                  </div>
                  <form
                    :if={card && length(card.printings) > 1}
                    phx-change="select_printing"
                  >
                    <input type="hidden" name="deck_card_id" value={dc.id} />
                    <select class="select select-xs bg-gray-700 w-full text-xs" name="printing_id">
                      <%= for p <- Enum.sort_by(card && card.printings || [], & &1["released_at"], :desc) do %>
                        <option value={p["id"]} selected={dc.printing_id == p["id"]}>
                          {String.upcase(p["set_code"])} #{p["collector_number"]}
                        </option>
                      <% end %>
                    </select>
                  </form>
                  <button phx-click="remove_card" phx-value-id={dc.id} class="text-gray-500 hover:text-red-400 text-xs opacity-0 group-hover:opacity-100 transition-opacity">
                    Remove
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
      </div><%!-- /deck-card-menu-hook --%>
      <%!-- Not found warning --%>
      <div :if={@not_found_cards != []} class="mt-4 bg-yellow-900/40 border border-yellow-700 rounded-lg p-4 text-sm text-yellow-300">
        <p class="font-semibold mb-1">Cards not found during import:</p>
        <ul class="list-disc list-inside space-y-0.5 text-yellow-400">
          <%= for name <- @not_found_cards do %>
            <li>{name}</li>
          <% end %>
        </ul>
      </div>
    </div>

    <%!-- Add Card Modal --%>
    <div
      :if={@adding_to_board}
      class="fixed inset-0 bg-black/80 flex items-center justify-center z-50"
      phx-click="close_add_card"
    >
      <div class="bg-gray-800 rounded-xl p-6 w-full max-w-2xl mx-4" phx-click="noop">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-xl font-bold">Add Card to {String.capitalize(@adding_to_board)}</h2>
          <button phx-click="close_add_card" class="text-gray-400 hover:text-white text-2xl leading-none">&times;</button>
        </div>
        <.live_component
          module={GoodtapWeb.CardSearchComponent}
          id={"add-card-#{@adding_to_board}"}
          filter={:no_tokens}
          on_select={:deck_card_selected}
        />
      </div>
    </div>
    """
  end
end
