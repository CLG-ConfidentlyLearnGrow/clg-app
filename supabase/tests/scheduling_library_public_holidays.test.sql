-- Summary: checks libraries are closed on public holidays by default (Carla,
-- 20 Nov 2026): a library counts as closed on its state's public holidays
-- unless an admin sets it as open; one-off times skip it that day; a weekly
-- booking makes no session there that day; any other session there that day
-- is refused; only admins can change the setting; and the to-do list says
-- "asked for by a tutor, family or student".
-- Reuses earlier scheduling test people: owner admin (...a0), tutor T3
-- (...13) and Sam Three. Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the public holiday database change again (checks it can run twice).
\ir ../migrations/20261122560200_libraries_closed_public_holidays.sql

select tests.claims(null); -- signs out, so the test user sets things up directly
select id as sam from public.students where full_name = 'Sam Three' \gset
-- (keeps Sam's student id as sam)
select id as bk from public.bookings limit 1 \gset
-- (keeps any existing booking's id as bk, to stand in for a weekly booking)
insert into public.libraries (name, suburb, confirmed_at) values ('Holiday Test Library', 'Unley', now()) returning id as lib \gset
-- (adds a confirmed SA library and keeps its id as lib)
insert into public.library_hours (library_id, weekday, opens, closes) values (:'lib', 2, '09:00', '17:00'); -- open Tuesdays 9am to 5pm

-- 1. Closed on public holidays by default.
select tests.eq((select count(*) from public.libraries where id = :'lib' and not open_public_holidays), 1::bigint, 'a new library is set as closed on public holidays'); -- closed by default
select tests.eq(private.library_closed_on(:'lib', date '2027-01-26')::int, 1, 'closed on Australia Day (Tuesday 26 Jan 2027)'); -- closed on a public holiday
select tests.eq(private.library_closed_on(:'lib', date '2027-02-02')::int, 0, 'not closed on an ordinary Tuesday'); -- open on an ordinary day
select tests.eq(private.library_open(:'lib', date '2027-01-26', time '10:00', 60)::int, 0, 'no one-off time there on the public holiday'); -- one-off times skip it
select tests.eq(private.library_open(:'lib', date '2027-02-02', time '10:00', 60)::int, 1, 'one-off time there on an ordinary Tuesday'); -- ordinary days still fine

-- 2. Sessions on the public holiday at that library.
insert into public.sessions (student_id, tutor_id, booking_id, subject, level_kind, delivery, library_id, starts_at, ends_at) values -- a weekly booking's session on the holiday:
  (:'sam', '00000000-0000-0000-0000-000000000013', :'bk', 'Holiday Test Maths', 'school', 'library', :'lib', -- Sam with tutor T3 at the library,
   timestamptz '2027-01-26 10:00 Australia/Adelaide', timestamptz '2027-01-26 11:00 Australia/Adelaide'); -- 10am to 11am on Australia Day
select tests.eq((select count(*) from public.sessions where subject = 'Holiday Test Maths'), 0::bigint, 'a weekly booking makes no session at a closed library on the holiday'); -- skipped
select tests.fails(format($$insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, library_id, starts_at, ends_at) values (%L, '00000000-0000-0000-0000-000000000013', 'Holiday Test One-off', 'school', 'library', %L, timestamptz '2027-01-26 10:00 Australia/Adelaide', timestamptz '2027-01-26 11:00 Australia/Adelaide')$$, :'sam', :'lib'), 'a one-off session at a closed library on the holiday'); -- refused

-- 3. Only admins can set a library as open on public holidays.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- signs in as tutor T3
set role authenticated; -- acts as a signed-in person, so access rules apply
update public.libraries set open_public_holidays = true where id = :'lib'; -- the tutor tries to change it (the access rules let this change nothing)
reset role; -- goes back to the test user
select tests.eq((select count(*) from public.libraries where id = :'lib' and not open_public_holidays), 1::bigint, 'a tutor cannot set a library as open on public holidays'); -- unchanged
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person, so access rules apply
update public.libraries set open_public_holidays = true where id = :'lib'; -- the admin sets it as open on public holidays
reset role; -- goes back to the test user
select tests.eq(private.library_closed_on(:'lib', date '2027-01-26')::int, 0, 'once set as open, it is not closed on the holiday'); -- now open
select tests.eq(private.library_open(:'lib', date '2027-01-26', time '10:00', 60)::int, 1, 'one-off time there on the holiday once set as open'); -- one-off times allowed

-- 4. The to-do wording for libraries asked for but not confirmed.
select tests.claims(null); -- signs out
insert into public.libraries (name, suburb, suggested_by) values ('Asked For Test Library', 'Norwood', '00000000-0000-0000-0000-000000000013') returning id as asked \gset
-- (adds a library suggested by tutor T3, so it waits to be confirmed, and keeps its id as asked)
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- signs in as tutor T3
set role authenticated; -- acts as a signed-in person, so access rules apply
insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000013', :'asked'); -- the tutor asks to teach there
reset role; -- goes back to the test user
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq((select count(*) from public.library_checks() where library_id = :'asked' and problem like 'Asked for by a tutor, family or student%'), 1::bigint, 'to-do says asked for by a tutor, family or student'); -- new wording
reset role; -- goes back to the test user

-- Undoes everything above.
rollback;

-- Prints that every check in this file passed.
\echo '  libraries closed on public holidays: all checks passed'
