defmodule GoodtapWeb.CardSearchComponent do
  @moduledoc """
  Reusable card search LiveComponent.

  Usage:
      <.live_component
        module={GoodtapWeb.CardSearchComponent}
        id="card-search"
        token_only={false}
        on_select="card_selected"
      />

  The parent receives a `on_select` event with:
      %{"card_id" => card.id, "card_name" => card.name, "printing_id" => printing_id_or_nil}
  """
  use GoodtapWeb, :live_component

  alias Goodtap.Catalog

  @default_limit 20

  def mount(socket) do
    {:ok,
     assign(socket,
       query: "",
       results: [],
       total: 0,
       token_only: false,
       # Map of card_id -> selected printing_id
       selected_printings: %{},
       # Map of card_id -> list of printings (loaded lazily)
       printings: %{}
     )}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:on_select, assigns.on_select)
      |> assign(:token_only, Map.get(assigns, :token_only, false))

    {:ok, socket}
  end

  def handle_event("search", %{"query" => query} = params, socket) do
    token_only =
      case Map.get(params, "token_only") do
        "true" -> true
        true -> true
        _ -> socket.assigns.token_only
      end

    {results, total} =
      if String.trim(query) == "" do
        {[], 0}
      else
        Catalog.search_cards_paged(query, limit: @default_limit, token_only: token_only)
      end

    {:noreply, assign(socket, query: query, results: results, total: total, token_only: token_only)}
  end

  def handle_event("toggle_token_only", _params, socket) do
    token_only = !socket.assigns.token_only
    {results, total} =
      if String.trim(socket.assigns.query) == "" do
        {[], 0}
      else
        Catalog.search_cards_paged(socket.assigns.query, limit: @default_limit, token_only: token_only)
      end

    {:noreply, assign(socket, token_only: token_only, results: results, total: total)}
  end

  def handle_event("load_printings", %{"card_name" => card_name, "card_id" => card_id}, socket) do
    printings =
      Map.put_new_lazy(socket.assigns.printings, card_id, fn ->
        Catalog.get_printings_for_card(card_name)
      end)

    {:noreply, assign(socket, printings: printings)}
  end

  def handle_event("select_printing", %{"card_id" => card_id, "printing_id" => printing_id}, socket) do
    selected_printings = Map.put(socket.assigns.selected_printings, card_id, printing_id)
    {:noreply, assign(socket, selected_printings: selected_printings)}
  end

  def handle_event("select_card", %{"card_id" => card_id, "card_name" => card_name}, socket) do
    printing_id = Map.get(socket.assigns.selected_printings, card_id)

    send(self(), {socket.assigns.on_select, %{
      "card_id" => card_id,
      "card_name" => card_name,
      "printing_id" => printing_id
    }})

    {:noreply, socket}
  end

  defp card_image(card, selected_printings, printings) do
    printing_id = Map.get(selected_printings, card.id)
    card_printings = Map.get(printings, card.id, [])

    selected_printing =
      if printing_id do
        Enum.find(card_printings, &(&1.id == printing_id))
      end

    cond do
      selected_printing ->
        get_in(selected_printing.image_uris, ["normal"]) || "/images/CardBack.png"
      true ->
        get_in(card.data, ["image_uris", "normal"]) ||
          get_in(card.data, ["card_faces", Access.at(0), "image_uris", "normal"]) ||
          "/images/CardBack.png"
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <%!-- Search input --%>
      <div class="flex gap-2 items-center">
        <input
          type="text"
          value={@query}
          phx-change="search"
          phx-target={@myself}
          phx-debounce="200"
          name="query"
          placeholder="Search cards..."
          class="input input-bordered flex-1 bg-gray-700"
          autofocus
        />
        <label
          :if={!@token_only}
          class="flex items-center gap-2 text-sm text-gray-300 cursor-pointer select-none whitespace-nowrap"
        >
          <input
            type="checkbox"
            checked={@token_only}
            phx-click="toggle_token_only"
            phx-target={@myself}
            class="checkbox checkbox-sm"
          />
          Tokens only
        </label>
      </div>

      <%!-- Results grid --%>
      <div class="flex flex-wrap gap-3 max-h-72 overflow-y-auto py-1">
        <%= for card <- @results do %>
          <% img = card_image(card, @selected_printings, @printings) %>
          <% card_printings = Map.get(@printings, card.id, []) %>
          <div class="flex flex-col items-center gap-1">
            <button
              phx-click="select_card"
              phx-value-card_id={card.id}
              phx-value-card_name={card.name}
              phx-target={@myself}
              class="rounded hover:ring-2 hover:ring-purple-400 transition-all"
              title={card.name}
              phx-mouseenter="load_printings"
              phx-value-card_id={card.id}
              phx-value-card_name={card.name}
              phx-target={@myself}
            >
              <img
                src={img}
                class="h-28 w-auto rounded shadow"
                draggable="false"
              />
            </button>
            <span class="text-xs text-gray-300 max-w-[4rem] truncate">{card.name}</span>
            <%!-- Printing selector (shown once printings are loaded) --%>
            <select
              :if={length(card_printings) > 1}
              class="select select-xs bg-gray-700 max-w-[5rem] text-xs"
              phx-change="select_printing"
              phx-value-card_id={card.id}
              phx-target={@myself}
              name="printing_id"
            >
              <option value="">Default</option>
              <%= for p <- card_printings do %>
                <option
                  value={p.id}
                  selected={Map.get(@selected_printings, card.id) == p.id}
                >
                  {String.upcase(p.set_code)} #{p.collector_number}
                </option>
              <% end %>
            </select>
          </div>
        <% end %>

        <div :if={@query != "" && @results == []} class="text-gray-400 text-sm py-2 text-center w-full">
          No cards found
        </div>
      </div>

      <%!-- Showing X of Y --%>
      <div :if={@total > 0} class="text-xs text-gray-500 text-right">
        Showing {min(length(@results), @total)} of {@total}
      </div>
    </div>
    """
  end
end
