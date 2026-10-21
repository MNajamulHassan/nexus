# Project Blueprint — Real-World GPS Multiplayer Game

**Working title:** Nexus / Hideout / TBD — shipped under the name **MANHUNT**  
**Primary platform for MVP:** Android  
**Future platform:** iOS  
**Client:** Flutter / Dart  
**Backend:** Supabase (PostgreSQL, Realtime, Auth, Edge Functions)  
**Map provider:** Mapbox  
**Initial game modes:** Hide & Seek, Infected  
**Target:** Deployable Android MVP in 7–14 days

> **This document is the original spec, not a live status tracker.** For what
> is actually built right now, see [`CURRENT_STATE.md`](CURRENT_STATE.md).
> For what's next (demo checklist + post-demo roadmap), see
> [`TARGET_STATE.md`](TARGET_STATE.md).

---

# 1. Product Vision

Build a real-world multiplayer game in which players physically move through a host-defined geographic play area.

A host creates a lobby, chooses a real-world area from a satellite map, draws the playable boundary and any restricted zones, chooses a game mode, and shares a QR code / join code with players.

Once the match starts, the map changes from normal satellite imagery to a dark tactical game map with simplified roads/buildings, glowing boundaries, restricted zones, player markers, timers and game-specific HUD elements.

The first two modes are:

1. **Hide & Seek**
2. **Infected**

The long-term architecture should support additional modes such as Capture the Flag, King of the Hill, Manhunt, Tag, shrinking-zone modes, and other location-based multiplayer games.

---

# 2. Product Principles

1. **Server-authoritative gameplay**
   - Phones report observations such as GPS location.
   - The server decides catches, infections, reveals, score and match state.
   - Never trust a client to declare another player caught.

2. **Privacy by default**
   - Track location only during an active match.
   - Do not permanently retain detailed location history unless there is a clear future reason.
   - Players only receive location data they are allowed to see.

3. **Real-world safety first**
   - Playable areas are host-defined.
   - Restricted/unsafe areas can be excluded.
   - Players get warnings before boundary penalties.
   - GPS uncertainty must be considered before punishments.

4. **Game first, map second**
   - Satellite imagery is for setup.
   - Actual gameplay uses a stylized tactical map that is easy to read.

5. **One reusable engine, multiple modes**
   - Avoid hardcoding the entire app around "hider" and "seeker".
   - Build reusable concepts: players, roles, zones, timers, events, proximity, scoring.

---

# 3. MVP Definition

## Included in MVP

### Account / identity
- Temporary nickname-based player identity
- Optional anonymous Supabase session
- Persistent accounts can come later

### Host
- Create lobby
- Select game mode
- Configure basic game settings
- Open satellite map
- Draw playable boundary
- Draw restricted zones
- Save selected geometry to the match
- Generate join code
- Generate QR code
- Start match
- End match manually

### Player
- Join by code
- Join by QR/deep link
- See lobby
- See game settings
- Receive role
- Grant location permission
- Participate in active match
- Receive warnings / status changes
- See final results

### Gameplay map
- Tactical dark/navy map
- Cyan playable boundary
- Restricted zones
- Current player marker
- Role-aware marker visibility
- Timer
- Next reveal timer
- Game state HUD

### Hide & Seek
- One configurable seeker
- Remaining players are hiders
- Hiding period
- Periodic location reveal
- Reveal lasts configurable number of seconds
- Automatic proximity catch
- Hider becomes caught/eliminated
- Last hider / time-limit resolution
- Hider score
- Seeker score

### Infected
- One initial infected player
- Other players are survivors
- Hiding period
- Automatic proximity infection
- Caught survivor becomes infected after short conversion delay
- Continue until all survivors are infected or time expires
- Survivor score
- Infected score

### Taunts
- Fixed built-in taunt sounds
- Cooldown
- Score reward
- Server-controlled usage
- No custom user audio in MVP

### Boundaries
- Playable polygon
- Restricted polygons
- Grace period for leaving playable area
- Warning state
- Disqualification after grace period
- GPS accuracy / hysteresis protection
- Optional restricted-area pause flow

