-- Summary: tests that a session cannot be a no-show while a change to it was
-- waiting for approval (Carla, 22 Nov 2026; tutor contract clause 3.4).
-- Reuses Cara One (from access_rules.test.sql), tutor T1 (...11), tutor T3
-- (...13) and the owner admin (...a0). Sessions and changes are written
-- straight in. Everything is undone at the end.
-- Checks: a waiting change, a change answered after the start, a change
-- confirmed in time, and no change at all; the admins' notice; the credit;
-- and that pay skips these sessions.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the change being tested again (earlier tests put back older versions of some functions).
\ir ../migrations/20261124711100_pending_change_no_no_show.sql
-- Runs it a second time, to check it is safe to run more than once.
\ir ../migrations/20261124711100_pending_change_no_no_show.sql

begin; -- Starts a change that is undone at the end, so nothing is left behind.
select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset

-- Four sessions with T1 that started an hour ago, each in its own subject so each change covers only one.
insert into public.sessions (id, student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) values -- Adds the sessions:
  ('00000000-0000-0000-0000-0000000c4a01', :'cara', '00000000-0000-0000-0000-000000000011', 'Pending Maths', 'school', 'online', now() - interval '1 hour', now()), -- a change is still waiting,
  ('00000000-0000-0000-0000-0000000c4a02', :'cara', '00000000-0000-0000-0000-000000000011', 'Late Maths', 'school', 'online', now() - interval '1 hour', now()), -- a change was confirmed only after the start,
  ('00000000-0000-0000-0000-0000000c4a03', :'cara', '00000000-0000-0000-0000-000000000011', 'Done Maths', 'school', 'online', now() - interval '1 hour', now()), -- a change was confirmed before the start,
  ('00000000-0000-0000-0000-0000000c4a04', :'cara', '00000000-0000-0000-0000-000000000011', 'Plain Maths', 'school', 'online', now() - interval '1 hour', now()); -- no change at all.

-- The changes (from T1 to T3), all sent a day before.
insert into public.tutor_change_offers (student_id, from_tutor, to_tutor, subject, from_date, reason, status, created_at, closed_at) values -- Adds the changes:
  (:'cara', '00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000013', 'Pending Maths', current_date - 2, 'Test change', 'waiting', now() - interval '1 day', null), -- still waiting,
  (:'cara', '00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000013', 'Late Maths', current_date - 2, 'Test change', 'confirmed', now() - interval '1 day', now() - interval '10 minutes'), -- confirmed after the start,
  (:'cara', '00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000013', 'Done Maths', current_date - 2, 'Test change', 'confirmed', now() - interval '1 day', now() - interval '2 hours'); -- confirmed in time.

-- 1. Which sessions count as "changed but not approved in time".
select tests.eq((select count(*) from (values ('00000000-0000-0000-0000-0000000c4a01'::uuid), ('00000000-0000-0000-0000-0000000c4a02'::uuid)) v(id) where private.session_change_pending(v.id)), 2, 'a waiting change, and one answered after the start, both count'); -- Checks: both count.
select tests.eq((select count(*) from (values ('00000000-0000-0000-0000-0000000c4a03'::uuid), ('00000000-0000-0000-0000-0000000c4a04'::uuid)) v(id) where private.session_change_pending(v.id)), 0, 'a change confirmed in time, or no change, does not count'); -- Checks: neither counts.

-- 2. The tutor records no-shows.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.record_session_outcome('00000000-0000-0000-0000-0000000c4a01', 'no_show'); -- A no-show for the session with a waiting change.
select public.record_session_outcome('00000000-0000-0000-0000-0000000c4a02', 'no_show'); -- A no-show for the session with a late answer.
select public.record_session_outcome('00000000-0000-0000-0000-0000000c4a03', 'no_show'); -- A no-show for the session changed in time.
select public.record_session_outcome('00000000-0000-0000-0000-0000000c4a04', 'no_show'); -- A no-show for the plain session.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.eq((select count(*) from public.sessions where id in ('00000000-0000-0000-0000-0000000c4a01', '00000000-0000-0000-0000-0000000c4a02') and status = 'cancelled' and cancel_reason_kind = 'change_pending' and cancelled_by_role = 'admin'), 2, 'sessions with a change not approved in time are closed by CLG, not no-shows'); -- Checks: closed for CLG to rebook.
select tests.eq((select count(*) from public.sessions where id in ('00000000-0000-0000-0000-0000000c4a03', '00000000-0000-0000-0000-0000000c4a04') and status = 'no_show'), 2, 'the other sessions are no-shows as usual'); -- Checks: unchanged.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Session to rebook: change not approved in time'), 2, 'the owner is told to follow up and rebook each one'); -- Checks: one notice each.
select tests.eq(private.billing_session_credit_percent('00000000-0000-0000-0000-0000000c4a01'), 100, 'the family gets full credit'); -- Checks: no charge.
select tests.eq(private.billing_session_credit_percent('00000000-0000-0000-0000-0000000c4a04'), 0, 'a real no-show still gets no credit'); -- Checks: unchanged.

-- 3. Pay skips these sessions (the pay builder picks sessions without them).
select tests.eq((select count(*) from pg_proc where proname = 'billing_build_pay' and prosrc like '%<> ''change_pending''%'), 1, 'pay builder skips sessions closed because a change was waiting'); -- Checks: no no-show or late cancellation pay.
select tests.eq((select count(*) from pg_proc where proname = 'record_session_outcome' and prosrc like '%session_change_pending%'), 1, 'recording an outcome checks for a waiting change'); -- Checks: the check is in place.

rollback; -- Undoes everything this test added.
\echo '  pending change, no no-show: all checks passed'
