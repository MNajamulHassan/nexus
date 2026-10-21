-- Lobby management: host-editable settings (incl. seeker selection) and
-- host-initiated kicks. Idempotent: safe to re-run.
--
-- Context (see the accompanying report's Step 1 findings):
--   - Lobby "live update" is NOT driven by Postgres Changes today: the live
--     DB's supabase_realtime publication is empty, so the onPostgresChanges
--     listeners wired up in game_repository.dart's subscribeLobby never
--     actually fire. The mechanism that reliably works is an explicit
--     Realtime Broadcast ('lobby_changed') the client sends right after a
--     successful join_game/leave_game/cancel_lobby RPC call, plus a 4s
--     polling safety-net timer in LobbyController as the ultimate fallback.
--     kick_player and update_game_settings follow the same pattern
--     Dart-side (see game_repository.dart) — there is nothing to add here
--     on the SQL side to "trigger" a refresh; the trigger is the client's
--     own post-RPC broadcast call.
--
-- Changes in this migration:
--   a) New games columns: seeker_mode ('RANDOM'|'MANUAL', default RANDOM)
--      and seeker_player_id (nullable uuid, no FK — membership is enforced
--      inside update_game_settings/start_game, not a cross-table
--      constraint, since the chosen player's membership can lapse between
--      being set and being read).
--   b) New public.game_kicked_players table: records who was removed from
--      a lobby and when, so join_game can refuse their rejoin. RLS
--      enabled with zero policies, and table privileges explicitly
--      revoked from anon/authenticated/public — same reasoning as the
--      security-hardening migration: Supabase's default privileges grant
--      table access on new `public` tables directly to anon/authenticated,
--      independent of the `public` role, so a bare "add no policies"
--      would leave it directly queryable via PostgREST without an
--      explicit revoke. Only the SECURITY DEFINER functions below (which
--      run as the table owner) can read or write it.
--   c) was_kicked: lets a client distinguish "I was kicked" from "the host
--      cancelled this lobby" after kick_player makes the games row
--      unreadable to them (see report Step 1 — deleting their
--      game_players row makes is_game_member false, so
--      games_select_host_or_member blocks their SELECT entirely; they
--      never get to see a game_players list that's merely missing their
--      own row).
--   d) update_game_settings: host-only, lobby-only, re-validates the same
--      bounds create_game already enforces (mode, settings object; the
--      table's own CHECK constraints cover timing/catch-radius positivity
--      on UPDATE the same as they do on INSERT). Host included among valid
--      MANUAL seeker choices because the host already has a game_players
--      row from create_game. p_settings is validated but NOT written (see
--      the inline comment at the UPDATE) — the only caller today always
--      sends '{}', which would otherwise silently wipe any existing
--      settings on every edit.
--   e) kick_player: host-only, lobby-only, cannot target self or a
--      non-member; clears games.seeker_player_id if the kicked player was
--      the chosen seeker.
--   f) leave_game: identical to the current function, plus clearing
--      seeker_player_id if the leaver was the chosen seeker.
--   g) start_game: identical to the current function, plus: in MANUAL
--      mode, use games.seeker_player_id as the seeker (raising if it's
--      null or no longer a member) instead of the random pick; RANDOM mode
--      is untouched.
--   h) join_game: identical to the current function (incl. the
--      security-hardening max_players check), plus: raise if the caller is
--      in game_kicked_players for this game, checked before the existing
--      idempotent already-a-member return.
--   i) Every function: security definer, set search_path = public, EXECUTE
--      revoked from public/anon, granted to authenticated. Full signatures
--      used in every revoke/grant. was_kicked is `language sql stable`
--      (matching is_game_member/is_game_host's style); the rest are
--      plpgsql. was_kicked, update_game_settings, and kick_player are
--      dropped first (new functions, but guards against a prior partial
--      apply leaving a different signature behind); leave_game,
--      start_game, and join_game keep their existing signature and return
--      type, so create or replace is sufficient for those three.

begin;

-- ---------------------------------------------------------------------------
-- (a) New games columns.
-- ---------------------------------------------------------------------------
alter table public.games
  add column if not exists seeker_mode text not null default 'RANDOM'
    check (seeker_mode in ('RANDOM', 'MANUAL'));

alter table public.games
  add column if not exists seeker_player_id uuid;

-- ---------------------------------------------------------------------------
-- (b) New table: who was kicked from which lobby.
-- ---------------------------------------------------------------------------
create table if not exists public.game_kicked_players (
  game_id uuid not null references public.games (id) on delete cascade,
  player_id uuid not null,
  kicked_at timestamptz not null default now(),
  primary key (game_id, player_id)
);

comment on table public.game_kicked_players is
  'Players removed from a lobby by its host. Blocks rejoin via join_code. '
  'No client access: read/written only by SECURITY DEFINER functions.';

alter table public.game_kicked_players enable row level security;

-- No policies: every role bound by RLS (i.e. not service_role, which
-- bypasses RLS) sees zero rows here regardless of grants below.
revoke all on table public.game_kicked_players from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- (c) was_kicked.
-- ---------------------------------------------------------------------------
drop function if exists public.was_kicked(uuid);

create function public.was_kicked(p_game_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.game_kicked_players
    where game_id = p_game_id and player_id = auth.uid()
  );
$$;

-- ---------------------------------------------------------------------------
-- (d) update_game_settings: host-only settings edit, including seeker mode.
-- ---------------------------------------------------------------------------
drop function if exists public.update_game_settings(
  uuid, text, integer, integer, double precision, integer, integer,
  boolean, jsonb, text, uuid
);

create function public.update_game_settings(
  p_game_id uuid,
  p_mode text,
  p_hiding_duration_seconds integer,
  p_match_duration_seconds integer,
  p_catch_radius_meters double precision,
  p_reveal_interval_seconds integer,
  p_reveal_duration_seconds integer,
  p_taunts_enabled boolean,
  p_settings jsonb,
  p_seeker_mode text,
  p_seeker_player_id uuid
)
returns public.games
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games;
  v_seeker_id uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_game from public.games where id = p_game_id for update;
  if v_game.id is null then
    raise exception 'Game not found';
  end if;

  if v_game.host_id <> v_user_id then
    raise exception 'Only the host can change settings';
  end if;

  if v_game.status not in ('CREATED', 'LOBBY') then
    raise exception 'Settings can only change before the match starts';
  end if;

  -- Same bounds validation create_game applies.
  if p_mode not in ('hide_and_seek', 'infected') then
    raise exception 'Invalid game mode';
  end if;

  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    raise exception 'settings must be a JSON object';
  end if;

  if p_seeker_mode not in ('RANDOM', 'MANUAL') then
    raise exception 'Invalid seeker mode';
  end if;

  if p_seeker_mode = 'MANUAL' then
    if p_seeker_player_id is null then
      raise exception 'Choose a seeker';
    end if;
    if not exists (
      select 1 from public.game_players
      where game_id = p_game_id and player_id = p_seeker_player_id
    ) then
      raise exception 'Chosen seeker is not a member of this lobby';
    end if;
    v_seeker_id := p_seeker_player_id;
  else
    v_seeker_id := null;
  end if;

  -- p_settings is validated above but deliberately not written: the only
  -- caller today (the lobby's Edit Settings sheet) always sends '{}', since
  -- nothing in the UI reads or edits the existing settings object, so
  -- applying it here would silently wipe out whatever create_game (or a
  -- future caller) already stored. The parameter stays, validated, for
  -- when a real caller needs it.
  update public.games
  set mode = p_mode,
      hiding_duration_seconds = p_hiding_duration_seconds,
      match_duration_seconds = p_match_duration_seconds,
      catch_radius_meters = p_catch_radius_meters,
      reveal_interval_seconds = p_reveal_interval_seconds,
      reveal_duration_seconds = p_reveal_duration_seconds,
      taunts_enabled = coalesce(p_taunts_enabled, true),
      seeker_mode = p_seeker_mode,
      seeker_player_id = v_seeker_id
  where id = p_game_id
  returning * into v_game;

  return v_game;
end;
$$;

-- ---------------------------------------------------------------------------
-- (e) kick_player: host-only removal.
-- ---------------------------------------------------------------------------
drop function if exists public.kick_player(uuid, uuid);

create function public.kick_player(p_game_id uuid, p_player_id uuid)
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
  values (p_game_id, p_player_id);

  update public.games
  set seeker_player_id = null
  where id = p_game_id and seeker_player_id = p_player_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- (f) leave_game: unchanged behaviour, plus clearing a manual seeker pick.
-- ---------------------------------------------------------------------------
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

  update public.games
  set seeker_player_id = null
  where id = p_game_id and seeker_player_id = v_user_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- (g) start_game: unchanged behaviour, plus a MANUAL-mode seeker pick.
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
    raise exception 'Need at least 2 players to start Hide & Seek';
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
-- (h) join_game: unchanged behaviour, plus refusing a kicked player's rejoin.
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

  if exists (
    select 1 from public.game_kicked_players
    where game_id = v_game.id and player_id = v_user_id
  ) then
    raise exception 'You were removed from this lobby';
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
-- (i) Grants. Full signatures; revoke from public/anon, grant to authenticated.
-- ---------------------------------------------------------------------------
revoke execute on function public.update_game_settings(
  uuid, text, integer, integer, double precision, integer, integer,
  boolean, jsonb, text, uuid
) from public, anon;
grant execute on function public.update_game_settings(
  uuid, text, integer, integer, double precision, integer, integer,
  boolean, jsonb, text, uuid
) to authenticated;

revoke execute on function public.kick_player(uuid, uuid) from public, anon;
grant execute on function public.kick_player(uuid, uuid) to authenticated;

revoke execute on function public.leave_game(uuid) from public, anon;
grant execute on function public.leave_game(uuid) to authenticated;

revoke execute on function public.start_game(uuid) from public, anon;
grant execute on function public.start_game(uuid) to authenticated;

revoke execute on function public.join_game(text) from public, anon;
grant execute on function public.join_game(text) to authenticated;

revoke execute on function public.was_kicked(uuid) from public, anon;
grant execute on function public.was_kicked(uuid) to authenticated;

commit;
