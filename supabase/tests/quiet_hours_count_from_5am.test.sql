-- Summary: tests that anything done in quiet hours counts as done at 5am
-- (Carla, 22 Nov 2026). Earlier billing tests put back older billing files,
-- so this applies the make-up credit rules, the waiver and the change being
-- tested again first. Reuses Cara One (from access_rules.test.sql) and tutor
-- T1 (...11).
-- Checks: the moment something counts from, family credit for a cancel
-- saved in quiet hours, and that a daytime cancel is unchanged.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the make-up credit rules again (earlier billing tests put back older ones).
\ir ../migrations/20261118100300_makeup_cancel_pay_rules.sql
-- Runs the waiver change again (it holds the newest family credit rules).
\ir ../migrations/20261118410100_late_cancel_waiver.sql
-- Runs the change being tested.
\ir ../migrations/20261124711000_quiet_hours_count_from_5am.sql
-- Runs it a second time, to check it is safe to run more than once.
\ir ../migrations/20261124711000_quiet_hours_count_from_5am.sql

begin; -- Starts a change that is undone at the end, so nothing is left behind.
select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset

-- 1. When something counts from (Adelaide time, quiet 9pm to 5am).
select tests.eq((select count(*) from (select 1 where private.counts_from(timestamp '2027-03-10 23:00' at time zone 'Australia/Adelaide') = timestamp '2027-03-11 05:00' at time zone 'Australia/Adelaide') x), 1, '11pm counts from 5am the next morning'); -- Checks: late evening moves to 5am tomorrow.
select tests.eq((select count(*) from (select 1 where private.counts_from(timestamp '2027-03-11 01:30' at time zone 'Australia/Adelaide') = timestamp '2027-03-11 05:00' at time zone 'Australia/Adelaide') x), 1, '1:30am counts from 5am the same morning'); -- Checks: early morning moves to 5am today.
select tests.eq((select count(*) from (select 1 where private.counts_from(timestamp '2027-03-11 14:00' at time zone 'Australia/Adelaide') = timestamp '2027-03-11 14:00' at time zone 'Australia/Adelaide') x), 1, '2pm is unchanged'); -- Checks: daytime is not moved.
select tests.eq((select count(*) from (select 1 where private.counts_from(timestamp '2027-03-11 05:00' at time zone 'Australia/Adelaide') = timestamp '2027-03-11 05:00' at time zone 'Australia/Adelaide') x), 1, '5am itself is unchanged'); -- Checks: the end of quiet hours is not moved.
select tests.eq((select count(*) from (select 1 where private.counts_from(null) is null) x), 1, 'no time stays no time'); -- Checks: a missing time stays missing.

-- 2. Family credit for a cancel saved in quiet hours.
-- A 7am session cancelled at 11pm the night before: 8 hr real notice, but it counts from 5am, so 2 hr: half credit.
select tests.eq(private.billing_cancel_credit_percent(timestamp '2027-03-11 07:00' at time zone 'Australia/Adelaide', timestamp '2027-03-10 23:00' at time zone 'Australia/Adelaide', 'family', 'cancelled'), 50, '7am session cancelled at 11pm: counts as 2 hr notice, half credit'); -- Checks: half credit.
-- A 6:30am session cancelled at 1am: 5.5 hr real notice, but it counts from 5am, so 1.5 hr: no credit.
select tests.eq(private.billing_cancel_credit_percent(timestamp '2027-03-11 06:30' at time zone 'Australia/Adelaide', timestamp '2027-03-11 01:00' at time zone 'Australia/Adelaide', 'family', 'cancelled'), 0, '6:30am session cancelled at 1am: counts as 1.5 hr notice, no credit'); -- Checks: no credit.
-- A 4pm session cancelled at 10pm two nights before: 42 hr real, 35 hr from 5am: still full credit.
select tests.eq(private.billing_cancel_credit_percent(timestamp '2027-03-12 16:00' at time zone 'Australia/Adelaide', timestamp '2027-03-10 22:00' at time zone 'Australia/Adelaide', 'family', 'cancelled'), 100, 'a cancel in quiet hours with plenty of notice still gets full credit'); -- Checks: full credit.
-- A 4pm session cancelled the day before at 7pm (not quiet hours): 21 hr: half credit, as before.
select tests.eq(private.billing_cancel_credit_percent(timestamp '2027-03-11 16:00' at time zone 'Australia/Adelaide', timestamp '2027-03-10 19:00' at time zone 'Australia/Adelaide', 'family', 'cancelled'), 50, 'a daytime cancel is measured as before'); -- Checks: unchanged.
-- CLG or the tutor cancelling still gives full credit, whatever the time.
select tests.eq(private.billing_cancel_credit_percent(timestamp '2027-03-11 06:30' at time zone 'Australia/Adelaide', timestamp '2027-03-11 01:00' at time zone 'Australia/Adelaide', 'tutor', 'cancelled'), 100, 'a tutor cancel in quiet hours still gives the family full credit'); -- Checks: full credit.

-- 3. The session-level credit (with make-up times) uses the same moment.
insert into public.sessions (id, student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at, status, cancelled_at, cancelled_by_role) -- Adds a cancelled session:
select '00000000-0000-0000-0000-0000000e5a01', s.id, '00000000-0000-0000-0000-000000000011', s.family_id, 'General Maths', 'school', 'online', -- for Cara with T1,
       timestamp '2027-03-11 06:30' at time zone 'Australia/Adelaide', timestamp '2027-03-11 07:30' at time zone 'Australia/Adelaide', -- 6:30 to 7:30am,
       'cancelled', timestamp '2027-03-11 01:00' at time zone 'Australia/Adelaide', 'family' -- cancelled by the family at 1am
from public.students s where s.id = :'cara'; -- (using Cara's family)
select tests.eq(private.billing_session_credit_percent('00000000-0000-0000-0000-0000000e5a01'), 0, 'session credit: cancelled at 1am for 6:30am counts as under 2 hr, no credit'); -- Checks: no credit.

-- 4. Every rule that measures notice now uses the moment it counts from.
select tests.eq((select count(*) from pg_proc where prosrc like '%private.counts_from(%' and proname in ('billing_cancel_credit_percent', 'billing_session_credit_percent', 'billing_build_pay', 'billing_log_my_hours', 'my_no_show_sessions')), 5, 'all five notice rules count from the end of quiet hours'); -- Checks: all five changed.

rollback; -- Undoes everything this test added.
\echo '  quiet_hours_count_from_5am: all checks passed'
