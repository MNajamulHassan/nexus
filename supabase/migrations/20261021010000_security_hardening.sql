-- Security hardening pass. Threat model: a friend modifying their own
-- client, not a determined attacker. Idempotent: safe to re-run.
--
-- Context this migration is responding to (see security-audit findings):
--   - Supabase's default privileges grant EXECUTE on new `public` functions
--     directly to anon/authenticated/service_role, independent of PUBLIC.
--     Every earlier `revoke all ... from public` therefore did NOT remove
--     anon's ability to call these functions directly.
--   - `grant select, insert, update on table public.player_locations to
--     authenticated` (20261004150200_rls_helpers_and_policies.sql:108),
--     combined with the player_locations_insert_own/update_own RLS
--     policies, lets a client write that table directly via PostgREST,
--     bypassing upsert_player_location and all its checks entirely.
--
-- Changes in this migration:
--   a) Explicitly revoke EXECUTE from anon (and public) on every function
--      the app calls, re-affirming authenticated's grant. Internal-only
--      functions (record_game_event, handle_new_user,
--      player_locations_guard) are revoked from authenticated too;
--      record_game_event keeps service_role.
--   b) Revoke direct INSERT/UPDATE/DELETE on player_locations from
--      authenticated and anon, so the only write path is
--      upsert_player_location (a SECURITY DEFINER function, unaffected by
--      the caller's own table grants). RLS policies are left in place as
--      a harmless second layer in case a future grant is added back.
--   c) upsert_player_location gains plausibility checks: reject on
--      implausible implied speed (>12 m/s, jitter-adjusted by subtracting
--      both fixes' accuracy radii before dividing) vs. the previous fix
--      (skipped if that previous fix is itself >60s old), reject missing
--      or >100m accuracy, silently drop (return the previous row
--      unchanged, no write) a client_timestamp older than the stored
--      previous one. server_received_at is always server `now()` — the
--      existing player_locations_guard trigger already enforces this
--      independently.
--   d) Freshness checks in fetch_catch_candidates and
--      fetch_seeker_location now key off server_received_at, not the
--      client-supplied client_timestamp. fetch_seeker_view gains the same
--      30s freshness filter (it previously had none).
--   e) attempt_catch now fails closed: a missing or >30s-stale location
--      for either party raises an exception instead of silently skipping
--      the distance check. Adds a 2-second per-seeker cooldown via a new
--      game_players.last_catch_attempt_at column (not explicitly
--      requested by name, but required to persist cooldown state across
--      calls — flagged in the accompanying report).
--      KNOWN LIMITATION (see report): attempt_catch returns public.games
--      (not void) and signals failure only by raising, so Postgres rolls
--      back the whole call — including the cooldown write below —
--      whenever a later check in the same call raises. The cooldown is
--      therefore durable across a *successful* catch but not across a
--      *failed* attempt. A durable fix would require changing how
--      failure is signaled (the return contract), which was out of
--      scope for this pass.
--   f) fetch_catch_candidates is rate-limited to one real scan per 2
--      seconds per caller via a new game_players.last_catch_scan_at
--      column; a call inside the window returns an empty result rather
--      than erroring, since this is a passive polling query.
--   g) join_game enforces a player cap via a new games.max_players column
--      (default 12).
--   h) Every recreated function keeps its existing `security definer` and
--      `set search_path = public`. No PostGIS function is touched.
--
-- Follow-up verification pass on this migration (no functional changes
-- unless noted — see the inline comments at each site):
--   a) attempt_catch's cooldown write is NOT durable on a failed attempt
--      (Postgres rolls back the whole call on a later raise). Left
--      as-is; see the KNOWN LIMITATION note above item (e) and the
--      inline comment at the cooldown UPDATE.
--   b) fetch_catch_candidates's last_catch_scan_at UPDATE is only ever
--      followed by plain `return`/`return query` (no later raise in this
--      function) — confirmed correct, no change needed.
--   c) upsert_player_location's out-of-order-timestamp check now returns
--      the existing row unchanged (`return v_previous;`) instead of
--      raising. This is valid because the function returns
--      public.player_locations, a composite type — returning an existing
--      row of that type is an ordinary early return, not a contract
--      change. Fixed; see the inline comment at that check.
--   d) upsert_player_location's accuracy check (null or >100m rejected)
--      confirmed correct as originally written, no change needed.

