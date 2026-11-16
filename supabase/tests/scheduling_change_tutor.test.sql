-- Summary: checks moving a student's booked sessions to a new tutor (Carla,
-- 15 Nov 2026): only matching admins with two-step sign-in can send a
-- change; the usual matching rules apply (checks, subject, clashes, most
-- hours, blocks); nothing moves until the new tutor and the family have both
-- confirmed; a no (with a reason) stops it; then the same sessions move (so
-- invoice lines stay with them), a started weekly booking is split, a
-- waiting request goes to the new tutor, the new tutor is matched and the
-- old match ends, everyone is told, and a record is kept that only matching
-- admins can read. The day and time can change too, for one weekly pattern. Reuses access_rules.test.sql
-- people: owner Olive (...a0), operations admin Sam Staff (...b0), tutor T1
-- (...11, teaches Cara General Maths), tutor T2 (...12, General Maths Years
-- 1 to 12), parent P1 (...01, Cara's parent). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this database change again (checks it can run twice).
\ir ../migrations/20261117600100_change_tutor.sql
-- Runs the day, time and confirmation change again too (it replaces parts of the one above).
\ir ../migrations/20261117600300_change_tutor_times.sql

select tests.claims(null); -- acts as the database itself while setting up
select id as cara, family_id as fam from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's student id as cara and her family as fam)
select id as vic, family_id as vfam from public.students where full_name = 'Vic Two' \gset
-- (keeps Vic's student id as vic and her family as vfam, for a clashing session)
\set sam '00000000-0000-0000-0000-0000000000b0'
-- (Sam Staff's account id, an operations admin)
\set t1 '00000000-0000-0000-0000-000000000011'
-- (tutor T1's account id, Cara's tutor now)
\set t2 '00000000-0000-0000-0000-000000000012'
-- (tutor T2's account id, the new tutor)
\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)
update public.tutor_assignments set starts_on = current_date - 30, ends_on = null where tutor_id = :'t1' and student_id = :'cara'; -- makes T1's match with Cara clearly current
update public.tutor_work_settings set max_weekly_hours = null where tutor_id = :'t2'; -- no hours limit on T2 to start with
delete from public.tutor_assignments where tutor_id = :'t2' and student_id = :'cara'; -- T2 doesn't teach Cara yet

-- Gives T2 the South Australian checks, so they're cleared for Cara.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner (checks added by an admin count as verified)
set role authenticated; -- acts as a signed-in person
insert into public.tutor_checks (tutor_id, kind, reference, expires_on) values -- adds T2's checks:
  (:'t2', 'wwcc_sa', 'WWCC-T2', current_date + 365), -- SA WWCC,
  (:'t2', 'rrhan_ec_fundamentals', null, current_date + 365), -- RRHAN-EC Fundamentals,
  (:'t2', 'rrhan_ec_masterclass', null, current_date + 365); -- and Masterclass, each for a year
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
select tests.eq(private.tutor_cleared_for_student(:'t2', :'cara')::int, 1, 'set-up: T2 is cleared for Cara'); -- starting point

-- A weekly General Maths booking with T1 that started two weeks ago, 4pm online, for 7 weeks.
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, status, confirmed_at, requested_by) -- the booking:
values (:'cara', :'t1', :'fam', 'General Maths', extract(isodow from current_date + 3)::smallint, '16:00', 60, 'online', current_date - 11, current_date + 31, 'confirmed', now(), :'sam') -- on the weekday 3 days from now
returning id as bk \gset
-- (keeps the booking's id as bk)
insert into public.sessions (booking_id, student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) -- its weekly sessions:
select :'bk', :'cara', :'t1', :'fam', 'General Maths', 'school', 'online', -- each an hour of General Maths online
  ((current_date + d) + time '16:00') at time zone 'Australia/Adelaide', ((current_date + d) + time '17:00') at time zone 'Australia/Adelaide' -- at 4pm Adelaide time
from unnest(array[-11, -4, 3, 10, 17, 24, 31]) d; -- two in the past, five to come
insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) -- and one extra session (not part of a booking):
values (:'cara', :'t1', :'fam', 'General Maths', 'school', 'online', ((current_date + 5) + time '10:00') at time zone 'Australia/Adelaide', ((current_date + 5) + time '11:00') at time zone 'Australia/Adelaide'); -- in 5 days, 10am
insert into public.billing_invoices (family_id, family_name, plan, method, status, period_start, period_end, first_session_on, send_on, due_on, charge_on) -- a paid invoice:
values (:'fam', 'Test family', 'term', 'card', 'paid', current_date, current_date + 30, current_date + 3, current_date, current_date, current_date) -- for this term
returning id as inv \gset
-- (keeps the invoice's id as inv)
insert into public.billing_invoice_lines (invoice_id, session_id, student_id, line_date, description, minutes, billed_minutes, hourly_cents, amount_cents) -- the next session is on it:
select :'inv', s.id, :'cara', current_date + 3, 'General Maths', 60, 60, 9500, 9500 from public.sessions s -- one line
where s.booking_id = :'bk' and s.starts_at > now() order by s.starts_at limit 1 -- (the first one to come)
returning session_id as paid_session \gset
-- (keeps that session's id as paid_session)
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by) -- a second weekly request still waiting for T1:
values (:'cara', :'t1', :'fam', 'General Maths', extract(isodow from current_date + 4)::smallint, '17:00', 60, 'online', current_date + 4, current_date + 32, now() + interval '1 day', :'p1') -- (another day, 5pm)
returning id as req \gset
-- (keeps the request's id as req)
insert into public.session_notices (account_id, session_id, kind, title, body, deliver_at) -- a reminder already waiting for P1 about the paid session:
values (:'p1', :'paid_session', 'reminder_first', 'Upcoming session', 'General Maths with Tess', now() + interval '2 days'); -- (names the old tutor)

-- 1. Only matching admins with two-step sign-in can send a change.
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'General Maths', %L, current_date, 'Trying')$q$, :'cara', :'t1', :'t2'), 'a tutor cannot send a change'); -- refused
select tests.fails($q$select * from public.tutor_change_pairs()$q$, 'a tutor cannot list sessions to move'); -- refused
select tests.fails($q$select * from public.tutor_change_offers$q$, 'nobody reads waiting changes directly'); -- refused
reset role; -- back to the database itself
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'General Maths', %L, current_date, 'Trying')$q$, :'cara', :'t1', :'t2'), 'a parent cannot send a change'); -- refused
reset role; -- back to the database itself
select tests.claims(:'sam'); -- signs in as Sam without two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'General Maths', %L, current_date, 'Trying')$q$, :'cara', :'t1', :'t2'), 'an admin needs two-step sign-in'); -- refused
reset role; -- back to the database itself

