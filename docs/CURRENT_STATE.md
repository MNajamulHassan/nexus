# Current State

Last updated: 2026-10-21

This is a live snapshot of what actually exists in the repo, not the plan.
For the original plan, see [`PROJECT_BLUEPRINT.md`](PROJECT_BLUEPRINT.md).
For what's left, see [`TARGET_STATE.md`](TARGET_STATE.md).

Everything below is marked **VERIFIED** (read directly from the current code
on `development`) or **unverified** (stated by the project owner, or not
checkable from the repo alone — e.g. anything about the live database's
actual state, since no migration has been applied from any Claude Code
session).

## One-line summary

MANHUNT (working title Nexus/Hideout) is a GPS multiplayer hide-and-seek
game against a live Supabase backend, with two modes — Hide & Seek and
Infected — both implemented server-side and client-side. **VERIFIED**: no
migration has ever been applied to a database from within any session that
produced this repo's history; **unverified**: whether the project owner has
applied them manually outside that history (see the migrations table below).

## Implemented (VERIFIED in code)

- **Auth**: anonymous Supabase auth session per device on first boot, plus
  display-name onboarding (`lib/core/auth/`, `lib/features/onboarding/`).
- **Create / join lobby**: host creates a lobby (mode, timing, catch radius,
  reveal windows, taunts toggle), draws a play area in the map editor
  (`lib/features/map_editor/`), gets a 6-character join code; a second
  device joins by code (`join_game` RPC).
