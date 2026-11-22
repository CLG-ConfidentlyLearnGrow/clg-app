-- Summary: tests for staff probation tracking (Carla, 20 Nov 2026):
--   1. the daily run sets up probation records for new tutors and admin
--      staff (never the owner);
--   2. a tutor is due at 30 completed sessions if that comes before 3 months,
--      and the owner is reminded once;
--   3. admin staff are due at 40 approved hours (one full-time work week);
--   4. anyone is due at 3 months if the target has not been reached;
--   5. the owner records passed, extended or ended, and an extension
--      reminds again on the new date;
--   6. only the owner can see or change probation records.
-- Reuses access_rules.test.sql people: owner Olive (...a0), operations admin
-- Sam (...b0), tutors T1 (...11) and T2 (...12), and Cara One (a learner).
-- Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the update again: it must be safe to run twice.
\ir ../migrations/20261123400100_staff_probation.sql
-- (admin probation changed to 40 hours)
\ir ../migrations/20261123700100_probation_admin_40_hours.sql

-- Keeps today and Cara's student id.
select private.billing_today() as today, (select id from public.students where full_name = 'Cara One') as cara \gset

-- ---------------------------------------------------------------------------
-- 1. Setting up records
-- ---------------------------------------------------------------------------
-- T1 started 40 days ago, Sam (admin) 20 days ago, T2 a year ago, and the owner 10 days ago.
insert into public.billing_staff_pay (account_id, employment, school_rate_cents, admin_rate_cents, started_on) values -- pay details:
  ('00000000-0000-0000-0000-000000000011', 'casual', 3500, null, :'today'::date - 40), -- T1
  ('00000000-0000-0000-0000-0000000000b0', 'casual', null, 3500, :'today'::date - 20), -- Sam
  ('00000000-0000-0000-0000-000000000012', 'casual', 3500, null, :'today'::date - 365), -- T2
  ('00000000-0000-0000-0000-0000000000a0', 'casual', null, 3500, :'today'::date - 10) -- the owner
on conflict (account_id) do update set employment = excluded.employment, school_rate_cents = excluded.school_rate_cents, admin_rate_cents = excluded.admin_rate_cents, started_on = excluded.started_on; -- or update them if they already exist
delete from public.staff_probations; -- starts with no records
select tests.claims(null); -- clears who is signed in (acts as the daily run)
select tests.eq(public.staff_probation_daily(), 0, 'nobody is due on the first run'); -- runs the daily step
select tests.eq((select count(*) from public.staff_probations where account_id = '00000000-0000-0000-0000-000000000011' and kind = 'tutor'), 1::bigint, 'a new tutor gets a record'); -- T1
select tests.eq((select count(*) from public.staff_probations where account_id = '00000000-0000-0000-0000-0000000000b0' and kind = 'admin'), 1::bigint, 'new admin staff get a record'); -- Sam
select tests.eq((select target from public.staff_probations where account_id = '00000000-0000-0000-0000-0000000000b0' and kind = 'admin'), 40, 'admin staff need 40 hours (one full-time week)'); -- Sam's target
select tests.eq((select target from public.staff_probations where account_id = '00000000-0000-0000-0000-000000000011' and kind = 'tutor'), 30, 'tutors still need 30 sessions'); -- T1's target
-- An admin record still at the old 30 hours moves to 40 when the change is run.
update public.staff_probations set target = 30 where account_id = '00000000-0000-0000-0000-0000000000b0'; -- pretends Sam's record is from before the change
\ir ../migrations/20261123700100_probation_admin_40_hours.sql
select tests.eq((select target from public.staff_probations where account_id = '00000000-0000-0000-0000-0000000000b0'), 40, 'old admin records move to 40 hours'); -- moved
select tests.eq((select target from public.staff_probations where account_id = '00000000-0000-0000-0000-000000000011'), 30, 'tutor records are not changed'); -- unchanged
select tests.eq((select count(*) from public.staff_probations where account_id = '00000000-0000-0000-0000-000000000012'), 0::bigint, 'someone who started a year ago is not set up'); -- T2
select tests.eq((select count(*) from public.staff_probations where account_id = '00000000-0000-0000-0000-0000000000a0'), 0::bigint, 'the owner is never set up'); -- the owner
select public.staff_probation_daily() as again \gset
-- (runs again: no duplicates)
select tests.eq((select count(*) from public.staff_probations), 2::bigint, 'running again adds no duplicates'); -- still two

