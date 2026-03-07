defmodule GoodtapWeb.CardSearchComponent do
  @moduledoc """
  Reusable card search LiveComponent.

  Usage:
      <.live_component
        module={GoodtapWeb.CardSearchComponent}
        id="card-search"
        filter={:no_tokens}
        show_filter_toggle={false}
        on_select="card_selected"
      />

  filter: :all | :tokens_only | :no_tokens (default: :all)
  show_filter_toggle: show buttons to switch filter at runtime (default: false)

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
       filter: :all,
       show_filter_toggle: false,
       selected_printings: %{}
     )}
  end

  def update(assigns, socket) do
    new_filter = Map.get(assigns, :filter, :all)
    old_filter = socket.assigns[:filter]

    socket =
      socket
      |> assign(:on_select, assigns.on_select)
      |> assign(:show_filter_toggle, Map.get(assigns, :show_filter_toggle, false))
      |> assign(:filter, new_filter)

    # Re-run search if filter changed and there's an active query
    socket =
      if old_filter != nil && old_filter != new_filter && socket.assigns.query != "" do
        {results, total} = Catalog.search_cards_paged(socket.assigns.query, limit: @default_limit, filter: new_filter)
        assign(socket, results: results, total: total)
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
{results, total} =
      if String.trim(query) == "" do
        {[], 0}
      else
        Catalog.search_cards_paged(query, limit: @default_limit, filter: socket.assigns.filter)
      end

    {:noreply, assign(socket, query: query, results: results, total: total)}
  end

  def handle_event("set_filter", %{"filter" => filter}, socket) do
    filter = String.to_existing_atom(filter)

    {results, total} =
      if String.trim(socket.assigns.query) == "" do
        {[], 0}
      else
        Catalog.search_cards_paged(socket.assigns.query, limit: @default_limit, filter: filter)
      end

    {:noreply, assign(socket, filter: filter, results: results, total: total)}
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

  defp card_image(card, selected_printings) do
    printing_id = Map.get(selected_printings, to_string(card.id))

    selected_printing =
      if printing_id && printing_id != "" do
        Enum.find(card.printings, &(&1["id"] == printing_id))
      end

    cond do
      selected_printing ->
        get_in(selected_printing, ["image_uris", "normal"]) || "/images/CardBack.png"
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
      <form phx-change="search" phx-target={@myself}>
        <input
          type="text"
          value={@query}
          phx-debounce="200"
          name="query"
          placeholder="Search cards..."
          class="input input-bordered w-full bg-gray-700"
          autofocus
        />
      </form>

      <%!-- Filter toggle --%>
      <div :if={@show_filter_toggle} class="flex gap-1 text-xs">
        <button
          phx-click="set_filter"
          phx-value-filter="all"
          phx-target={@myself}
          class={["px-2 py-1 rounded", if(@filter == :all, do: "bg-purple-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600")]}
        >All</button>
        <button
          phx-click="set_filter"
          phx-value-filter="tokens_only"
          phx-target={@myself}
          class={["px-2 py-1 rounded", if(@filter == :tokens_only, do: "bg-purple-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600")]}
        >Tokens only</button>
        <button
          phx-click="set_filter"
          phx-value-filter="no_tokens"
          phx-target={@myself}
          class={["px-2 py-1 rounded", if(@filter == :no_tokens, do: "bg-purple-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600")]}
        >No tokens</button>
      </div>

      <%!-- Results grid --%>
      <div class="flex flex-wrap gap-3 max-h-72 overflow-y-auto py-1" id={"card-search-results-#{@myself.cid}"} phx-hook="CardPreview">
        <%= for card <- @results do %>
          <% img = card_image(card, @selected_printings) %>
          <div class="flex flex-col items-center gap-1 w-24">
            <button
              phx-click="select_card"
              phx-value-card_id={card.id}
              phx-value-card_name={card.name}
              phx-target={@myself}
              class="rounded hover:ring-2 hover:ring-purple-400 transition-all"
              title={card.name}
            >
              <img src={img} class="h-28 w-auto rounded shadow" draggable="false" data-card-img={img} />
            </button>
            <span class="text-xs text-gray-300 w-full truncate text-center">{card.name}</span>
            <%!-- Printing selector --%>
            <form
              :if={length(card.printings) > 1}
              phx-change="select_printing"
              phx-target={@myself}
            >
              <input type="hidden" name="card_id" value={card.id} />
              <select class="select select-xs bg-gray-700 w-full text-xs" name="printing_id">
                <%= for p <- card.printings do %>
                  <option
                    value={p["id"]}
                    selected={Map.get(@selected_printings, to_string(card.id)) == p["id"]}
                  >
                    {String.upcase(p["set_code"])} #{p["collector_number"]}
                  </option>
                <% end %>
              </select>
            </form>
          </div>
        <% end %>

        <div :if={@query != "" && @results == []} class="col-span-4 text-gray-400 text-sm py-2 text-center w-full">
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
