create or replace function public.has_aal2()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce((auth.jwt() ->> 'aal') = 'aal2', false);
$$;

revoke all on function public.has_aal2() from public;
grant execute on function public.has_aal2() to authenticated;

drop policy if exists "Users manage their own profile" on public.profiles;
create policy "Users manage their own profile"
on public.profiles for all
using ((select auth.uid()) = user_id and (select public.has_aal2()))
with check ((select auth.uid()) = user_id and (select public.has_aal2()));

drop policy if exists "Users manage their own goals" on public.study_goals;
create policy "Users manage their own goals"
on public.study_goals for all
using ((select auth.uid()) = user_id and (select public.has_aal2()))
with check ((select auth.uid()) = user_id and (select public.has_aal2()));

drop policy if exists "Users manage their own topic progress" on public.topic_progress;
create policy "Users manage their own topic progress"
on public.topic_progress for all
using ((select auth.uid()) = user_id and (select public.has_aal2()))
with check ((select auth.uid()) = user_id and (select public.has_aal2()));

drop policy if exists "Users manage their own study sessions" on public.study_sessions;
create policy "Users manage their own study sessions"
on public.study_sessions for all
using ((select auth.uid()) = user_id and (select public.has_aal2()))
with check ((select auth.uid()) = user_id and (select public.has_aal2()));

drop policy if exists "Users manage their own reviews" on public.reviews;
create policy "Users manage their own reviews"
on public.reviews for all
using ((select auth.uid()) = user_id and (select public.has_aal2()))
with check ((select auth.uid()) = user_id and (select public.has_aal2()));
