# Current State

Last updated: 2026-10-20

This is a live snapshot of what actually exists in the repo, not the plan.
For the original plan, see [`PROJECT_BLUEPRINT.md`](PROJECT_BLUEPRINT.md).
For what's left, see [`TARGET_STATE.md`](TARGET_STATE.md).

## One-line summary

Hide & Seek is implemented end-to-end against the live Supabase backend:
create lobby → join → start → hiding phase → hunt → reveal → server-side
catch → results. It has not yet been run on real phones outdoors. Infected
mode, boundary enforcement, background location, pause, taunts, and scoring
are not built.

## Implemented

### Identity & auth (`lib/core/auth/`)
- Anonymous Supabase auth session created per device on first boot
- Display-name onboarding (`features/onboarding`)

### Lobby (`lib/features/game_create`, `map_editor`, `join_game`, `lobby`)
- Create lobby: pick Hide & Seek or Infected (Infected not implemented past
  this point), set match/hiding duration, catch radius, reveal interval +
  duration, taunts toggle
- Satellite map editor: draw one playable polygon + any number of restricted
  polygons, saved via the `replace_game_zones` RPC
- Join by 6-character code (`join_game` RPC)
- Realtime player list (Postgres changes + broadcast fallback + a 4s safety
  poll), host cancel / player leave

### Match lifecycle (built 2026-10-20, see `supabase/migrations/20261020000000_match_lifecycle.sql`)
- `start_game(p_game_id)` — host-only. Requires ≥2 players. Randomly assigns
  one `SEEKER`, rest `HIDER`, sets all players `ACTIVE`, flips
  `games.status` to `HIDING_PHASE`, stamps `started_at`.
- `sync_match_state(p_game_id)` — callable by any member, polled every 3s by
  every connected phone. Server-authoritative tick that:
  - flips `HIDING_PHASE` → `ACTIVE` once `hiding_duration_seconds` elapses
  - checks the seeker's latest stored location against every `ACTIVE` hider
    with `ST_DWithin(..., catch_radius_meters)` and marks catches
    (`ELIMINATED`, `caught_at`)
  - ends the match (`FINISHED`, `ended_at`) when no hiders remain or
    `match_duration_seconds` elapses
- `fetch_seeker_view(p_game_id)` — seeker-only (raises otherwise). Returns
  hider coordinates only while `games.status = 'ACTIVE'` **and** the
  server-computed reveal window is open (time-math off `started_at`,
  `hiding_duration_seconds`, `reveal_interval_seconds`,
  `reveal_duration_seconds`). Empty otherwise — hiders are never exposed via
  direct table access.
- `fetch_game_zones(p_game_id)` — GeoJSON readback of a game's zones for the
  gameplay map (raw `geometry::text` would be WKB hex, not usable client-side).
- `lib/features/match/match_screen.dart` — tactical dark map (own GPS marker,
  playable boundary outline, hider markers while revealed), phase/role/
  countdown HUD, reports location via `watchPosition()` + `upsert_player_location`.
- `lib/features/results/results_screen.dart` — seeker-wins/hiders-win banner,
  per-hider caught-time or "survived" line.

### Backend schema (`supabase/migrations/`)
- `profiles`, `games`, `game_players`, `game_zones` (PostGIS `geography`),
  `player_locations` (latest fix only, no history), `game_events`
  (append-only)
- RLS on every client-facing table; all writes go through
  `SECURITY DEFINER` RPCs. `player_locations` is selectable only by its own
  owner — the seeker sees hiders exclusively through `fetch_seeker_view`,
  never the raw table.

## Explicitly not built

- Infected mode
- Boundary / restricted-zone enforcement during a live match (no
  out-of-bounds warning, grace timer, or disqualify — the zones exist and
  are drawn on the map, nothing reads them once the match starts)
- Background location / Android foreground service — the app must stay
  open and awake for the whole match; this is the biggest real-world
  reliability gap
- Pause system
- Taunts
- Scoring — `game_players.score` / `survival_seconds` columns exist and are
  never written; the results screen computes survival/caught time live from
  `caught_at` / `started_at` / `ended_at` instead
- QR generation/scanning — `qr_flutter` / `mobile_scanner` are dependencies,
  unused in code; join is code-entry only

## Known limitations / risks

- Countdown and "exposed/hidden" text on the Match screen are computed from
  each phone's **local** clock for display only. The actual catch/reveal/
  finish decisions run on Postgres `now()` via the RPCs above, so gameplay
  correctness doesn't depend on phone clocks — only the displayed seconds
  might drift slightly between phones.
- `sync_match_state` catches are skipped if the seeker's last reported fix is
  older than 30 seconds (stale-location guard) — a seeker with a dead
  location stream will stop catching anyone until it recovers.
- No retry/backoff beyond "try again next 3s tick" on network failure.
- **Not yet tested on real devices / outdoor GPS.** Verified so far:
  `flutter analyze` clean, `flutter test` passes, debug APK builds. The
  actual gameplay loop (reveal timing, catch radius, realtime navigation
  across phones) has not been run against live GPS.

## File map (added/changed 2026-10-20)

- `supabase/migrations/20261020000000_match_lifecycle.sql`
- `lib/models/game.dart` — `GamePlayerRecord.role`/`caughtAt`, `HiderSighting`, `LobbyErrorKind.match`
- `lib/core/game/game_repository.dart` — `startGame`, `syncMatchState`, `fetchSeekerView`, `reportLocation`, `fetchZones`
- `lib/core/location/location_service.dart` — `watchPosition()` continuous stream
- `lib/core/maps/map_style_service.dart` — `tactical` (dark) style
- `lib/app/router.dart` — `/match/:gameId`, `/results/:gameId`
- `lib/features/lobby/lobby_screen.dart` — Start Match button, status-driven auto-navigation
- `lib/features/match/match_screen.dart` — new
- `lib/features/results/results_screen.dart` — new
