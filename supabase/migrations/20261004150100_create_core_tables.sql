-- Core match schema. Authoritative gameplay columns exist here, but clients
-- do not receive write grants on them (see later migrations).

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) > 0),
  created_at timestamptz not null default now()
);

comment on table public.profiles is
  'Public player identity. id matches auth.users.id.';

-- ---------------------------------------------------------------------------
-- games
-- ---------------------------------------------------------------------------
create table public.games (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles (id) on delete restrict,
  join_code text not null,
  mode text not null,
  status text not null default 'CREATED',
  created_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz,
  hiding_duration_seconds integer not null,
  match_duration_seconds integer not null,
  catch_radius_meters double precision not null,
  reveal_interval_seconds integer not null,
  reveal_duration_seconds integer not null,
  taunts_enabled boolean not null default true,
  settings jsonb not null default '{}'::jsonb,

  constraint games_join_code_key unique (join_code),
  constraint games_join_code_format check (join_code ~ '^[A-Z0-9]{6}$'),
  constraint games_mode_check check (mode in ('hide_and_seek', 'infected')),
  constraint games_status_check check (
    status in (
      'CREATED',
      'LOBBY',
      'STARTING',
      'HIDING_PHASE',
      'ACTIVE',
      'FINISHED',
      'CLOSED'
    )
  ),
  constraint games_hiding_duration_check check (hiding_duration_seconds > 0),
  constraint games_match_duration_check check (match_duration_seconds > 0),
  constraint games_catch_radius_check check (catch_radius_meters > 0),
  constraint games_reveal_interval_check check (reveal_interval_seconds > 0),
  constraint games_reveal_duration_check check (reveal_duration_seconds > 0),
  constraint games_settings_object check (jsonb_typeof(settings) = 'object')
);

comment on table public.games is
  'Host-created match. status/host_id are server-authoritative.';
comment on column public.games.settings is
  'Optional extras (grace seconds, pause limits) without extra columns.';

create index games_host_id_idx on public.games (host_id);
create index games_status_idx on public.games (status);

-- ---------------------------------------------------------------------------
-- game_players
-- ---------------------------------------------------------------------------
create table public.game_players (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  player_id uuid not null references public.profiles (id) on delete cascade,
  role text,
  status text not null default 'JOINED',
  joined_at timestamptz not null default now(),
  caught_at timestamptz,
  infected_at timestamptz,
  pause_used_seconds integer not null default 0,
  score integer not null default 0,
  survival_seconds integer not null default 0,

  constraint game_players_game_player_key unique (game_id, player_id),
  constraint game_players_role_check check (
    role is null
    or role in ('SEEKER', 'HIDER', 'INFECTED', 'SURVIVOR')
  ),
  constraint game_players_status_check check (
    status in (
      'JOINED',
      'READY',
      'ACTIVE',
      'PAUSED',
      'OUT_OF_BOUNDS',
      'DISCONNECTED',
      'ELIMINATED',
      'FINISHED'
    )
  ),
  constraint game_players_pause_used_check check (pause_used_seconds >= 0),
  constraint game_players_survival_check check (survival_seconds >= 0)
);

comment on table public.game_players is
  'Lobby/match membership. role, score, caught_at, infected_at are authoritative.';

create index game_players_game_id_idx on public.game_players (game_id);
create index game_players_player_id_idx on public.game_players (player_id);
create index game_players_game_status_idx on public.game_players (game_id, status);

-- ---------------------------------------------------------------------------
-- game_zones
-- ---------------------------------------------------------------------------
create table public.game_zones (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  type text not null,
  name text,
  geometry geography (polygon, 4326) not null,
  rules jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint game_zones_type_check check (
    type in ('PLAYABLE', 'RESTRICTED', 'START', 'SAFE')
  ),
  constraint game_zones_rules_object check (jsonb_typeof(rules) = 'object'),
  constraint game_zones_geometry_valid check (st_isvalid(geometry::geometry))
);

comment on table public.game_zones is
  'Host-defined play geometry. geography(Polygon, 4326) for meter-accurate checks.';
comment on column public.game_zones.geometry is
  'WGS84 polygon, GeoJSON order (lng, lat). Use ST_Covers / ST_DWithin in meters.';

create index game_zones_game_id_idx on public.game_zones (game_id);
create index game_zones_game_type_idx on public.game_zones (game_id, type);
create index game_zones_geometry_gix on public.game_zones using gist (geometry);

-- One outer playable boundary per match.
create unique index game_zones_one_playable_idx
  on public.game_zones (game_id)
  where type = 'PLAYABLE';

-- ---------------------------------------------------------------------------
-- player_locations
-- Latest fix only. No history rows.
-- ---------------------------------------------------------------------------
create table public.player_locations (
  game_id uuid not null references public.games (id) on delete cascade,
  player_id uuid not null references public.profiles (id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  accuracy_meters double precision not null,
  heading double precision,
  speed double precision,
  client_timestamp timestamptz not null,
  server_received_at timestamptz not null default now(),
  location geography (point, 4326) generated always as (
    st_setsrid(st_makepoint(longitude, latitude), 4326)::geography
  ) stored,

  primary key (game_id, player_id),
  constraint player_locations_latitude_check check (latitude between -90 and 90),
  constraint player_locations_longitude_check check (longitude between -180 and 180),
  constraint player_locations_accuracy_check check (accuracy_meters >= 0),
  constraint player_locations_member_fk foreign key (game_id, player_id)
    references public.game_players (game_id, player_id) on delete cascade
);

comment on table public.player_locations is
  'Latest GPS observation per player in a match. Not a history table.';
comment on column public.player_locations.location is
  'Generated geography point for server-side proximity queries.';

create index player_locations_player_id_idx on public.player_locations (player_id);
create index player_locations_location_gix on public.player_locations using gist (location);

-- ---------------------------------------------------------------------------
-- game_events
-- ---------------------------------------------------------------------------
create table public.game_events (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  player_id uuid references public.profiles (id) on delete set null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint game_events_type_not_empty check (char_length(trim(event_type)) > 0),
  constraint game_events_payload_object check (jsonb_typeof(payload) = 'object')
);

comment on table public.game_events is
  'Append-only match events. Clients cannot insert. Do not store hidden coordinates in payload.';

create index game_events_game_created_idx on public.game_events (game_id, created_at desc);
create index game_events_game_type_idx on public.game_events (game_id, event_type);
