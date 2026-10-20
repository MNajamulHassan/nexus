-- Two fixes from the first real-device test:
-- 1. fetch_catch_candidates ignored the host's configured catch radius and
--    used a hardcoded 15m instead — use games.catch_radius_meters.
-- 2. Hiders had no way to see the seeker at all. Add an always-on (while
--    ACTIVE) seeker location feed for hiders — this is the opposite of
--    fetch_seeker_view (which gates hider visibility to reveal windows for
--    the seeker); the seeker is never hidden from hiders.

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
      v_game.catch_radius_meters
    );
end;
$$;

-- Any game member may call this; it only ever returns the seeker, and only
-- while the hunt is live. Hiders use it to always know where the seeker is.
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
    and pl.client_timestamp >= now() - interval '30 seconds'
  limit 1;
end;
$$;

revoke all on function public.fetch_seeker_location(uuid) from public;
grant execute on function public.fetch_seeker_location(uuid) to authenticated;
