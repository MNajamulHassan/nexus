-- Read-only verification for 20261021010000_security_hardening.sql.
-- Run each block after applying the migration. Nothing here writes data.

-- 1) Confirm anon has NO EXECUTE on any function touched by the migration.
-- Expect: zero rows.
select routine_name, grantee, privilege_type
from information_schema.routine_privileges
where routine_schema = 'public'
  and grantee = 'anon'
  and routine_name in (
    'attempt_catch', 'cancel_lobby', 'create_game', 'fetch_catch_candidates',
    'fetch_game_zones', 'fetch_seeker_location', 'fetch_seeker_view',
    'join_game', 'leave_game', 'replace_game_zones', 'set_player_ready',
    'start_game', 'sync_match_state', 'upsert_player_location',
    'generate_join_code', 'is_game_host', 'is_game_member',
    'record_game_event', 'handle_new_user', 'player_locations_guard'
  )
order by routine_name;

-- 2) Confirm authenticated still has EXECUTE on every app-facing function.
-- Expect: one row per function listed, privilege_type = 'EXECUTE'.
select routine_name, grantee, privilege_type
from information_schema.routine_privileges
where routine_schema = 'public'
  and grantee = 'authenticated'
  and routine_name in (
    'attempt_catch', 'cancel_lobby', 'create_game', 'fetch_catch_candidates',
    'fetch_game_zones', 'fetch_seeker_location', 'fetch_seeker_view',
    'join_game', 'leave_game', 'replace_game_zones', 'set_player_ready',
    'start_game', 'sync_match_state', 'upsert_player_location',
    'generate_join_code', 'is_game_host', 'is_game_member'
  )
order by routine_name;

-- 2b) Confirm authenticated has NO EXECUTE on the internal-only functions.
-- Expect: zero rows.
select routine_name, grantee, privilege_type
from information_schema.routine_privileges
where routine_schema = 'public'
  and grantee = 'authenticated'
  and routine_name in ('record_game_event', 'handle_new_user', 'player_locations_guard');

-- 2c) Confirm service_role still has EXECUTE on record_game_event.
-- Expect: one row.
select routine_name, grantee, privilege_type
from information_schema.routine_privileges
where routine_schema = 'public'
  and grantee = 'service_role'
  and routine_name = 'record_game_event';

-- 3) Confirm authenticated/anon have no direct INSERT/UPDATE/DELETE on
-- player_locations — writes must go only through upsert_player_location.
-- Expect: zero rows.
select grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public'
  and table_name = 'player_locations'
  and grantee in ('authenticated', 'anon')
  and privilege_type in ('INSERT', 'UPDATE', 'DELETE');

-- 3b) Confirm SELECT on player_locations is untouched (should still show
-- authenticated — this migration did not revoke it).
select grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public'
  and table_name = 'player_locations'
  and grantee in ('authenticated', 'anon')
  and privilege_type = 'SELECT';

-- 4) Function settings (SECURITY DEFINER + pinned search_path) for every
-- function this migration touched or re-affirmed.
select
  p.proname as function_name,
  p.prosecdef as is_security_definer,
  p.proconfig as config_settings
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'attempt_catch', 'cancel_lobby', 'create_game', 'fetch_catch_candidates',
    'fetch_game_zones', 'fetch_seeker_location', 'fetch_seeker_view',
    'join_game', 'leave_game', 'replace_game_zones', 'set_player_ready',
    'start_game', 'sync_match_state', 'upsert_player_location',
    'generate_join_code', 'is_game_host', 'is_game_member',
    'record_game_event', 'handle_new_user', 'player_locations_guard'
  )
order by p.proname;

-- 5) New columns exist with the expected defaults.
-- Expect: three rows (games.max_players, game_players.last_catch_scan_at,
-- game_players.last_catch_attempt_at).
select table_name, column_name, column_default, is_nullable
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'games' and column_name = 'max_players')
    or (table_name = 'game_players' and column_name in ('last_catch_scan_at', 'last_catch_attempt_at'))
  );
