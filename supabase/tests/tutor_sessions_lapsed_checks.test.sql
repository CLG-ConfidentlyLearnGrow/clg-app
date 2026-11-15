-- Summary: a tutor's sessions are hidden while their checks have lapsed
-- (Carla, 16 Nov 2026), and come back once the checks are current again.
-- Picks a tutor-only account with a session, lets their checks run out,
-- checks every place a tutor sees sessions and offers, then puts the
-- checks back. Reuses access_rules.test.sql helpers (tests.claims, tests.eq).

-- Runs the update again: it must be safe to run twice, and earlier test
-- files may have re-run older updates that replace the same functions.
\ir ../migrations/20261117300100_hide_sessions_lapsed_checks.sql

-- ---------------------------------------------------------------------------
-- Picks a tutor-only account with a session, whose checks are in date
-- ---------------------------------------------------------------------------
-- The tutor and one of their sessions (and that session's booking).
select x.tutor_id as tutor, x.id as session, x.booking_id as booking -- the tutor, session and booking,
from public.sessions x -- from the sessions,
where private.tutor_cleared_for_student(x.tutor_id, x.student_id) -- whose tutor's checks are in date for that student,
  and x.booking_id is not null -- that came from a booking,
  and not exists (select 1 from public.account_roles r where r.account_id = x.tutor_id and r.role <> 'tutor') -- and whose tutor has no other role,
order by x.starts_at desc limit 1 \gset

-- ---------------------------------------------------------------------------
-- Checks in date: the tutor sees the session and its booking
-- ---------------------------------------------------------------------------
select tests.claims(:'tutor', 'aal2'); -- Signs in as the tutor, with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.sessions where id = :'session'), 1, 'tutor sees their session while checks are in date'); -- Checks the session can be read,
select tests.eq((select count(*) from public.bookings where id = :'booking'), 1, 'tutor sees their booking while checks are in date'); -- and its booking,
select tests.eq((select count(*) from public.list_sessions('2000-01-01', '2100-01-01') where id = :'session'), 1, 'session in the tutor''s list while checks are in date'); -- and it's in their sessions list,
select tests.eq((select count(*) from public.list_bookings() where id = :'booking'), 1, 'booking in the tutor''s list while checks are in date'); -- and the booking is in their list.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Checks lapse: everything about that student is hidden from the tutor
-- ---------------------------------------------------------------------------
select tests.claims(null); -- Signs out, so the change below is made as the system (not as the tutor).
create temp table saved_checks as select id, expires_on from public.tutor_checks where tutor_id = :'tutor'; -- Keeps the tutor's check dates, to put back after.
update public.tutor_checks set expires_on = current_date - 1 where tutor_id = :'tutor'; -- Every check runs out yesterday.

select tests.claims(:'tutor', 'aal2'); -- Signs in as the tutor again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.sessions where id = :'session'), 0, 'session hidden once checks lapse'); -- Checks the session is hidden,
select tests.eq((select count(*) from public.bookings where id = :'booking'), 0, 'booking hidden once checks lapse'); -- and its booking,
select tests.eq((select count(*) from public.list_sessions('2000-01-01', '2100-01-01')), 0, 'sessions list empty once checks lapse'); -- and their sessions list is empty,
select tests.eq((select count(*) from public.list_bookings()), 0, 'bookings list empty once checks lapse'); -- and their bookings list,
select tests.eq((select count(*) from public.list_notes_due()), 0, 'no notes to write once checks lapse'); -- and notes still to write,
select tests.eq((select count(*) from public.offer_card(:'booking')), 0, 'offer details hidden once checks lapse'); -- and the offer's details,
select tests.eq((select as_tutor from public.my_offers_to_answer()), 0, 'no offers to answer once checks lapse'); -- and the "waiting for your answer" number.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The family and CLG still see the session.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner, with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_sessions('2000-01-01', '2100-01-01') where id = :'session'), 1, 'CLG still sees the session'); -- Checks admins still see it.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Checks renewed: the session comes back by itself
-- ---------------------------------------------------------------------------
select tests.claims(null); -- Signs out, so the change below is made as the system.
update public.tutor_checks c set expires_on = s.expires_on from saved_checks s where s.id = c.id; -- Puts the check dates back.
select tests.claims(:'tutor', 'aal2'); -- Signs in as the tutor again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_sessions('2000-01-01', '2100-01-01') where id = :'session'), 1, 'session back once checks are current'); -- Checks the session is back.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- Prints that every check in this file passed.
\echo '  tutor sessions hidden while checks lapse: all checks passed'
