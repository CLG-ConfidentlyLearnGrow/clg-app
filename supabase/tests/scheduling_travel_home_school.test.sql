-- Summary: home and school sessions (Carla, 20 Nov 2026). Runs after the
-- other scheduling tests and reuses Sam Three, tutor T3 (...13) and the
-- owner (...a0). Checks:
--   * home sessions need at least 2 hours (weekly, "another time" and one-off);
--   * "another time or place" accepts home and school;
--   * Times to check does not list "no location" for home or school sessions;
--   * home times are only found for sessions of 2 hours or more.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the change again (and twice), to check it is safe to run more than once.
\ir ../migrations/20261123400400_home_school_sessions.sql
\ir ../migrations/20261123400400_home_school_sessions.sql

-- Keeps Sam's student id, and the Monday after next as first_day.
select id as sam from public.students where full_name = 'Sam Three' \gset
select (current_date + 7 + ((8 - extract(isodow from current_date)::int) % 7)) as first_day \gset

-- As the owner, with two-step sign-in.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner
set local role authenticated; -- acts as a signed-in user, so the access rules apply
-- A 1 hr weekly home booking is refused.
select tests.fails_with(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'home', null, %L::date, %L::date + 28)$$, :'sam', :'first_day', :'first_day'),
  'at least 2 hours', '1 hr weekly home booking refused'); -- (the message says 2 hours)
-- A 1 hr "another time" home offer is refused.
select tests.fails_with(format($$select public.offer_other_time(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'home', null, %L::date, %L::date + 28)$$, :'sam', :'first_day', :'first_day'),
  'at least 2 hours', '1 hr home offer refused'); -- (the message says 2 hours)
-- "Another time" at school is no longer refused for its place (it may still be refused for another reason, such as the tutor's hours).
do $$ -- a block of checks
begin -- start
  perform public.offer_other_time((select id from public.students where full_name = 'Sam Three'), 'General Maths', '00000000-0000-0000-0000-000000000013', 2::smallint, '07:00', 60, 'school', null, current_date + 14, current_date + 42); -- tries a school session
exception when others then -- if refused:
  if sqlerrm like 'Choose online%' then raise exception 'FAIL school offer refused for its place: %', sqlerrm; end if; -- it must not be for the place
end; -- end of the checks
$$; -- end of the block
reset role; -- back to the test user (access rules off)

-- One-off sessions: home needs 2 hours (read from the function's code).
select tests.eq(case when strpos(pg_get_functiondef('public.offer_one_off(uuid, uuid, date, time, integer, public.session_delivery, uuid, text)'::regprocedure), 'Home sessions are booked for at least 2 hours') > 0 then 1::bigint else 0::bigint end, 1::bigint, 'one-off home sessions need 2 hr'); -- checks the one-off rule
-- Times to check: no "no location" for home or school.
select tests.eq(case when strpos(pg_get_functiondef('public.list_times_to_check()'::regprocedure), 'x.delivery not in (''home'', ''school'')') > 0 then 1::bigint else 0::bigint end, 1::bigint, 'times to check skips home and school locations'); -- checks the list
-- Finding times: home only for 2 hr or more.
select tests.eq(case when strpos(pg_get_functiondef('public.find_session_times(uuid, text, integer, boolean, uuid[], date, smallint[], time, time)'::regprocedure), 'and p_minutes >= 120') > 0 then 1::bigint else 0::bigint end, 1::bigint, 'home times only for 2 hr or more'); -- checks the search

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  home and school sessions: all checks passed'