begin;

-- ---------------------------------------------------------------------------
-- New columns (added before the functions that reference them)
-- ---------------------------------------------------------------------------
alter table public.games
  add column if not exists max_players integer not null default 12;

alter table public.game_players
  add column if not exists last_catch_scan_at timestamptz;

alter table public.game_players
  add column if not exists last_catch_attempt_at timestamptz;

-- ---------------------------------------------------------------------------
-- (b) Close the direct-write bypass on player_locations.
-- SELECT stays as-is (own-row-only via RLS; unused by the app today but not
-- part of what was asked to change).
-- ---------------------------------------------------------------------------
revoke insert, update, delete on table public.player_locations
  from authenticated, anon;

-- ---------------------------------------------------------------------------
-- (c) upsert_player_location: plausibility checks.
-- ---------------------------------------------------------------------------
create or replace function public.upsert_player_location(
  p_game_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_heading double precision default null,
  p_speed double precision default null,
  p_client_timestamp timestamptz default now()
)
returns public.player_locations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_previous public.player_locations;
  v_row public.player_locations;
  v_now timestamptz := now();
  v_elapsed_seconds double precision;
  v_distance_meters double precision;
  v_implied_speed double precision;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if not public.is_game_member(p_game_id) then
    raise exception 'Not a member of this game';
  end if;

  if p_accuracy_meters is null or p_accuracy_meters > 100 then
    raise exception 'Location accuracy is missing or worse than 100m';
  end if;

  select * into v_previous
  from public.player_locations
  where game_id = p_game_id and player_id = v_user_id;

  if v_previous.player_id is not null then
    -- Out-of-order write: drop silently by returning the existing row
    -- unchanged. `return v_previous;` is valid here because this function
    -- returns public.player_locations (a composite type, not void/SETOF) —
    -- returning an existing row of that same type is an ordinary early
    -- return, not a contract change.
    if p_client_timestamp < v_previous.client_timestamp then
      return v_previous;
    end if;

    -- Gap measured on the server clock, not the client-supplied one.
    v_elapsed_seconds := extract(epoch from (v_now - v_previous.server_received_at));

    if v_elapsed_seconds > 0 and v_elapsed_seconds <= 60 then
      v_distance_meters := st_distance(
        st_setsrid(st_makepoint(p_longitude, p_latitude), 4326)::geography,
        v_previous.location
      );
      -- Subtract both fixes' reported accuracy radii before dividing, so
      -- two GPS fixes that are merely jittering within their own error
      -- margins aren't read as implausible movement.
      v_implied_speed := greatest(0, v_distance_meters - v_previous.accuracy_meters - p_accuracy_meters)
        / v_elapsed_seconds;

      if v_implied_speed > 12 then
        raise exception 'Location implies an implausible speed of % m/s (limit 12 m/s)',
          round(v_implied_speed::numeric, 1);
      end if;
    end if;
  end if;

  insert into public.player_locations (
    game_id,
    player_id,
    latitude,
    longitude,
    accuracy_meters,
    heading,
    speed,
    client_timestamp,
    server_received_at
  )
  values (
    p_game_id,
    v_user_id,
    p_latitude,
    p_longitude,
    p_accuracy_meters,
    p_heading,
    p_speed,
    p_client_timestamp,
    v_now
  )
  on conflict (game_id, player_id) do update
    set latitude = excluded.latitude,
        longitude = excluded.longitude,
        accuracy_meters = excluded.accuracy_meters,
        heading = excluded.heading,
        speed = excluded.speed,
        client_timestamp = excluded.client_timestamp,
        server_received_at = v_now
  returning * into v_row;

  return v_row;
end;
$$;

-- ---------------------------------------------------------------------------
-- (d) + (f) fetch_catch_candidates: server-clock freshness, exclude
-- eliminated hiders (unchanged, already present), 2s per-caller scan
-- throttle (empty result, not an exception).
-- ---------------------------------------------------------------------------
drop function if exists public.fetch_catch_candidates(uuid);

