-- Replace automatic GPS-radius catching with a seeker-triggered, manual
-- catch: the seeker must hold a catch button for a client-enforced duration
-- while a hider is server-confirmed to be close. The server still decides
-- whether a catch is valid; it just no longer decides *when* one happens.

-- Lazy state-machine tick: phase transition and match end only. Catch
-- detection moved to attempt_catch(), triggered by the seeker's client.
create or replace function public.sync_match_state(p_game_id uuid)
returns public.games
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games;
  v_active_hiders integer;
  v_now timestamptz := now();
  v_active_at timestamptz;
  v_end_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if not public.is_game_member(p_game_id) then
    raise exception 'Not a member of this game';
  end if;

  select * into v_game from public.games where id = p_game_id for update;
  if v_game.id is null then
    raise exception 'Game not found';
  end if;

  if v_game.status not in ('HIDING_PHASE', 'ACTIVE') then
    return v_game;
  end if;

  v_active_at := v_game.started_at + make_interval(secs => v_game.hiding_duration_seconds);
  v_end_at := v_active_at + make_interval(secs => v_game.match_duration_seconds);

  if v_game.status = 'HIDING_PHASE' and v_now >= v_active_at then
    update public.games set status = 'ACTIVE' where id = p_game_id returning * into v_game;
    insert into public.game_events (game_id, event_type) values (p_game_id, 'HUNT_STARTED');
  end if;

  if v_game.status = 'ACTIVE' then
    select count(*) into v_active_hiders
    from public.game_players
    where game_id = p_game_id and role = 'HIDER' and status = 'ACTIVE';

    if v_active_hiders = 0 then
      update public.games set status = 'FINISHED', ended_at = v_now where id = p_game_id returning * into v_game;
      insert into public.game_events (game_id, event_type, payload)
      values (p_game_id, 'GAME_FINISHED', jsonb_build_object('reason', 'all_caught'));
    elsif v_now >= v_end_at then
      update public.games set status = 'FINISHED', ended_at = v_now where id = p_game_id returning * into v_game;
      insert into public.game_events (game_id, event_type, payload)
      values (p_game_id, 'GAME_FINISHED', jsonb_build_object('reason', 'timeout'));
    end if;
  end if;

  return v_game;
end;
$$;

-- Seeker-only: active hiders within catch range of the seeker's freshest
-- location. Returns an id + distance only — never raw hider coordinates,
-- preserving the existing reveal-window privacy model.
create or replace function public.fetch_catch_candidates(p_game_id uuid)
returns table (hider_id uuid, distance_meters double precision)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games;
  v_seeker record;
  v_candidate_radius constant double precision := 15;
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

  select pl.latitude, pl.longitude, pl.client_timestamp
    into v_seeker
    from public.player_locations pl
    where pl.game_id = p_game_id and pl.player_id = v_user_id;

  if v_seeker.latitude is null or v_seeker.client_timestamp < now() - interval '30 seconds' then
    return;
  end if;

  return query
  select gp.player_id,
    st_distance(
      pl.location,
      st_setsrid(st_makepoint(v_seeker.longitude, v_seeker.latitude), 4326)::geography
    )
  from public.game_players gp
  join public.player_locations pl
    on pl.game_id = gp.game_id and pl.player_id = gp.player_id
  where gp.game_id = p_game_id
    and gp.role = 'HIDER'
    and gp.status = 'ACTIVE'
    and pl.client_timestamp >= now() - interval '30 seconds'
    and st_dwithin(
      pl.location,
      st_setsrid(st_makepoint(v_seeker.longitude, v_seeker.latitude), 4326)::geography,
      v_candidate_radius
    );
end;
$$;

-- Seeker-triggered catch. Validates role/state server-side; applies a loose
-- GPS backstop (100m) since true proximity can only be known on-device
-- (GPS today, Bluetooth later) and can't be re-verified by the server.
create or replace function public.attempt_catch(p_game_id uuid, p_hider_id uuid)
returns public.games
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games;
  v_seeker_loc record;
  v_hider_loc record;
  v_distance double precision;
  v_active_hiders integer;
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

  select latitude, longitude into v_seeker_loc
    from public.player_locations where game_id = p_game_id and player_id = v_user_id;
  select latitude, longitude into v_hider_loc
    from public.player_locations where game_id = p_game_id and player_id = p_hider_id;

  if v_seeker_loc.latitude is not null and v_hider_loc.latitude is not null then
    v_distance := st_distance(
      st_setsrid(st_makepoint(v_seeker_loc.longitude, v_seeker_loc.latitude), 4326)::geography,
      st_setsrid(st_makepoint(v_hider_loc.longitude, v_hider_loc.latitude), 4326)::geography
    );
    if v_distance > 100 then
      raise exception 'Players are too far apart for a catch';
    end if;
  end if;

  update public.game_players
  set status = 'ELIMINATED', caught_at = now()
  where game_id = p_game_id and player_id = p_hider_id;

  insert into public.game_events (game_id, player_id, event_type, payload)
  values (p_game_id, p_hider_id, 'PLAYER_CAUGHT', jsonb_build_object('player_id', p_hider_id, 'method', 'manual'));

  select count(*) into v_active_hiders
  from public.game_players
  where game_id = p_game_id and role = 'HIDER' and status = 'ACTIVE';

  if v_active_hiders = 0 then
    update public.games set status = 'FINISHED', ended_at = now() where id = p_game_id returning * into v_game;
    insert into public.game_events (game_id, event_type, payload)
    values (p_game_id, 'GAME_FINISHED', jsonb_build_object('reason', 'all_caught'));
  end if;

  return v_game;
end;
$$;

revoke all on function public.fetch_catch_candidates(uuid) from public;
revoke all on function public.attempt_catch(uuid, uuid) from public;

grant execute on function public.fetch_catch_candidates(uuid) to authenticated;
grant execute on function public.attempt_catch(uuid, uuid) to authenticated;
