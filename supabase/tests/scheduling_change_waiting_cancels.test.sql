-- Summary: checks that a session is cancelled while a change to it is still
-- waiting for confirmation (Carla, 23 Nov 2026), and the three choices that
-- follow: confirm the change (the session comes back with the new tutor),
-- offer other times (a request for CLG), or keep it cancelled.
-- Reuses access_rules.test.sql people: owner Olive (...a0), operations admin
-- Sam Staff (...b0), tutor T1 (...11, Cara's tutor), tutor T2 (...12, the
-- new tutor) and parent P1 (...01, Cara's parent). Everything is undone at
-- the end.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the change being tested (earlier tests put back older versions of some functions).
\ir ../migrations/20261125400100_change_waiting_cancels_session.sql
-- Runs it a second time, to check it is safe to run more than once.
\ir ../migrations/20261125400100_change_waiting_cancels_session.sql

begin; -- Starts a change that is undone at the end, so nothing is left behind.
select tests.claims(null); -- Acts as the database itself while setting up.
select id as cara, family_id as fam from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's student id as cara and her family as fam)
\set sam '00000000-0000-0000-0000-0000000000b0'
-- (Sam Staff's account id, an operations admin)
\set t1 '00000000-0000-0000-0000-000000000011'
-- (tutor T1's account id, Cara's tutor now)
\set t2 '00000000-0000-0000-0000-000000000012'
-- (tutor T2's account id, the new tutor)
\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)
update public.tutor_assignments set starts_on = current_date - 30, ends_on = null where tutor_id = :'t1' and student_id = :'cara'; -- Makes T1's match with Cara clearly current.
update public.tutor_work_settings set max_weekly_hours = null where tutor_id = :'t2'; -- No hours limit on T2.
delete from public.tutor_assignments where tutor_id = :'t2' and student_id = :'cara'; -- T2 does not teach Cara yet.
update public.scheduling_settings set change_cancel_hours = 24; -- The default "cancel while waiting" time: 24 hr.

-- Gives T2 the South Australian checks, so they are cleared for Cara.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner (checks added by an admin count as verified).
set role authenticated; -- Acts as a signed-in person.
insert into public.tutor_checks (tutor_id, kind, reference, expires_on) values -- Adds T2's checks:
  (:'t2', 'wwcc_sa', 'WWCC-T2', current_date + 365), -- SA WWCC,
  (:'t2', 'rrhan_ec_fundamentals', null, current_date + 365), -- RRHAN-EC Fundamentals,
  (:'t2', 'rrhan_ec_masterclass', null, current_date + 365); -- and Masterclass, each for a year.
reset role; -- Back to the database itself.
select tests.claims(null); -- Acts as the database itself.

-- Three General Maths sessions with T1, online, on the hour:
insert into public.sessions (id, student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) values -- Adds the sessions:
  ('00000000-0000-0000-0000-0000000c5a01', :'cara', :'t1', :'fam', 'General Maths', 'school', 'online', date_trunc('hour', now()) + interval '10 hours', date_trunc('hour', now()) + interval '11 hours'), -- about 10 hr away (inside 24 hr),
  ('00000000-0000-0000-0000-0000000c5a02', :'cara', :'t1', :'fam', 'General Maths', 'school', 'online', date_trunc('hour', now()) + interval '1 hour', date_trunc('hour', now()) + interval '2 hours'), -- under 2 hr away,
  ('00000000-0000-0000-0000-0000000c5a03', :'cara', :'t1', :'fam', 'General Maths', 'school', 'online', date_trunc('hour', now()) + interval '3 days', date_trunc('hour', now()) + interval '3 days 1 hour'); -- 3 days away (outside 24 hr).

-- Sam sends the change from T1 to T2, starting today.
select tests.claims(:'sam', 'aal2'); -- Signs in as Sam with two-step sign-in.
set role authenticated; -- Acts as a signed-in person.
select public.propose_tutor_change(:'cara', :'t1', 'General Maths', :'t2', current_date, 'Tutor leaving CLG') as offer \gset
-- (keeps the waiting change's id as offer)
reset role; -- Back to the database itself.
select tests.claims(null); -- Acts as the database itself.

-- 1. The check: with a 5 hr setting nothing is close enough; with 24 hr only the 10 hr session is cancelled.
update public.scheduling_settings set change_cancel_hours = 5; -- A shorter setting, for this check.
select tests.eq(private.cancel_sessions_for_waiting_changes(), 0, 'with a 5 hr setting, nothing is cancelled yet'); -- Checks: none.
update public.scheduling_settings set change_cancel_hours = 24; -- Back to 24 hr.
select tests.eq(private.cancel_sessions_for_waiting_changes(), 1, 'with 24 hr, one session is cancelled'); -- Checks: one.
select tests.eq(private.cancel_sessions_for_waiting_changes(), 0, 'running the check again cancels nothing more'); -- Checks: once only.
select tests.eq((select count(*) from public.sessions where id = '00000000-0000-0000-0000-0000000c5a01' and status = 'cancelled' and cancelled_by_role = 'admin' and cancel_reason_kind = 'change_pending'), 1::bigint, 'the 10 hr session is cancelled by CLG because a change is waiting'); -- Checks: cancelled.
select tests.eq((select count(*) from public.sessions where id in ('00000000-0000-0000-0000-0000000c5a02', '00000000-0000-0000-0000-0000000c5a03') and status = 'scheduled'), 2::bigint, 'the session under 2 hr away and the one 3 days away stay booked'); -- Checks: unchanged.
select tests.eq(private.billing_session_credit_percent('00000000-0000-0000-0000-0000000c5a01'), 100, 'the family gets full credit'); -- Checks: no charge.
select tests.eq((select count(*) from public.change_cancelled_sessions where session_id = '00000000-0000-0000-0000-0000000c5a01' and offer_id = :'offer' and status = 'open'), 1::bigint, 'a record waits for a choice'); -- Checks: the record.
select tests.eq((select count(*) from public.session_notices where account_id = :'t1' and kind = 'change_cancelled' and title = 'Session cancelled'), 1::bigint, 'the current tutor is told the session is cancelled'); -- Checks: T1 told.
select tests.eq((select count(*) from public.session_notices where account_id = :'t2' and kind = 'change_cancelled' and title = 'Session cancelled: please choose what happens'), 1::bigint, 'the new tutor is asked to choose'); -- Checks: T2 asked.
select tests.eq((select count(*) from public.session_notices where account_id = :'p1' and kind = 'change_cancelled' and body like '%no charge%'), 1::bigint, 'the parent is asked to choose, and told there is no charge'); -- Checks: P1 asked.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Session cancelled: change still waiting'), 1::bigint, 'the owner is told'); -- Checks: admins told.

-- 2. Who sees the choice.
select tests.claims(:'p1'); -- Signs in as parent P1.
set role authenticated; -- Acts as a signed-in person.
select tests.eq((select count(*) from public.my_change_cancelled_sessions() where answer_as = 'family' and can_confirm and change_waiting), 1::bigint, 'the parent sees the session to choose for, and can confirm the change'); -- Checks: visible.
select tests.fails($q$select * from public.change_cancelled_sessions$q$, 'families cannot read the records directly'); -- Checks: refused.
reset role; -- Back to the database itself.
select tests.claims(:'t2', 'aal2'); -- Signs in as the new tutor T2.
set role authenticated; -- Acts as a signed-in person.
select tests.eq((select count(*) from public.my_change_cancelled_sessions() where answer_as = 'tutor' and from_tutor_name is null), 1::bigint, 'the new tutor sees it (without the old tutor''s name)'); -- Checks: visible.
reset role; -- Back to the database itself.
select tests.claims(:'t1', 'aal2'); -- Signs in as the current tutor T1.
set role authenticated; -- Acts as a signed-in person.
select tests.eq((select count(*) from public.my_change_cancelled_sessions()), 0::bigint, 'the current tutor is not asked to choose'); -- Checks: not theirs.
select tests.fails($q$select public.answer_change_cancelled_session('00000000-0000-0000-0000-0000000c5a01', 'kept_cancelled')$q$, 'the current tutor cannot choose'); -- Checks: refused.
reset role; -- Back to the database itself.

-- 3. "Keep it cancelled" (tried, then undone so the other paths can be checked).
savepoint keep_path; -- A point to go back to.
select tests.claims(:'p1'); -- Signs in as parent P1.
set role authenticated; -- Acts as a signed-in person.
select tests.fails($q$select public.answer_change_cancelled_session('00000000-0000-0000-0000-0000000c5a01', 'maybe')$q$, 'only the two choices are allowed'); -- Checks: refused.
select tests.eq((public.answer_change_cancelled_session('00000000-0000-0000-0000-0000000c5a01', 'kept_cancelled') = 'kept_cancelled')::int, 1, 'the parent keeps it cancelled'); -- Checks: saved.
select tests.fails($q$select public.answer_change_cancelled_session('00000000-0000-0000-0000-0000000c5a01', 'other_times', 'Friday 4pm')$q$, 'a second choice is refused'); -- Checks: first answer counts.
reset role; -- Back to the database itself.
select tests.claims(null); -- Acts as the database itself.
select tests.eq((select count(*) from public.session_notices where account_id = :'t2' and title = 'Session staying cancelled'), 1::bigint, 'the new tutor is told'); -- Checks: T2 told.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Cancelled session kept cancelled'), 1::bigint, 'the owner is told'); -- Checks: admins told.
select tests.claims(:'t2', 'aal2'); -- Signs in as T2.
set role authenticated; -- Acts as a signed-in person.
select public.answer_tutor_change(:'offer', true); -- T2 confirms the change.
reset role; -- Back to the database itself.
select tests.claims(:'p1'); -- Signs in as P1.
set role authenticated; -- Acts as a signed-in person.
select tests.eq((public.answer_tutor_change(:'offer', true) = 'confirmed')::int, 1, 'the change is made once both confirm'); -- Checks: confirmed.
reset role; -- Back to the database itself.
select tests.claims(null); -- Acts as the database itself.
select tests.eq((select count(*) from public.sessions where id = '00000000-0000-0000-0000-0000000c5a01' and status = 'cancelled'), 1::bigint, 'a session kept cancelled does not come back'); -- Checks: stays cancelled.
select tests.eq((select count(*) from public.sessions where id in ('00000000-0000-0000-0000-0000000c5a02', '00000000-0000-0000-0000-0000000c5a03') and tutor_id = :'t2' and status = 'scheduled'), 2::bigint, 'the other sessions move to the new tutor'); -- Checks: moved.
rollback to savepoint keep_path; -- Goes back to before the choice.

-- 4. "Offer other times" from the family makes a request for CLG.
savepoint times_path; -- A point to go back to.
select tests.claims(:'p1'); -- Signs in as parent P1.
set role authenticated; -- Acts as a signed-in person.
select tests.fails($q$select public.answer_change_cancelled_session('00000000-0000-0000-0000-0000000c5a01', 'other_times', '')$q$, 'other times need the days and times that suit'); -- Checks: refused.
select tests.eq((public.answer_change_cancelled_session('00000000-0000-0000-0000-0000000c5a01', 'other_times', 'Friday after 4pm') = 'other_times')::int, 1, 'the parent offers other times'); -- Checks: saved.
reset role; -- Back to the database itself.
select tests.claims(null); -- Acts as the database itself.
select tests.eq((select count(*) from public.session_requests r join public.change_cancelled_sessions c on c.request_id = r.id where c.session_id = '00000000-0000-0000-0000-0000000c5a01' and r.status = 'open' and r.note = 'Friday after 4pm' and r.tutor_id = :'t2'), 1::bigint, 'a request with the times goes to CLG''s Requests list'); -- Checks: request made.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Other times offered for a cancelled session' and body like '%Friday after 4pm%'), 1::bigint, 'the owner is told the times'); -- Checks: admins told.
rollback to savepoint times_path; -- Goes back to before the choice.

-- 5. "Confirm the change": once both confirm, the cancelled session comes back with the new tutor.
select tests.claims(:'t2', 'aal2'); -- Signs in as T2.
set role authenticated; -- Acts as a signed-in person.
select public.answer_tutor_change(:'offer', true); -- T2 confirms the change.
reset role; -- Back to the database itself.
select tests.claims(:'p1'); -- Signs in as P1.
set role authenticated; -- Acts as a signed-in person.
select tests.eq((public.answer_tutor_change(:'offer', true) = 'confirmed')::int, 1, 'the change is made once both confirm'); -- Checks: confirmed.
select tests.eq((select count(*) from public.my_change_cancelled_sessions()), 0::bigint, 'nothing is left to choose'); -- Checks: card gone.
reset role; -- Back to the database itself.
select tests.claims(null); -- Acts as the database itself.
select tests.eq((select count(*) from public.sessions where id = '00000000-0000-0000-0000-0000000c5a01' and status = 'scheduled' and tutor_id = :'t2' and cancel_reason_kind is null and cancelled_at is null), 1::bigint, 'the cancelled session is back on, with the new tutor'); -- Checks: restored and moved.
select tests.eq((select count(*) from public.change_cancelled_sessions where session_id = '00000000-0000-0000-0000-0000000c5a01' and status = 'restored'), 1::bigint, 'the record says it came back'); -- Checks: marked restored.
select tests.eq((select count(*) from public.sessions where student_id = :'cara' and tutor_id = :'t2' and status = 'scheduled'), 3::bigint, 'all three sessions are now with the new tutor'); -- Checks: all moved.
select tests.eq((select count(*) from pg_proc where proname = 'finish_tutor_change' and prosrc like '%restore_change_cancelled_sessions%'), 1::bigint, 'making a change brings back sessions cancelled while it waited'); -- Checks: the step is in place.

rollback; -- Undoes everything this test added.
\echo '  change waiting cancels session: all checks passed'
