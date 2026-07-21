create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.study_goals (
  user_id uuid primary key references auth.users(id) on delete cascade,
  weekly_hours numeric(8, 2) not null default 0 check (weekly_hours >= 0),
  weekly_questions integer not null default 0 check (weekly_questions >= 0),
  completion_target integer not null default 0 check (completion_target between 0 and 100),
  accuracy_target integer not null default 0 check (accuracy_target between 0 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.topic_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  topic_id text not null,
  discipline_id text not null,
  completed boolean not null default false,
  completed_at timestamptz,
  questions integer not null default 0 check (questions >= 0),
  correct_answers integer not null default 0 check (correct_answers >= 0),
  wrong_answers integer not null default 0 check (wrong_answers >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, topic_id)
);

create table public.study_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id text,
  study_date date not null,
  discipline text,
  topic text,
  study_type text,
  duration_seconds integer not null default 0 check (duration_seconds >= 0),
  questions integer not null default 0 check (questions >= 0),
  correct_answers integer not null default 0 check (correct_answers >= 0),
  wrong_answers integer not null default 0 check (wrong_answers >= 0),
  notes text,
  source text not null default 'manual' check (source in ('cronometro', 'manual', 'modal', 'importacao')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, client_id)
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id text,
  discipline text,
  topic text not null,
  study_date date not null,
  review_date date not null,
  interval_days integer not null check (interval_days > 0),
  completed boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, client_id)
);

create index topic_progress_user_id_idx on public.topic_progress(user_id);
create index study_sessions_user_date_idx on public.study_sessions(user_id, study_date desc);
create index reviews_user_date_idx on public.reviews(user_id, review_date);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger study_goals_set_updated_at
before update on public.study_goals
for each row execute function public.set_updated_at();

create trigger topic_progress_set_updated_at
before update on public.topic_progress
for each row execute function public.set_updated_at();

create trigger study_sessions_set_updated_at
before update on public.study_sessions
for each row execute function public.set_updated_at();

create trigger reviews_set_updated_at
before update on public.reviews
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.study_goals enable row level security;
alter table public.topic_progress enable row level security;
alter table public.study_sessions enable row level security;
alter table public.reviews enable row level security;

create policy "Users manage their own profile"
on public.profiles for all
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users manage their own goals"
on public.study_goals for all
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users manage their own topic progress"
on public.topic_progress for all
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users manage their own study sessions"
on public.study_sessions for all
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users manage their own reviews"
on public.reviews for all
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

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

  insert into public.study_goals (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
