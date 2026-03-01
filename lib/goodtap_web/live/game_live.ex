defmodule GoodtapWeb.GameLive do
  use GoodtapWeb, :live_view

  alias Goodtap.{Games, Catalog}
  alias Goodtap.GameEngine.{Actions, State}
  alias GoodtapWeb.Hotkeys

  def mount(%{"id" => id}, _session, socket) do
    game = Games.get_game!(id)
    user = socket.assigns.current_scope.user

    # Verify user is in this game
    unless game.host_id == user.id || game.opponent_id == user.id do
      {:ok, push_navigate(socket, to: ~p"/games")}
    else
      my_role = if game.host_id == user.id, do: "host", else: "opponent"
      opp_role = if my_role == "host", do: "opponent", else: "host"

      game_state = game.game_state || %{}

      Games.subscribe_to_game(game.id)

      {:ok,
       assign(socket,
         game: game,
         game_state: game_state,
         my_role: my_role,
         opp_role: opp_role,
         page_title: "Game",
         # UI state
         open_zone: nil,
         context_menu: nil,
         # Scry
         scry_session: nil,
         # Token search
         token_search: nil,
         token_query: "",
         token_results: [],
         token_only: true,
         token_place_x: 0.1,
         token_place_y: 0.5,
         # Add counter
         adding_counter_to: nil,
         counter_name_input: "",
         # End game
         end_game_modal: false,
         # Multi-card selection
         selected_cards: MapSet.new()
       )}
    end
  end

  # ─── PubSub Handlers ──────────────────────────────────────────────────────

  def handle_info({:game_state_updated, new_state}, socket) do
    {:noreply, assign(socket, game_state: new_state)}
  end

  def handle_info({:game_updated, game}, socket) do
    {:noreply, assign(socket, game: game)}
  end

  def handle_info(:game_ended, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "The game has ended.")
     |> push_navigate(to: ~p"/games")}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ─── Context Menu ─────────────────────────────────────────────────────────

  def handle_event("context_menu", params, socket) do
    instance_id = params["instance_id"]
    zone = params["zone"]
    x = params["x"]
    y = params["y"]

    actions = Hotkeys.valid_actions_for(zone)

    context_menu = %{
      instance_id: instance_id,
      zone: zone,
      x: x,
      y: y,
      actions: actions,
      scry_count: 1
    }

    {:noreply, assign(socket, context_menu: context_menu)}
  end

  def handle_event("close_context_menu", _params, socket) do
    {:noreply, assign(socket, context_menu: nil)}
  end

  # ─── Multi-Card Selection ─────────────────────────────────────────────────

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_cards: MapSet.new())}
  end

  def handle_event("set_selection", %{"instance_ids" => ids}, socket) do
    {:noreply, assign(socket, selected_cards: MapSet.new(ids))}
  end

  def handle_event("adjust_scry_count", %{"delta" => delta}, socket) do
    case socket.assigns.context_menu do
      nil -> {:noreply, socket}
      menu ->
        new_count = max(1, min(20, menu.scry_count + String.to_integer(delta)))
        {:noreply, assign(socket, context_menu: %{menu | scry_count: new_count})}
    end
  end

  # ─── Keyboard Shortcuts ───────────────────────────────────────────────────

  def handle_event("hotkey", %{"key" => key, "instance_id" => id, "zone" => zone}, socket) do
    selected = socket.assigns.selected_cards
    has_selection = not MapSet.equal?(selected, MapSet.new())

    # Selection takes full precedence for card-level keys: fire even with no hovered card
    cond do
      has_selection and key == "d" ->
        apply_to_selection(socket, fn st, p, sid -> Actions.move_to_graveyard(st, p, sid, "battlefield") end)

      has_selection and key == "s" ->
        apply_to_selection(socket, fn st, p, sid -> Actions.move_to_exile(st, p, sid, "battlefield") end)

      has_selection and key == "f" ->
        apply_to_selection(socket, fn st, p, sid -> Actions.flip_card(st, p, sid, "battlefield") end)

      has_selection and key == "space" ->
        apply_to_selection(socket, fn st, p, sid -> Actions.tap(st, p, sid) end)

      has_selection and key == "t" ->
        apply_to_selection(socket, fn st, p, sid -> Actions.move_to_deck(st, p, sid, "battlefield") end)

      has_selection and key == "y" ->
        apply_to_selection(socket, fn st, p, sid -> Actions.move_to_deck_bottom(st, p, sid, "battlefield") end)

      true ->
        case key do
          "d" when not is_nil(id) ->
            apply_action(socket, fn st, p -> Actions.move_to_graveyard(st, p, id, zone) end)

          "s" when not is_nil(id) ->
            apply_action(socket, fn st, p -> Actions.move_to_exile(st, p, id, zone) end)

          "f" when not is_nil(id) ->
            apply_action(socket, fn st, p -> Actions.flip_card(st, p, id, zone) end)

          "space" when not is_nil(id) ->
            apply_action(socket, fn st, p -> Actions.tap(st, p, id) end)

          "t" when not is_nil(id) ->
            apply_action(socket, fn st, p -> Actions.move_to_deck(st, p, id, zone) end)

          "y" when not is_nil(id) ->
            apply_action(socket, fn st, p -> Actions.move_to_deck_bottom(st, p, id, zone) end)

          "v" ->
            apply_action(socket, fn st, p -> Actions.shuffle(st, p) end)

          "u" when not is_nil(id) ->
            {:noreply, assign(socket, adding_counter_to: id, counter_name_input: "")}

          "k" when not is_nil(id) ->
            apply_action(socket, fn st, p -> Actions.copy_card(st, p, id) end)

          "w" ->
            {:noreply, assign(socket, token_search: true, token_query: "", token_results: [], token_only: true)}

          "x" ->
            apply_action(socket, fn st, p -> Actions.untap_all(st, p) end)

          "c" ->
            apply_action(socket, fn st, p -> Actions.draw(st, p, 1) end)

          n when n in ["1", "2", "3", "4", "5", "6", "7", "8", "9"] ->
            count = String.to_integer(n)
            apply_action(socket, fn st, p -> Actions.draw(st, p, count) end)

          _ ->
            {:noreply, socket}
        end
    end
  end

  # ─── Card Actions ─────────────────────────────────────────────────────────

  def handle_event("action", %{"type" => "tap", "instance_id" => id}, socket) do
    apply_action(socket, fn state, player ->
      Actions.tap(state, player, id)
    end)
  end

  def handle_event("action", %{"type" => "move_to_graveyard", "instance_id" => id, "zone" => zone}, socket) do
    apply_action(socket, fn state, player ->
      Actions.move_to_graveyard(state, player, id, zone)
    end)
  end

  def handle_event("action", %{"type" => "move_to_exile", "instance_id" => id, "zone" => zone}, socket) do
    apply_action(socket, fn state, player ->
      Actions.move_to_exile(state, player, id, zone)
    end)
  end

  def handle_event("action", %{"type" => "move_to_hand", "instance_id" => id, "zone" => zone}, socket) do
    apply_action(socket, fn state, player ->
      Actions.move_to_hand(state, player, id, zone)
    end)
  end

  def handle_event("action", %{"type" => "move_to_deck_top", "instance_id" => id, "zone" => zone}, socket) do
    apply_action(socket, fn state, player ->
      Actions.move_to_deck(state, player, id, zone)
    end)
  end

  def handle_event("action", %{"type" => "move_to_deck_bottom", "instance_id" => id, "zone" => zone}, socket) do
    apply_action(socket, fn state, player ->
      Actions.move_to_deck_bottom(state, player, id, zone)
    end)
  end

  def handle_event("action", %{"type" => "flip_card", "instance_id" => id, "zone" => zone}, socket) do
    apply_action(socket, fn state, player ->
      Actions.flip_card(state, player, id, zone)
    end)
  end

  def handle_event("action", %{"type" => "copy_card", "instance_id" => id}, socket) do
    apply_action(socket, fn state, player ->
      Actions.copy_card(state, player, id)
    end)
  end

  def handle_event("action", %{"type" => "find_card"}, socket) do
    player = socket.assigns.my_role
    {:noreply, assign(socket, open_zone: {player, "deck", %{find: true, query: ""}}, context_menu: nil)}
  end

  def handle_event("action", %{"type" => "shuffle"}, socket) do
    apply_action(socket, fn state, player ->
      Actions.shuffle(state, player)
    end)
  end

  def handle_event("action", %{"type" => "draw", "count" => count}, socket) do
    apply_action(socket, fn state, player ->
      Actions.draw(state, player, String.to_integer(to_string(count)))
    end)
  end

  def handle_event("action", %{"type" => "draw"}, socket) do
    apply_action(socket, fn state, player ->
      Actions.draw(state, player, 1)
    end)
  end

  # ─── Life & Trackers ──────────────────────────────────────────────────────

  def handle_event("adjust_life", %{"delta" => delta}, socket) do
    delta = String.to_integer(delta)
    apply_action(socket, fn state, player -> Actions.adjust_life(state, player, delta) end)
  end

  def handle_event("add_tracker", %{"name" => name}, socket) do
    name = String.trim(name)

    if name != "" do
      apply_action(socket, fn state, player -> Actions.add_tracker(state, player, name) end)
    else
      {:noreply, socket}
    end
  end

  def handle_event("adjust_tracker", %{"index" => idx, "delta" => delta}, socket) do
    idx = String.to_integer(idx)
    delta = String.to_integer(delta)
    apply_action(socket, fn state, player -> Actions.adjust_tracker(state, player, idx, delta) end)
  end

  def handle_event("remove_tracker", %{"index" => idx}, socket) do
    idx = String.to_integer(idx)
    apply_action(socket, fn state, player -> Actions.remove_tracker(state, player, idx) end)
  end

  # ─── Counters ─────────────────────────────────────────────────────────────

  def handle_event("show_add_counter", %{"instance_id" => id}, socket) do
    {:noreply, assign(socket, adding_counter_to: id, counter_name_input: "")}
  end

  def handle_event("add_counter", %{"name" => name}, socket) do
    id = socket.assigns.adding_counter_to
    name = String.trim(name)

    if id && name != "" do
      socket =
        apply_action_inline(socket, fn state, player ->
          Actions.add_counter(state, player, id, name)
        end)

      {:noreply, assign(socket, adding_counter_to: nil)}
    else
      {:noreply, assign(socket, adding_counter_to: nil)}
    end
  end

  def handle_event("cancel_add_counter", _params, socket) do
    {:noreply, assign(socket, adding_counter_to: nil)}
  end

  def handle_event("adjust_counter", %{"instance_id" => id, "counter_index" => idx, "delta" => delta}, socket) do
    idx = String.to_integer(idx)
    delta = String.to_integer(delta)
    apply_action(socket, fn state, player -> Actions.update_counter(state, player, id, idx, delta) end)
  end

  def handle_event("remove_counter", %{"instance_id" => id, "counter_index" => idx}, socket) do
    idx = String.to_integer(idx)
    apply_action(socket, fn state, player -> Actions.remove_counter(state, player, id, idx) end)
  end

  # ─── Zone Popup ───────────────────────────────────────────────────────────

  def handle_event("open_zone", %{"zone" => zone, "owner" => owner}, socket) do
    {:noreply, assign(socket, open_zone: {owner, zone, %{}})}
  end

  def handle_event("close_zone", _params, socket) do
    {:noreply, assign(socket, open_zone: nil)}
  end

  # ─── Drag & Drop ──────────────────────────────────────────────────────────

  def handle_event("drag_end", params, socket) do
    instance_id = params["instance_id"]
    from_zone = params["from_zone"]
    target_zone = params["target_zone"]
    x = params["x"] || 0.1
    y = params["y"] || 0.5
    owner = params["owner"] || socket.assigns.my_role
    selected_ids = params["selected_instance_ids"] || []

    # Only allow moving your own cards
    if owner != socket.assigns.my_role do
      {:noreply, socket}
    else
      insert_index = case params["insert_index"] do
        nil -> nil
        idx -> trunc(idx)
      end

      socket =
        case {from_zone, target_zone} do
          # Battlefield reposition (same zone)
          {"battlefield", "battlefield"} ->
            is_multi = length(selected_ids) > 1 and Enum.member?(selected_ids, instance_id)
            if is_multi do
              # Move all selected cards by the same delta as the dragged card
              apply_action_inline(socket, fn state, player ->
                bf_cards = get_in(state, [player, "zones", "battlefield"]) || []
                dragged = Enum.find(bf_cards, &(&1["instance_id"] == instance_id))
                dx = x - (dragged["x"] || 0.1)
                dy = y - (dragged["y"] || 0.5)
                Enum.reduce(selected_ids, {:ok, state}, fn sid, {:ok, st} ->
                  card = Enum.find(get_in(st, [player, "zones", "battlefield"]) || [], &(&1["instance_id"] == sid))
                  if card do
                    nx = max(0.0, min(0.98, (card["x"] || 0.1) + dx))
                    ny = max(0.0, min(0.98, (card["y"] || 0.5) + dy))
                    Actions.update_battlefield_position(st, player, sid, nx, ny)
                  else
                    {:ok, st}
                  end
                end)
                |> elem(1)
                |> then(&{:ok, &1})
              end)
            else
              apply_action_inline(socket, fn state, player ->
                Actions.update_battlefield_position(state, player, instance_id, x, y)
              end)
            end

          # Same list-zone reorder
          {zone, zone} when zone in ["hand", "deck", "graveyard", "exile"] ->
            apply_action_inline(socket, fn state, player ->
              Actions.reorder_in_zone(state, player, zone, instance_id, insert_index || 0)
            end)

          # Cross-zone moves — apply to all selected cards if multi
          {_, "battlefield"} ->
            all_ids = if length(selected_ids) > 1, do: selected_ids, else: [instance_id]
            apply_action_inline(socket, fn state, player ->
              Enum.reduce(all_ids, {:ok, state}, fn sid, {:ok, st} ->
                src = find_card_zone(st, player, sid) || from_zone
                Actions.move_to_battlefield(st, player, sid, src, x, y)
              end) |> elem(1) |> then(&{:ok, &1})
            end)

          {_, "graveyard"} ->
            all_ids = if length(selected_ids) > 1, do: selected_ids, else: [instance_id]
            apply_action_inline(socket, fn state, player ->
              Enum.reduce(all_ids, {:ok, state}, fn sid, {:ok, st} ->
                src = find_card_zone(st, player, sid) || from_zone
                Actions.move_to_graveyard(st, player, sid, src)
              end) |> elem(1) |> then(&{:ok, &1})
            end)

          {_, "exile"} ->
            all_ids = if length(selected_ids) > 1, do: selected_ids, else: [instance_id]
            apply_action_inline(socket, fn state, player ->
              Enum.reduce(all_ids, {:ok, state}, fn sid, {:ok, st} ->
                src = find_card_zone(st, player, sid) || from_zone
                Actions.move_to_exile(st, player, sid, src)
              end) |> elem(1) |> then(&{:ok, &1})
            end)

          {_, "hand"} ->
            all_ids = if length(selected_ids) > 1, do: selected_ids, else: [instance_id]
            apply_action_inline(socket, fn state, player ->
              Enum.reduce(Enum.with_index(all_ids), {:ok, state}, fn {sid, i}, {:ok, st} ->
                src = find_card_zone(st, player, sid) || from_zone
                idx = if is_integer(insert_index), do: insert_index + i, else: nil
                Actions.move_to_hand(st, player, sid, src, idx)
              end) |> elem(1) |> then(&{:ok, &1})
            end)

          {_, "deck"} ->
            all_ids = if length(selected_ids) > 1, do: selected_ids, else: [instance_id]
            apply_action_inline(socket, fn state, player ->
              Enum.reduce(Enum.with_index(all_ids), {:ok, state}, fn {sid, i}, {:ok, st} ->
                src = find_card_zone(st, player, sid) || from_zone
                idx = if is_integer(insert_index), do: insert_index + i, else: nil
                Actions.move_to_deck(st, player, sid, src, idx)
              end) |> elem(1) |> then(&{:ok, &1})
            end)

          _ ->
            socket
        end

      # Keep the zone popup open when reordering within the same zone,
      # close it when a card is moved out.
      open_zone =
        case socket.assigns.open_zone do
          {owner, zone, opts} when zone == target_zone and owner == socket.assigns.my_role -> {owner, zone, opts}
          _ -> nil
        end

      {:noreply, assign(socket, open_zone: open_zone)}
    end
  end

  def handle_event("update_card_position", %{"instance_id" => id, "x" => x, "y" => y}, socket) do
    apply_action(socket, fn state, player ->
      Actions.update_battlefield_position(state, player, id, x, y)
    end)
  end

  # ─── Scry ─────────────────────────────────────────────────────────────────

  def handle_event("begin_scry", %{"count" => count_str}, socket) do
    count = min(String.to_integer(to_string(count_str)), 20)
    state = socket.assigns.game_state
    player = socket.assigns.my_role

    {top_cards, new_state} = Actions.scry_reveal(state, player, count)

    {:noreply,
     assign(socket,
       game_state: new_state,
       context_menu: nil,
       scry_session: %{cards: top_cards, count: count, decisions: %{}}
     )}
  end

  def handle_event("scry_decision", %{"instance_id" => id, "dest" => dest}, socket) do
    scry = socket.assigns.scry_session
    new_decisions = Map.put(scry.decisions, id, dest)
    scry = %{scry | decisions: new_decisions}

    if map_size(new_decisions) == length(scry.cards) do
      # All decided, resolve
      state = socket.assigns.game_state
      player = socket.assigns.my_role
      new_state = Actions.scry_resolve(state, player, new_decisions, scry.cards)

      socket = persist_and_broadcast(socket, new_state)
      {:noreply, assign(socket, scry_session: nil)}
    else
      {:noreply, assign(socket, scry_session: scry)}
    end
  end

  def handle_event("cancel_scry", _params, socket) do
    # Put cards back on top of deck
    scry = socket.assigns.scry_session
    state = socket.assigns.game_state
    player = socket.assigns.my_role

    if scry do
      # Return all cards to deck top (in order)
      decisions = Map.new(scry.cards, &{&1["instance_id"], "top"})
      new_state = Actions.scry_resolve(state, player, decisions, scry.cards)
      socket = persist_and_broadcast(socket, new_state)
      {:noreply, assign(socket, scry_session: nil)}
    else
      {:noreply, socket}
    end
  end

  # ─── Token Search ─────────────────────────────────────────────────────────

  def handle_event("show_token_search", %{"x" => x, "y" => y}, socket) do
    {:noreply,
     assign(socket,
       token_search: true,
       token_query: "",
       token_results: [],
       token_only: true,
       token_place_x: x,
       token_place_y: y
     )}
  end

  def handle_event("token_search", params, socket) do
    query = params["query"] || ""
    token_only = params["token_only"] == "true"

    results =
      if String.length(query) >= 2 do
        if token_only do
          Catalog.search_tokens(query, 15)
        else
          Catalog.search_cards(query, 15)
        end
      else
        []
      end

    {:noreply, assign(socket, token_query: query, token_only: token_only, token_results: results)}
  end

  def handle_event("create_token", %{"card_id" => card_id}, socket) do
    card = Catalog.get_card!(card_id)
    x = socket.assigns.token_place_x
    y = socket.assigns.token_place_y

    socket =
      apply_action_inline(socket, fn state, player ->
        Actions.create_token(state, player, card, x, y)
      end)

    {:noreply, assign(socket, token_search: nil, token_query: "", token_results: [])}
  end

  def handle_event("close_token_search", _params, socket) do
    {:noreply, assign(socket, token_search: nil)}
  end

  # ─── Find Card ────────────────────────────────────────────────────────────

  def handle_event("find_card_search", %{"query" => query}, socket) do
    case socket.assigns.open_zone do
      {owner, zone, opts} ->
        {:noreply, assign(socket, open_zone: {owner, zone, %{opts | query: query}})}
      _ ->
        {:noreply, socket}
    end
  end

  # ─── End Game ─────────────────────────────────────────────────────────────

  def handle_event("show_end_game", _params, socket) do
    {:noreply, assign(socket, end_game_modal: true)}
  end

  def handle_event("cancel_end_game", _params, socket) do
    {:noreply, assign(socket, end_game_modal: false)}
  end

  def handle_event("confirm_end_game", _params, socket) do
    game = socket.assigns.game
    Games.broadcast_game_ended(game.id)
    Games.end_game(game)

    {:noreply,
     socket
     |> put_flash(:info, "Game ended.")
     |> push_navigate(to: ~p"/games")}
  end

  # ─── Private Helpers ─────────────────────────────────────────────────────

  defp apply_action(socket, action_fn) do
    state = socket.assigns.game_state
    player = socket.assigns.my_role
    socket = assign(socket, context_menu: nil)

    case action_fn.(state, player) do
      {:ok, new_state} ->
        socket = persist_and_broadcast(socket, new_state)
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  defp apply_action_inline(socket, action_fn) do
    state = socket.assigns.game_state
    player = socket.assigns.my_role

    case action_fn.(state, player) do
      {:ok, new_state} ->
        persist_and_broadcast(socket, new_state)

      {:error, _reason} ->
        socket
    end
  end


  # Find which zone a card currently lives in (searches all zones for the player)
  defp find_card_zone(state, player, instance_id) do
    zones = ["hand", "battlefield", "graveyard", "exile", "deck"]
    Enum.find_value(zones, fn zone ->
      cards = get_in(state, [player, "zones", zone]) || []
      if Enum.any?(cards, &(&1["instance_id"] == instance_id)), do: zone
    end)
  end

  defp apply_to_selection(socket, action_fn) do
    ids = MapSet.to_list(socket.assigns.selected_cards)
    socket = assign(socket, context_menu: nil)
    state = socket.assigns.game_state
    player = socket.assigns.my_role

    new_state =
      Enum.reduce(ids, state, fn id, st ->
        case action_fn.(st, player, id) do
          {:ok, updated} -> updated
          {:error, _} -> st
        end
      end)

    socket = persist_and_broadcast(socket, new_state)
    {:noreply, socket}
  end

  defp persist_and_broadcast(socket, new_state) do
    game = socket.assigns.game
    {:ok, _} = Games.update_game_state(game, new_state)
    Games.broadcast_game_state(game.id, new_state)
    assign(socket, game_state: new_state)
  end

  # ─── Template Helpers ─────────────────────────────────────────────────────

  defp my_state(game_state, my_role), do: game_state[my_role] || %{}
  defp opp_state(game_state, opp_role), do: game_state[opp_role] || %{}

  defp zone_cards(player_state, zone) do
    get_in(player_state, ["zones", zone]) || []
  end

  defp card_display_url(card, viewer_role, owner_role, zone) do
    State.card_display_url(card, viewer_role, owner_role, zone)
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:my, my_state(assigns.game_state, assigns.my_role))
      |> assign(:opp, opp_state(assigns.game_state, assigns.opp_role))

    ~H"""
    <div
      id="game-container"
      class="game-layout h-full flex flex-col overflow-hidden bg-gray-950 select-none"
      phx-hook="DragDrop"
      data-my-role={@my_role}
    >
      <%!-- Opponent Info Bar --%>
      <div class="flex items-center gap-4 px-4 py-2 bg-gray-900 border-b border-gray-700 shrink-0">
        <span class="font-bold text-sm">{@opp["username"] || "Opponent"}</span>
        <div class="flex items-center gap-1 text-sm">
          <span class="text-red-400">♥</span>
          <span class="font-mono font-bold">{@opp["life"] || 20}</span>
        </div>
        <%= for {tracker, idx} <- Enum.with_index(@opp["trackers"] || []) do %>
          <div class="flex items-center gap-1 text-xs bg-gray-700 rounded px-2 py-1">
            <span>{tracker["name"]}</span>
            <span class="font-mono font-bold">{tracker["value"]}</span>
          </div>
        <% end %>
        <div class="ml-auto flex items-center gap-2 text-xs text-gray-400">
          <span>Hand: {length(zone_cards(@opp, "hand"))}</span>
          <button
            phx-click="open_zone"
            phx-value-zone="deck"
            phx-value-owner={@opp_role}
            class="hover:text-white"
          >
            Deck: {length(zone_cards(@opp, "deck"))}
          </button>
          <button
            phx-click="open_zone"
            phx-value-zone="graveyard"
            phx-value-owner={@opp_role}
            class="hover:text-white"
          >
            GY: {length(zone_cards(@opp, "graveyard"))}
          </button>
          <button
            phx-click="open_zone"
            phx-value-zone="exile"
            phx-value-owner={@opp_role}
            class="hover:text-white"
          >
            EX: {length(zone_cards(@opp, "exile"))}
          </button>
        </div>
      </div>

      <%!-- Battlefields — flex-1 shared area, split equally --%>
      <div class="flex-1 flex flex-col min-h-0">
        <%!-- Opponent Battlefield (rotated 180° so their near edge faces them) --%>
        <div
          id="opp-battlefield"
          class="flex-1 relative bg-gray-900 border-b border-gray-700 overflow-hidden"
          data-drop-zone="opp-battlefield"
          style="transform: rotate(180deg);"
        >
          <%= for card <- zone_cards(@opp, "battlefield") do %>
            <div
              class={["card-on-battlefield absolute cursor-pointer", if(card["tapped"], do: "is-tapped", else: "")]}
              style={"left: #{trunc((card["x"] || 0.1) * 100)}%; top: #{trunc((card["y"] || 0.1) * 100)}%;"}
            >
              <%!-- counter-rotate so cards appear right-side-up inside the 180° flipped field --%>
              <div
                style="transform: rotate(180deg); transform-origin: center;"
                data-card-img={card_display_url(card, @my_role, @opp_role, "battlefield")}
              >
                <div class="flex flex-col items-center">
                  <img
                    src={card_display_url(card, @my_role, @opp_role, "battlefield")}
                    class="card-image rounded shadow-lg"
                    draggable="false"
                  />
                  <%= if (card["counters"] || []) != [] do %>
                    <div class="flex flex-col gap-0.5 mt-0.5 items-center">
                      <%= for counter <- card["counters"] || [] do %>
                        <div class="bg-gray-600/90 text-white rounded px-1.5 py-0.5 flex flex-col items-center leading-tight w-full">
                          <span class="font-mono text-sm font-bold">{counter["value"]}</span>
                          <span class="text-xs text-gray-300 text-center">{counter["name"]}</span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- My Battlefield --%>
        <div
          id="my-battlefield"
          class="flex-1 relative bg-gray-850 overflow-hidden"
          data-drop-zone="battlefield"
          phx-hook="Battlefield"
        >
          <%= for card <- zone_cards(@my, "battlefield") do %>
            <div
              id={"card-#{card["instance_id"]}"}
              class={[
                "card-on-battlefield absolute cursor-pointer transition-transform",
                if(card["tapped"], do: "is-tapped", else: ""),
                if(MapSet.member?(@selected_cards, card["instance_id"]), do: "is-selected", else: ""),
              ]}
              style={"left: #{trunc((card["x"] || 0.1) * 100)}%; top: #{trunc((card["y"] || 0.1) * 100)}%;"}
              data-draggable="true"
              data-instance-id={card["instance_id"]}
              data-zone="battlefield"
              data-owner={@my_role}
              data-card-img={card_display_url(card, @my_role, @my_role, "battlefield")}
              data-selected={if MapSet.member?(@selected_cards, card["instance_id"]), do: "true", else: "false"}
              data-is-token={if card["is_token"], do: "true", else: "false"}
            >
              <div class="flex flex-col items-center">
                <%!-- Card image with hover highlight --%>
                <div class="card-draggable">
                  <img
                    src={card_display_url(card, @my_role, @my_role, "battlefield")}
                    class="card-image rounded shadow-lg"
                    draggable="false"
                  />
                </div>

                <%!-- Counters display — vertical stack below card, centered --%>
                <div :if={(card["counters"] || []) != []} class="flex flex-col gap-0.5 mt-0.5 items-center" data-no-hotkey>
                  <%= for {counter, cidx} <- Enum.with_index(card["counters"] || []) do %>
                    <div class="relative group/counter">
                      <div class="bg-gray-600/90 text-white rounded px-1.5 py-0.5 flex flex-col items-center leading-tight">
                        <div class="flex items-center gap-1 justify-center">
                          <button
                            phx-click="adjust_counter"
                            phx-value-instance_id={card["instance_id"]}
                            phx-value-counter_index={cidx}
                            phx-value-delta="-1"
                            class="text-xs hover:text-red-300 shrink-0"
                          >-</button>
                          <span class="font-mono text-sm font-bold">{counter["value"]}</span>
                          <button
                            phx-click="adjust_counter"
                            phx-value-instance_id={card["instance_id"]}
                            phx-value-counter_index={cidx}
                            phx-value-delta="1"
                            class="text-xs hover:text-green-300 shrink-0"
                          >+</button>
                        </div>
                        <span class="text-xs text-gray-300 text-center">{counter["name"]}</span>
                      </div>
                      <button
                        phx-click="remove_counter"
                        phx-value-instance_id={card["instance_id"]}
                        phx-value-counter_index={cidx}
                        class="absolute -right-4 top-1/2 -translate-y-1/2 hidden group-hover/counter:flex items-center justify-center bg-black text-white text-xs rounded-r w-4 h-full hover:text-red-400"
                      >×</button>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Zone Piles (sideways / landscape orientation to distinguish from battlefield cards) --%>
          <%!-- Graveyard pile: bottom-left (sideways / landscape) --%>
          <div
            id="pile-graveyard"
            class="zone-pile absolute rounded shadow-lg overflow-hidden"
            style="width: 78px; height: 56px; bottom: 8px; left: 8px; z-index: 20;"
            data-drop-zone="graveyard"
            data-pile-zone="graveyard"
            phx-click="open_zone"
            phx-value-zone="graveyard"
            phx-value-owner={@my_role}
          >
            <%= if zone_cards(@my, "graveyard") != [] do %>
              <%!-- Persistent background card image (always visible, even during drag) --%>
              <img
                src={card_display_url(hd(zone_cards(@my, "graveyard")), @my_role, @my_role, "graveyard")}
                class="rounded pointer-events-none"
                style="position: absolute; top: 50%; left: 50%; width: 56px; height: 78px; object-fit: cover; transform: translate(-50%, -50%) rotate(90deg);"
                draggable="false"
              />
              <%!-- Transparent draggable overlay for the top card --%>
              <div
                id={"graveyard-top-#{hd(zone_cards(@my, "graveyard"))["instance_id"]}"}
                class="absolute inset-0 cursor-pointer"
                data-draggable="true"
                data-instance-id={hd(zone_cards(@my, "graveyard"))["instance_id"]}
                data-zone="graveyard"
                data-owner={@my_role}
                data-card-img={card_display_url(hd(zone_cards(@my, "graveyard")), @my_role, @my_role, "graveyard")}
              ></div>
            <% else %>
              <div class="w-full h-full bg-gray-800 border border-gray-600 rounded flex flex-col items-center justify-center gap-0.5 cursor-pointer">
                <span class="text-gray-400 text-xs font-semibold">GY</span>
              </div>
            <% end %>
            <div class="absolute bottom-0 right-0 bg-black/70 text-white text-xs px-1 rounded-tl leading-4 pointer-events-none">
              {length(zone_cards(@my, "graveyard"))}
            </div>
          </div>

          <%!-- Exile pile: above graveyard on left (sideways / landscape) --%>
          <div
            id="pile-exile"
            class="zone-pile absolute rounded shadow-lg overflow-hidden"
            style="width: 78px; height: 56px; bottom: 72px; left: 8px; z-index: 20;"
            data-drop-zone="exile"
            data-pile-zone="exile"
            phx-click="open_zone"
            phx-value-zone="exile"
            phx-value-owner={@my_role}
          >
            <%= if zone_cards(@my, "exile") != [] do %>
              <%!-- Persistent background card image (always visible, even during drag) --%>
              <img
                src={card_display_url(hd(zone_cards(@my, "exile")), @my_role, @my_role, "exile")}
                class="rounded pointer-events-none"
                style="position: absolute; top: 50%; left: 50%; width: 56px; height: 78px; object-fit: cover; transform: translate(-50%, -50%) rotate(90deg);"
                draggable="false"
              />
              <%!-- Transparent draggable overlay for the top card --%>
              <div
                id={"exile-top-#{hd(zone_cards(@my, "exile"))["instance_id"]}"}
                class="absolute inset-0 cursor-pointer"
                data-draggable="true"
                data-instance-id={hd(zone_cards(@my, "exile"))["instance_id"]}
                data-zone="exile"
                data-owner={@my_role}
                data-card-img={card_display_url(hd(zone_cards(@my, "exile")), @my_role, @my_role, "exile")}
              ></div>
            <% else %>
              <div class="w-full h-full bg-gray-800 border border-gray-600 rounded flex flex-col items-center justify-center gap-0.5 cursor-pointer">
                <span class="text-gray-400 text-xs font-semibold">EX</span>
              </div>
            <% end %>
            <div class="absolute bottom-0 right-0 bg-black/70 text-white text-xs px-1 rounded-tl leading-4 pointer-events-none">
              {length(zone_cards(@my, "exile"))}
            </div>
          </div>

          <%!-- Deck pile: bottom-right (upright, top card draggable) --%>
          <div
            id="pile-deck"
            class="zone-pile absolute rounded shadow-lg overflow-hidden"
            style="width: 56px; height: 78px; bottom: 8px; right: 8px; z-index: 20;"
            data-drop-zone="deck"
            data-pile-zone="deck"
            data-no-preview
            phx-click="open_zone"
            phx-value-zone="deck"
            phx-value-owner={@my_role}
          >
            <%= if zone_cards(@my, "deck") != [] do %>
              <%!-- Persistent background image (always visible, even during drag) --%>
              <img
                src={card_display_url(hd(zone_cards(@my, "deck")), @my_role, @my_role, "deck")}
                class="absolute inset-0 w-full h-full object-cover rounded pointer-events-none"
                draggable="false"
              />
              <%!-- Transparent draggable overlay for the top card --%>
              <div
                id={"deck-top-#{hd(zone_cards(@my, "deck"))["instance_id"]}"}
                class="absolute inset-0 cursor-pointer"
                data-draggable="true"
                data-instance-id={hd(zone_cards(@my, "deck"))["instance_id"]}
                data-zone="deck"
                data-owner={@my_role}
                data-card-img={card_display_url(hd(zone_cards(@my, "deck")), @my_role, @my_role, "deck")}
              ></div>
              <div class="absolute bottom-0 right-0 bg-black/70 text-white text-xs px-1 rounded-tl leading-4 pointer-events-none" style="z-index: 1;">
                {length(zone_cards(@my, "deck"))}
              </div>
            <% else %>
              <div class="w-full h-full bg-gray-800 border border-gray-600 rounded flex flex-col items-center justify-center gap-0.5">
                <span class="text-gray-400 text-xs font-semibold">DECK</span>
              </div>
            <% end %>
          </div>

          <%!-- Right-click context placeholder (handled via JS) --%>
          <div
            :if={@context_menu}
            id="context-menu"
            class="fixed z-50 bg-gray-800 border border-gray-600 rounded-lg shadow-xl py-1 min-w-40"
            style={"left: #{@context_menu.x}px; top: #{@context_menu.y}px;"}
          >
            <%= for action <- @context_menu.actions do %>
              <%= if action == :scry do %>
                <%!-- Scry row: label + count adjuster + confirm --%>
                <div class="flex items-center px-4 py-2 text-sm gap-2">
                  <span class="flex-1">Scry</span>
                  <button
                    phx-click="adjust_scry_count"
                    phx-value-delta="-1"
                    class="text-gray-400 hover:text-white w-5 text-center"
                  >−</button>
                  <span class="font-mono w-4 text-center">{@context_menu.scry_count}</span>
                  <button
                    phx-click="adjust_scry_count"
                    phx-value-delta="1"
                    class="text-gray-400 hover:text-white w-5 text-center"
                  >+</button>
                  <button
                    phx-click="begin_scry"
                    phx-value-count={@context_menu.scry_count}
                    class="btn btn-xs btn-outline ml-1"
                  >Go</button>
                </div>
              <% else %>
                <button
                  class="w-full text-left px-4 py-2 text-sm hover:bg-gray-700 flex items-center justify-between"
                  phx-click="action"
                  phx-value-type={action}
                  phx-value-instance_id={@context_menu.instance_id}
                  phx-value-zone={@context_menu.zone}
                >
                  <span>{Hotkeys.action_label(action)}</span>
                  <span :if={Hotkeys.key_for(action)} class="text-xs text-gray-400 ml-4">
                    {Hotkeys.display_for(action)}
                  </span>
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- My Info Bar --%>
      <div class="flex items-center gap-4 px-4 py-2 bg-gray-900 border-t border-gray-700 shrink-0">
          <%!-- Life Total --%>
          <div class="flex items-center gap-1">
            <span class="text-red-400 font-bold">♥</span>
            <button
              phx-click="adjust_life"
              phx-value-delta="-1"
              class="btn btn-xs btn-ghost text-red-400"
            >-</button>
            <span class="font-mono font-bold text-lg w-8 text-center">{@my["life"] || 20}</span>
            <button
              phx-click="adjust_life"
              phx-value-delta="1"
              class="btn btn-xs btn-ghost text-green-400"
            >+</button>
          </div>

          <%!-- Trackers --%>
          <%= for {tracker, idx} <- Enum.with_index(@my["trackers"] || []) do %>
            <div class="relative group/tracker">
              <div class="flex items-center gap-1 text-xs bg-gray-700 rounded px-2 py-1">
                <span>{tracker["name"]}</span>
                <button
                  phx-click="adjust_tracker"
                  phx-value-index={idx}
                  phx-value-delta="-1"
                  class="hover:text-red-400"
                >-</button>
                <span class="font-mono font-bold">{tracker["value"]}</span>
                <button
                  phx-click="adjust_tracker"
                  phx-value-index={idx}
                  phx-value-delta="1"
                  class="hover:text-green-400"
                >+</button>
              </div>
              <button
                phx-click="remove_tracker"
                phx-value-index={idx}
                class="absolute -right-4 top-0 hidden group-hover/tracker:flex items-center justify-center bg-black text-white text-xs rounded-r w-4 h-full hover:text-red-400"
              >×</button>
            </div>
          <% end %>

          <form phx-submit="add_tracker" class="flex gap-1">
            <input
              type="text"
              name="name"
              placeholder="+ Tracker"
              class="input input-xs bg-gray-700 w-24 placeholder-gray-500"
            />
          </form>

          <div class="ml-auto flex items-center gap-2 text-xs text-gray-400">
            <span>Hand: {length(zone_cards(@my, "hand"))}</span>
            <button phx-click="show_end_game" class="text-red-400 hover:text-red-300">
              End Game
            </button>
          </div>
        </div>

        <%!-- Hand --%>
        <div
          id="my-hand"
          data-drop-zone="hand"
          class="flex items-center bg-gray-900 border-t border-gray-700 overflow-x-auto shrink-0"
          style="height: 120px;"
        >
          <div class="flex items-center gap-1 px-4 py-2 min-w-max mx-auto">
            <%= for card <- zone_cards(@my, "hand") do %>
              <div
                id={"hand-card-#{card["instance_id"]}"}
                class={[
                  "shrink-0 cursor-pointer hover:scale-110 transition-transform relative",
                  ]}
                data-draggable="true"
                data-instance-id={card["instance_id"]}
                data-zone="hand"
                data-owner={@my_role}
                data-card-img={card_display_url(card, @my_role, @my_role, "hand")}
                data-is-token={if card["is_token"], do: "true", else: "false"}
              >
                <img
                  src={card_display_url(card, @my_role, @my_role, "hand")}
                  class="h-24 w-auto rounded shadow"
                  draggable="false"
                />
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Zone Popup (inline, below hand) --%>
        <div
          :if={@open_zone}
          class="bg-gray-900 border-t border-gray-600 shrink-0"
          style="height: 180px;"
        >
          <% {zone_owner, zone_name, zone_opts} = @open_zone %>
          <% zone_player = if zone_owner == @my_role, do: @my, else: @opp %>
          <% is_find = Map.get(zone_opts, :find, false) %>
          <div class="flex items-center justify-between px-4 py-1 border-b border-gray-700">
            <div class="flex items-center gap-3">
              <span class="font-semibold text-sm">
                {if is_find, do: "Find Card", else: String.capitalize(zone_name)} ({length(zone_cards(zone_player, zone_name))} cards)
              </span>
              <form :if={is_find} phx-change="find_card_search">
                <input
                  type="text"
                  name="query"
                  value={Map.get(zone_opts, :query, "")}
                  phx-debounce="100"
                  placeholder="Filter by name..."
                  class="input input-xs bg-gray-700 w-40 placeholder-gray-500"
                  autofocus
                />
              </form>
            </div>
            <button phx-click="close_zone" class="text-gray-400 hover:text-white text-xl leading-none">×</button>
          </div>
          <div
            class="flex overflow-x-auto"
            style="height: 148px;"
            data-drop-zone={zone_name}
            {if zone_name == "deck" and not is_find, do: [{"data-no-preview", ""}], else: []}
          >
            <div class="flex items-center gap-2 px-4 py-2 min-w-max mx-auto">
              <%
                cards = zone_cards(zone_player, zone_name)
                cards = if is_find do
                  query = String.downcase(Map.get(zone_opts, :query, ""))
                  cards
                  |> Enum.sort_by(& &1["name"])
                  |> Enum.filter(fn c -> query == "" or String.contains?(String.downcase(c["name"]), query) end)
                else
                  cards
                end
              %>
              <%= for card <- cards do %>
                <% display_card = if is_find, do: Map.put(card, "known", true), else: card %>
                <div
                  class="shrink-0 cursor-pointer hover:scale-105 transition-transform"
                  data-draggable="true"
                  data-instance-id={card["instance_id"]}
                  data-zone={zone_name}
                  data-owner={zone_owner}
                  data-card-img={card_display_url(display_card, @my_role, zone_owner, zone_name)}
                >
                  <img
                    src={card_display_url(display_card, @my_role, zone_owner, zone_name)}
                    class="h-32 w-auto rounded shadow"
                    draggable="false"
                  />
                </div>
              <% end %>
            </div>
          </div>
        </div>

      <%!-- Card Preview Panel (shown on hover via JS, hidden during drag) --%>
      <div
        id="card-preview-panel"
        class="fixed top-1/2 -translate-y-1/2 z-[9999] pointer-events-none"
        style="display: none; right: 12px;"
      >
        <img
          id="card-preview-img"
          src=""
          class="rounded-lg shadow-2xl"
          style="height: 420px; width: auto;"
          draggable="false"
        />
      </div>

      <%!-- Scry Modal --%>
      <div
        :if={@scry_session}
        class="fixed inset-0 bg-black/80 flex items-center justify-center z-50"
      >
        <div class="bg-gray-800 rounded-xl p-6 max-w-4xl w-full mx-4">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-xl font-bold">
              Scrying {length(@scry_session.cards)} card(s)
            </h2>
            <button phx-click="cancel_scry" class="text-gray-400 hover:text-white">Cancel</button>
          </div>

          <div class="flex gap-3 overflow-x-auto pb-2">
            <%= for card <- @scry_session.cards do %>
              <div class="shrink-0 text-center">
                <img
                  src={card_display_url(Map.put(card, "known", true), @my_role, @my_role, "deck")}
                  class="h-40 w-auto rounded shadow mx-auto mb-2"
                />
                <div class="text-xs text-gray-300 mb-2 max-w-24 truncate">{card["name"]}</div>
                <div :if={!Map.has_key?(@scry_session.decisions, card["instance_id"])} class="flex flex-col gap-1">
                  <button
                    phx-click="scry_decision"
                    phx-value-instance_id={card["instance_id"]}
                    phx-value-dest="top"
                    class="btn btn-xs btn-outline"
                  >
                    Top
                  </button>
                  <button
                    phx-click="scry_decision"
                    phx-value-instance_id={card["instance_id"]}
                    phx-value-dest="bottom"
                    class="btn btn-xs btn-ghost"
                  >
                    Bottom
                  </button>
                  <button
                    phx-click="scry_decision"
                    phx-value-instance_id={card["instance_id"]}
                    phx-value-dest="graveyard"
                    class="btn btn-xs btn-ghost text-red-400"
                  >
                    Grave
                  </button>
                  <button
                    phx-click="scry_decision"
                    phx-value-instance_id={card["instance_id"]}
                    phx-value-dest="exile"
                    class="btn btn-xs btn-ghost text-yellow-400"
                  >
                    Exile
                  </button>
                </div>
                <div :if={Map.has_key?(@scry_session.decisions, card["instance_id"])} class="text-xs text-green-400 capitalize">
                  → {Map.get(@scry_session.decisions, card["instance_id"])}
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Token Search Modal --%>
      <div
        :if={@token_search}
        class="fixed inset-0 bg-black/80 flex items-center justify-center z-50"
      >
        <div class="bg-gray-800 rounded-xl p-6 w-full max-w-lg mx-4">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-xl font-bold">Create Token / Spawn Card</h2>
            <button phx-click="close_token_search" class="text-gray-400 hover:text-white">×</button>
          </div>

          <form phx-change="token_search" phx-submit="token_search">
            <input
              type="text"
              name="query"
              value={@token_query}
              phx-debounce="200"
              placeholder="Search cards or tokens..."
              class="input input-bordered w-full bg-gray-700 mb-2"
              autofocus
            />
            <label class="flex items-center gap-2 text-sm text-gray-300 mb-3 cursor-pointer select-none">
              <input
                type="checkbox"
                name="token_only"
                value="true"
                checked={@token_only}
                class="checkbox checkbox-sm"
              />
              Tokens only
            </label>
          </form>

          <div class="flex flex-wrap gap-3 max-h-72 overflow-y-auto py-1">
            <%= for card <- @token_results do %>
              <%
                img_url =
                  get_in(card.data, ["image_uris", "normal"]) ||
                  get_in(card.data, ["card_faces", Access.at(0), "image_uris", "normal"])
              %>
              <button
                phx-click="create_token"
                phx-value-card_id={card.id}
                class="flex flex-col items-center gap-1 rounded hover:ring-2 hover:ring-purple-400 transition-all"
                title={card.name}
                data-card-img={img_url || "/images/CardBack.png"}
              >
                <img
                  src={img_url || "/images/CardBack.png"}
                  class="h-28 w-auto rounded shadow"
                  draggable="false"
                />
                <span class="text-xs text-gray-300 max-w-16 truncate">{card.name}</span>
              </button>
            <% end %>

            <div :if={@token_query != "" && @token_results == []} class="text-gray-400 text-sm py-2 text-center w-full">
              No cards found
            </div>
          </div>
        </div>
      </div>

      <%!-- Add Counter Modal --%>
      <div
        :if={@adding_counter_to}
        class="fixed inset-0 bg-black/70 flex items-center justify-center z-50"
      >
        <div class="bg-gray-800 rounded-xl p-6 w-80 mx-4">
          <h2 class="text-lg font-bold mb-4">Add Counter</h2>
          <form phx-submit="add_counter">
            <input
              type="text"
              name="name"
              value="+1/+1"
              class="input input-bordered w-full bg-gray-700 mb-3"
              autofocus
            />
            <div class="flex gap-2 justify-end">
              <button type="button" phx-click="cancel_add_counter" class="btn btn-ghost btn-sm">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary btn-sm">Add</button>
            </div>
          </form>
        </div>
      </div>

      <%!-- End Game Modal --%>
      <div
        :if={@end_game_modal}
        class="fixed inset-0 bg-black/80 flex items-center justify-center z-50"
      >
        <div class="bg-gray-800 rounded-xl p-6 w-80 mx-4 text-center">
          <h2 class="text-xl font-bold mb-2">End Game?</h2>
          <p class="text-gray-400 text-sm mb-6">
            The game will not be saved. Both players will be redirected to the home screen.
          </p>
          <div class="flex gap-3 justify-center">
            <button phx-click="cancel_end_game" class="btn btn-ghost">Cancel</button>
            <button phx-click="confirm_end_game" class="btn btn-error">End Game</button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
