-- Authoritative writes. Clients call these instead of inserting games,
-- membership, zones, or events directly.

create or replace function public.generate_join_code()
returns text
language plpgsql
as $$
declare
  v_code text;
begin
  loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    exit when not exists (
      select 1 from public.games where join_code = v_code
    );
  end loop;
  return v_code;
end;
$$;

revoke all on function public.generate_join_code() from public;

create or replace function public.create_game(
  p_mode text,
  p_hiding_duration_seconds integer,
  p_match_duration_seconds integer,
  p_catch_radius_meters double precision,
  p_reveal_interval_seconds integer,
  p_reveal_duration_seconds integer,
  p_taunts_enabled boolean default true,
  p_settings jsonb default '{}'::jsonb
)
returns public.games
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

  if not exists (select 1 from public.profiles where id = v_user_id) then
    raise exception 'Profile required';
  end if;

  if p_mode not in ('hide_and_seek', 'infected') then
    raise exception 'Invalid game mode';
  end if;

  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    raise exception 'settings must be a JSON object';
  end if;

  insert into public.games (
    host_id,
    join_code,
    mode,
    status,
    hiding_duration_seconds,
    match_duration_seconds,
    catch_radius_meters,
    reveal_interval_seconds,
    reveal_duration_seconds,
    taunts_enabled,
    settings
  )
  values (
    v_user_id,
    public.generate_join_code(),
    p_mode,
    'LOBBY',
    p_hiding_duration_seconds,
    p_match_duration_seconds,
    p_catch_radius_meters,
    p_reveal_interval_seconds,
    p_reveal_duration_seconds,
    coalesce(p_taunts_enabled, true),
    p_settings
  )
  returning * into v_game;

  insert into public.game_players (game_id, player_id, status)
  values (v_game.id, v_user_id, 'JOINED');

  return v_game;
end;
$$;

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

  insert into public.game_players (game_id, player_id, status)
  values (v_game.id, v_user_id, 'JOINED')
  returning * into v_player;

  return v_player;
end;
$$;

