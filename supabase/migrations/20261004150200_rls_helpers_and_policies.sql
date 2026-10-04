-- RLS helpers run as the table owner so policy checks do not recurse.
-- search_path is pinned. EXECUTE is revoked from PUBLIC.

create or replace function public.is_game_member(p_game_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.game_players
    where game_id = p_game_id
      and player_id = auth.uid()
  );
$$;

create or replace function public.is_game_host(p_game_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.games
    where id = p_game_id
      and host_id = auth.uid()
  );
$$;

-- Clients may upsert their own location, but cannot retarget the row
-- or forge the server receive timestamp.
create or replace function public.player_locations_guard()
returns trigger
language plpgsql
as $$
begin
  new.server_received_at := now();

  if tg_op = 'UPDATE'
     and (
       new.game_id is distinct from old.game_id
       or new.player_id is distinct from old.player_id
     ) then
    raise exception 'Location identity cannot change';
  end if;

  return new;
end;
$$;

drop trigger if exists player_locations_guard on public.player_locations;
create trigger player_locations_guard
  before insert or update on public.player_locations
  for each row execute function public.player_locations_guard();

revoke all on function public.is_game_member(uuid) from public;
revoke all on function public.is_game_host(uuid) from public;
revoke all on function public.player_locations_guard() from public;
grant execute on function public.is_game_member(uuid) to authenticated;
grant execute on function public.is_game_host(uuid) to authenticated;

-- New auth users get a profile row aligned to auth.users.id.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), 'Player')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Privileges
-- authenticated may not write authoritative tables directly.
-- anon has no table access (anonymous sign-in still uses authenticated).
-- ---------------------------------------------------------------------------
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.games from anon, authenticated;
revoke all on table public.game_players from anon, authenticated;
revoke all on table public.game_zones from anon, authenticated;
revoke all on table public.player_locations from anon, authenticated;
revoke all on table public.game_events from anon, authenticated;

grant select, insert on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;

grant select on table public.games to authenticated;
grant select on table public.game_players to authenticated;
grant select on table public.game_zones to authenticated;
grant select on table public.game_events to authenticated;

grant select, insert, update on table public.player_locations to authenticated;

-- ---------------------------------------------------------------------------
-- Enable RLS on every client-accessed table
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.games enable row level security;
alter table public.game_players enable row level security;
alter table public.game_zones enable row level security;
alter table public.player_locations enable row level security;
alter table public.game_events enable row level security;

alter table public.profiles force row level security;
alter table public.games force row level security;
alter table public.game_players force row level security;
alter table public.game_zones force row level security;
alter table public.player_locations force row level security;
alter table public.game_events force row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create policy profiles_select_self_or_same_game
  on public.profiles
  for select
  to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.game_players mine
      join public.game_players theirs
        on theirs.game_id = mine.game_id
      where mine.player_id = auth.uid()
        and theirs.player_id = profiles.id
    )
  );

create policy profiles_insert_self
  on public.profiles
  for insert
  to authenticated
  with check (id = auth.uid());

create policy profiles_update_self
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- games: readable by host or members. No client writes (RPC only).
-- ---------------------------------------------------------------------------
create policy games_select_host_or_member
  on public.games
  for select
  to authenticated
  using (
    host_id = auth.uid()
    or public.is_game_member(id)
  );

-- ---------------------------------------------------------------------------
-- game_players: members can see the lobby list. No client writes.
-- ---------------------------------------------------------------------------
create policy game_players_select_same_game
  on public.game_players
  for select
  to authenticated
  using (
    public.is_game_member(game_id)
    or public.is_game_host(game_id)
  );

-- ---------------------------------------------------------------------------
-- game_zones: members need the map. Writes go through replace_game_zones.
-- ---------------------------------------------------------------------------
create policy game_zones_select_same_game
  on public.game_zones
  for select
  to authenticated
  using (
    public.is_game_member(game_id)
    or public.is_game_host(game_id)
  );

-- ---------------------------------------------------------------------------
-- player_locations: own row only. Never "all members can select".
-- ---------------------------------------------------------------------------
create policy player_locations_select_own
  on public.player_locations
  for select
  to authenticated
  using (player_id = auth.uid());

create policy player_locations_insert_own
  on public.player_locations
  for insert
  to authenticated
  with check (
    player_id = auth.uid()
    and public.is_game_member(game_id)
  );

create policy player_locations_update_own
  on public.player_locations
  for update
  to authenticated
  using (player_id = auth.uid())
  with check (
    player_id = auth.uid()
    and public.is_game_member(game_id)
  );

-- ---------------------------------------------------------------------------
-- game_events: members may read the public feed. No client inserts.
-- Payloads must never include hidden precise coordinates.
-- ---------------------------------------------------------------------------
create policy game_events_select_same_game
  on public.game_events
  for select
  to authenticated
  using (
    public.is_game_member(game_id)
    or public.is_game_host(game_id)
  );