-- ---------------------------------------------------------------------------
-- 2. A tutor reaching 30 sessions before 3 months
-- ---------------------------------------------------------------------------
-- 29 completed sessions, one a day from 35 days ago, plus one cancelled.
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status) -- the sessions:
select :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', -- T1 with Cara, online,
       ((:'today'::date - 36 + g) + time '10:00') at time zone 'Australia/Adelaide', -- 10am each day,
       ((:'today'::date - 36 + g) + time '11:00') at time zone 'Australia/Adelaide', -- to 11am,
       'completed' -- completed
from generate_series(1, 29) g; -- 29 days in a row
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status, cancelled_at) -- a cancelled session (does not count):
values (:'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', ((:'today'::date - 5) + time '15:00') at time zone 'Australia/Adelaide', ((:'today'::date - 5) + time '16:00') at time zone 'Australia/Adelaide', 'cancelled', now()); -- 5 days ago
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner
set role authenticated; -- as a signed-in person, so the access rules apply
select tests.eq((select done from public.staff_probation_list() where account_id = '00000000-0000-0000-0000-000000000011')::bigint, 29, 'counts completed sessions only'); -- 29 so far
select tests.eq((select (state = 'on_track')::int from public.staff_probation_list() where account_id = '00000000-0000-0000-0000-000000000011'), 1, 'not due at 29 sessions and 40 days'); -- not yet
reset role; -- back to the test runner
-- The 30th session, 3 days ago.
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status) -- one more:
values (:'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', ((:'today'::date - 3) + time '15:00') at time zone 'Australia/Adelaide', ((:'today'::date - 3) + time '16:00') at time zone 'Australia/Adelaide', 'completed'); -- completed
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner
set role authenticated; -- as a signed-in person
select tests.eq((select (state = 'due')::int from public.staff_probation_list() where account_id = '00000000-0000-0000-0000-000000000011'), 1, 'due at 30 sessions'); -- due now
select tests.eq((select due_on - :'today'::date from public.staff_probation_list() where account_id = '00000000-0000-0000-0000-000000000011'), -3, 'due on the day of the 30th session'); -- 3 days ago
select tests.eq(public.staff_probation_due_count(), 1, 'one due for the side menu'); -- the menu number
reset role; -- back to the test runner
select tests.claims(null); -- acts as the daily run
select tests.eq(public.staff_probation_daily(), 1, 'one reminder sent'); -- the daily step
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Probation review due: Tess Tutor' and body like '%reached 30 sessions%'), 1::bigint, 'the owner is told why'); -- the owner's notice
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000b0' and title like 'Probation review due%'), 0::bigint, 'operations admins are not told'); -- not Sam
select tests.eq(public.staff_probation_daily(), 0, 'running again sends nothing'); -- once only
select tests.eq((select count(*) from public.session_notices where title = 'Probation review due: Tess Tutor'), 1::bigint, 'the owner is told only once'); -- no second notice

-- ---------------------------------------------------------------------------
-- 3. Admin staff reaching 40 hours
-- ---------------------------------------------------------------------------
-- 39 approved hours, plus 1 hour still waiting for approval (not counted).
insert into public.billing_hour_logs (account_id, work_date, minutes, note, status) values -- Sam's hours:
  ('00000000-0000-0000-0000-0000000000b0', :'today'::date - 15, 600, 'Office work', 'approved'), -- 10 hours
  ('00000000-0000-0000-0000-0000000000b0', :'today'::date - 10, 600, 'Office work', 'approved'), -- 10 hours
  ('00000000-0000-0000-0000-0000000000b0', :'today'::date - 8, 600, 'Office work', 'approved'), -- 10 hours
  ('00000000-0000-0000-0000-0000000000b0', :'today'::date - 6, 540, 'Office work', 'approved'), -- 9 hours
  ('00000000-0000-0000-0000-0000000000b0', :'today'::date - 2, 60, 'Office work', 'submitted'); -- 1 hour, not approved yet
select tests.claims(null); -- acts as the daily run
select tests.eq(public.staff_probation_daily(), 0, 'not due at 39 approved hours'); -- nothing yet
update public.billing_hour_logs set status = 'approved' where account_id = '00000000-0000-0000-0000-0000000000b0' and status = 'submitted'; -- the last hour is approved
select tests.eq(public.staff_probation_daily(), 1, 'due once 40 hours are approved'); -- reminder sent
select tests.eq((select count(*) from public.session_notices where title = 'Probation review due: Sam Staff' and body like '%(admin)%reached 40 hours on%'), 1::bigint, 'the admin reminder says 40 hours'); -- the notice
select tests.eq((select (pr.reached_on - :'today'::date)::bigint from public.staff_probations p, private.staff_probation_progress(p.id) pr where p.account_id = '00000000-0000-0000-0000-0000000000b0'), -2, 'reached on the day the 40th hour was worked'); -- 2 days ago

