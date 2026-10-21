-- Read-only verification for 20261021020000_lobby_management.sql.
-- Run each block after applying the migration. Nothing here writes data.

-- 1) Function settings (SECURITY DEFINER + pinned search_path) for every
-- function this migration touched. Expect one row per name below.
select
  p.proname as function_name,
  p.prosecdef as is_security_definer,
  p.proconfig as config_settings
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'was_kicked', 'update_game_settings', 'kick_player', 'leave_game',
    'start_game', 'join_game'
  )
order by p.proname;

-- 2) Confirm anon has no EXECUTE on any overload of these functions,
-- checked per-oid via has_function_privilege (not information_schema,
-- which reports by name and can hide a second overload with different
-- grants). Expect: zero rows.
select
  p.proname,
  p.oid::regprocedure as signature,
  has_function_privilege('anon', p.oid, 'execute') as has_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'was_kicked', 'update_game_settings', 'kick_player', 'leave_game',
    'start_game', 'join_game'
  )
  and has_function_privilege('anon', p.oid, 'execute');

-- 3) Confirm none of these functions have a duplicate overload sitting in
-- pg_proc. Expect: zero rows.
select p.proname, count(*) as overload_count
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'was_kicked', 'update_game_settings', 'kick_player', 'leave_game',
    'start_game', 'join_game'
  )
group by p.proname
having count(*) > 1;

-- 4) game_kicked_players exists, has RLS enabled, and has zero policies.
-- Expect: one row, relrowsecurity = true, policy_count = 0.
select
  c.relname,
  c.relrowsecurity as rls_enabled,
  (
    select count(*) from pg_policies pol
    where pol.schemaname = 'public' and pol.tablename = 'game_kicked_players'
  ) as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'game_kicked_players';

-- 4b) Confirm no direct table privileges reached anon/authenticated/public
-- on game_kicked_players. Expect: zero rows.
select grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public'
  and table_name = 'game_kicked_players'
  and grantee in ('anon', 'authenticated', 'public');

-- 5) New games columns exist with the expected defaults.
-- Expect: two rows (seeker_mode default 'RANDOM'::text, seeker_player_id
-- nullable with no default).
select column_name, column_default, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'games'
  and column_name in ('seeker_mode', 'seeker_player_id')
order by column_name;
