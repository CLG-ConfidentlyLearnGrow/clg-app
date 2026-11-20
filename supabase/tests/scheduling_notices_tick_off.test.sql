-- Summary: checks ticking off notices (Carla, 20 Nov 2026): a person can mark
-- one of their own notices as seen, as done, or as not done after all; they
-- cannot tick off someone else's notice, a notice not yet delivered, or edit
-- a notice directly; and done notices drop out of the unread count.
-- Reuses access_rules.test.sql people: parent P1 (...01) and parent P2 (...02).
-- Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the tick-off database change again (checks it can run twice).
\ir ../migrations/20261122560100_tick_off_notices.sql

\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)
\set p2 '00000000-0000-0000-0000-000000000002'
-- (parent P2's account id)

-- Three notices for P1 (two delivered, one for tomorrow) and one for P2.
select tests.claims(null); -- signs out, so the test user adds them directly
insert into public.session_notices (account_id, kind, title, body, deliver_at) values -- adds the notices:
  (:'p1', 'booking_requested', 'Tick test A', 'First test notice.', now() - interval '1 hour'), -- P1, delivered an hour ago
  (:'p1', 'booking_requested', 'Tick test B', 'Second test notice.', now() - interval '2 hours'), -- P1, delivered two hours ago
  (:'p1', 'booking_requested', 'Tick test later', 'Not yet delivered.', now() + interval '1 day'), -- P1, not delivered until tomorrow
  (:'p2', 'booking_requested', 'Tick test P2', 'Someone else''s notice.', now() - interval '1 hour'); -- P2's own notice
select id as a_id from public.session_notices where title = 'Tick test A' \gset
-- (keeps notice A's id as a_id)
select id as b_id from public.session_notices where title = 'Tick test B' \gset
-- (keeps notice B's id as b_id)
select id as later_id from public.session_notices where title = 'Tick test later' \gset
-- (keeps the not-yet-delivered notice's id as later_id)
select id as p2_id from public.session_notices where title = 'Tick test P2' \gset
-- (keeps P2's notice id as p2_id)

-- 1. Marking a notice as seen.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq((select count(*) from public.session_notices where title like 'Tick test%' and read_at is null), 2::bigint, 'P1 sees two unread test notices (not the future one, not P2''s)'); -- starts with two unread
select public.tick_off_notice(:'a_id', 'seen'); -- P1 ticks notice A as seen
select tests.eq((select count(*) from public.session_notices where id = :'a_id' and read_at is not null and done_at is null), 1::bigint, 'seen marks it read but not done'); -- read, not done
select tests.eq((select count(*) from public.session_notices where title like 'Tick test%' and read_at is null), 1::bigint, 'one fewer unread after seen'); -- one unread left

-- 2. Marking a notice as done (also marks it read), then undoing it.
select public.tick_off_notice(:'b_id', 'done'); -- P1 ticks notice B as done
select tests.eq((select count(*) from public.session_notices where id = :'b_id' and read_at is not null and done_at is not null), 1::bigint, 'done marks it read and done'); -- read and done
select tests.eq((select count(*) from public.session_notices where title like 'Tick test%' and read_at is null), 0::bigint, 'done notices leave the unread count'); -- none unread
select public.tick_off_notice(:'b_id', 'done'); -- P1 presses done again
select tests.eq((select count(*) from public.session_notices where id = :'b_id' and done_at is not null), 1::bigint, 'pressing done twice is fine'); -- still done
select public.tick_off_notice(:'b_id', 'not_done'); -- P1 says it is not done after all
select tests.eq((select count(*) from public.session_notices where id = :'b_id' and read_at is not null and done_at is null), 1::bigint, 'not done puts it back, still read'); -- back in the list, still read

-- 3. What P1 cannot do.
select tests.fails(format($$select public.tick_off_notice(%L, 'done')$$, :'p2_id'), 'tick off someone else''s notice'); -- refused: P2's notice
select tests.fails(format($$select public.tick_off_notice(%L, 'seen')$$, :'later_id'), 'tick off a notice not yet delivered'); -- refused: not delivered yet
select tests.fails(format($$select public.tick_off_notice(%L, 'delete')$$, :'a_id'), 'an action that is not seen, done or not done'); -- refused: unknown action
select tests.fails(format($$update public.session_notices set done_at = now() where id = %L$$, :'a_id'), 'change a notice directly'); -- refused: no direct changes
reset role; -- goes back to the test user (access rules off)
select tests.eq((select count(*) from public.session_notices where id = :'p2_id' and read_at is null and done_at is null), 1::bigint, 'P2''s notice is untouched'); -- P2's notice unchanged
select tests.eq((select count(*) from public.session_notices where id = :'later_id' and read_at is null), 1::bigint, 'the future notice is untouched'); -- future notice unchanged

-- 4. Signed out: refused.
select tests.claims(null); -- signs out
set role authenticated; -- acts as a signed-in role with no person
select tests.fails(format($$select public.tick_off_notice(%L, 'seen')$$, :'a_id'), 'tick off while signed out'); -- refused: nobody signed in
reset role; -- goes back to the test user

-- Undoes everything above.
rollback;

-- Prints that every check in this file passed.
\echo '  ticking off notices: all checks passed'