create or replace function public.leave_game(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_status text;
  v_host_id uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select g.status, g.host_id
  into v_status, v_host_id
  from public.games g
  where g.id = p_game_id;

  if v_status is null then
    raise exception 'Game not found';
  end if;

  if v_host_id = v_user_id then
    raise exception 'Host cannot leave; end the game instead';
  end if;

  if v_status not in ('CREATED', 'LOBBY') then
    raise exception 'Cannot leave after the match has started';
  end if;

  delete from public.game_players
  where game_id = p_game_id
    and player_id = v_user_id;
end;
$$;

create or replace function public.set_player_ready(
  p_game_id uuid,
  p_ready boolean default true
)
returns public.game_players
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game_status text;
  v_player public.game_players;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select status
  into v_game_status
  from public.games
  where id = p_game_id;

  if v_game_status is null then
    raise exception 'Game not found';
  end if;

  if v_game_status not in ('CREATED', 'LOBBY') then
    raise exception 'Ready state can only change in lobby';
  end if;

  update public.game_players
  set status = case when p_ready then 'READY' else 'JOINED' end
  where game_id = p_game_id
    and player_id = v_user_id
    and status in ('JOINED', 'READY')
  returning * into v_player;

  if v_player.id is null then
    raise exception 'Player is not in this lobby';
  end if;

  return v_player;
end;
$$;

create or replace function public.replace_game_zones(
  p_game_id uuid,
  p_zones jsonb
)
returns setof public.game_zones
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_status text;
  v_host_id uuid;
  v_zone jsonb;
  v_type text;
  v_playable geography;
  v_geom geography;
  v_playable_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select status, host_id
  into v_status, v_host_id
  from public.games
  where id = p_game_id;

  if v_host_id is null then
    raise exception 'Game not found';
  end if;

  if v_host_id <> v_user_id then
    raise exception 'Only the host can set zones';
  end if;

  if v_status not in ('CREATED', 'LOBBY') then
    raise exception 'Zones can only be changed before the match starts';
  end if;

  if p_zones is null or jsonb_typeof(p_zones) <> 'array' then
    raise exception 'zones must be a JSON array';
  end if;

  delete from public.game_zones
  where game_id = p_game_id;

  for v_zone in select value from jsonb_array_elements(p_zones)
  loop
    v_type := v_zone ->> 'type';

    if v_type is null then
      raise exception 'Each zone needs a type';
    end if;

    if coalesce(v_zone -> 'geometry' ->> 'type', '') <> 'Polygon' then
      raise exception 'Zone geometry must be a GeoJSON Polygon';
    end if;

    begin
      v_geom := st_setsrid(
        st_geomfromgeojson((v_zone -> 'geometry')::text),
        4326
      )::geography;
    exception
      when others then
        raise exception 'Invalid zone geometry';
    end;

    if not st_isvalid(v_geom::geometry) then
      raise exception 'Zone geometry is not a valid polygon';
    end if;

    if v_type = 'PLAYABLE' then
      v_playable_count := v_playable_count + 1;
      v_playable := v_geom;
    end if;

    insert into public.game_zones (game_id, type, name, geometry, rules)
    values (
      p_game_id,
      v_type,
      v_zone ->> 'name',
      v_geom,
      coalesce(v_zone -> 'rules', '{}'::jsonb)
    );
  end loop;

  if v_playable_count <> 1 then
    raise exception 'Exactly one PLAYABLE zone is required';
  end if;

  if exists (
    select 1
    from public.game_zones z
    where z.game_id = p_game_id
      and z.type = 'RESTRICTED'
      and not st_covers(v_playable, z.geometry)
  ) then
    raise exception 'Restricted zones must sit inside the playable area';
  end if;

  return query
  select *
  from public.game_zones
  where game_id = p_game_id;
end;
$$;

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
  v_row public.player_locations;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if not public.is_game_member(p_game_id) then
    raise exception 'Not a member of this game';
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
    now()
  )
  on conflict (game_id, player_id) do update
    set latitude = excluded.latitude,
        longitude = excluded.longitude,
        accuracy_meters = excluded.accuracy_meters,
        heading = excluded.heading,
        speed = excluded.speed,
        client_timestamp = excluded.client_timestamp,
        server_received_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

-- Service-role / future Edge Functions only. Clients must not insert events.
create or replace function public.record_game_event(
  p_game_id uuid,
  p_player_id uuid,
  p_event_type text,
  p_payload jsonb default '{}'::jsonb
)
returns public.game_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.game_events;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Forbidden';
  end if;

  insert into public.game_events (game_id, player_id, event_type, payload)
  values (
    p_game_id,
    p_player_id,
    p_event_type,
    coalesce(p_payload, '{}'::jsonb)
  )
  returning * into v_event;

  return v_event;
end;
$$;

revoke all on function public.create_game(
  text, integer, integer, double precision, integer, integer, boolean, jsonb
) from public;
revoke all on function public.join_game(text) from public;
revoke all on function public.leave_game(uuid) from public;
revoke all on function public.set_player_ready(uuid, boolean) from public;
revoke all on function public.replace_game_zones(uuid, jsonb) from public;
revoke all on function public.upsert_player_location(
  uuid, double precision, double precision, double precision,
  double precision, double precision, timestamptz
) from public;
revoke all on function public.record_game_event(uuid, uuid, text, jsonb) from public;

grant execute on function public.create_game(
  text, integer, integer, double precision, integer, integer, boolean, jsonb
) to authenticated;
grant execute on function public.join_game(text) to authenticated;
grant execute on function public.leave_game(uuid) to authenticated;
grant execute on function public.set_player_ready(uuid, boolean) to authenticated;
grant execute on function public.replace_game_zones(uuid, jsonb) to authenticated;
grant execute on function public.upsert_player_location(
  uuid, double precision, double precision, double precision,
  double precision, double precision, timestamptz
) to authenticated;

grant execute on function public.record_game_event(uuid, uuid, text, jsonb)
  to service_role;
