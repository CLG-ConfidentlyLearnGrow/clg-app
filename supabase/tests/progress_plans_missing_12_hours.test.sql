-- Summary: tests the follow-up of a missing plan for the next session
-- (Carla, 22 Nov 2026; migration 20261124710400_plans_missing_12_hours.sql).
-- Reuses earlier tests' people: owner ...a0 (admin), tutor T1 ...11
-- (teaches Cara One). Checks: the tutor is reminded at 6 hr and admins are
-- told at 12 hr when the summary is in but the plan is missing and a next
-- session is booked; nothing is sent when the student was absent, when no
-- next session is booked, or once the plan is saved. Everything is rolled
-- back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the database change twice (checks it can run more than once).
\ir ../migrations/20261124710400_plans_missing_12_hours.sql
\ir ../migrations/20261124710400_plans_missing_12_hours.sql

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset

-- Three past sessions with tutor T1, each ended 13 hours ago (A, B, C), and
-- one coming session (D) so a next session is booked.
insert into public.sessions (id, student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status) values -- Adds the sessions:
  ('00000000-0000-0000-0000-0000000f1a01', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', now() - interval '14 hours', now() - interval '13 hours', 'completed'), -- A: came, no plan,
  ('00000000-0000-0000-0000-0000000f1a02', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', now() - interval '14 hours 30 minutes', now() - interval '13 hours 30 minutes', 'completed'), -- B: absent,
  ('00000000-0000-0000-0000-0000000f1a03', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', now() - interval '15 hours', now() - interval '14 hours', 'completed'), -- C: came, plan saved,
  ('00000000-0000-0000-0000-0000000f1a04', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', now() + interval '2 days', now() + interval '2 days 1 hour', 'scheduled'); -- D: the next session.
-- The summaries for A, B and C.
insert into public.session_notes (id, student_id, tutor_id, session_id, session_date, minutes, attendance, went_well, next_step) values -- Adds the summaries:
  ('00000000-0000-0000-0000-0000000f1b01', :'cara', '00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000f1a01', current_date, 60, 'attended', 'Good work on fractions.', 'Order three fractions.'), -- A: came,
  ('00000000-0000-0000-0000-0000000f1b02', :'cara', '00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000f1a02', current_date, 60, 'absent', null, null), -- B: absent,
  ('00000000-0000-0000-0000-0000000f1b03', :'cara', '00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000f1a03', current_date, 60, 'attended', 'Good work on decimals.', 'Round to one place.'); -- C: came.
insert into public.session_plans (note_id, student_id, tutor_id, focus, activities) -- Saves C's plan:
values ('00000000-0000-0000-0000-0000000f1b03', :'cara', '00000000-0000-0000-0000-000000000011', 'Rounding decimals', 'Number line then game'); -- (its focus and activities)

select private.queue_plan_reminders(); -- Runs the hourly plan job.
select tests.eq((select count(*) from public.progress_notices where session_id = '00000000-0000-0000-0000-0000000f1a01' and kind = 'plan_reminder' and account_id = '00000000-0000-0000-0000-000000000011'), 1::bigint, 'the tutor is reminded about the missing plan'); -- Checks: T1 is reminded about A.
select tests.eq((select count(*) from public.progress_notices where session_id = '00000000-0000-0000-0000-0000000f1a01' and kind = 'plan_overdue' and account_id = '00000000-0000-0000-0000-0000000000a0'), 1::bigint, 'admins are told at 12 hours'); -- Checks: the owner is told about A.
select tests.eq((select count(*) from public.progress_notices where session_id in ('00000000-0000-0000-0000-0000000f1a02', '00000000-0000-0000-0000-0000000f1a03') and kind in ('plan_reminder', 'plan_overdue')), 0::bigint, 'nothing when the student was absent or the plan is saved'); -- Checks: nothing for B or C.
select private.queue_plan_reminders(); -- Runs the job again.
select tests.eq((select count(*) from public.progress_notices where session_id = '00000000-0000-0000-0000-0000000f1a01' and kind = 'plan_reminder'), 1::bigint, 'each person is told only once'); -- Checks: running again adds no second reminder for the tutor.

-- At 8 hours (between 6 and 12) only the tutor is reminded.
update public.sessions set starts_at = now() - interval '9 hours', ends_at = now() - interval '8 hours' where id = '00000000-0000-0000-0000-0000000f1a01'; -- Moves A to 8 hours ago.
delete from public.progress_notices where session_id = '00000000-0000-0000-0000-0000000f1a01'; -- Clears its notices.
select private.queue_plan_reminders(); -- Runs the job.
select tests.eq((select count(*) from public.progress_notices where session_id = '00000000-0000-0000-0000-0000000f1a01' and kind = 'plan_reminder'), 1::bigint, 'the tutor is reminded at 6 hours'); -- Checks: T1 reminded.
select tests.eq((select count(*) from public.progress_notices where session_id = '00000000-0000-0000-0000-0000000f1a01' and kind = 'plan_overdue'), 0::bigint, 'admins are not told before 12 hours'); -- Checks: no admin notice yet.

-- With no next session booked, no plan is asked for.
delete from public.sessions where id = '00000000-0000-0000-0000-0000000f1a04'; -- Removes the coming session D, so none is booked.
delete from public.progress_notices where session_id = '00000000-0000-0000-0000-0000000f1a01'; -- Clears A's notices.
select private.queue_plan_reminders(); -- Runs the job.
select tests.eq((select count(*) from public.progress_notices where session_id = '00000000-0000-0000-0000-0000000f1a01' and kind in ('plan_reminder', 'plan_overdue')), 0::bigint, 'no plan is asked for when no next session is booked'); -- Checks: nothing sent.

-- Undoes everything this file did.
rollback; -- Throws away every change made in this file.

-- Prints that every check in this file passed.
\echo '  plans for the next session followed up at 6 and 12 hours: all checks passed'