-- ---------------------------------------------------------------------------
-- 4. Three months with fewer than 30 sessions
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner
set role authenticated; -- as a signed-in person
select public.staff_probation_start('00000000-0000-0000-0000-000000000012', 'tutor', (:'today'::date - interval '3 months')::date, 'Started before the app') as t2 \gset
-- (sets up T2's probation, started exactly 3 months ago)
select tests.eq((select (state = 'due')::int from public.staff_probation_list() where id = :'t2'), 1, 'due at 3 months with no sessions'); -- due by time
select tests.fails($$select public.staff_probation_start('00000000-0000-0000-0000-000000000012', 'tutor')$$, 'only one record per role'); -- no duplicate
select tests.fails($$select public.staff_probation_start('00000000-0000-0000-0000-000000000012', 'admin')$$, 'not an admin'); -- T2 is not staff admin
reset role; -- back to the test runner
select tests.claims(null); -- acts as the daily run
select tests.eq(public.staff_probation_daily(), 1, 'the 3-month reminder is sent'); -- reminder
select tests.eq((select count(*) from public.session_notices where title like 'Probation review due: %' and body like '%reached 3 months on%'), 1::bigint, 'the reminder says 3 months'); -- the notice

-- ---------------------------------------------------------------------------
-- 5. Recording the review
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.staff_probation_decide(%L, 'extended', %L)$$, :'t2', :'today'), 'an extension needs a future date'); -- today is refused
select public.staff_probation_decide(:'t2', 'extended', :'today'::date + 7, 'Needs more sessions first'); -- extends T2 by a week
select tests.eq((select (state = 'due_soon')::int from public.staff_probation_list() where id = :'t2'), 1, 'an extension is due soon, not now'); -- due soon
select tests.eq((select (note = 'Needs more sessions first')::int from public.staff_probation_list() where id = :'t2'), 1, 'the note is kept'); -- the note
select public.staff_probation_decide(id, 'passed') from public.staff_probations where account_id = '00000000-0000-0000-0000-000000000011'; -- T1 passes
select tests.eq((select (state = 'passed' and decided_at is not null)::int from public.staff_probation_list() where account_id = '00000000-0000-0000-0000-000000000011'), 1, 'marked passed'); -- passed
select tests.eq(public.staff_probation_due_count(), 1, 'only Sam is still due'); -- the menu number
reset role; -- back to the test runner
-- The extension date arrives: the owner is reminded again.
update public.staff_probations set extended_to = :'today'::date - 1 where id = :'t2'; -- pretends the week has passed
select tests.claims(null); -- acts as the daily run
select tests.eq(public.staff_probation_daily(), 1, 'reminded again on the extended date'); -- reminder
select tests.eq((select count(*) from public.session_notices where body like '%extended probation ends on%'), 1::bigint, 'the reminder mentions the extension'); -- the notice
select tests.eq((select count(*) from public.session_notices where title like 'Probation review due: Tess Tutor%'), 1::bigint, 'nobody who passed is reminded again'); -- T1 not again

-- ---------------------------------------------------------------------------
-- 6. Only the owner
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- signs in as Sam (operations)
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.staff_probation_list()), 0::bigint, 'operations admins see no probations'); -- nothing
select tests.eq((select count(*) from public.staff_probations), 0::bigint, 'operations admins cannot read the table'); -- nothing
select tests.eq(public.staff_probation_due_count(), 0, 'operations admins get no menu number'); -- zero
select tests.fails(format($$select public.staff_probation_decide(%L, 'passed')$$, :'t2'), 'operations admins cannot decide'); -- refused
select tests.fails($$select public.staff_probation_daily()$$, 'operations admins cannot run reminders'); -- refused
select tests.fails($$update public.staff_probations set status = 'passed'$$, 'nobody writes the table directly'); -- refused
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- signs in as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.staff_probations), 0::bigint, 'a tutor cannot read their own record'); -- nothing
select tests.fails($$select public.staff_probation_start('00000000-0000-0000-0000-000000000011', 'tutor')$$, 'a tutor cannot set up a probation'); -- refused
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal1'); -- the owner without two-step login
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.staff_probation_list()), 0::bigint, 'the owner needs two-step login'); -- nothing
reset role; -- back to the test runner

-- Undoes everything above.
rollback;
