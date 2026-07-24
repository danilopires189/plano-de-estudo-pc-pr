-- Multi-concurso: estrutura editável + progresso isolado por concurso

create table public.contests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  cargo text,
  banca text,
  exam_date date,
  syllabus jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index contests_user_id_idx on public.contests(user_id);
create index contests_user_updated_idx on public.contests(user_id, updated_at desc);

create trigger contests_set_updated_at
before update on public.contests
for each row execute function public.set_updated_at();

alter table public.contests enable row level security;

create policy "Users manage their own contests"
on public.contests for all
using ((select auth.uid()) = user_id and (select public.has_aal2()))
with check ((select auth.uid()) = user_id and (select public.has_aal2()));

alter table public.profiles
  add column if not exists active_contest_id uuid references public.contests(id) on delete set null;

-- Criar concurso legado para quem já tem progresso
insert into public.contests (user_id, name, cargo, banca, exam_date, syllabus)
select distinct owner.user_id,
  'PC PR - Polícia Civil do Estado do Paraná',
  'Agente de Polícia Judiciária',
  'FGV',
  date '2026-10-11',
  '[]'::jsonb
from (
  select user_id from public.topic_progress
  union
  select user_id from public.study_sessions
  union
  select user_id from public.reviews
  union
  select user_id from public.study_goals
) as owner
where not exists (
  select 1 from public.contests c where c.user_id = owner.user_id
);

update public.profiles p
set active_contest_id = c.id
from public.contests c
where c.user_id = p.user_id
  and p.active_contest_id is null;

-- study_goals: passar a ser por concurso
alter table public.study_goals add column if not exists contest_id uuid references public.contests(id) on delete cascade;

update public.study_goals g
set contest_id = c.id
from public.contests c
where c.user_id = g.user_id
  and g.contest_id is null;

delete from public.study_goals where contest_id is null;

alter table public.study_goals alter column contest_id set not null;
alter table public.study_goals drop constraint study_goals_pkey;
alter table public.study_goals add primary key (user_id, contest_id);

-- topic_progress
alter table public.topic_progress add column if not exists contest_id uuid references public.contests(id) on delete cascade;

update public.topic_progress t
set contest_id = c.id
from public.contests c
where c.user_id = t.user_id
  and t.contest_id is null;

delete from public.topic_progress where contest_id is null;

alter table public.topic_progress alter column contest_id set not null;
alter table public.topic_progress drop constraint if exists topic_progress_user_id_topic_id_key;
alter table public.topic_progress add constraint topic_progress_user_contest_topic_key unique (user_id, contest_id, topic_id);
create index if not exists topic_progress_contest_idx on public.topic_progress(contest_id);

-- study_sessions
alter table public.study_sessions add column if not exists contest_id uuid references public.contests(id) on delete cascade;

update public.study_sessions s
set contest_id = c.id
from public.contests c
where c.user_id = s.user_id
  and s.contest_id is null;

delete from public.study_sessions where contest_id is null;

alter table public.study_sessions alter column contest_id set not null;
alter table public.study_sessions drop constraint if exists study_sessions_user_id_client_id_key;
alter table public.study_sessions add constraint study_sessions_user_contest_client_key unique (user_id, contest_id, client_id);
create index if not exists study_sessions_contest_idx on public.study_sessions(contest_id, study_date desc);

-- reviews
alter table public.reviews add column if not exists contest_id uuid references public.contests(id) on delete cascade;

update public.reviews r
set contest_id = c.id
from public.contests c
where c.user_id = r.user_id
  and r.contest_id is null;

delete from public.reviews where contest_id is null;

alter table public.reviews alter column contest_id set not null;
alter table public.reviews drop constraint if exists reviews_user_id_client_id_key;
alter table public.reviews add constraint reviews_user_contest_client_key unique (user_id, contest_id, client_id);
create index if not exists reviews_contest_idx on public.reviews(contest_id, review_date);

-- handle_new_user: não cria goals globais; goals nascem com o concurso
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)))
  on conflict (user_id) do nothing;
  return new;
end;
$$;

-- Upsert concurso (meta + edital)
create or replace function public.upsert_contest(payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  contest_uuid uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_aal2() then
    raise exception 'AAL2 required';
  end if;

  contest_uuid := nullif(payload ->> 'id', '')::uuid;

  if contest_uuid is null then
    insert into public.contests (
      user_id, name, cargo, banca, exam_date, syllabus
    ) values (
      current_user_id,
      coalesce(nullif(payload ->> 'name', ''), 'Novo concurso'),
      nullif(payload ->> 'cargo', ''),
      nullif(payload ->> 'banca', ''),
      nullif(payload ->> 'exam_date', '')::date,
      coalesce(payload -> 'syllabus', '[]'::jsonb)
    )
    returning id into contest_uuid;

    insert into public.study_goals (user_id, contest_id)
    values (current_user_id, contest_uuid)
    on conflict (user_id, contest_id) do nothing;
  else
    update public.contests
    set
      name = coalesce(nullif(payload ->> 'name', ''), name),
      cargo = nullif(payload ->> 'cargo', ''),
      banca = nullif(payload ->> 'banca', ''),
      exam_date = nullif(payload ->> 'exam_date', '')::date,
      syllabus = coalesce(payload -> 'syllabus', syllabus)
    where id = contest_uuid
      and user_id = current_user_id;

    if not found then
      raise exception 'Contest not found';
    end if;

    insert into public.study_goals (user_id, contest_id)
    values (current_user_id, contest_uuid)
    on conflict (user_id, contest_id) do nothing;
  end if;

  update public.profiles
  set active_contest_id = contest_uuid
  where user_id = current_user_id;

  return contest_uuid;
end;
$$;

revoke all on function public.upsert_contest(jsonb) from public;
grant execute on function public.upsert_contest(jsonb) to authenticated;

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

  delete from public.contests
  where id = p_contest_id
    and user_id = current_user_id;

  update public.profiles
  set active_contest_id = (
    select id from public.contests
    where user_id = current_user_id
    order by updated_at desc
    limit 1
  )
  where user_id = current_user_id;
end;
$$;

revoke all on function public.delete_contest(uuid) from public;
grant execute on function public.delete_contest(uuid) to authenticated;

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
    where id = p_contest_id and user_id = current_user_id
  ) then
    raise exception 'Contest not found';
  end if;

  update public.profiles
  set active_contest_id = p_contest_id
  where user_id = current_user_id;