-- 2. The page's lists.
select tests.claims(:'sam', 'aal2'); -- signs in as Sam with two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.eq((select upcoming_sessions from public.tutor_change_pairs(:'cara') where tutor_id = :'t1' and subject = 'General Maths'), 6, 'Cara has 6 upcoming sessions with T1'); -- 5 weekly and 1 extra
select tests.eq((select paid_sessions from public.tutor_change_pairs(:'cara') where tutor_id = :'t1'), 1, 'one of them is already on an invoice'); -- the paid one
select tests.eq((select count(*) from public.tutor_change_candidates(:'cara', :'t1', 'General Maths', current_date) where tutor_id = :'t2' and clashes = 0 and not at_max), 1::bigint, 'T2 is a free candidate'); -- listed and free
select tests.eq((select count(*) from public.tutor_change_candidates(:'cara', :'t1', 'General Maths', current_date) where tutor_id = :'t1'), 0::bigint, 'the current tutor is not a candidate'); -- not listed
select tests.eq((select count(*) from public.tutor_change_pattern(:'cara', :'t1', 'General Maths', current_date) where not same_pattern), 1::bigint, 'with the extra session, they are not all on one day and time'); -- mixed
select tests.eq((select count(*) from public.tutor_change_pattern(:'cara', :'t1', 'General Maths', current_date + 6) where same_pattern and start_time = '16:00'), 1::bigint, 'after it, they are all at 4pm on one day'); -- one pattern
reset role; -- back to the database itself

