-- The seeker should be able to actually see a hider once close enough to
-- catch them, not just get a distance number. Return coordinates for
-- in-range hiders too — hider privacy is still preserved for anyone
-- outside catch range (fetch_seeker_view's reveal-window gate is
-- unchanged; this only applies to hiders already within the catch
-- radius, who you could reach out and touch).
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
    ),
    pl.latitude,
    pl.longitude
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

revoke all on function public.fetch_catch_candidates(uuid) from public;
grant execute on function public.fetch_catch_candidates(uuid) to authenticated;
