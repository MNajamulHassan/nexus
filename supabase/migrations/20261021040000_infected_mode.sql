-- Infected mode: a caught hider joins the seeking team instead of being
-- eliminated. Hide & Seek behaviour is byte-identical to before this
-- migration. Idempotent: safe to re-run.
--
-- Context (see the accompanying report's Step 1 findings):
--   - games.mode already accepts 'infected' (create_core_tables.sql's
--     games_mode_check), and the Dart GameMode enum/GameConfig helpers
--     already round-trip it — Create Game already lets a host pick
--     Infected today, it just behaved identically to hide_and_seek
--     server-side until this migration.
--   - fetch_catch_candidates and fetch_seeker_view already key off
--     `role = 'SEEKER'` for the caller, with no restriction to "the one
--     designated seeker" — confirmed they already work for a newly
--     infected player with zero changes, and that the caller's own row
--     is excluded from what they see (both only ever return role='HIDER'
--     rows, and the caller must be role='SEEKER' to call them at all).
--     Not touched here.
--   - sync_match_state's own "v_active_hiders = 0" branch (reason
--     'all_caught', not mode-aware) is unreachable dead code, pre-existing
--     and unrelated to this migration: both functions take `for update`
--     on the same games row, and zero-active-hiders can only ever be
--     produced by attempt_catch, which always finishes the game itself
--     in the same call. Not touched here.
--
-- Changes in this migration:
--   a) attempt_catch: when games.mode = 'infected', a successful catch
--      sets the caught player's role to 'SEEKER' (status stays 'ACTIVE',
--      caught_at = now()) and records a 'PLAYER_INFECTED' event with the
--      same payload shape PLAYER_CAUGHT uses, instead of eliminating them.
--      hide_and_seek mode is untouched. In both modes, the game still ends
--      when no ACTIVE hiders remain; the finish reason is 'all_infected'
--      for infected, 'all_caught' for hide_and_seek. The fail-closed
--      location checks, the 100m backstop, and the per-seeker cooldown are
--      all unchanged.
--   b) fetch_seeker_location: removed the `limit 1` so a hider sees every
--      current seeker, not just one — required for infected mode, where
--      more than one player can hold role='SEEKER' at once. Same columns,
--      same freshness filter. This breaks the existing Dart parsing
--      (GameRepository.fetchSeekerLocation only read rows.first into a
--      single SeekerSighting?) — fixed in the accompanying Dart changes
--      to return a list.
--   c) start_game: only the "Need at least 2 players" error text changes,
--      from "...to start Hide & Seek" to the mode-neutral "...to start
--      the match". Nothing else in the function changes — the MANUAL
--      seeker-mode logic added by the lobby-management migration is
--      carried over unmodified.
--   d) Every function: security definer, set search_path = public, same
--      signatures and return types as today (create or replace is
--      sufficient). EXECUTE revoked from public/anon, granted to
--      authenticated, full signatures in every revoke/grant.

begin;

-- ---------------------------------------------------------------------------
-- (a) attempt_catch: infect instead of eliminate when games.mode = 'infected'.
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
  -- See the security-hardening migration's header comment for why this
  -- wasn't restructured.
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

  -- Infected: the caught hider joins the seeking team instead of being
  -- eliminated. Hide & Seek: unchanged elimination.
  if v_game.mode = 'infected' then
    update public.game_players
    set role = 'SEEKER', caught_at = v_now
    where game_id = p_game_id and player_id = p_hider_id;

    insert into public.game_events (game_id, player_id, event_type, payload)
    values (p_game_id, p_hider_id, 'PLAYER_INFECTED', jsonb_build_object('player_id', p_hider_id, 'method', 'manual'));
  else
    update public.game_players
    set status = 'ELIMINATED', caught_at = v_now
    where game_id = p_game_id and player_id = p_hider_id;

    insert into public.game_events (game_id, player_id, event_type, payload)
    values (p_game_id, p_hider_id, 'PLAYER_CAUGHT', jsonb_build_object('player_id', p_hider_id, 'method', 'manual'));
  end if;

  select count(*) into v_active_hiders
  from public.game_players
  where game_id = p_game_id and role = 'HIDER' and status = 'ACTIVE';

  if v_active_hiders = 0 then
    update public.games set status = 'FINISHED', ended_at = v_now where id = p_game_id returning * into v_game;
    insert into public.game_events (game_id, event_type, payload)
    values (
      p_game_id,
      'GAME_FINISHED',
      jsonb_build_object(
        'reason',
        case when v_game.mode = 'infected' then 'all_infected' else 'all_caught' end
      )
    );
  end if;

  return v_game;
end;
$$;

-- ---------------------------------------------------------------------------
-- (b) fetch_seeker_location: return every current seeker, not just one.
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
    and pl.server_received_at >= now() - interval '30 seconds';
end;
$$;

-- ---------------------------------------------------------------------------
-- (c) start_game: mode-neutral error text only.
-- ---------------------------------------------------------------------------
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
    raise exception 'Need at least 2 players to start the match';
  end if;

  if v_game.seeker_mode = 'MANUAL' then
    if v_game.seeker_player_id is null or not exists (
      select 1 from public.game_players
      where game_id = p_game_id and player_id = v_game.seeker_player_id
    ) then
      raise exception 'Choose a seeker before starting';
    end if;
    v_seeker_id := v_game.seeker_player_id;
  else
    select player_id into v_seeker_id
    from public.game_players
    where game_id = p_game_id
    order by random()
    limit 1;
  end if;

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

-- ---------------------------------------------------------------------------
-- (d) Grants. Full signatures; revoke from public/anon, grant to authenticated.
-- ---------------------------------------------------------------------------
revoke execute on function public.attempt_catch(uuid, uuid) from public, anon;
grant execute on function public.attempt_catch(uuid, uuid) to authenticated;

revoke execute on function public.fetch_seeker_location(uuid) from public, anon;
grant execute on function public.fetch_seeker_location(uuid) to authenticated;

revoke execute on function public.start_game(uuid) from public, anon;
grant execute on function public.start_game(uuid) to authenticated;

commit;
