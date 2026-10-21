-- Read-only verification for 20261021040000_infected_mode.sql.
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
  and p.proname in ('attempt_catch', 'fetch_seeker_location', 'start_game')
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
  and p.proname in ('attempt_catch', 'fetch_seeker_location', 'start_game')
  and has_function_privilege('anon', p.oid, 'execute');

-- 3) Confirm none of these functions have a duplicate overload sitting in
-- pg_proc. Expect: zero rows.
select p.proname, count(*) as overload_count
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('attempt_catch', 'fetch_seeker_location', 'start_game')
group by p.proname
having count(*) > 1;
