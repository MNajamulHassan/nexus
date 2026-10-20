-- fetch_seeker_view's RETURNS TABLE declares an output column named
-- player_id, which PL/pgSQL turns into an implicit function-scoped
-- variable of that name. The exists() check below referenced player_id
-- unqualified, colliding with that variable: "column reference player_id
-- is ambiguous". Qualify it against game_players explicitly.
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
    and gp.status = 'ACTIVE';
end;
$$;
