# Target State

Last updated: 2026-10-21

What's next, roughly in priority order. For what's already built, see
[`CURRENT_STATE.md`](CURRENT_STATE.md), including its Known limitations
section — most items below are the fix for one of those limitations.

## Near-term roadmap

1. **Bluetooth proximity catch.** GPS proximity (today's only signal) is
   noisy and spoofable by a modified client. Plan: use BLE signal-strength
   (RSSI) as a first-pass "are we actually near each other" spike detector
   between the seeker and a candidate hider, then verify with a rotating
   per-device token exchanged over BLE (so a replayed/relayed signal can't
   fake proximity after the fact). GPS stays as the fallback/backstop for
   devices without BLE or with it disabled.
2. **Compass heading.** `AppLocation.headingDegrees` is GPS
   course-over-ground today — meaningless while stationary. Read the
   device magnetometer (e.g. via a sensor plugin) so the self/seeker
   arrow markers point the way the phone is actually facing, not just the
   way it was last moving.
3. **`DO NOT ENTER` zones.** Extend `game_zones.type`'s allowed values and
   add live boundary enforcement during a match (warning, grace timer,
   disqualify) — today zones are drawn and stored but nothing reads them
   once a match starts.
4. **Ban as a separate action from kick.** Kick is deliberately
   remove-only now (a kicked player can rejoin with the same code — see
   `20261021030000_kick_is_remove_only.sql`'s header comment). A real ban
   (permanently blocking rejoin) should be its own RPC and its own table
   state, not a flag on `kick_player`.
5. **Ready flow.** `set_player_ready` has existed since the first
   authoritative-RPCs migration but has no Dart caller — either wire it
   up (lobby UI, a ready-check before `start_game`) or remove the unused
   RPC and the `READY` status value.
6. **Settings screen.** Referenced by the UI-polish task as explicitly
   skipped; no screen, no provider, nothing to build on yet.
7. **Accuracy-aware catch tolerance.** `fetch_catch_candidates`'s
   `ST_DWithin` check against `catch_radius_meters` doesn't buffer for
   either party's reported GPS accuracy, unlike
   `upsert_player_location`'s own jitter-tolerant speed check. Add a
   capped accuracy buffer (e.g. `least(accuracy, 20)` per party) to stop
   boundary flicker from pure GPS noise.
8. **Durable catch cooldown.** `attempt_catch`'s 2-second per-seeker
   cooldown is only durable across a *successful* catch today, because
   the function signals failure by raising (which rolls back the
   cooldown write too). Fixing this for real requires changing how
   failure is signaled — either a result value instead of a raised
   exception (a Dart-side change too), or an autonomous sub-transaction
   for just the cooldown write. Both were explicitly out of scope when
   this was first found; still unresolved.
9. **Tests for match/lobby RPCs.** Everything server-side
   (`attempt_catch`, `start_game`, `join_game`, `kick_player`,
   `update_game_settings`, freshness/plausibility checks, etc.) has been
   verified so far by static reading and manual report-writing, never by
   an actual pgTAP/integration test run against a real or ephemeral
   Postgres instance — because no session has been allowed to apply a
   migration or run anything against a database. A real test suite would
   need that permission explicitly granted.

## Already covered, not repeated here

Scoring (`game_players.score`/`survival_seconds` unwritten), background
location / Android foreground service, pause system, taunts — all remain
unbuilt per the original blueprint and are lower priority than the items
above; see the blueprint's own roadmap sections for detail.

## Still explicitly out of scope

Per the blueprint plus every session's accumulated scope cuts: iOS, public
matchmaking, friends, leaderboards, chat/voice, custom taunt audio,
cosmetics, achievements, payments, ads, ranked play, spectator streaming,
full anti-cheat, indoor positioning, a Zombie Mode roadmap (it's a separate
local singleplayer feature, not part of this multiplayer target state).
