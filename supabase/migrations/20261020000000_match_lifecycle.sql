-- Hide & Seek match lifecycle: start, phase/catch tick, seeker reveal view,
-- and zone readback. Clients never decide catches or roles themselves.

create or replace function public.start_game(p_game_id uuid)
returns public.games
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games;
  v_seeker_id uuid;
  v_player_count integer;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_game from public.games where id = p_game_id for update;
  if v_game.id is null then
    raise exception 'Game not found';
  end if;

  if v_game.host_id <> v_user_id then
    raise exception 'Only the host can start the match';
  end if;

  if v_game.status not in ('CREATED', 'LOBBY') then
    raise exception 'Game already started';
  end if;

  select count(*) into v_player_count
  from public.game_players
  where game_id = p_game_id;

  if v_player_count < 2 then
    raise exception 'Need at least 2 players to start Hide & Seek';
  end if;

  select player_id into v_seeker_id
  from public.game_players
  where game_id = p_game_id
  order by random()
  limit 1;

  update public.game_players
  set role = case when player_id = v_seeker_id then 'SEEKER' else 'HIDER' end,
      status = 'ACTIVE'
  where game_id = p_game_id;

  update public.games
  set status = 'HIDING_PHASE', started_at = now()
  where id = p_game_id
  returning * into v_game;

  insert into public.game_events (game_id, player_id, event_type, payload)
  values (p_game_id, v_seeker_id, 'GAME_STARTED', jsonb_build_object('seeker_id', v_seeker_id));

  return v_game;
end;
$$;

-- Lazy state-machine tick: phase transition, proximity catch, match end.
-- Safe to call repeatedly from every connected client; purely idempotent
-- given the same wall-clock time and stored locations.
create or replace function public.sync_match_state(p_game_id uuid)
returns public.games
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games;
  v_seeker record;
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
    select gp.player_id, pl.latitude, pl.longitude, pl.client_timestamp
      into v_seeker
      from public.game_players gp
      join public.player_locations pl
        on pl.game_id = gp.game_id and pl.player_id = gp.player_id
      where gp.game_id = p_game_id and gp.role = 'SEEKER'
      limit 1;

    if v_seeker.player_id is not null and v_seeker.client_timestamp >= v_now - interval '30 seconds' then
      update public.game_players hider
      set status = 'ELIMINATED', caught_at = v_now
      from public.player_locations pl
      where hider.game_id = p_game_id
        and hider.role = 'HIDER'
        and hider.status = 'ACTIVE'
        and pl.game_id = hider.game_id
        and pl.player_id = hider.player_id
        and pl.client_timestamp >= v_now - interval '30 seconds'
        and st_dwithin(
          pl.location,
          st_setsrid(st_makepoint(v_seeker.longitude, v_seeker.latitude), 4326)::geography,
          v_game.catch_radius_meters
        );

      insert into public.game_events (game_id, player_id, event_type, payload)
      select p_game_id, hider.player_id, 'PLAYER_CAUGHT', jsonb_build_object('player_id', hider.player_id)
      from public.game_players hider
      where hider.game_id = p_game_id
        and hider.role = 'HIDER'
        and hider.status = 'ELIMINATED'
        and hider.caught_at = v_now;
    end if;

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

-- Seeker-only, reveal-window-only hider location feed. Returns nothing
-- outside an active reveal window, and raises for anyone but the seeker.
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
    select 1 from public.game_players
    where game_id = p_game_id and player_id = v_user_id and role = 'SEEKER'
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
    and gp.status = 'ACTIVE';
end;
$$;

-- GeoJSON readback of a game's zones for members/host (geometry::text would
-- return WKB hex, not something the client can parse).
create or replace function public.fetch_game_zones(p_game_id uuid)
returns table (
  id uuid,
  type text,
  name text,
  geojson text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if not (public.is_game_member(p_game_id) or public.is_game_host(p_game_id)) then
    raise exception 'Not a member of this game';
  end if;

  return query
  select z.id, z.type, z.name, st_asgeojson(z.geometry)
  from public.game_zones z
  where z.game_id = p_game_id;
end;
$$;

revoke all on function public.start_game(uuid) from public;
revoke all on function public.sync_match_state(uuid) from public;
revoke all on function public.fetch_seeker_view(uuid) from public;
revoke all on function public.fetch_game_zones(uuid) from public;

grant execute on function public.start_game(uuid) to authenticated;
grant execute on function public.sync_match_state(uuid) to authenticated;
grant execute on function public.fetch_seeker_view(uuid) to authenticated;
grant execute on function public.fetch_game_zones(uuid) to authenticated;