### Pause
- Maximum match pause allowance per player
- Pause can only be used under allowed conditions
- No score earned while paused
- Cannot taunt while paused
- Cannot catch / be caught while paused
- Return to valid play area before pause expires

### Result screen
- Player ranking
- Survival time
- Taunts
- Catches / infections
- Score
- Match result

---

# 4. Explicitly Out of Scope for First MVP

Do not spend the first week building:

- iOS release
- Public matchmaking
- Friends system
- Global leaderboards
- Chat
- Voice chat
- Custom uploaded taunt audio
- Skins / cosmetics
- Achievements
- Payments
- Ads
- Ranked matchmaking
- Spectator streaming
- Full anti-cheat
- Bluetooth catch verification
- Indoor positioning
- Public community maps
- Saved player profiles with deep statistics
- Social feed
- Replay system
- Advanced moderation
- Push notifications outside a live match
- More than two game modes

---

# 5. Technology Stack

## Mobile Client

**Flutter / Dart**

Recommended packages:

- `flutter_riverpod` — state management
- `go_router` — navigation
- `supabase_flutter` — backend/auth/realtime
- `mapbox_maps_flutter` — map rendering
- `geolocator` — location
- `permission_handler` — permissions
- `qr_flutter` — lobby QR generation
- `mobile_scanner` — QR scanning
- `flutter_secure_storage` — secrets/session data
- `freezed` / `json_serializable` — typed models, optional for MVP
- `just_audio` — taunt playback

## Backend

**Supabase**

Use:

- PostgreSQL
- PostGIS
- Realtime
- Anonymous / simple auth
- Edge Functions
- Row-Level Security
- Database functions where useful

## Maps

**Mapbox**

Two major styles:

1. `editor_satellite`
   - Host uses satellite imagery to select and draw the real-world area.

2. `game_tactical`
   - Dark navy background
   - Simplified roads / paths
   - Muted buildings
   - Cyan highlights
   - Red restricted areas
   - Minimal labels

---

# 6. High-Level Architecture

```text
                    ┌──────────────────────────┐
                    │        Supabase          │
                    │                          │
                    │ PostgreSQL + PostGIS     │
                    │ Realtime                 │
                    │ Edge Functions           │
                    │ Auth                     │
                    └────────────┬─────────────┘
                                 │
                         Realtime / HTTPS
                                 │
              ┌──────────────────┴─────────────────┐
              │                                    │
      ┌───────▼────────┐                  ┌────────▼───────┐
      │ Android Client │                  │ Android Client │
      │    Flutter     │                  │    Flutter     │
      │                │                  │                │
      │ Mapbox         │                  │ Mapbox         │
      │ GPS            │                  │ GPS            │
      │ Game UI        │                  │ Game UI        │
      └────────────────┘                  └────────────────┘
```

---

# 7. Core Domain Model

Avoid designing the entire application around only seekers and hiders.

Use generic concepts:

```text
GameSession
├── GameMode
├── Players
├── Roles
├── Zones
├── LocationEngine
├── ProximityEngine
├── RevealEngine
├── ScoreEngine
├── TimerEngine
└── EventEngine
```

Game modes define the rules.

Example:

```text
Hide & Seek
roles = SEEKER, HIDER
caught_behavior = ELIMINATE
```

```text
Infected
roles = INFECTED, SURVIVOR
caught_behavior = CONVERT_ROLE
```

---

# 8. Match State Machine

Recommended match states:

```text
CREATED
  ↓
LOBBY
  ↓
STARTING
  ↓
HIDING_PHASE
  ↓
ACTIVE
  ↓
FINISHED
  ↓
CLOSED
```

Temporary substates/events:

```text
REVEAL_ACTIVE
PLAYER_OUT_OF_BOUNDS
PLAYER_PAUSED
PLAYER_DISCONNECTED
PLAYER_CAUGHT
PLAYER_INFECTED
```

Do not model every temporary condition as the entire match state. Most should be player state or timed event state.

---

# 9. Player States

Generic:

