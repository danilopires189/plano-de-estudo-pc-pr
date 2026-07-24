-- Soft-delete de concursos: arquivar em vez de apagar

alter table public.contests
  add column if not exists archived_at timestamptz;

create index if not exists contests_user_active_idx
  on public.contests(user_id, updated_at desc)
  where archived_at is null;

create index if not exists contests_user_archived_idx
  on public.contests(user_id, archived_at desc)
  where archived_at is not null;

create or replace function public.delete_contest(p_contest_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_aal2() then
    raise exception 'AAL2 required';
  end if;

  update public.contests
  set archived_at = now()
  where id = p_contest_id
    and user_id = current_user_id
    and archived_at is null;

  if not found then
    raise exception 'Contest not found';
  end if;

  update public.profiles
  set active_contest_id = (
    select id from public.contests
    where user_id = current_user_id
      and archived_at is null
    order by updated_at desc
    limit 1
  )
  where user_id = current_user_id
    and active_contest_id = p_contest_id;
end;
$$;

create or replace function public.restore_contest(p_contest_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_aal2() then
    raise exception 'AAL2 required';
  end if;

  update public.contests
  set archived_at = null
  where id = p_contest_id
    and user_id = current_user_id
    and archived_at is not null;

  if not found then
    raise exception 'Contest not found';
  end if;
end;
$$;

revoke all on function public.restore_contest(uuid) from public;
grant execute on function public.restore_contest(uuid) to authenticated;

create or replace function public.set_active_contest(p_contest_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_aal2() then
    raise exception 'AAL2 required';
  end if;

  if not exists (
    select 1 from public.contests
    where id = p_contest_id
      and user_id = current_user_id
      and archived_at is null
  ) then
    raise exception 'Contest not found';
  end if;

  update public.profiles
  set active_contest_id = p_contest_id
  where user_id = current_user_id;
end;
$$;
