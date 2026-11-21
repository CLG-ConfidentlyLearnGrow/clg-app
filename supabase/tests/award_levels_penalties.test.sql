-- Summary: tests for the Miscellaneous Award rules (Carla, 18 Nov 2026):
--   1. a tutor is Level 1 for 3 months, then Level 2; Level 3 or 4 is chosen;
--   2. at 3 months a rate below the Level 2 minimum is raised from that day,
--      the owner is told once, and a Xero to-do is added;
--   3. award rates can be uploaded with a level;
--   4. penalty rate top-ups for Saturday, after 7pm and public holidays,
--      only when the tutor's own rate is below the award rate;
--   5. top-ups go on the Xero to-do list, and only the server can do that.
-- Reuses access_rules.test.sql people: owner (...a0), tutors T1 (...11) and
-- T2 (...12), and Cara One (an SA learner). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs both updates again: they must be safe to run twice.
-- (award levels and the move to Level 2)
\ir ../migrations/20261121700100_award_levels_three_months.sql
-- (penalty rates)
\ir ../migrations/20261121700200_award_penalty_rates.sql

-- Keeps today and Cara's student id.
select private.billing_today() as today, (select id from public.students where full_name = 'Cara One') as cara \gset
-- Keeps last Saturday, the Monday before it and the Tuesday before it (all in the past).
select (date_trunc('week', :'today'::date)::date - 2) as sat, (date_trunc('week', :'today'::date)::date - 7) as mon, (date_trunc('week', :'today'::date)::date - 6) as tue \gset

-- ---------------------------------------------------------------------------
-- 1. Levels
-- ---------------------------------------------------------------------------
-- T1: casual, $33.00 school rate, started 4 months ago. T2: casual, $32.50, started 10 days ago.
insert into public.billing_staff_pay (account_id, employment, school_rate_cents, started_on) values -- the two tutors' pay details:
  ('00000000-0000-0000-0000-000000000011', 'casual', 3300, :'today'::date - interval '4 months'), -- T1
  ('00000000-0000-0000-0000-000000000012', 'casual', 3250, :'today'::date - 10) -- T2
on conflict (account_id) do update set employment = excluded.employment, school_rate_cents = excluded.school_rate_cents, started_on = excluded.started_on, school_level = 1, guaranteed_weekly_minutes = null; -- or update them if they already exist
select tests.eq(private.billing_level_on('00000000-0000-0000-0000-000000000011', 'school', :'today'), 2, 'over 3 months is Level 2'); -- T1 is Level 2 today
select tests.eq(private.billing_level_on('00000000-0000-0000-0000-000000000011', 'school', (:'today'::date - interval '2 months')::date), 1, 'under 3 months is Level 1'); -- T1 was Level 1 two months ago
select tests.eq(private.billing_level_on('00000000-0000-0000-0000-000000000012', 'school', :'today'), 1, 'a new tutor is Level 1'); -- T2 is Level 1
select tests.eq(private.billing_level_on('00000000-0000-0000-0000-000000000011', 'tertiary', :'today'), 1, 'other work has no levels yet'); -- tertiary is Level 1
select tests.eq(private.billing_under_award('00000000-0000-0000-0000-000000000011', 'school', 3300, :'today')::int, 1, '$33.00 is under the Level 2 casual minimum'); -- $33.85 is the minimum
select tests.eq(private.billing_under_award('00000000-0000-0000-0000-000000000012', 'school', 3250, :'today')::int, 0, '$32.50 is fine at Level 1'); -- $32.18 is the minimum

-- ---------------------------------------------------------------------------
-- 2. The 3-month mark
-- ---------------------------------------------------------------------------
-- Moves T1's start back so 3 months were reached 20 days ago (a recent move).
update public.billing_staff_pay set started_on = (:'today'::date - 20 - interval '3 months')::date where account_id = '00000000-0000-0000-0000-000000000011'; -- T1 reached 3 months 20 days ago
select tests.claims(null); -- clears who is signed in (acts as the daily run)
select tests.eq(public.billing_apply_award_rates(), 1, 'one rate raised at 3 months'); -- runs the daily step
select tests.eq((select school_rate_cents from public.billing_staff_pay where account_id = '00000000-0000-0000-0000-000000000011'), 3385, 'raised to the Level 2 casual minimum'); -- T1 now $33.85
select tests.eq((select effective_from from public.billing_staff_rate_changes where account_id = '00000000-0000-0000-0000-000000000011' and new_cents = 3385) - :'today'::date, -20, 'the raise starts on the 3-month day'); -- from the day they reached 3 months
select tests.eq(private.billing_pay_rate_on('00000000-0000-0000-0000-000000000011', 'school', :'today'::date - 21), 3300, 'work before 3 months keeps the old rate'); -- the day before
select tests.eq((select school_rate_cents from public.billing_staff_pay where account_id = '00000000-0000-0000-0000-000000000012'), 3250, 'a new tutor is not changed'); -- T2 unchanged
select tests.eq((select count(*) from public.billing_xero_tasks where account_id = '00000000-0000-0000-0000-000000000011' and details like 'School tutoring classification: Miscellaneous Award Level 1 to Level 2%'), 1::bigint, 'a Xero to-do to change the classification'); -- the classification to-do
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'A tutor is now Level 2'), 1::bigint, 'the owner is told'); -- the owner's notice
select tests.eq(public.billing_apply_award_rates(), 0, 'running again changes nothing'); -- safe to repeat
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'A tutor is now Level 2'), 1::bigint, 'the owner is told only once'); -- no second notice

