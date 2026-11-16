-- Summary: checks the first-time app tour's saved progress (Carla, 16 Nov
-- 2026): people can only save tours for their own dashboards, admin level
-- tours need the admin role, nobody writes the table directly, people only
-- see their own progress, a finished tour stays finished when replayed and
-- closed early, and a new edition of a tour starts fresh. Reuses
-- access_rules.test.sql people: operations admin Sam Staff (...b0), tutor
-- T1 (...11), parent P1 (...01), parent P2 (...02), adult learner (...21, a
-- student). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the app tour database change again (checks it can run twice).
\ir ../migrations/20261119300100_app_tour.sql

\set sam '00000000-0000-0000-0000-0000000000b0'
-- (Sam Staff's account id: operations admin)
\set t1 '00000000-0000-0000-0000-000000000011'
-- (tutor T1's account id)
\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)
\set p2 '00000000-0000-0000-0000-000000000002'
-- (parent P2's account id)
\set adult '00000000-0000-0000-0000-000000000021'
-- (the adult learner's account id: a student)

-- 1. A parent saves their own tour, and only their own.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person, so access rules apply
select public.app_tour_save('parent', 1, 3, false); -- P1 closes the parent tour at step 3
select tests.eq((select step::bigint from public.app_tour_progress where tour = 'parent'), 3::bigint, 'a parent''s progress is saved'); -- step 3 kept
select tests.fails($q$select public.app_tour_save('tutor', 1, 1, false)$q$, 'a parent can''t save the tutor tour'); -- refused
select tests.fails($q$select public.app_tour_save('owner', 1, 1, false)$q$, 'a parent can''t save an admin tour'); -- refused
select tests.fails($q$select public.app_tour_save('robot', 1, 1, false)$q$, 'only real tours can be saved'); -- refused
select tests.fails($q$select public.app_tour_save('parent', 1, 500, false)$q$, 'steps out of range are refused'); -- refused
select tests.fails($q$select public.app_tour_save('parent', 0, 1, false)$q$, 'versions out of range are refused'); -- refused
select tests.fails(format($q$insert into public.app_tour_progress (account_id, tour, version) values (%L, 'student', 1)$q$, :'p1'), 'nobody writes the table directly'); -- refused
select tests.fails($q$update public.app_tour_progress set finished = true$q$, 'nobody changes the table directly'); -- refused
reset role; -- back to the database itself

-- 2. People see only their own progress.
select tests.claims(:'p2'); -- signs in as parent P2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.app_tour_progress), 0::bigint, 'another parent can''t see P1''s progress'); -- hidden
reset role; -- back to the database itself
select tests.claims(null); -- signed out
set role anon; -- acts as a visitor who isn't signed in
select tests.fails($q$select public.app_tour_save('parent', 1, 1, false)$q$, 'signed-out visitors can''t save'); -- refused
reset role; -- back to the database itself

-- 3. Finishing, replaying, and a new edition.
select tests.claims(:'p1'); -- signs in as parent P1 again
set role authenticated; -- acts as a signed-in person
select public.app_tour_save('parent', 1, 9, true); -- P1 finishes the tour
select public.app_tour_save('parent', 1, 2, false); -- later replays it from the App guide and closes it at step 2
select tests.eq((select count(*) from public.app_tour_progress where tour = 'parent' and finished), 1::bigint, 'a replay closed early doesn''t undo finishing'); -- still finished
select tests.eq((select step::bigint from public.app_tour_progress where tour = 'parent'), 2::bigint, 'the replay''s step is kept for "carry on"'); -- step 2
select public.app_tour_save('parent', 2, 1, false); -- a new edition of the tour comes out, and P1 closes it at step 1
select tests.eq((select count(*) from public.app_tour_progress where tour = 'parent' and finished), 0::bigint, 'a new edition starts fresh'); -- not finished yet
select tests.eq((select version::bigint from public.app_tour_progress where tour = 'parent'), 2::bigint, 'the new edition is recorded'); -- version 2
reset role; -- back to the database itself

-- 4. Each role's own tour.
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select public.app_tour_save('tutor', 1, 1, false); -- a tutor saves the tutor tour
select tests.fails($q$select public.app_tour_save('parent', 1, 1, false)$q$, 'a tutor can''t save the parent tour'); -- refused
reset role; -- back to the database itself
select tests.claims(:'adult'); -- signs in as the adult learner
set role authenticated; -- acts as a signed-in person
select public.app_tour_save('student', 1, 1, false); -- a student saves the student tour
reset role; -- back to the database itself
select tests.claims(:'sam', 'aal2'); -- signs in as Sam (an admin)
set role authenticated; -- acts as a signed-in person
select public.app_tour_save('operations', 1, 4, true); -- an admin saves an admin level tour
select tests.eq((select count(*) from public.app_tour_progress), 1::bigint, 'an admin only sees their own progress'); -- just Sam's row
reset role; -- back to the database itself

-- 5. Progress is removed with the account.
select tests.claims(null); -- acts as the database itself
select tests.eq((select count(*) from pg_constraint where conrelid = 'public.app_tour_progress'::regclass and contype = 'f' and confdeltype = 'c'), 1::bigint, 'tour progress is deleted with the account'); -- the link to the account is set to cascade

-- Throws away everything this test did.
rollback;