create function public.fetch_catch_candidates(p_game_id uuid)
returns table (
  hider_id uuid,
  distance_meters double precision,
  latitude double precision,
  longitude double precision
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games;
  v_seeker record;
  v_last_scan timestamptz;
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_game from public.games where id = p_game_id;
  if v_game.id is null then
    raise exception 'Game not found';
  end if;

  if not exists (
    select 1 from public.game_players
    where game_id = p_game_id and player_id = v_user_id and role = 'SEEKER'
  ) then
    raise exception 'Only the seeker can view this';
  end if;

  if v_game.status <> 'ACTIVE' then
    return;
  end if;

  select last_catch_scan_at into v_last_scan
  from public.game_players
  where game_id = p_game_id and player_id = v_user_id;

  if v_last_scan is not null and v_now - v_last_scan < interval '2 seconds' then
    return; -- Rate-limited: empty result, not an error.
  end if;

  update public.game_players
  set last_catch_scan_at = v_now
  where game_id = p_game_id and player_id = v_user_id;

  select pl.latitude, pl.longitude, pl.server_received_at
    into v_seeker
    from public.player_locations pl
    where pl.game_id = p_game_id and pl.player_id = v_user_id;

  if v_seeker.latitude is null or v_seeker.server_received_at < v_now - interval '30 seconds' then
    return;
  end if;

  return query
  select gp.player_id,
    st_distance(
      pl.location,
      st_setsrid(st_makepoint(v_seeker.longitude, v_seeker.latitude), 4326)::geography
    ),
    pl.latitude,
    pl.longitude
  from public.game_players gp
  join public.player_locations pl
    on pl.game_id = gp.game_id and pl.player_id = gp.player_id
  where gp.game_id = p_game_id
    and gp.role = 'HIDER'
    and gp.status = 'ACTIVE'
    and pl.server_received_at >= v_now - interval '30 seconds'
    and st_dwithin(
      pl.location,
      st_setsrid(st_makepoint(v_seeker.longitude, v_seeker.latitude), 4326)::geography,
      v_game.catch_radius_meters
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- (d) fetch_seeker_location: server-clock freshness.
-- ---------------------------------------------------------------------------
create or replace function public.fetch_seeker_location(p_game_id uuid)
returns table (
  seeker_id uuid,
  latitude double precision,
  longitude double precision,
  client_timestamp timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if not public.is_game_member(p_game_id) then
    raise exception 'Not a member of this game';
  end if;

  select * into v_game from public.games where id = p_game_id;
  if v_game.id is null then
    raise exception 'Game not found';
  end if;

  if v_game.status <> 'ACTIVE' then
    return;
  end if;

  return query
  select gp.player_id, pl.latitude, pl.longitude, pl.client_timestamp
  from public.game_players gp
  join public.player_locations pl
    on pl.game_id = gp.game_id and pl.player_id = gp.player_id
  where gp.game_id = p_game_id
    and gp.role = 'SEEKER'
    and pl.server_received_at >= now() - interval '30 seconds'
  limit 1;
end;
$$;

-- ---------------------------------------------------------------------------
-- (d) fetch_seeker_view: add the 30s freshness filter it previously lacked.
-- ---------------------------------------------------------------------------
create or replace function public.fetch_seeker_view(p_game_id uuid)
returns table (
  player_id uuid,
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision,
  client_timestamp timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games;
  v_is_seeker boolean;
  v_active_at timestamptz;
  v_elapsed_active double precision;
  v_reveal_active boolean;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_game from public.games where id = p_game_id;
  if v_game.id is null then
    raise exception 'Game not found';
  end if;

  select exists (
    select 1 from public.game_players gp
    where gp.game_id = p_game_id and gp.player_id = v_user_id and gp.role = 'SEEKER'
  ) into v_is_seeker;

  if not v_is_seeker then
    raise exception 'Only the seeker can view this';
  end if;

  if v_game.status <> 'ACTIVE' then
    return;
  end if;

  v_active_at := v_game.started_at + make_interval(secs => v_game.hiding_duration_seconds);
  v_elapsed_active := extract(epoch from (now() - v_active_at));
  if v_elapsed_active < 0 then
    return;
  end if;

  v_reveal_active := mod(v_elapsed_active::numeric, v_game.reveal_interval_seconds::numeric)
    < v_game.reveal_duration_seconds;

  if not v_reveal_active then
    return;
  end if;

  return query
  select pl.player_id, pl.latitude, pl.longitude, pl.accuracy_meters, pl.client_timestamp
  from public.game_players gp
  join public.player_locations pl
    on pl.game_id = gp.game_id and pl.player_id = gp.player_id
  where gp.game_id = p_game_id
    and gp.role = 'HIDER'
    and gp.status = 'ACTIVE'
    and pl.server_received_at >= now() - interval '30 seconds';
end;
$$;

-- ---------------------------------------------------------------------------
-- (e) attempt_catch: fail closed on missing/stale locations, keep the 100m
-- check, add a 2s per-seeker cooldown.
-- ---------------------------------------------------------------------------
create or replace function public.attempt_catch(p_game_id uuid, p_hider_id uuid)
returns public.games
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games;
  v_seeker_loc public.player_locations;
  v_hider_loc public.player_locations;
  v_distance double precision;
  v_active_hiders integer;
  v_now timestamptz := now();
  v_last_attempt timestamptz;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_game from public.games where id = p_game_id for update;
  if v_game.id is null then
    raise exception 'Game not found';
  end if;
  if v_game.status <> 'ACTIVE' then
    raise exception 'Match is not active';
  end if;

  if not exists (
    select 1 from public.game_players
    where game_id = p_game_id and player_id = v_user_id and role = 'SEEKER' and status = 'ACTIVE'
  ) then
    raise exception 'Only the active seeker can catch';
  end if;

  if not exists (
    select 1 from public.game_players
    where game_id = p_game_id and player_id = p_hider_id and role = 'HIDER' and status = 'ACTIVE'
  ) then
    raise exception 'Target is not an active hider';
  end if;

  -- Per-seeker cooldown. NOTE: this write is only durable when the call
  -- goes on to succeed — if any check below raises, Postgres rolls back
  -- this UPDATE along with everything else in this invocation, so the
  -- cooldown does not actually block a tight loop of *failing* attempts.
  -- See the migration's header comment for why this wasn't restructured.
  select last_catch_attempt_at into v_last_attempt
  from public.game_players
  where game_id = p_game_id and player_id = v_user_id;

  if v_last_attempt is not null and v_now - v_last_attempt < interval '2 seconds' then
    raise exception 'Catch attempts are rate-limited; wait a moment and try again';
  end if;

  update public.game_players
  set last_catch_attempt_at = v_now
  where game_id = p_game_id and player_id = v_user_id;

  select * into v_seeker_loc
    from public.player_locations where game_id = p_game_id and player_id = v_user_id;
  select * into v_hider_loc
    from public.player_locations where game_id = p_game_id and player_id = p_hider_id;

  -- Fail closed: a missing or stale fix for either party blocks the catch
  -- instead of silently skipping the distance check.
  if v_seeker_loc.player_id is null or v_seeker_loc.server_received_at < v_now - interval '30 seconds' then
    raise exception 'Your location is missing or too old to catch right now';
  end if;
  if v_hider_loc.player_id is null or v_hider_loc.server_received_at < v_now - interval '30 seconds' then
    raise exception 'That player''s location is missing or too old to catch right now';
  end if;

  v_distance := st_distance(
    st_setsrid(st_makepoint(v_seeker_loc.longitude, v_seeker_loc.latitude), 4326)::geography,
    st_setsrid(st_makepoint(v_hider_loc.longitude, v_hider_loc.latitude), 4326)::geography
  );
  if v_distance > 100 then
    raise exception 'Players are too far apart for a catch';
  end if;

  update public.game_players
  set status = 'ELIMINATED', caught_at = v_now
  where game_id = p_game_id and player_id = p_hider_id;

  insert into public.game_events (game_id, player_id, event_type, payload)
  values (p_game_id, p_hider_id, 'PLAYER_CAUGHT', jsonb_build_object('player_id', p_hider_id, 'method', 'manual'));

  select count(*) into v_active_hiders
  from public.game_players
  where game_id = p_game_id and role = 'HIDER' and status = 'ACTIVE';

  if v_active_hiders = 0 then
    update public.games set status = 'FINISHED', ended_at = v_now where id = p_game_id returning * into v_game;
    insert into public.game_events (game_id, event_type, payload)
    values (p_game_id, 'GAME_FINISHED', jsonb_build_object('reason', 'all_caught'));
  end if;

  return v_game;
end;
$$;

-- ---------------------------------------------------------------------------
-- (g) join_game: enforce games.max_players.
-- ---------------------------------------------------------------------------
create or replace function public.join_game(p_join_code text)
returns public.game_players
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games;
  v_player public.game_players;
  v_player_count integer;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (select 1 from public.profiles where id = v_user_id) then
    raise exception 'Profile required';
  end if;

  select *
  into v_game
  from public.games
  where join_code = upper(trim(p_join_code));

  if v_game.id is null then
    raise exception 'Game not found';
  end if;

  if v_game.status not in ('CREATED', 'LOBBY') then
    raise exception 'Game is not joinable';
  end if;

  select *
  into v_player
  from public.game_players
  where game_id = v_game.id
    and player_id = v_user_id;

  if v_player.id is not null then
    return v_player;
  end if;

  select count(*) into v_player_count
  from public.game_players
  where game_id = v_game.id;

  if v_player_count >= v_game.max_players then
    raise exception 'This lobby is full';
  end if;

  insert into public.game_players (game_id, player_id, status)
  values (v_game.id, v_user_id, 'JOINED')
  returning * into v_player;

  return v_player;
end;
$$;

-- ---------------------------------------------------------------------------
-- (a) Grants: app-facing functions keep authenticated, lose anon/public.
-- Do not touch PostGIS functions.
-- ---------------------------------------------------------------------------
revoke execute on function public.attempt_catch(uuid, uuid) from public, anon;
grant execute on function public.attempt_catch(uuid, uuid) to authenticated;

revoke execute on function public.cancel_lobby(uuid) from public, anon;
grant execute on function public.cancel_lobby(uuid) to authenticated;

revoke execute on function public.create_game(
  text, integer, integer, double precision, integer, integer, boolean, jsonb
) from public, anon;
grant execute on function public.create_game(
  text, integer, integer, double precision, integer, integer, boolean, jsonb
) to authenticated;

revoke execute on function public.fetch_catch_candidates(uuid) from public, anon;
grant execute on function public.fetch_catch_candidates(uuid) to authenticated;

revoke execute on function public.fetch_game_zones(uuid) from public, anon;
grant execute on function public.fetch_game_zones(uuid) to authenticated;

revoke execute on function public.fetch_seeker_location(uuid) from public, anon;
grant execute on function public.fetch_seeker_location(uuid) to authenticated;

revoke execute on function public.fetch_seeker_view(uuid) from public, anon;
grant execute on function public.fetch_seeker_view(uuid) to authenticated;

revoke execute on function public.join_game(text) from public, anon;
grant execute on function public.join_game(text) to authenticated;

revoke execute on function public.leave_game(uuid) from public, anon;
grant execute on function public.leave_game(uuid) to authenticated;

revoke execute on function public.replace_game_zones(uuid, jsonb) from public, anon;
grant execute on function public.replace_game_zones(uuid, jsonb) to authenticated;

revoke execute on function public.set_player_ready(uuid, boolean) from public, anon;
grant execute on function public.set_player_ready(uuid, boolean) to authenticated;

revoke execute on function public.start_game(uuid) from public, anon;
grant execute on function public.start_game(uuid) to authenticated;

revoke execute on function public.sync_match_state(uuid) from public, anon;
grant execute on function public.sync_match_state(uuid) to authenticated;

revoke execute on function public.upsert_player_location(
  uuid, double precision, double precision, double precision,
  double precision, double precision, timestamptz
) from public, anon;
grant execute on function public.upsert_player_location(
  uuid, double precision, double precision, double precision,
  double precision, double precision, timestamptz
) to authenticated;

revoke execute on function public.generate_join_code() from public, anon;
grant execute on function public.generate_join_code() to authenticated;

revoke execute on function public.is_game_host(uuid) from public, anon;
grant execute on function public.is_game_host(uuid) to authenticated;

revoke execute on function public.is_game_member(uuid) from public, anon;
grant execute on function public.is_game_member(uuid) to authenticated;

-- Internal-only: not called by the client at all. Lock down fully.
revoke execute on function public.record_game_event(uuid, uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.record_game_event(uuid, uuid, text, jsonb)
  to service_role;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

revoke execute on function public.player_locations_guard() from public, anon, authenticated;

commit;