-- A changed start date goes on the Xero to-do list.
update public.billing_staff_pay set started_on = :'today'::date - 9 where account_id = '00000000-0000-0000-0000-000000000012'; -- T2's start date corrected
select tests.eq((select count(*) from public.billing_xero_tasks where account_id = '00000000-0000-0000-0000-000000000012' and details like '%Start date: % to ' || to_char(:'today'::date - 9, 'FMDD Mon YYYY') || '%'), 1::bigint, 'start date change listed for Xero'); -- the to-do for the corrected date

-- Only the owner and Finance see the levels.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner
set role authenticated; -- as a signed-in person, so the access rules apply
select tests.eq((select level from public.billing_staff_levels() where account_id = '00000000-0000-0000-0000-000000000011'), 2, 'owner sees T1 at Level 2'); -- the owner's view
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- signs in as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.billing_staff_levels()), 0::bigint, 'a tutor sees no levels'); -- nothing for tutors
reset role; -- back to the test runner

-- ---------------------------------------------------------------------------
-- 3. Uploading rates with a level
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.billing_upload_award_rates(%L, '[{"work_kind":"school","employment":"casual","level":7,"rate_cents":3500}]')$$, :'today'::date + 200), 'a level that does not exist'); -- Level 7 is refused
select tests.eq(public.billing_upload_award_rates(:'today'::date + 200, '[{"work_kind":"school","employment":"casual","rate_cents":3400},{"work_kind":"school","employment":"casual","level":2,"rate_cents":3550}]'), 0, 'future rates with levels saved'); -- Level 1 (no level given) and Level 2
reset role; -- back to the test runner
select tests.eq(((select string_agg(level || ':' || min_rate_cents, ',' order by level) from public.billing_award_rates where effective_from = :'today'::date + 200) = '1:3400,2:3550')::int, 1, 'each level kept separately'); -- both rows saved

-- ---------------------------------------------------------------------------
-- 4. Penalty rate top-ups
-- ---------------------------------------------------------------------------
-- T1 is based in SA (public holidays follow the tutor's state; Carla, 18 Nov 2026).
insert into public.tutor_work_settings (tutor_id, work_state) values ('00000000-0000-0000-0000-000000000011', 'SA') on conflict (tutor_id) do update set work_state = 'SA'; -- T1's work state
-- Sets aside any real public holidays (SA or Victoria) on last week's Monday,
-- Tuesday and Saturday, so these checks give the same result whatever week
-- the tests run in (for example Easter, Christmas or a long weekend). The
-- rollback at the end of this file puts them back.
delete from public.public_holidays where state in ('SA', 'VIC') and holiday_on in (:'mon'::date, :'tue'::date, :'sat'::date); -- clears real holidays on those three days
-- A public holiday in SA on last week's Tuesday.
insert into public.public_holidays (state, holiday_on, name) values ('SA', :'tue', 'Test holiday') on conflict do nothing; -- the holiday
-- Three completed sessions for T1 ($33.85): Saturday 10-11am, Monday 6:30-7:30pm, and the holiday 10-11am.
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status) values -- the sessions:
  (:'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', (:'sat'::date + time '10:00') at time zone 'Australia/Adelaide', (:'sat'::date + time '11:00') at time zone 'Australia/Adelaide', 'completed'), -- Saturday
  (:'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', (:'mon'::date + time '18:30') at time zone 'Australia/Adelaide', (:'mon'::date + time '19:30') at time zone 'Australia/Adelaide', 'completed'), -- Monday evening
  (:'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', (:'tue'::date + time '10:00') at time zone 'Australia/Adelaide', (:'tue'::date + time '11:00') at time zone 'Australia/Adelaide', 'completed'); -- the holiday
update public.sessions set worked_from = starts_at, worked_to = ends_at -- signed on and off on time
where tutor_id = '00000000-0000-0000-0000-000000000011' and status = 'completed' and worked_from is null; -- for those three sessions

select tests.claims(null); -- acts as the daily run
select public.billing_build_pay(:'mon'::date, :'sat'::date) as built \gset
-- (works out pay for those days; the count is kept but not checked)