- **Lobby**: live player list, host-only **Edit settings** (reusing the
  Create Game fields), **manual seeker** selection (`seeker_mode`
  `'RANDOM'`/`'MANUAL'` + `seeker_player_id` on `games`, enforced in
  `update_game_settings`/`start_game`), host-only **kick** that is
  **remove-only** — a kicked player can rejoin with the same code
  (`kick_player`/`join_game`, `game_kicked_players` table,
  `was_kicked` RPC distinguishing "you were removed" from "the host
  cancelled").
- **Hide & Seek**: one random or host-chosen seeker, rest hiders; seeker
  catches a hider via a **hold-to-catch** button (`_HoldToCatchButton` in
  `lib/features/match/match_screen.dart`), server-validated by
  `attempt_catch`; eliminated hiders stop being tracked; match ends when no
  active hiders remain or time runs out.
- **Infected**: same match shell, but `attempt_catch` flips a caught hider's
  `role` to `SEEKER` instead of eliminating them (`caught_at` doubles as
  infection time); a hider can see **every** current seeker, not just one
  (`fetch_seeker_location` has no row limit); match ends the same way, with
  a distinct finish reason (`all_infected` vs `all_caught`).
- **Results**: Hide & Seek shows seeker-wins/hiders-win and per-hider
  caught-time or "survived"; Infected shows its own outcome text and a
  Seekers/Survivors listing with each seeker's "Original seeker" or
  "Infected after \<duration\>" line.
- **GPS reliability**: a 5s heartbeat re-sends the last fix so a stationary
  device's server-side freshness doesn't expire; `wakelock_plus` keeps the
  screen on for the whole match; a hider's seeker marker(s) are kept for a
  45s grace window after a poll comes back empty (distinguishes "briefly
  stale" from "actually gone"); client-side jitter smoothing on every
  marker (self, seeker, hider).
- **UI theme**: Rajdhani (headings/labels/buttons/timers) and Exo 2 (body)
  fonts, navy/cyan/glass-card tokens in `lib/app/theme.dart`, wired into
  cards/buttons/inputs/dialogs/snackbars/chips/etc. so every screen inherits
  it.

## Every migration in `supabase/migrations/`

| File | Purpose | Live DB |
|---|---|---|
| `20261004150000_enable_postgis.sql` | Enables the PostGIS extension, needed for polygon/distance checks. | unverified |
| `20261004150100_create_core_tables.sql` | Creates `profiles`, `games`, `game_players`, `game_zones`, `player_locations`, `game_events`. | unverified |
| `20261004150200_rls_helpers_and_policies.sql` | `is_game_member`/`is_game_host` helpers, RLS policies on every client-facing table. | unverified |
| `20261004150300_authoritative_rpcs.sql` | Original write RPCs: `create_game`, `join_game`, `leave_game`, `set_player_ready`, `replace_game_zones`, `upsert_player_location`, `record_game_event`. | unverified |
| `20261004183000_cancel_lobby.sql` | Host-only rollback for a lobby that never left `CREATED`/`LOBBY`. | unverified |
| `20261004190000_lobby_realtime.sql` | Adds `games`/`game_players` to the `supabase_realtime` publication (see Known limitations — this is the one most worth checking manually). | unverified |
| `20261020000000_match_lifecycle.sql` | Original `start_game`/`sync_match_state`/`fetch_seeker_view`/`fetch_game_zones` (automatic GPS-radius catching). | unverified |
| `20261020010000_manual_catch.sql` | Replaces automatic catching with seeker-triggered `attempt_catch` + `fetch_catch_candidates`. | unverified |
| `20261020020000_seeker_visibility_and_catch_radius.sql` | Fixes `fetch_catch_candidates` to use the host's configured catch radius instead of a hardcoded 15m. | unverified |
| `20261020030000_fix_seeker_view_ambiguity.sql` | Fixes a PL/pgSQL column-name/variable-name collision in `fetch_seeker_view`. | unverified |
| `20261021000000_catch_candidate_locations.sql` | `fetch_catch_candidates` returns in-range hider coordinates, not just distance. | unverified |
| `20261021010000_security_hardening.sql` | Locks down function/table grants (anon loses EXECUTE), location plausibility checks, fail-closed catch, cooldowns, server-clock freshness, 12-player cap. | unverified |
| `20261021020000_lobby_management.sql` | `update_game_settings`, `kick_player`, manual seeker selection. | unverified |
| `20261021030000_kick_is_remove_only.sql` | Makes kick remove-only (rejoin clears the kicked marker). | unverified |
| `20261021040000_infected_mode.sql` | Server-side Infected mode logic. | unverified |

"Live DB: unverified" means exactly that — whether any of these have been
applied to the actual Supabase project cannot be determined by reading this
repo. The project owner has stated migrations are applied manually via the
Supabase SQL editor as needed; that statement is not independently
verifiable from the repo.

## Security model (plain language, VERIFIED in the migrations above)

- Row-Level Security is enabled on every client-facing table.
- `player_locations` is readable only by its own owner via RLS — the seeker
  never reads hider coordinates from the table directly, only through
  `fetch_seeker_view`/`fetch_catch_candidates`, which apply their own
  role/reveal-window/freshness checks.
- Every write goes through a `SECURITY DEFINER` RPC, never a direct table
  insert/update from the client.
- `anon` has no `EXECUTE` on any app-facing function (Supabase's default
  privileges grant EXECUTE to `anon`/`authenticated` directly on new
  functions, independent of the `public` role, so every function
  explicitly revokes from `public, anon` and grants only to
  `authenticated`).
- Location plausibility checks in `upsert_player_location`: accuracy must
  be present and `<= 100m`; implied speed since the previous fix (jitter-
  adjusted by subtracting both fixes' accuracy radii) must be `<= 12 m/s`
  within a 60s window.
- Freshness is judged on the server clock (`server_received_at`), never the
  client-supplied `client_timestamp` (which is attacker-controlled and
  stored for display only).
- `attempt_catch` fails closed: a missing or >30s-stale location fix for
  either party blocks the catch instead of silently skipping the distance
  check.
- Rate limits: a 2s cooldown per seeker on catch attempts (not durable
  across a *failed* attempt — see Known limitations), a 2s throttle per
  seeker on catch-candidate scans.
- `games.max_players` caps a lobby at 12 (enforced in `join_game`).

## Lobby realtime mechanism (VERIFIED)

Postgres Changes (`onPostgresChanges` in `game_repository.dart`'s
`subscribeLobby`) is wired up but does not reliably fire — the live
project's `supabase_realtime` publication was found empty during this
project's work, meaning the `alter publication ... add table` statements in
`20261004190000_lobby_realtime.sql` either were never applied or were reset
afterward (unverified which). The mechanism that actually works today is:
an explicit Realtime **Broadcast** (`lobby_changed` event) the client sends
right after a successful `join_game`/`leave_game`/`cancel_lobby`/
`kick_player`/`update_game_settings`/`start_game` RPC call, plus an
unconditional **4-second polling timer** in `LobbyController` as the
fallback that guarantees eventual consistency regardless of realtime state.

## Known limitations

- **Catch cooldown not durable on failed attempts** — `attempt_catch`
  returns `public.games` (not void) and signals failure by raising, so
  Postgres rolls back the whole call (including the cooldown write) when a
  later check raises. The cooldown only persists across a *successful*
  catch.
- **GPS accuracy-tolerance migration not done** — `fetch_catch_candidates`'s
  in-range check (`ST_DWithin` against `catch_radius_meters`) does not add
  any buffer for either party's GPS accuracy, so results can flicker near
  the boundary purely from GPS noise.
- **100m catch backstop is flat** — `attempt_catch`'s final distance check
  is a hardcoded 100m, independent of the game's configured
  `catch_radius_meters`.
- **`set_player_ready` has no client wrapper** — the RPC exists (and has
  since the original migration) but `GameRepository` never calls it; the
  `READY` player status is unused by any screen.
- **`games.settings` blob is unused** — `update_game_settings` validates
  but does not write `p_settings`, since the only caller always sends `{}`
  with no UI to edit it; writing it would silently wipe any existing value.
- **`qr_flutter`/`mobile_scanner` are unused dependencies** — present in
  `pubspec.yaml`, zero references in `lib/` (grepped). Join is code-entry
  only.
- **No `DO NOT ENTER` zone type** — `game_zones.type` only accepts
  `'PLAYABLE'`, `'RESTRICTED'`, `'START'`, `'SAFE'`; restricted zones are
  drawn and stored but nothing reads them once a match is live (no
  boundary enforcement).
- **`headingDegrees` is GPS course-over-ground, not a compass heading** —
  only meaningful while moving (see the doc comment on
  `AppLocation.headingDegrees`); there's no magnetometer reading anywhere.
- **Catch radius bounds (5-100m) are enforced client-side only**
  (`GameConfig.validate`) — the database only enforces `> 0` via a table
  CHECK constraint, no upper bound.
- **Infected multi-seeker path is untested with 3+ devices** — this
  project's device testing used two physical phones; a hider seeing
  multiple simultaneous seeker markers has not been exercised beyond
  `flutter test` widget-level checks.
- **Zombie Mode** is a separate, fully local singleplayer feature, out of
  scope for everything else described in this document.
- **Debug screens are gated behind `kDebugMode`** — the GPS Test/Map
  Test/Map Editor shortcuts on Home only appear in debug builds, not
  release.

## Syllabus coverage (implicit-animation widgets added for the UI-polish pass)

**AnimatedContainer**
- `lib/features/game_create/game_settings_form.dart:159` — mode card border/background eases between selected and unselected.
- `lib/features/lobby/lobby_screen.dart:742` — settings summary card's border flashes accent then eases back ~800ms after a settings change.
- `lib/features/match/match_screen.dart:1292` — hold-to-catch button's border eases between idle and actively-held.
- `lib/features/match/match_screen.dart:1617` — legend panel's background shape/radius eases between collapsed and expanded.

**AnimatedCrossFade**
- `lib/features/home/home_screen.dart:90` — name block ("name set" vs "no name yet").
- `lib/features/game_create/create_game_screen.dart:198` — play-area status/error text.
- `lib/features/join_game/join_game_screen.dart:103` — join-code error text.
- `lib/features/lobby/lobby_screen.dart:555` — Start Match button vs "waiting for players" card.
- `lib/features/match/match_screen.dart:1624` — legend's collapsed icon vs full panel.

**AnimatedOpacity**
- `lib/features/lobby/lobby_screen.dart:684` — realtime banner dims while not fully connected.
- `lib/features/match/match_screen.dart:1104` — catch/infection banner fade.
- `lib/features/match/match_screen.dart:1036` and `:1187` — pre-existing intro-reveal fades (not new; the catch banner above reuses their duration/curve).

Line numbers VERIFIED by grep against `development` at the time of writing;
they will drift with future edits.