```text
JOINED
READY
ACTIVE
PAUSED
OUT_OF_BOUNDS
DISCONNECTED
ELIMINATED
FINISHED
```

Role is separate from status.

Example:

```text
role = HIDER
status = ACTIVE
```

or:

```text
role = INFECTED
status = ACTIVE
```

---

# 10. Database Schema

## `profiles`

```text
id UUID PK
display_name TEXT
created_at TIMESTAMPTZ
```

## `games`

```text
id UUID PK
host_id UUID
join_code TEXT UNIQUE
mode TEXT
status TEXT
name TEXT

created_at TIMESTAMPTZ
started_at TIMESTAMPTZ
ended_at TIMESTAMPTZ

hiding_duration_seconds INT
match_duration_seconds INT

catch_radius_meters NUMERIC
reveal_interval_seconds INT
reveal_duration_seconds INT

out_of_bounds_grace_seconds INT
max_pause_seconds INT

settings JSONB
```

## `game_players`

```text
id UUID PK
game_id UUID
player_id UUID

role TEXT
status TEXT

joined_at TIMESTAMPTZ
caught_at TIMESTAMPTZ
infected_at TIMESTAMPTZ

pause_used_seconds INT DEFAULT 0

score INT DEFAULT 0
survival_seconds INT DEFAULT 0

UNIQUE(game_id, player_id)
```

## `game_zones`

```text
id UUID PK
game_id UUID

type TEXT
name TEXT

geometry GEOGRAPHY/POLYGON

rules JSONB
created_at TIMESTAMPTZ
```

Zone types:

```text
PLAYABLE
RESTRICTED
START
SAFE
```

## `player_locations`

For MVP, only keep the latest authoritative location per player.

```text
game_id UUID
player_id UUID

latitude DOUBLE
longitude DOUBLE
accuracy_meters DOUBLE
heading DOUBLE
speed DOUBLE

client_timestamp TIMESTAMPTZ
server_received_at TIMESTAMPTZ

PRIMARY KEY(game_id, player_id)
```

## `game_events`

```text
id UUID PK
game_id UUID
player_id UUID NULL

event_type TEXT
payload JSONB
created_at TIMESTAMPTZ
```

Examples:

```text
GAME_STARTED
REVEAL_STARTED
REVEAL_ENDED
PLAYER_CAUGHT
PLAYER_INFECTED
PLAYER_TAUNTED
PLAYER_OUT_OF_BOUNDS
PLAYER_RETURNED
PLAYER_PAUSED
PLAYER_RESUMED
PLAYER_DISQUALIFIED
GAME_FINISHED
```

## `taunt_events`

Optional separate table if needed.

```text
id UUID PK
game_id UUID
player_id UUID
taunt_type TEXT
created_at TIMESTAMPTZ
bonus_awarded BOOLEAN
```

---

# 11. Realtime Design

Separate realtime information by purpose.

Recommended concepts:

```text
game:{gameId}:public
game:{gameId}:host
game:{gameId}:player:{playerId}
```

## Public match channel

May contain:

- player joined
- player left
- game state
- player eliminated
- infection event
- score update
- reveal countdown
- match finished

## Host channel

May contain:

- disconnect warnings
- pause requests
- boundary violations
- moderation/admin actions

## Private player channel

May contain:

- role assignment
- private warnings
- reveal data the player is allowed to see
- catch/infection confirmation

Never broadcast all precise locations to all clients.

---

# 12. Location Engine

## Client location payload

```json
{
  "lat": 34.000000,
  "lng": 73.000000,
  "accuracy": 7.2,
  "speed": 1.1,
  "heading": 150.0,
  "capturedAt": "..."
}
```

Server adds its own receive time.

## Suggested update intervals

MVP:

- Active foreground gameplay: every 2 seconds
- Background / low movement: 3–5 seconds
- If implementation becomes unstable, use a fixed 3 seconds first

Do not optimize too early.

## Accuracy rules

Never assume GPS is exact.

A location should be considered low confidence when accuracy is poor.

Suggested MVP policy:

