# GoodTap Implementation Plan

Status key: [ ] pending, [x] done, [~] in progress

---

## 0. Prerequisite Refactors

These need to happen first because multiple todos depend on them.

### 0a. Multiple printings support (new `card_printings` table + Scryfall unique-artwork import)
- [ ] Add migration: `card_printings` table with `(id, card_name, set_code, collector_number, image_uris jsonb, data jsonb)`
  - `card_name` references the oracle name (no FK — same reason as deck_cards)
  - index on `card_name`
- [ ] Add `CardPrinting` Ecto schema
- [ ] Add seed/update function that downloads `unique-artwork` bulk data from Scryfall and upserts into `card_printings`
  - Hook into `update_cards` / `force_reset` so both tables are always refreshed together
- [ ] Add `Catalog.get_printings_for_card(card_name)` query
- [ ] Add `Catalog.get_printing(id)` query
- [ ] Update `DeckCard` to optionally store `printing_id` (nullable string, no FK)
- [ ] Migration to add `printing_id` to `deck_cards`

### 0b. Shared `CardSearch` LiveComponent
Extract the token-search modal into a reusable `CardSearch` LiveComponent used in both:
- The game board (token/card spawning — current token_search modal)
- The deck editor (add card to deck)

Component API:
```
<.live_component module={GoodtapWeb.CardSearchComponent}
  id="card-search"
  token_only={false}
  on_select="card_selected"  # event sent to parent
/>
```
Internally handles:
- Text search input with debounce
- Token-only toggle (shown only when `token_only` prop is false)
- Results grid with card image previews
- Printing selector dropdown per card (populated from `card_printings`)
- "Showing X of Y" footer
- 20 results per page

### 0c. `is_token` fix for double-faced tokens
- [ ] Update seeds to set `is_token: true` when `layout in ["token", "double_faced_token"]`
- [ ] Update `Card.is_token` migration default logic (backfill query)
- [ ] Update `search_tokens` in Catalog to include `double_faced_token` layout

---

## 1. Deck Importer Improvements

### 1a. Support printings in import
- [ ] Update `Plaintext` importer to parse `(SET) collector_number` from lines like `4 Brainstorm (DSC) 113`
  - Return `%{name: name, quantity: qty, board: board, set_code: set_code, collector_number: collector_number}`
- [ ] Update `insert_deck_cards` to resolve printing: look up `card_printings` by `(set_code, collector_number)`, store `printing_id` on the `DeckCard`
- [ ] Still use front-face name logic (strip `//`) when resolving the oracle card

### 1b. Deck editor UI (replace read-only detail panel)
The deck detail panel becomes a full editor. Layout:

**Header**: deck name (editable inline), close button, view toggle (List | Previews)

**List view** (default):
- Cards grouped by board (Commander / Main / Sideboard), sorted alphabetically
- Each row: `[qty] [card name]` with:
  - Click qty → inline editable input (no popup, just turns into `<input>` in place)
  - `×` button on right to remove card
  - Right-click → context menu with "Move to Main" / "Move to Sideboard" / "Set as Commander"
- "Add card" button at bottom of each section → opens `CardSearch` component inline

**Preview view**:
- Cards shown as images in a grid
- Each card has a printing dropdown overlay
- Clicking a card image shows the full card preview

### 1c–1e. Card search improvements (in CardSearch component)
- [ ] Show 20 results (not 15)
- [ ] "Showing X of Y" footer
- [ ] Printing selector dropdown per result card
- [ ] Preview updates to show selected printing image

---

## 2. Commander Support

- [ ] Migration: add `commander_card_name` (string, nullable) and `commander_printing_id` (string, nullable) to `decks` table
- [ ] Update `Deck` schema
- [ ] Deck editor: right-click on a card → "Set as Commander" option
  - Calls `Decks.set_commander(deck, card_name, printing_id)`
  - Commander section shown at top of deck detail if set
  - Setting new commander replaces old; removing is done via an × on the commander row
- [ ] Game init: if deck has a commander, place it on the battlefield at load time (not in deck)
  - Update `State.build_player_state/2` — pull commander out, call `build_card_instance`, add to `battlefield` zone at a fixed starting position

---

## 3. Post-game Sideboarding