-- 3. The matching rules.
select tests.claims(null); -- acts as the database itself
insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) -- T2 already has a session at one of the same times:
values (:'vic', :'t2', :'vfam', 'Science', 'school', 'online', ((current_date + 10) + time '16:30') at time zone 'Australia/Adelaide', ((current_date + 10) + time '17:30') at time zone 'Australia/Adelaide') -- (overlaps 4pm in 10 days)
returning id as clash \gset
-- (keeps it as clash)
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select tests.eq((select clashes from public.tutor_change_candidates(:'cara', :'t1', 'General Maths', current_date) where tutor_id = :'t2'), 1, 'the clash shows on the candidate'); -- shown
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'General Maths', %L, current_date, 'Tutor leaving')$q$, :'cara', :'t1', :'t2'), 'a clashing tutor is refused'); -- refused
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
update public.sessions set status = 'cancelled', cancelled_at = now() where id = :'clash'; -- clears the clash
update public.tutor_work_settings set max_weekly_hours = 1 where tutor_id = :'t2'; -- T2 may only teach 1 hr a week
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'General Maths', %L, current_date, 'Tutor leaving')$q$, :'cara', :'t1', :'t2'), 'going past the tutor''s most hours is refused'); -- refused (2 hr a week would move)
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
update public.tutor_work_settings set max_weekly_hours = null where tutor_id = :'t2'; -- removes the limit again
insert into public.match_blocks (tutor_id, student_id, blocked_by_role, reason) values (:'t2', :'cara', 'family', 'Family asked for a different tutor.') returning id as blk \gset
-- (blocks T2 from Cara for the next check, keeping it as blk)
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'General Maths', %L, current_date, 'Tutor leaving')$q$, :'cara', :'t1', :'t2'), 'a blocked tutor is refused'); -- refused
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
delete from public.match_blocks where id = :'blk'; -- removes the block
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'General Maths', %L, current_date, '')$q$, :'cara', :'t1', :'t2'), 'a reason is needed'); -- refused
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'General Maths', %L, current_date - 1, 'Tutor leaving')$q$, :'cara', :'t1', :'t2'), 'the date cannot be in the past'); -- refused
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'Science', %L, current_date, 'Tutor leaving')$q$, :'cara', :'t1', :'t2'), 'nothing to move in another subject'); -- refused
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'General Maths', %L, current_date, 'Tutor leaving', true, 1::smallint, '17:00')$q$, :'cara', :'t1', :'t2'), 'the day and time cannot change when sessions are on different days'); -- refused (the extra session differs)
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'General Maths', %L, current_date + 6, 'Tutor leaving', true, null, '17:10')$q$, :'cara', :'t1', :'t2'), 'start times are on the quarter hour'); -- refused

