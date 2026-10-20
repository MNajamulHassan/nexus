# Nexus

A real-world GPS multiplayer game. Players physically move through a
host-defined play area; the host draws the boundary on a satellite map, the
app switches to a dark tactical map for the match, and the server decides
catches from GPS proximity. First game mode: Hide & Seek.

- Client: Flutter / Dart
- Backend: Supabase (PostgreSQL + PostGIS, Realtime, Auth, RLS)
- Maps: Mapbox

## Docs

- [`docs/PROJECT_BLUEPRINT.md`](docs/PROJECT_BLUEPRINT.md) — original product/technical spec
- [`docs/CURRENT_STATE.md`](docs/CURRENT_STATE.md) — what's actually built, right now
- [`docs/TARGET_STATE.md`](docs/TARGET_STATE.md) — demo checklist + near-term roadmap

## Running

Mapbox and Supabase config live in `env/dev.json` (not committed). Always
pass it via `--dart-define-from-file`:

```bash
flutter devices
flutter run -d <deviceId> --dart-define-from-file=env/dev.json
```

Release build for installing on demo devices:

```bash
flutter build apk --release --dart-define-from-file=env/dev.json
```

Database changes live in `supabase/migrations/*.sql`, applied in order via
the Supabase SQL Editor (no linked Supabase CLI project in this repo yet).
