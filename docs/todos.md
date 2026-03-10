# Multiplayer Implementation Plan

## Overview

Add multiplayer support (2–6 players). The host sets a max player count. Players join via invite link. Each player sees one opponent's battlefield at a time via a selector. Battlefield cards placed "on the opponent's side" track which opponent they belong to. Player roles shift from binary "host"/"opponent" strings to numbered player keys (`"p1"`, `"p2"`, `"p3"`, etc.) where `"p1"` is always the host.

---

## Implementation Checklist

### Phase 1 — Database Schema
- [x] Add migration: add `max_players` integer column (default 2) to `games`
- [x] Add migration: add `game_players` join table (`id`, `game_id`, `user_id`, `player_key`, `joined_at`)
- [x] Keep `host_id` on games (host is always p1); remove `opponent_id` from games (it's now in game_players)
- [x] Update `Game` schema: remove `belongs_to :opponent`; add `has_many :game_players`
- [x] Update `Game` changeset to drop `opponent_id` field

### Phase 2 — Games Context (games.ex)
- [x] `create_game(host, opts)`: accept `max_players` opt; insert host as `"p1"` in `game_players`
- [x] `join_game(game, user)`: assign next available player key; return `{:ok, game, player_key}` or `{:error, :full}`
- [x] `set_player_deck(game, player_key, deck_id)`: replaces `set_host_deck`/`set_opponent_deck`
- [x] `get_game!/1` and `get_game/1`: preload `game_players` (with user)
- [x] `list_active_games_for_user/1`: query via `game_players` join
- [x] `maybe_start_game/1`: check all `game_players` have a deck selected
- [x] `start_sideboarding/1`: init `sideboard_ready` map with all player keys
- [x] `all_sideboard_ready?/1`: check all player keys (replaces `both_sideboard_ready?`)
- [x] Added `player_key_for/2` and `player_keys/1` helpers

### Phase 3 — Game Engine: State (state.ex)
- [x] `initialize/3`: new signature `initialize(players_with_keys, deck_id_map, opts)`
- [x] `initialize_with_card_lists/3`: same pattern
- [x] `build_game_state/2`: dynamic N-player die roll and log
- [x] `build_card_instance/2`: `known` defaults to `%{}` (empty, not pre-seeded)
- [x] Added `all_player_keys(state)` helper

### Phase 4 — Game Engine: Actions (actions.ex)
- [x] `mark_known_to_both(card, state)` / `clear_known_to_both(card, state)`: derive keys from state
- [x] Added `mark_known_to_all/2` and `clear_known_to_all/2`
- [x] All functions that called old `mark_known_to_both/1` updated to pass state
- [x] `put_in_known/3`: simplified (no legacy boolean fallback)
- [x] `copy_opponent_card/4`: explicit `source_player` parameter
- [x] `reveal_cards/3`: reveals to all other players
- [x] `hide_hand/2`: clears knowledge for all other players
- [x] `next_z/1`: uses `all_player_keys(state)` for renumbering
- [x] Added `other_player_keys/2` helper

### Phase 5 — Game Setup LiveView (game_setup_live.ex)
- [x] `mount_game/2`: derive `my_role` from `game_players` lookup
- [x] Join logic: check `length(game_players) < max_players`; redirect if full with flash
- [x] `handle_event("select_deck")`: calls `Games.set_player_deck/3`
- [x] `maybe_start_game` path: calls `GameEngineState.initialize/3`
- [x] Setup template: shows all players with deck status; dynamic waiting row

### Phase 6 — Game LiveView (game_live.ex): Core Logic
- [x] `mount_game/2`: derive `my_role` via `Games.player_key_for`; add `opponent_roles` and `viewed_opponent` assigns
- [x] `handle_event("context_menu")`: any non-my owner triggers opponent actions
- [x] `handle_event("hotkey")`: uses `viewed_opponent` instead of `opp_role`
- [x] `copy_opponent_card` action: passes `owner` or `viewed_opponent` as source
- [x] `card_name_from_state/3`: uses `all_know?/2` helper (checks all player keys)
- [x] Added `handle_event("set_viewed_opponent")`
- [x] Sideboard restart: builds `players_with_keys` and `card_specs` dynamically
- [x] `all_know?/2` private helper added

### Phase 7 — Game LiveView: Rendering
- [x] Opponent selector bar: shown when `length(opponent_roles) > 1`; each button shows username, life, trackers
- [x] Opponent info bar / hand / battlefield: use `@viewed_opponent` instead of `@opp_role`
- [x] Die roll modal: loops over all player keys dynamically; handles ties with N players

### Phase 8 — JS / Client Side
- [x] No changes needed (already uses `data-my-role` from DOM)

### Phase 9 — Games List Page
- [x] `list_active_games_for_user/1`: uses `game_players` join
- [x] Games list template: shows all opponents by name; "X/Y players" when waiting
- [x] New game button: form with `max_players` selector (2–6)
- [x] `delete_game` auth: uses `player_key_for` instead of `host_id`/`opponent_id`

---

## Key Design Decisions

**Player keys**: `"p1"`, `"p2"`, ..., `"p6"`. `p1` is always the host.

**Known state for N players**: `card["known"]` is `%{"p1" => bool, ...}`. `mark_known_to_both(card, state)` derives all keys from state.

**No viewport_owner on cards for MVP**: Each player's battlefield is their own zone; opponent cards are rendered in the opponent's section when that opponent is viewed.

**No backward compatibility needed**: Existing games cleared on deploy.

---

## Files Changed

1. `priv/repo/migrations/20260308220001_add_multiplayer_to_games.exs` — new migration
2. `lib/goodtap/games/game_player.ex` — new schema
3. `lib/goodtap/games/game.ex` — schema updated
4. `lib/goodtap/games/games.ex` — context rewritten
5. `lib/goodtap/game_engine/state.ex` — initialization updated
6. `lib/goodtap/game_engine/actions.ex` — actions updated
7. `lib/goodtap_web/live/game_setup_live.ex` — setup flow updated
8. `lib/goodtap_web/live/game_live.ex` — main game updated
9. `lib/goodtap_web/live/game_list_live.ex` — list updated
10. `test/support/game_fixtures.ex` — fixtures use p1/p2
11. `test/goodtap/game_engine/state_test.exs` — tests updated + new tests
12. `test/goodtap/game_engine/actions_test.exs` — tests updated + new tests