-- 4. The change, from tomorrow: sent, then confirmed by both.
select public.propose_tutor_change(:'cara', :'t1', 'General Maths', :'t2', current_date + 1, 'Tutor leaving CLG') as offer \gset
-- (keeps the waiting change's id as offer)
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'General Maths', %L, current_date + 1, 'Again')$q$, :'cara', :'t1', :'t2'), 'only one waiting change at a time'); -- refused
select tests.eq((select count(*) from public.tutor_change_offers_list(:'cara') where status = 'waiting' and sessions = 6 and not tutor_ok and not family_ok), 1::bigint, 'the admin sees it waiting for both'); -- waiting
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
select tests.eq((select count(*) from public.sessions where student_id = :'cara' and tutor_id = :'t2'), 0::bigint, 'nothing has moved yet'); -- not yet
select tests.eq((select count(*) from public.session_notices where account_id = :'t2' and title = 'Please confirm new sessions'), 1::bigint, 'T2 is asked to confirm'); -- asked
select tests.eq((select count(*) from public.session_notices where account_id = :'p1' and title = 'Please confirm a change'), 1::bigint, 'the parent is asked to confirm'); -- asked
select tests.eq((select count(*) from public.session_notices where account_id = :'t1' and title = 'Sessions moved'), 0::bigint, 'T1 is not told yet'); -- not yet
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1 (the old tutor)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_tutor_changes_to_answer()), 0::bigint, 'the old tutor is not asked'); -- not theirs
select tests.fails(format($q$select public.answer_tutor_change(%L, true)$q$, :'offer'), 'the old tutor cannot answer'); -- refused
reset role; -- back to the database itself
select tests.claims(:'t2', 'aal2'); -- signs in as tutor T2 (the new tutor)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_tutor_changes_to_answer() where answer_as = 'tutor' and from_tutor_name is null), 1::bigint, 'T2 sees it to answer (without the old tutor''s name)'); -- theirs
select tests.eq((select count(*) from public.my_tutor_changes_to_answer() t where to_jsonb(t) ? 'reason'), 0::bigint, 'and never the admin''s reason'); -- hidden
select tests.eq(length(public.answer_tutor_change(:'offer', true)), 7::bigint, 'T2 confirms (still waiting)'); -- 'waiting'
select tests.fails(format($q$select public.answer_tutor_change(%L, true)$q$, :'offer'), 'T2 cannot confirm twice'); -- refused
reset role; -- back to the database itself
select tests.eq((select count(*) from public.sessions where student_id = :'cara' and tutor_id = :'t2'), 0::bigint, 'still nothing moved until the family confirms'); -- not yet
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_tutor_changes_to_answer() where answer_as = 'family' and to_tutor_name = 'Tom Tutor'), 1::bigint, 'the parent sees it to answer'); -- theirs
select tests.fails($q$select * from public.tutor_change_offers_list()$q$, 'families cannot see the admin list'); -- refused
select tests.eq(length(public.answer_tutor_change(:'offer', true)), 9::bigint, 'the parent confirms, and the change is made'); -- 'confirmed'
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
select tests.eq((select count(*) from public.sessions where student_id = :'cara' and tutor_id = :'t2' and status = 'scheduled'), 6::bigint, 'all six are now with T2'); -- moved
select tests.eq((select count(*) from public.sessions where booking_id = :'bk' and tutor_id = :'t1' and starts_at < now()), 2::bigint, 'past sessions stay with T1'); -- history kept
select tests.eq((select count(*) from public.billing_invoice_lines l join public.sessions s on s.id = l.session_id where l.invoice_id = :'inv' and s.tutor_id = :'t2'), 1::bigint, 'the paid session is still on the invoice, now with T2'); -- paid stays paid
select tests.eq((select count(*) from public.bookings where id = :'bk' and last_date = current_date + 2), 1::bigint, 'the old booking ends the day before the first moved session'); -- split
select tests.eq((select count(*) from public.bookings where renews_booking = :'bk' and tutor_id = :'t2' and status = 'confirmed' and first_date = current_date + 3 and last_date = current_date + 31), 1::bigint, 'a new booking with T2 carries on to the same end date'); -- carried on
select tests.eq((select count(*) from public.sessions s join public.bookings b on b.id = s.booking_id where b.renews_booking = :'bk' and s.tutor_id = :'t2'), 5::bigint, 'the moved weekly sessions belong to the new booking'); -- linked
select tests.eq((select count(*) from public.bookings where id = :'req' and tutor_id = :'t2' and status = 'requested' and tutor_reply_by > now() + interval '47 hours'), 1::bigint, 'the waiting request goes to T2 with 48 hours to answer'); -- request moved
select tests.eq((select count(*) from public.tutor_assignments where tutor_id = :'t2' and student_id = :'cara' and private.assignment_is_current(starts_on, ends_on)), 1::bigint, 'T2 is now matched with Cara'); -- matched
select tests.eq((select count(*) from public.tutor_assignments where tutor_id = :'t1' and student_id = :'cara' and lower(subject) = 'general maths' and ends_on = current_date), 1::bigint, 'T1''s match with Cara ends today'); -- ended
select tests.eq((select count(*) from public.session_notices where session_id = :'paid_session' and kind = 'reminder_first'), 0::bigint, 'the old reminder (naming T1) is withdrawn'); -- withdrawn
select tests.eq((select count(*) from public.session_notices where account_id = :'t2' and title = 'Change confirmed'), 1::bigint, 'T2 is told it is done'); -- new tutor told
select tests.eq((select count(*) from public.session_notices where account_id = :'p1' and title = 'Change confirmed' and body like '%Tom Tutor%'), 1::bigint, 'the parent is told, with the new tutor''s name'); -- family told
select tests.eq((select count(*) from public.session_notices where account_id = :'t1' and title = 'Sessions moved' and body not like '%leaving%'), 1::bigint, 'T1 gets a plain notice, with no reason'); -- old tutor told
select tests.eq((select count(*) from public.tutor_changes where student_id = :'cara' and sessions_moved = 6 and bookings_moved = 2 and changed_by = :'sam'), 1::bigint, 'the change is recorded as Sam''s'); -- recorded
select tests.eq((select count(*) from public.tutor_change_offers where id = :'offer' and status = 'confirmed' and change_id is not null), 1::bigint, 'the waiting change is marked confirmed'); -- closed

