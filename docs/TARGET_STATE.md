# Target State

Last updated: 2026-10-20

What "done" means next, in two horizons: the demo tomorrow, and what comes
after it. For what's already built, see [`CURRENT_STATE.md`](CURRENT_STATE.md).

## Immediate target: demo-ready for 2026-10-21

Trimmed from the blueprint's Definition of Done (section 39) down to Hide &
Seek only, per the explicit scope cut made this session (no Infected, no
boundary enforcement, no background location).

| # | Requirement | Status |
|---|---|---|
| 1 | Host creates a lobby, draws a play area, gets a join code | Done |
| 2 | A second (and third) phone joins by code and shows up live in the lobby | Done |
| 3 | Host starts the match; server assigns one seeker, rest hiders | Done, untested on real GPS |
| 4 | Hiding countdown runs in sync on every phone | Done, untested |
| 5 | Hunt phase shows a tactical map with the real drawn boundary | Done, untested |
| 6 | Hiders are invisible to the seeker except during reveal windows | Done, untested |
| 7 | A catch is decided by the server from GPS proximity — no client self-reports | Done, untested |
| 8 | Match ends (all caught, or timeout) and every phone lands on results automatically | Done, untested |
| 9 | No crash across that full loop on 2+ physical outdoor phones | **Not yet verified** |

Row 9 is the only open item. No more features need to be built for the demo —
what's left is testing. If testing surfaces a bug, fix it narrowly; don't
expand scope while the clock is running.

## Pre-demo checklist

- [ ] Apply `supabase/migrations/20261020000000_match_lifecycle.sql` via the
      Supabase SQL Editor
- [ ] Confirm the Supabase project isn't paused (free tier auto-pauses after
      ~7 days idle — this project has been untouched since 2026-10-04)
- [ ] Full 2-phone outdoor loop test: lobby → join → start → hide → reveal →
      catch → results, both directions (seeker wins, hiders win on timeout)
- [ ] Release APK built and installed on every demo phone
- [ ] Each demo phone: location permission set to "Precise," GPS on,
      mobile data or Wi-Fi on, screen kept awake for the whole match
- [ ] Lobby timings reset to demo-realistic values after fast test runs
      (short hiding/reveal windows are for testing, not the actual demo)

## After the demo (near-term roadmap, not tonight)

In rough priority order — these are the next real features, not polish:

1. **Boundary enforcement** (blueprint §14) — out-of-bounds warning, grace
   timer, disqualify. The zones already exist and render on the gameplay
   map; nothing reads them once a match is live.
2. **Background location / Android foreground service** — the single
   biggest real-world reliability gap. Today, locking or minimizing a phone
   silently stops that player's location reporting.
3. **Scoring** — `game_players.score` / `survival_seconds` columns exist and
   are never written. Results currently derive everything live from
   timestamps instead of persisted scores.
4. **Infected mode** — second game mode from the blueprint; reuses most of
   the match-lifecycle plumbing (`start_game`, `sync_match_state` pattern)
   built for Hide & Seek.
5. **Taunts, pause system, QR join** — blueprint-listed, lower priority than
   the above.

## Still explicitly out of scope

Per blueprint §4 plus tonight's scope cuts: iOS, public matchmaking, friends,
leaderboards, chat/voice, custom taunt audio, cosmetics, achievements,
payments, ads, ranked play, spectator streaming, full anti-cheat,
Bluetooth-assisted catches, indoor positioning.
