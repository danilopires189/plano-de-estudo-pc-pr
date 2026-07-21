create or replace function public.replace_study_data(
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

  insert into public.study_goals (
    user_id,
    weekly_hours,
    weekly_questions,
    completion_target,
    accuracy_target
  ) values (
    current_user_id,
    coalesce((goals ->> 'weekly_hours')::numeric, 0),
    coalesce((goals ->> 'weekly_questions')::integer, 0),
    coalesce((goals ->> 'completion_target')::integer, 0),
    coalesce((goals ->> 'accuracy_target')::integer, 0)
  )
  on conflict (user_id) do update set
    weekly_hours = excluded.weekly_hours,
    weekly_questions = excluded.weekly_questions,
    completion_target = excluded.completion_target,
    accuracy_target = excluded.accuracy_target;

  delete from public.topic_progress where user_id = current_user_id;
  insert into public.topic_progress (
    user_id,
    topic_id,
    discipline_id,
    completed,
    completed_at,
    questions,
    correct_answers,
    wrong_answers
  )
  select
    current_user_id,
    item ->> 'topic_id',
    item ->> 'discipline_id',
    coalesce((item ->> 'completed')::boolean, false),
    nullif(item ->> 'completed_at', '')::timestamptz,
    coalesce((item ->> 'questions')::integer, 0),
    coalesce((item ->> 'correct_answers')::integer, 0),
    coalesce((item ->> 'wrong_answers')::integer, 0)
  from jsonb_array_elements(coalesce(topics, '[]'::jsonb)) as item;

  delete from public.study_sessions where user_id = current_user_id;
  insert into public.study_sessions (
    user_id,
    client_id,
    study_date,
    discipline,
    topic,
    study_type,
    duration_seconds,
    questions,
    correct_answers,
    wrong_answers,
    notes,
    source
  )
  select
    current_user_id,
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

  delete from public.reviews where user_id = current_user_id;
  insert into public.reviews (
    user_id,
    client_id,
    discipline,
    topic,
    study_date,
    review_date,
    interval_days,
    completed,
    completed_at
  )
  select
    current_user_id,
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

revoke all on function public.replace_study_data(jsonb, jsonb, jsonb, jsonb) from public;
grant execute on function public.replace_study_data(jsonb, jsonb, jsonb, jsonb) to authenticated;