-- 5. Who can read the record.
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.recent_tutor_changes(:'cara') where reason = 'Tutor leaving CLG' and to_tutor_name = 'Tom Tutor'), 1::bigint, 'matching admins see the change'); -- visible
select tests.fails(format($q$select public.propose_tutor_change(%L, %L, 'General Maths', %L, current_date, 'Again')$q$, :'cara', :'t1', :'t2'), 'nothing left to move a second time'); -- refused
select tests.fails($q$update public.tutor_changes set reason = 'Changed'$q$, 'nobody edits the record directly'); -- refused
reset role; -- back to the database itself
select tests.claims(:'t2', 'aal2'); -- signs in as tutor T2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.tutor_changes), 0::bigint, 'tutors cannot read the record'); -- hidden
reset role; -- back to the database itself
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.recent_tutor_changes()), 0::bigint, 'families cannot read the record'); -- hidden
reset role; -- back to the database itself

-- 6. Back to T1 on a new day and time, without telling T2: a no, a failure, then a yes.
select tests.claims(null); -- acts as the database itself
select (case when extract(isodow from current_date + 3)::int > 1 then extract(isodow from current_date + 3)::int - 1 else 2 end) as newday \gset
-- (keeps the new weekday as newday: the day before the booked one, or Tuesday if booked on Monday)
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select public.propose_tutor_change(:'cara', :'t2', 'General Maths', :'t1', current_date + 20, 'Safety re-match', false, :'newday'::smallint, '17:00') as back1 \gset
-- (sends the change, keeping its id as back1)
reset role; -- back to the database itself
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_tutor_changes_to_answer() where new_time like '%at 5:00pm' and old_time like '%at 4:00pm'), 1::bigint, 'the parent sees the old and new times'); -- shown
select tests.fails(format($q$select public.answer_tutor_change(%L, false, '')$q$, :'back1'), 'saying no needs a reason'); -- refused
select tests.eq(length(public.answer_tutor_change(:'back1', false, 'Thursdays do not suit us.')), 8::bigint, 'the parent says no'); -- 'declined'
reset role; -- back to the database itself
select tests.eq((select count(*) from public.sessions where student_id = :'cara' and tutor_id = :'t1' and starts_at > now()), 0::bigint, 'nothing moves after a no'); -- nothing
select tests.eq((select count(*) from public.session_notices where kind = 'staff_alert' and title = 'Tutor change declined' and body like '%do not suit%'), (select count(distinct ar.account_id) from public.account_roles ar left join public.admin_profiles ap on ap.account_id = ar.account_id where ar.role = 'admin' and coalesce(ap.level, 'owner') in ('owner', 'operations')), 'full admins are told why'); -- told
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select public.propose_tutor_change(:'cara', :'t2', 'General Maths', :'t1', current_date + 20, 'Safety re-match', false, :'newday'::smallint, '17:00') as back2 \gset
-- (sends it again, keeping its id as back2)
reset role; -- back to the database itself
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1 (the new tutor this time)
set role authenticated; -- acts as a signed-in person
select public.answer_tutor_change(:'back2', true); -- T1 confirms
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) -- meanwhile T1 is booked at the new time:
select :'vic', :'t1', :'vfam', 'Science', 'school', 'online', (m.local_date + time '17:00') at time zone 'Australia/Adelaide', (m.local_date + time '18:00') at time zone 'Australia/Adelaide' -- an hour at 5pm,
from private.moved_times((select array_agg(id) from public.sessions where student_id = :'cara' and tutor_id = :'t2' and starts_at > now() + interval '20 days'), :'newday'::smallint, '17:00', 'Australia/Adelaide') m limit 1 -- on one of the new days
returning id as clash2 \gset
-- (keeps it as clash2)
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq(length(public.answer_tutor_change(:'back2', true)), 6::bigint, 'the parent confirms, but the change cannot be made now'); -- 'failed'
reset role; -- back to the database itself
select tests.eq((select count(*) from public.sessions where student_id = :'cara' and tutor_id = :'t1' and starts_at > now()), 0::bigint, 'nothing moves when it fails'); -- nothing
select tests.eq((select count(*) from public.tutor_change_offers where id = :'back2' and closed_note like '%same time%'), 1::bigint, 'and the reason is kept for admins'); -- why
delete from public.sessions where id = :'clash2'; -- clears the clash
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select public.propose_tutor_change(:'cara', :'t2', 'General Maths', :'t1', current_date + 20, 'Safety re-match', false, :'newday'::smallint, '17:00') as back3 \gset
-- (sends it a third time, keeping its id as back3)
reset role; -- back to the database itself
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select public.answer_tutor_change(:'back3', true); -- T1 confirms
reset role; -- back to the database itself
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq(length(public.answer_tutor_change(:'back3', true)), 9::bigint, 'the parent confirms, and it is made'); -- 'confirmed'
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
select tests.eq((select count(*) from public.sessions where student_id = :'cara' and tutor_id = :'t1' and starts_at > now() -- two sessions moved back to T1,
  and extract(isodow from starts_at at time zone 'Australia/Adelaide') = :newday and (starts_at at time zone 'Australia/Adelaide')::time = '17:00'), 2::bigint, 'two later sessions move to T1 at 5pm on the new day'); -- (on the new day at 5pm)