```text
accuracy <= 20m:
usable

20m < accuracy <= 40m:
usable for broad boundary logic,
not ideal for catch confirmation

accuracy > 40m:
low confidence
```

These are starting values only and must be playtested.

---

# 13. Proximity / Catch Engine

Distance calculation happens on the server.

Use PostGIS geography distance or a server-side geographic calculation.

Do not trust:

```text
client says "I caught player X"
```

Instead:

```text
Seeker/infected location
+
Target location
+
Accuracy
+
Time freshness
=
server decision
```

## Initial catch rule

Start with:

```text
catch radius: 20m
```

Require:

- both locations are recent
- both accuracy readings are acceptable
- proximity condition persists for multiple readings / several seconds

Example MVP:

```text
distance <= 20m
for 4 seconds
with both accuracies <= 20m
→ caught
```

If this proves unreliable, tune it during real-world testing.

---

# 14. Boundary Engine

## Playable area

One outer polygon.

## Restricted zones

Zero or more inner polygons.

## Out-of-bounds logic

Do not trigger a penalty from one GPS sample.

Recommended logic:

```text
player appears outside
↓
confirm across multiple readings / short delay
↓
OUT_OF_BOUNDS warning begins
↓
60 second return timer
↓
if player returns:
clear warning
↓
if player remains outside:
DISQUALIFIED
```

## Hysteresis / tolerance

Use a spatial buffer so GPS jitter near the edge does not repeatedly switch a player between inside/outside.

Possible starting tolerance:

```text
5–15m
```

Exact value must be tested.

---

# 15. Restricted Zones

Restricted areas are mainly game-rule geometry, not proof that a person physically entered a specific room.

GPS cannot reliably determine tiny indoor spaces.

Use restricted zones for larger areas such as:

- building wings
- private sections
- roads
- unsafe areas
- staff areas
- inaccessible grounds

Player enters a restricted region:

```text
warning
↓
return to allowed area
OR
eligible pause flow
```

---

# 16. Pause System

Purpose:
- Allow a player to temporarily stop participating for legitimate reasons.
- Prevent using restricted/inaccessible areas as tactical hiding locations.

Recommended MVP:

```text
max pause allowance = 5 minutes / match
max pause activations = 1
```

While paused:

- no survival points
- no taunt
- no catch
- cannot be caught
- location still used only for determining whether player returned to the valid area
- pause timer continues
- must return before timer expires

On expiry:

```text
not back in valid area
→ disqualified
```

Prevent pause abuse:

- only allow pause when player is in a server-recognized eligible state
- optional host approval can be added after MVP

---

# 17. Satellite Setup Map

Host setup uses normal satellite imagery.

Workflow:

```text
Create Game
↓
Choose Game Mode
↓
Open Map
↓
Search / Use My Location
↓
Satellite View
↓
Draw Playable Polygon
↓
Draw Restricted Zones
↓
Confirm
↓
Save Geometry
↓
Create Lobby
```

Editing tools:

- add point
- undo point
- complete polygon
- edit polygon
- delete polygon
- add restricted area
- zoom
- recenter

MVP should prioritize functionality over advanced polygon editing UX.

---

# 18. Tactical Gameplay Map

The gameplay map should match the chosen visual direction:

- dark navy / black base
- cyan / electric blue roads
- simplified building footprints
- low visual clutter
- glowing playable boundary
- red restricted areas
- blue/cyan player marker
- role-specific markers
- large readable HUD

Do not render full satellite imagery during gameplay by default.

The same geographic coordinates are used; only the map style changes.

---

# 19. Hide & Seek Rules

## Roles

```text
1 SEEKER
N HIDER
```

Host options:

- random seeker
- host-selected seeker

## Match flow

```text
Lobby
↓
Roles assigned
↓
Hiding phase
↓
Active hunt
↓
Periodic reveal
↓
Catch events
↓
Last hider or timeout
↓
Results
```

## Reveal

Starting recommendation:

```text
every 10 minutes
duration 30 seconds
```

During reveal:
- seeker may see live hider location updates
- hiders see warning that their location is exposed

After reveal:
- precise hider location disappears again

## Win conditions

Possible MVP:

