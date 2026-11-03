-- Term reviews become a paid opt-in, and monthly summaries stop (module:
-- progress). Carla, 2 Nov 2026.
--
-- * Term reviews are an add-on families choose and pay for. Only students
--   with the "Term reviews" add-on get one. The owner sets the price and
--   switches it to "paid" under Admin > Progress; until then it is off and
--   no reviews are made. Admins give it to each student whose family opts
--   in (see docs/features/add-ons.md).
-- * The student's tutor still writes the review, so no student
--   information goes to any AI tool. The form reminds tutors not to paste
--   student details into AI tools.
-- * Reviews follow each student's own study period (government or private
--   school terms, or their own tertiary dates), 3 weeks before it ends.
-- * Monthly summaries are no longer sent. Ones already sent stay readable.
--
-- Needs 20261102500100_study_plan_add_on.sql and
-- 20261103000300_scheduling_study_periods.sql. Safe to run more than once.

insert into public.add_ons (code, name, description, mode, price_period, gst_applies) values
  ('term_reviews', 'Term reviews',
   'A written review from the student''s tutor near the end of each term: how the term went, skills at the start and end of term, and the focus for next term. Checked by CLG before the family sees it.',
   'off', 'term', false)
on conflict (code) do nothing;

-- Daily: a draft review for each student with the add-on and a current
-- tutor who wrote a session note this study period, 3 weeks before it ends.
create or replace function private.queue_term_reviews()
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Australia/Adelaide')::date;
  v_count integer;
begin
  with due as (
    select st.id as student_id, ta.tutor_id, t.label, t.starts_on, t.ends_on
    from public.students st
    cross join lateral private.student_terms(st.id) t
    join public.tutor_assignments ta on ta.student_id = st.id
      and private.assignment_is_current(ta.starts_on, ta.ends_on)
    where t.ends_on between v_today and v_today + 21
      and coalesce(private.has_add_on('term_reviews', st.id), false)
      -- Only students who had a session note this study period.
      and exists (select 1 from public.session_notes n
                  where n.student_id = st.id and n.tutor_id = ta.tutor_id
                    and n.session_date between t.starts_on and t.ends_on)
  ),
  made as (
    insert into public.term_reviews (student_id, tutor_id, term_label, term_starts_on, term_ends_on)
    select distinct d.student_id, d.tutor_id, d.label, d.starts_on, d.ends_on
    from due d
    on conflict do nothing
    returning id, student_id, tutor_id, term_label, term_ends_on
  )
  insert into public.progress_notices (account_id, student_id, review_id, kind, title, body, deliver_at)
  select m.tutor_id, m.student_id, m.id, 'review_due',
         left('Term review to write: ' || st.full_name, 200),
         left(format('Please write %s''s %s review by %s, so CLG can check it before the term ends. '
                     || 'Write it yourself and don''t put any student details into AI tools.',
                     st.full_name, m.term_label, to_char(m.term_ends_on - 14, 'FMDD Mon')), 1000),
         private.outside_quiet_hours(now())
  from made m join public.students st on st.id = m.student_id
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function private.queue_term_reviews() from public;

-- Monthly summaries: no longer sent.
create or replace function private.queue_monthly_summaries(p_month date default null)
returns integer language sql
set search_path = ''
as $$ select 0 $$;
revoke all on function private.queue_monthly_summaries(date) from public;

do $$
begin
  if to_regclass('cron.job') is not null then
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'clg-monthly-summaries'$q$;
  end if;
end;
$$;