select tests.eq((select count(*) from public.bookings where tutor_id = :'t1' and student_id = :'cara' and status = 'confirmed' and weekday = :newday and start_time = '17:00' and last_date >= current_date + 30), 1::bigint, 'the booking that carries on has the new day and time'); -- booking updated
select tests.eq((select count(*) from public.session_notices where account_id = :'t2' and title = 'Sessions moved'), 0::bigint, 'T2 is not told when the box is unticked'); -- not told
select tests.eq((select count(*) from public.session_notices where account_id = :'p1' and title = 'Change confirmed' and body like '%New time:%5:00pm%'), 1::bigint, 'the parent is told the new time'); -- told
select tests.eq((select count(*) from public.tutor_assignments where tutor_id = :'t2' and student_id = :'cara' and ends_on = current_date + 19), 1::bigint, 'T2''s match ends the day before the change'); -- ends before the change
select tests.eq((select count(*) from public.tutor_changes where new_weekday = :newday and new_start = '17:00'), 1::bigint, 'the record keeps the new day and time'); -- recorded

-- 7. Withdrawing a waiting change.
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select public.propose_tutor_change(:'cara', :'t2', 'General Maths', :'t1', current_date + 6, 'Trying another way') as w \gset
-- (sends one more change, keeping its id as w)
select public.withdraw_tutor_change(:'w', 'Sorted it another way.'); -- withdraws it
select tests.fails(format($q$select public.withdraw_tutor_change(%L)$q$, :'w'), 'cannot withdraw twice'); -- refused
reset role; -- back to the database itself
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.answer_tutor_change(%L, true)$q$, :'w'), 'a withdrawn change cannot be answered'); -- refused
reset role; -- back to the database itself

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  change tutor: all checks passed'