-- Saturday: 60 min at 145% of $27.08 = $39.27/hr, minus $33.85 = $5.42.
select tests.eq((select l.amount_cents from public.billing_pay_lines l join public.sessions s on s.id = l.session_id where l.kind = 'penalty' and (s.starts_at at time zone 'Australia/Adelaide')::date = :'sat'), 542, 'Saturday top-up'); -- the Saturday line
-- Monday 6:30-7:30pm: 30 min before 7pm at 125% ($33.85, no top-up), 30 min after 7pm at $39.27: $2.71.
select tests.eq((select l.amount_cents from public.billing_pay_lines l join public.sessions s on s.id = l.session_id where l.kind = 'penalty' and (s.starts_at at time zone 'Australia/Adelaide')::date = :'mon'), 271, 'evening top-up for the time after 7pm only'); -- the Monday line
-- Holiday: 60 min at 250% of $27.08 = $67.70/hr, minus $33.85 = $33.85.
select tests.eq((select l.amount_cents from public.billing_pay_lines l join public.sessions s on s.id = l.session_id where l.kind = 'penalty' and (s.starts_at at time zone 'Australia/Adelaide')::date = :'tue'), 3385, 'public holiday top-up'); -- the holiday line
select tests.eq((select sum(minutes) from public.billing_pay_lines where account_id = '00000000-0000-0000-0000-000000000011' and kind = 'penalty'), 0::bigint, 'top-ups add no hours'); -- no double counting
select tests.eq((select count(*) from public.billing_pay_lines where kind = 'penalty' and note like 'Award penalty rate: 60 min Saturday at 145% ($39.27/hr)%'), 1::bigint, 'the note explains the top-up'); -- the note
select tests.eq((public.billing_build_pay(:'mon'::date, :'sat'::date) = :built)::int, 1, 'working out pay again gives the same lines'); -- safe to repeat
select tests.eq((select count(*) from public.billing_pay_lines where kind = 'penalty' and account_id = '00000000-0000-0000-0000-000000000011'), 3::bigint, 'still three top-ups after a re-run'); -- no duplicates

-- Public holidays follow the tutor's state, not the learner's: T1 moves to Victoria.
update public.tutor_work_settings set work_state = 'VIC' where tutor_id = '00000000-0000-0000-0000-000000000011'; -- T1 is now based in Victoria
select public.billing_build_pay(:'mon'::date, :'sat'::date) as built_vic \gset
-- (works out pay again)
select tests.eq((select count(*) from public.billing_pay_lines l join public.sessions s on s.id = l.session_id where l.kind = 'penalty' and (s.starts_at at time zone 'Australia/Adelaide')::date = :'tue'), 0::bigint, 'an SA holiday is not a holiday for a Victorian tutor'); -- no holiday top-up (the SA learner does not count)
insert into public.public_holidays (state, holiday_on, name) values ('VIC', :'tue', 'Test Victorian holiday') on conflict do nothing; -- the same day becomes a Victorian holiday
select public.billing_build_pay(:'mon'::date, :'sat'::date) as built_vic2 \gset
-- (works out pay again)
select tests.eq((select l.amount_cents from public.billing_pay_lines l join public.sessions s on s.id = l.session_id where l.kind = 'penalty' and (s.starts_at at time zone 'Australia/Adelaide')::date = :'tue'), 3385, 'a holiday in the tutor''s own state is paid'); -- the holiday top-up is back
update public.tutor_work_settings set work_state = 'SA' where tutor_id = '00000000-0000-0000-0000-000000000011'; -- T1 back in SA for the rest

-- A tutor paid above every award rate gets no top-up.
update public.billing_staff_pay set school_rate_cents = 7000 where account_id = '00000000-0000-0000-0000-000000000011'; -- T1 now $70/hr
delete from public.billing_staff_rate_changes where account_id = '00000000-0000-0000-0000-000000000011'; -- forgets the earlier raise, so $70 applies to those days
select public.billing_build_pay(:'mon'::date, :'sat'::date) as built2 \gset
-- (works out pay again at the new rate)
select tests.eq((select count(*) from public.billing_pay_lines where kind = 'penalty' and account_id = '00000000-0000-0000-0000-000000000011'), 0::bigint, 'no top-up above the award rates'); -- none
update public.billing_staff_pay set school_rate_cents = 3385 where account_id = '00000000-0000-0000-0000-000000000011'; -- back to $33.85
select public.billing_build_pay(:'mon'::date, :'sat'::date) as built3 \gset
-- (works out pay again, so the top-ups are back)

-- ---------------------------------------------------------------------------
-- 5. Top-ups to the Xero to-do list
-- ---------------------------------------------------------------------------
select array_agg(id)::text as penalty_ids from public.billing_pay_lines where kind = 'penalty' and account_id = '00000000-0000-0000-0000-000000000011' \gset
-- (keeps the top-up ids)
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.billing_note_penalty_pay(%L::uuid[])$$, :'penalty_ids'), 'signed-in person adds penalty to-dos'); -- only the server can
reset role; -- back to the test runner
select tests.claims(null); -- acts as the server
select tests.eq(public.billing_note_penalty_pay(:'penalty_ids'::uuid[]), 1, 'one to-do for the person'); -- one per person
select tests.eq((select count(*) from public.billing_xero_tasks where kind = 'penalty_pay' and account_id = '00000000-0000-0000-0000-000000000011' and details like 'Award penalty rate top-up of $41.98%'), 1::bigint, 'the to-do has the total'); -- $5.42 + $2.71 + $33.85

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  award levels and penalty rates: all checks passed'