- [ ] New game status: `"sideboarding"` (between games in a series)
- [ ] "End Game" modal gains two options: "End Series" (delete) and "Sideboard & Play Again"
- [ ] "Sideboard & Play Again" flow:
  - Opens a new `SideboardLive` modal/overlay (or inline in game_live)
  - Shows main deck and sideboard side by side as card lists with quantities
  - Cards can be moved between main/side with +/- buttons (partial moves allowed)
  - Submit button — once both players submit, triggers next game start
  - Uses PubSub to coordinate: when both players submit, server calls `Games.start_next_game/2`
- [ ] `Games.start_next_game/2` — rebuild game state from updated deck compositions, reset zones, keep same game record

---

## 4. Die Roll on First Load

- [ ] On game start (when `game_live` first mounts and game is freshly `active`), each player automatically rolls 2d6
- [ ] Roll stored in game_state: `game_state["rolls"]["host"]` / `game_state["rolls"]["opponent"]`
- [ ] Once both rolls are in, show a modal: "You rolled X, opponent rolled Y. [Winner] goes first!"
- [ ] Log the rolls
- [ ] Modal has a "Close" button; game proceeds normally

Implementation:
- `Actions.roll_dice(state, player)` — generates two random 1–6 values, stores sum in state
- On mount in `game_live`, if no roll exists for my player yet, immediately dispatch `roll_dice` action
- Watch for both rolls in `handle_info({:game_state_updated, ...})` to show/hide modal

---

## 5. Opponent Zones Visible

- [ ] Opponent info bar shows clickable zone piles (graveyard, exile) — same UI as player's side but rotated/positioned at top
- [ ] Clicking opponent's graveyard/exile opens zone popup (read-only — no drag, no actions for now unless todo 6c is implemented)
- [ ] Opponent hand shows face-down cards (backs only, count matches actual hand size)
- [ ] The word labels become clickable zone pile buttons matching the player's side

---

## 6. Battlefield Drop Glitches

### 6a. Card disappears on invalid drop
- [ ] In `drag_drop.js`: on `dragend` / mouse-up with no valid drop target, animate card back to origin
- [ ] Track `dragOrigin` (zone + index) on drag start; restore if drop is invalid

### 6b. Drop on opponent battlefield
- [ ] Allow cards to be dropped onto opponent's battlefield half
- [ ] In `drag_drop.js`: treat opponent battlefield as a valid drop zone
- [ ] In `handle_event("drop", ...)`: detect if target zone owner != my_role, call `move_to_battlefield` with opponent's player key

### 6c. Copy opponent cards
- [ ] Add `allow_opponent_action: [:copy_card]` logic
- [ ] Right-click on opponent battlefield card → shows "Copy" option only
- [ ] `copy_card` action already works; just need to wire up opponent card context menu

---

## 7. Fast-click increment bug

- [ ] In the life/tracker +/- buttons, the issue is LiveView batching rapid clicks
- [ ] Fix: use `phx-click` with `phx-debounce="0"` to force immediate processing, or switch to a client-side counter that sends a single delta on blur/settle
- [ ] Alternative: accumulate clicks in JS and send a single `adjust_life` with the total delta after a short idle timeout (cleaner)

---

## 8. Game limit + delete on game list

- [ ] `game_list_live`: count user's active games; if >= 10, grey out "New Game" button with hover tooltip
- [ ] Add `×` button on each game row → shows confirmation modal → calls `Games.end_game/1`
- [ ] Update `Games` context: `count_active_games_for_user(user_id)` helper

---

## 9. Live game join page

- [ ] `game_join_live` (or `game_setup_live`) subscribes to `"game:#{game.id}"` PubSub
- [ ] Host's page updates in real-time when opponent opens the invite link (opponent joins → `broadcast_game_update` → host sees opponent name appear without refresh)
- [ ] Already using PubSub for game state — just need to subscribe and handle `{:game_updated, game}` in setup live

---

## Implementation Order

1. **0c** — is_token fix (quick, unblocks token search)
2. **0a** — card_printings table + seed (needed by 1a, 1e, 2)
3. **0b** — CardSearch component (needed by 1b, 1d)
4. **1a** — printing-aware import parser
5. **1b + 1c-e** — deck editor UI with CardSearch
6. **9** — live join page (quick PubSub wire-up)
7. **7** — fast-click fix (quick)
8. **8** — game limit + delete
9. **2** — commander support
10. **4** — die roll
11. **5** — opponent zones
12. **6** — battlefield drop fixes
13. **3** — sideboarding (most complex, depends on 2)