- Seeker wins if all hiders are caught before match timer expires.
- Remaining hiders win if match timer expires.

Individual ranking is based on score.

---

# 20. Infected Rules

## Roles

```text
1 initial INFECTED
N SURVIVORS
```

## Match flow

```text
Lobby
↓
Initial infected selected
↓
Hiding phase
↓
Hunt starts
↓
Infected catches survivor
↓
Survivor begins transformation timer
↓
Survivor becomes infected
↓
Infected team grows
↓
All infected OR time expires
```

## Infection delay

Recommended starting point:

```text
30 seconds
```

During conversion:
- player cannot infect others
- player cannot be caught again
- player gets clear UI countdown

## Win conditions

- Infected team wins if no survivors remain.
- Survivors win if one or more survive until time expires.

---

# 21. Taunt System

MVP uses built-in audio only.

Example taunts:

- whistle
- laugh
- clap
- "hey"
- bell

## Rules

Recommended:

```text
cooldown = 120 seconds
```

Taunt is server-authorized.

Server checks:

- player is alive / active
- player is not paused
- cooldown expired

Then it broadcasts the taunt event to eligible opponents.

## MVP reveal effect

Keep MVP simple:

- play taunt sound on opponent devices
- optionally show "Taunt detected"

Do not add complex approximate-area clues until core gameplay is stable.

Later:
- approximate direction
- approximate radius
- high-risk taunt tiers
- exact-position burst

---

# 22. Scoring

The purpose of scoring is to identify standout players, not merely the last surviving player.

## Hide & Seek — Hider score

Initial tuning:

```text
Survival: +50 / minute
Taunt used: +50
Survive 2 minutes after taunt: +100
Survive reveal: +150
Last hider: +300
```

Do not over-reward taunt spam.

## Hide & Seek — Seeker score

```text
Catch: +300
Fast catch bonus: +100
Catch after target taunt: +100
Catch all hiders: +500
```

## Infected — Survivor score

```text
Survival: +50 / minute
Taunt: +50
Taunt survival: +100
Survive reveal: +150
Last survivor: +300
```

## Infected — Infected score

```text
Infection: +300
Fast infection bonus: +100
Infect taunting survivor: +100
```

All numbers are placeholders for playtesting.

---

# 23. Security Model

## Rules

- Client cannot modify another player.
- Client cannot directly assign roles.
- Client cannot directly set score.
- Client cannot directly declare catches/infections.
- Client cannot read hidden locations.
- Host privileges are server-validated.
- Join code does not equal full authorization.
- All important operations check current game state.
- Row-Level Security is enabled.

## Sensitive data

Do not expose:
- full precise location history
- locations after the match ends
- hidden hider/survivor coordinates outside allowed reveal periods

---

# 24. Anti-Cheat — MVP

Do not attempt perfect anti-cheat in week one.

Implement basic safeguards:

- server time is authoritative
- reject stale locations
- reject impossible teleports
- flag unrealistic speed
- detect missing location updates
- handle location permission disabled
- handle player leaving match
- disqualify / mark disconnected after configurable grace period

Later:
- mock-location detection
- Play Integrity API
- rooted-device signals
- more advanced movement anomaly detection

---

# 25. Connectivity

A live match requires internet.

Handle:

```text
connection lost
↓
player marked temporarily disconnected
↓
grace timer
↓
reconnect restores session
OR
forfeit/disqualification
```

Recommended MVP disconnect grace:

```text
60 seconds
```

---

# 26. Background Location

Background location is one of the hardest pieces.

Required use case:
- hider locks phone
- app is minimized
- game must still receive location

Approach:
- foreground service on Android when a match is active
- persistent Android notification such as:
  "Nexus match active — location sharing is on"
- stop service immediately after match ends

Do not track outside active gameplay.

---

# 27. Android Permissions

Likely required:

- precise / fine location
- background location
- foreground service location
- internet
- notifications where required

Use a pre-permission explanation screen.

Example copy:

> Location is used only while an active match is running so the game can enforce play boundaries, detect nearby catches and perform timed reveal events.

---

