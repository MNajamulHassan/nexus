-- Kick is remove-only, not a ban: a kicked player can rejoin with the same
-- join code. A real ban (permanently blocking rejoin) could be added later
-- as its own separate action, distinct from kick_player. Idempotent: safe
-- to re-run.
--
-- Changes in this migration:
--   a) kick_player: identical to the current function, except the insert
--      into game_kicked_players becomes an upsert
--      (on conflict (game_id, player_id) do update set kicked_at = now()).
--      The row itself still exists afterward so was_kicked keeps driving
--      the "You were removed" lobby notice — only join_game's handling of
--      it changes (see (b)).
--   b) join_game: identical to the current function (including the
--      max_players check and every other line), except: removed the raise
--      that blocked a kicked player's rejoin entirely; instead, right
--      before the existing idempotent already-a-member return, delete that
--      player's game_kicked_players row for this game, so rejoining clears
--      the marker and was_kicked goes back to false for them.
--   c) Every function: security definer, set search_path = public, same
--      signatures as today (create or replace is sufficient — neither
--      signature nor return type changes). EXECUTE revoked from
--      public/anon, granted to authenticated, full signatures in every
--      revoke/grant.

begin;

-- ---------------------------------------------------------------------------
-- (a) kick_player: upsert into game_kicked_players instead of a plain insert.
-- ---------------------------------------------------------------------------
create or replace function public.kick_player(p_game_id uuid, p_player_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_host_id uuid;
  v_status text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select host_id, status
  into v_host_id, v_status
  from public.games
  where id = p_game_id
  for update;

  if v_host_id is null then
    raise exception 'Game not found';
  end if;

  if v_host_id <> v_user_id then
    raise exception 'Only the host can remove players';
  end if;

  if v_status not in ('CREATED', 'LOBBY') then
    raise exception 'Players can only be removed before the match starts';
  end if;

  if p_player_id = v_user_id then
    raise exception 'The host cannot remove themselves';
  end if;

  if not exists (
    select 1 from public.game_players
    where game_id = p_game_id and player_id = p_player_id
  ) then
    raise exception 'That player is not in this lobby';
  end if;

  delete from public.game_players
  where game_id = p_game_id and player_id = p_player_id;

  insert into public.game_kicked_players (game_id, player_id)
  values (p_game_id, p_player_id)
  on conflict (game_id, player_id) do update set kicked_at = now();

  update public.games
  set seeker_player_id = null
  where id = p_game_id and seeker_player_id = p_player_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- (b) join_game: a kicked player can rejoin; rejoining clears their marker.
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

  delete from public.game_kicked_players
  where game_id = v_game.id and player_id = v_user_id;

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
-- (c) Grants. Full signatures; revoke from public/anon, grant to authenticated.
-- ---------------------------------------------------------------------------
revoke execute on function public.kick_player(uuid, uuid) from public, anon;
grant execute on function public.kick_player(uuid, uuid) to authenticated;

revoke execute on function public.join_game(text) from public, anon;
grant execute on function public.join_game(text) to authenticated;

commit;
