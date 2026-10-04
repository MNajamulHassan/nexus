-- Host-only rollback for a lobby that never left CREATED/LOBBY.
-- Needed when create_game succeeds but replace_game_zones fails.
-- Does not weaken RLS: clients still cannot DELETE games directly.

create or replace function public.cancel_lobby(p_game_id uuid)
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
  where id = p_game_id;

  if v_host_id is null then
    raise exception 'Game not found';
  end if;

  if v_host_id <> v_user_id then
    raise exception 'Only the host can cancel this lobby';
  end if;

  if v_status not in ('CREATED', 'LOBBY') then
    raise exception 'Cannot cancel after the match has started';
  end if;

  delete from public.games
  where id = p_game_id;
end;
$$;

revoke all on function public.cancel_lobby(uuid) from public;
grant execute on function public.cancel_lobby(uuid) to authenticated;