# 28. Privacy / Legal Checklist

Before public launch:

- Privacy Policy
- Terms of Service
- clear location disclosure
- background location disclosure
- data retention policy
- account/data deletion flow if persistent accounts are added
- third-party processor disclosure
- age policy
- safety rules
- no-trespassing warning
- permission to use play area statement
- safety disclaimer
- map provider terms compliance
- app-store data safety forms

Recommended product policy:

```text
No detailed location history retained after match completion.
```

Only retain match statistics unless technically necessary.

---

# 29. Safety Rules

Host confirmation before match:

```text
□ I have selected an area that is appropriate for play.
□ Players must obey local laws and property restrictions.
□ Unsafe and private areas should be marked as restricted.
```

Player confirmation:

```text
Do not trespass.
Do not enter roads or unsafe areas.
Do not play while operating a vehicle.
Pay attention to your surroundings.
```

---

# 30. Flutter Project Structure

```text
lib/
├── main.dart
│
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── theme.dart
│
├── core/
│   ├── constants/
│   ├── errors/
│   ├── location/
│   │   ├── location_service.dart
│   │   ├── location_permissions.dart
│   │   └── location_models.dart
│   ├── maps/
│   │   ├── map_style_service.dart
│   │   ├── polygon_service.dart
│   │   └── map_models.dart
│   ├── realtime/
│   └── utils/
│
├── features/
│   ├── onboarding/
│   ├── home/
│   ├── game_create/
│   ├── map_editor/
│   ├── lobby/
│   ├── game/
│   │   ├── application/
│   │   ├── domain/
│   │   ├── data/
│   │   └── presentation/
│   ├── taunts/
│   └── results/
│
├── models/
│   ├── game.dart
│   ├── player.dart
│   ├── zone.dart
│   ├── location.dart
│   └── game_event.dart
│
└── services/
    ├── supabase_service.dart
    ├── game_service.dart
    └── realtime_service.dart
```

Do not over-engineer the folder structure before features exist.

---

# 31. Suggested Screens

## Onboarding
- logo
- display name
- location explanation

## Home
- Create Game
- Join Game

## Create Game
- Game mode
- Basic rules
- Select area

## Map Editor
- satellite map
- draw outer boundary
- draw restricted areas
- confirm

## Lobby
- QR
- lobby code
- player list
- ready status
- game settings
- host start button

## Role Reveal
- Seeker / Hider
- Infected / Survivor

## Hiding Countdown
- timer
- role instructions

## Gameplay
- tactical map
- timer
- score
- taunt
- warning banners
- reveal countdown

## Pause / Boundary Warning
- status
- countdown

## Results
- match outcome
- rankings
- stats

---

# 32. One-Week Aggressive Build Plan

This is possible only if scope stays strict.

The goal is:

> A functional Android build that can be installed on multiple phones and complete a real match.

It is **not** the goal to have a polished commercial Play Store release in seven days.

## Day 1 — Foundation + GPS + Map

### Tasks
- create Flutter project
- create Git repository
- configure Supabase
- configure Mapbox
- create basic theme
- implement home screen
- show current GPS position
- show satellite map
- show tactical map style
- switch between styles

### End-of-day acceptance
- Android build runs on physical phone
- current location appears on map
- satellite and tactical map both work

---

## Day 2 — Map Editor + Lobby

### Tasks
- draw playable polygon
- draw restricted zones
- save zones to Supabase
- create game row
- generate join code
- join by code
- player list
- Realtime lobby updates
- QR display

### Acceptance
Two phones can join the same lobby and see each other in the player list.

---

## Day 3 — Match Lifecycle + Live Location

### Tasks
- role assignment
- hiding phase
- server timestamps
- match states
- send location updates
- tactical gameplay map
- server stores latest location
- reconnect basics

### Acceptance
Two or more phones can start a match and server receives live location.

---

## Day 4 — Hide & Seek Core

### Tasks
- seeker/hider roles
- reveal scheduler
- reveal visibility rules
- server-side distance checking
- caught state
- match completion
- basic scores

### Acceptance
A real outdoor Hide & Seek match can be completed.