end;
$$;

revoke all on function public.set_active_contest(uuid) from public;
grant execute on function public.set_active_contest(uuid) to authenticated;

-- Sync de progresso escopado por concurso
create or replace function public.replace_study_data(
  p_contest_id uuid,
  goals jsonb,
  topics jsonb,
  sessions jsonb,
  review_items jsonb
)
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
  if p_contest_id is null then
    raise exception 'Contest required';
  end if;
  if not exists (
    select 1 from public.contests
    where id = p_contest_id and user_id = current_user_id
  ) then
    raise exception 'Contest not found';
  end if;

  insert into public.study_goals (
    user_id,
    contest_id,
    weekly_hours,
    weekly_questions,
    completion_target,
    accuracy_target
  ) values (
    current_user_id,
    p_contest_id,
    coalesce((goals ->> 'weekly_hours')::numeric, 0),
    coalesce((goals ->> 'weekly_questions')::integer, 0),
    coalesce((goals ->> 'completion_target')::integer, 0),
    coalesce((goals ->> 'accuracy_target')::integer, 0)
  )
  on conflict (user_id, contest_id) do update set
    weekly_hours = excluded.weekly_hours,
    weekly_questions = excluded.weekly_questions,
    completion_target = excluded.completion_target,
    accuracy_target = excluded.accuracy_target;

  delete from public.topic_progress
  where user_id = current_user_id and contest_id = p_contest_id;

  insert into public.topic_progress (
    user_id, contest_id, topic_id, discipline_id, completed, completed_at,
    questions, correct_answers, wrong_answers
  )
  select
    current_user_id,
    p_contest_id,
    item ->> 'topic_id',
    item ->> 'discipline_id',
    coalesce((item ->> 'completed')::boolean, false),
    nullif(item ->> 'completed_at', '')::timestamptz,
    coalesce((item ->> 'questions')::integer, 0),
    coalesce((item ->> 'correct_answers')::integer, 0),
    coalesce((item ->> 'wrong_answers')::integer, 0)
  from jsonb_array_elements(coalesce(topics, '[]'::jsonb)) as item;

  delete from public.study_sessions
  where user_id = current_user_id and contest_id = p_contest_id;

  insert into public.study_sessions (
    user_id, contest_id, client_id, study_date, discipline, topic, study_type,
    duration_seconds, questions, correct_answers, wrong_answers, notes, source
  )
  select
    current_user_id,
    p_contest_id,
    item ->> 'client_id',
    (item ->> 'study_date')::date,
    nullif(item ->> 'discipline', ''),
    nullif(item ->> 'topic', ''),
    nullif(item ->> 'study_type', ''),
    coalesce((item ->> 'duration_seconds')::integer, 0),
    coalesce((item ->> 'questions')::integer, 0),
    coalesce((item ->> 'correct_answers')::integer, 0),
    coalesce((item ->> 'wrong_answers')::integer, 0),
    nullif(item ->> 'notes', ''),
    coalesce(nullif(item ->> 'source', ''), 'manual')
  from jsonb_array_elements(coalesce(sessions, '[]'::jsonb)) as item;

  delete from public.reviews
  where user_id = current_user_id and contest_id = p_contest_id;

  insert into public.reviews (
    user_id, contest_id, client_id, discipline, topic, study_date, review_date,
    interval_days, completed, completed_at
  )
  select
    current_user_id,
    p_contest_id,
    item ->> 'client_id',
    nullif(item ->> 'discipline', ''),
    item ->> 'topic',
    (item ->> 'study_date')::date,
    (item ->> 'review_date')::date,
    (item ->> 'interval_days')::integer,
    coalesce((item ->> 'completed')::boolean, false),
    nullif(item ->> 'completed_at', '')::timestamptz
  from jsonb_array_elements(coalesce(review_items, '[]'::jsonb)) as item;
end;
$$;

revoke all on function public.replace_study_data(uuid, jsonb, jsonb, jsonb, jsonb) from public;
grant execute on function public.replace_study_data(uuid, jsonb, jsonb, jsonb, jsonb) to authenticated;

-- Remove assinatura antiga (sem contest_id)
drop function if exists public.replace_study_data(jsonb, jsonb, jsonb, jsonb);
