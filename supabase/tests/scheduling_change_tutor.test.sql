-- Summary: checks moving a student's booked sessions to a new tutor (Carla,
-- 15 Nov 2026): only matching admins with two-step sign-in can do it; the
-- usual matching rules apply (checks, subject, clashes, most hours, blocks);
-- the same sessions move (so invoice lines stay with them), a started
-- weekly booking is split, a waiting request goes to the new tutor, the new
-- tutor is matched and the old match ends, everyone is told, and a record is
-- kept that only matching admins can read. Reuses access_rules.test.sql
-- people: owner Olive (...a0), operations admin Sam Staff (...b0), tutor T1
-- (...11, teaches Cara General Maths), tutor T2 (...12, General Maths Years
-- 1 to 12), parent P1 (...01, Cara's parent). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this database change again (checks it can run twice).
\ir ../migrations/20261117600100_change_tutor.sql

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

-- 1. Only matching admins with two-step sign-in.
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.fails(format($q$select public.change_session_tutor(%L, %L, 'General Maths', %L, current_date, 'Trying')$q$, :'cara', :'t1', :'t2'), 'a tutor can''t change tutors'); -- refused
select tests.fails($q$select * from public.tutor_change_pairs()$q$, 'a tutor can''t list sessions to move'); -- refused
reset role; -- back to the database itself
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.change_session_tutor(%L, %L, 'General Maths', %L, current_date, 'Trying')$q$, :'cara', :'t1', :'t2'), 'a parent can''t change tutors'); -- refused
reset role; -- back to the database itself
select tests.claims(:'sam'); -- signs in as Sam without two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.change_session_tutor(%L, %L, 'General Maths', %L, current_date, 'Trying')$q$, :'cara', :'t1', :'t2'), 'an admin needs two-step sign-in'); -- refused
reset role; -- back to the database itself

-- 2. The page's lists.
select tests.claims(:'sam', 'aal2'); -- signs in as Sam with two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.eq((select upcoming_sessions from public.tutor_change_pairs(:'cara') where tutor_id = :'t1' and subject = 'General Maths'), 6, 'Cara has 6 upcoming sessions with T1'); -- 5 weekly and 1 extra
select tests.eq((select paid_sessions from public.tutor_change_pairs(:'cara') where tutor_id = :'t1'), 1, 'one of them is already on an invoice'); -- the paid one
select tests.eq((select count(*) from public.tutor_change_candidates(:'cara', :'t1', 'General Maths', current_date) where tutor_id = :'t2' and clashes = 0 and not at_max), 1::bigint, 'T2 is a free candidate'); -- listed and free
select tests.eq((select count(*) from public.tutor_change_candidates(:'cara', :'t1', 'General Maths', current_date) where tutor_id = :'t1'), 0::bigint, 'the current tutor isn''t a candidate'); -- not listed
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
select tests.fails(format($q$select public.change_session_tutor(%L, %L, 'General Maths', %L, current_date, 'Tutor leaving')$q$, :'cara', :'t1', :'t2'), 'a clashing tutor is refused'); -- refused
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
update public.sessions set status = 'cancelled', cancelled_at = now() where id = :'clash'; -- clears the clash
update public.tutor_work_settings set max_weekly_hours = 1 where tutor_id = :'t2'; -- T2 may only teach 1 hr a week
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.change_session_tutor(%L, %L, 'General Maths', %L, current_date, 'Tutor leaving')$q$, :'cara', :'t1', :'t2'), 'going past the tutor''s most hours is refused'); -- refused (2 hr a week would move)
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
update public.tutor_work_settings set max_weekly_hours = null where tutor_id = :'t2'; -- removes the limit again
insert into public.match_blocks (tutor_id, student_id, blocked_by_role, reason) values (:'t2', :'cara', 'family', 'Family asked for a different tutor.') returning id as blk \gset
-- (blocks T2 from Cara for the next check, keeping it as blk)
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.change_session_tutor(%L, %L, 'General Maths', %L, current_date, 'Tutor leaving')$q$, :'cara', :'t1', :'t2'), 'a blocked tutor is refused'); -- refused
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
delete from public.match_blocks where id = :'blk'; -- removes the block
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.change_session_tutor(%L, %L, 'General Maths', %L, current_date, '')$q$, :'cara', :'t1', :'t2'), 'a reason is needed'); -- refused
select tests.fails(format($q$select public.change_session_tutor(%L, %L, 'General Maths', %L, current_date - 1, 'Tutor leaving')$q$, :'cara', :'t1', :'t2'), 'the date can''t be in the past'); -- refused
select tests.fails(format($q$select public.change_session_tutor(%L, %L, 'Science', %L, current_date, 'Tutor leaving')$q$, :'cara', :'t1', :'t2'), 'nothing to move in another subject'); -- refused

-- 4. The change, from tomorrow.
select tests.eq(public.change_session_tutor(:'cara', :'t1', 'General Maths', :'t2', current_date + 1, 'Tutor leaving CLG'), 6, 'six sessions move'); -- the change
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
select tests.eq((select count(*) from public.session_notices where account_id = :'t2' and title = 'Sessions added'), 1::bigint, 'T2 is told'); -- new tutor told
select tests.eq((select count(*) from public.session_notices where account_id = :'p1' and title = 'New tutor' and body like '%Tom Tutor%'), 1::bigint, 'the parent is told the new tutor''s name'); -- family told
select tests.eq((select count(*) from public.session_notices where account_id = :'t1' and title = 'Sessions moved' and body not like '%leaving%'), 1::bigint, 'T1 gets a plain notice, with no reason'); -- old tutor told
select tests.eq((select count(*) from public.tutor_changes where student_id = :'cara' and sessions_moved = 6 and bookings_moved = 2), 1::bigint, 'the change is recorded'); -- recorded

-- 5. Who can read the record.
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.recent_tutor_changes(:'cara') where reason = 'Tutor leaving CLG' and to_tutor_name = 'Tom Tutor'), 1::bigint, 'matching admins see the change'); -- visible
select tests.fails(format($q$select public.change_session_tutor(%L, %L, 'General Maths', %L, current_date, 'Again')$q$, :'cara', :'t1', :'t2'), 'nothing left to move a second time'); -- refused
select tests.fails($q$update public.tutor_changes set reason = 'Changed'$q$, 'nobody edits the record directly'); -- refused
reset role; -- back to the database itself
select tests.claims(:'t2', 'aal2'); -- signs in as tutor T2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.tutor_changes), 0::bigint, 'tutors can''t read the record'); -- hidden
reset role; -- back to the database itself
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.recent_tutor_changes()), 0::bigint, 'families can''t read the record'); -- hidden
reset role; -- back to the database itself

-- 6. Not telling the old tutor (e.g. while a concern is looked into).
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select tests.eq(public.change_session_tutor(:'cara', :'t2', 'General Maths', :'t1', current_date + 20, 'Back to the first tutor', false), 2, 'two later sessions move back to T1'); -- in 24 and 31 days
reset role; -- back to the database itself
select tests.eq((select count(*) from public.session_notices where account_id = :'t2' and title = 'Sessions moved'), 0::bigint, 'T2 isn''t told when the box is unticked'); -- not told
select tests.eq((select count(*) from public.tutor_assignments where tutor_id = :'t2' and student_id = :'cara' and ends_on = current_date + 19), 1::bigint, 'T2''s match ends the day before the change'); -- ends before the change

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  change tutor: all checks passed'