---

## Day 5 — Infected + Taunts

### Tasks
- survivor/infected roles
- infection conversion
- transformation timer
- infection victory
- taunt button
- sound playback
- cooldown
- scoring integration

### Acceptance
A real Infected match can be completed.

---

## Day 6 — Boundary / Background / Reliability

### Tasks
- playable boundary validation
- restricted zones
- out-of-bounds warning
- 60s grace
- pause system
- Android foreground location service
- screen locked/minimized test
- disconnect handling
- permission UX

### Acceptance
Game continues reliably when phones are locked/minimized and handles leaving the game area.

---

## Day 7 — Test + Release Candidate

### Tasks
- playtest with 3–6 phones
- fix critical bugs
- tune GPS/catch radius
- tune boundaries
- improve HUD
- final privacy/safety copy
- app icon / package name
- release signing
- build APK
- build AAB
- version 0.1.0

### Acceptance
- signed Android APK installs
- signed AAB builds
- one complete Hide & Seek match
- one complete Infected match
- no known crash/blocker in primary flow

---

# 33. Two-Week Safer Plan

If the first week goes well, use week two for quality rather than adding many features.

## Days 8–9
- background location edge cases
- GPS accuracy tuning
- server authorization audit
- RLS review
- reconnection improvements

## Day 10
- UI polish
- animations
- tactical HUD polish
- role-specific map states

## Day 11
- map editor improvements
- polygon edit/delete
- better restricted zones
- saved map presets if time allows

## Day 12
- game balance
- taunt cooldown tuning
- scoring tuning
- Infected balancing

## Day 13
- broad device testing
- battery testing
- network-loss tests
- permission-denied flows

## Day 14
- release candidate
- documentation
- Play Console preparation
- screenshots
- store listing draft
- privacy forms
- closed/internal testing build

---

# 34. Critical Path

These are the features that can block the project:

```text
1. GPS works on real phones
2. Realtime location sync works
3. Background location works
4. Server-side distance logic works
5. Polygon containment works
6. Hidden locations are actually hidden
7. Match state stays synchronized
```

Everything else is secondary.

If behind schedule, remove:

1. QR scanning
2. saved maps
3. pause approval
4. fancy animations
5. complex scoring bonuses
6. advanced taunt clues

Do **not** remove:
- server authority
- correct privacy visibility
- GPS accuracy handling
- boundary safety
- real-device testing

---

# 35. Testing Matrix

## Map
- polygon creation
- invalid polygon
- player near boundary
- player outside boundary
- player re-enters
- restricted zone

## Location
- good GPS
- poor GPS
- indoor GPS
- device stationary
- device moving quickly
- screen locked
- app backgrounded

## Network
- Wi-Fi → mobile data
- temporary disconnect
- long disconnect
- reconnect

## Hide & Seek
- reveal starts
- reveal ends
- location hidden outside reveal
- catch occurs
- catch does not falsely occur
- last hider
- timeout

## Infected
- initial role
- infection
- conversion delay
- new infected can hunt
- all infected
- survivor timeout

## Taunt
- cooldown
- invalid use while paused
- score
- opponent playback

## Security
- hider cannot query other hider location
- survivor cannot query hidden infected/private data if not allowed
- non-host cannot start match
- client cannot manually set score

---

# 36. Release Definition

## Developer release
A signed APK that can be installed directly.

## Testing release
A signed AAB uploaded to Google Play internal/closed testing.

## Public release
Requires:
- Play Console listing
- policy declarations
- background location review
- privacy policy
- Data Safety form
- store review

Public availability is not fully under the developer's timing because review can take additional time.

---

# 37. AI-Assisted Development Workflow

AI can make the seven-day target realistic only if it is used as an implementation assistant, not allowed to redesign the project every few hours.

## Recommended workflow per feature

1. Give AI the relevant blueprint section.
2. Ask it to inspect current files.
3. Ask for a short implementation plan.
4. Approve/adjust.
5. Implement one feature.
6. Run analyzer/tests/build.
7. Fix only actual errors.
8. Commit.
9. Move to next feature.

## Avoid

- "Build the whole game"
- huge prompts that alter unrelated files
- repeatedly changing architecture
- letting AI invent database fields independently
- adding optional features before critical path is tested

## Good prompt structure

```text
Task:
Implement [specific feature].

Read first:
- docs/PROJECT_BLUEPRINT.md
- relevant existing files

Constraints:
- Follow existing architecture.
- Do not modify unrelated features.
- Server remains authoritative.
- Do not expose hidden player locations.
- Run flutter analyze after changes.
- Report changed files and remaining issues.
```

---

# 38. Git Strategy

Recommended:

```text
main
development
feature/*
```

Flow:

```text
feature/map-editor
→ development
→ test
→ main
```

For a one-week sprint, feature branches can be short-lived.

Commit examples:

```text
feat: add satellite map editor
feat: add lobby realtime sync
feat: add hide and seek roles
feat: add server proximity catches
feat: add infected conversion flow
feat: add taunt cooldown
fix: prevent boundary jitter penalties
```

---

# 39. Definition of Done for Android MVP

The MVP is complete when:

1. Host can create a match.
2. Host can choose a real location on satellite imagery.
3. Host can draw a playable polygon.
4. Host can mark restricted zones.
5. Players can join the lobby from separate Android phones.
6. Host can launch Hide & Seek.
7. Hiders receive correct hidden/reveal behavior.
8. Server detects catch proximity.
9. Match can finish correctly.
10. Host can launch Infected.
11. Infection conversion works.
12. Taunts work with cooldown.
13. Score is calculated server-side.
14. Out-of-bounds handling works.
15. Basic pause handling works.
16. Background location survives normal screen lock/minimize.
17. Results screen appears.
18. No client can trivially read every player's precise location.
19. Signed APK is installable.
20. Signed AAB builds successfully.

---

# 40. Success Metric for Week One

Do not judge week one by visual polish.

The successful demonstration is:

> Five people walk onto a real campus/park, scan or enter a lobby code, start an Infected match, lock their phones when they want, move through the physical area, receive boundary warnings, taunt each other, infect players through proximity, and finish with a synchronized score screen without needing developer intervention.

If that works, the project has proven its core technology.

---

# 41. Immediate First Tasks

Before coding gameplay:

1. Create repository.
2. Add this document under `docs/PROJECT_BLUEPRINT.md`.
3. Create Supabase project.
4. Create Mapbox account/token.
5. Create Flutter app.
6. Configure Android package name.
7. Add development and production environment configuration.
8. Build one screen showing:
   - current GPS coordinates
   - accuracy
   - current position on satellite map
9. Build tactical style map.
10. Test outdoors on a physical Android device.

Only after that should lobby/game code begin.

---

# 42. Post-MVP Backlog

Possible future roadmap:

## Gameplay
- Manhunt
- Capture the Flag
- King of the Hill
- Tag
- shrinking zone
- teams
- assists
- advanced taunts

## Social
- profiles
- friends
- private groups
- stats
- achievements

## Maps
- saved maps
- host-shared maps
- verified community maps
- custom map themes

## Anti-cheat
- integrity verification
- better mock-location detection
- movement anomaly scoring
- device trust signals

## Proximity
- Bluetooth-assisted final catch
- UWB on supported devices

## Platform
- iOS
- Apple Sign In
- push notifications

## Monetization
Only after gameplay is proven:
- cosmetic themes
- cosmetic taunts
- premium host customization

Do not monetize before the game is actually fun and reliable.

---

# 43. Final MVP Scope Freeze

For the first deployable Android version, the scope is frozen to:

```text
Flutter Android client
Supabase backend
Mapbox satellite setup map
Dark tactical gameplay map
Host-created play boundary
Restricted zones
Lobby code / QR
Hide & Seek
Infected
GPS tracking
Background location
Reveal mechanic
Proximity catch/infection
Taunts
Scoring
Out-of-bounds warnings
Basic pause
Results
Signed APK/AAB
```

Anything outside this list should be treated as post-MVP unless it is required to fix correctness, security, safety or release policy issues.
