-- Summary: tests that a tutor waits 15 minutes before recording a no-show (Carla, 16 Nov 2026).
-- Reuses Cara One (from access_rules.test.sql), tutor T1 (...11) and the
-- owner admin (...a0). Sessions are written straight in.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset

-- Three online sessions with tutor T1: started 5 minutes ago, 20 minutes ago, and 5 minutes ago (for the admin).
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) -- Adds the sessions:
values (:'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', now() - interval '5 minutes', now() + interval '55 minutes'), -- started 5 minutes ago,
       (:'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', now() - interval '20 minutes', now() + interval '40 minutes'), -- started 20 minutes ago,
       (:'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', now() - interval '6 minutes', now() + interval '54 minutes'); -- started 6 minutes ago.
-- Keeps the 5-minute one's id as early.
select id as early from public.sessions where student_id = :'cara' and starts_at between now() - interval '5 minutes 30 seconds' and now() - interval '4 minutes' \gset
-- Keeps the 20-minute one's id as waited.
select id as waited from public.sessions where student_id = :'cara' and starts_at between now() - interval '21 minutes' and now() - interval '19 minutes' \gset
-- Keeps the 6-minute one's id as for_admin.
select id as for_admin from public.sessions where student_id = :'cara' and starts_at between now() - interval '7 minutes' and now() - interval '5 minutes 30 seconds' \gset

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with(format($$select public.record_session_outcome(%L, 'no_show')$$, :'early'), 'Please wait 15 minutes', 'wait 15 minutes'); -- Checks this is refused with a plain message: a no-show 5 minutes in.
select public.record_session_outcome(:'waited', 'no_show'); -- Records a no-show 20 minutes in.
select tests.eq((select count(*) from public.sessions where id = :'waited' and status = 'no_show'), 1, 'no-show after 15 minutes'); -- Checks: it's recorded after 15 minutes.
select public.record_session_outcome(:'early', 'completed'); -- Done is still fine at any time after the start.
select tests.eq((select count(*) from public.sessions where id = :'early' and status = 'completed'), 1, 'done before 15 minutes is fine'); -- Checks: marking done isn't held back.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.record_session_outcome(:'for_admin', 'no_show'); -- An admin can record it straight away (e.g. the family rang).
select tests.eq((select count(*) from public.sessions where id = :'for_admin' and status = 'no_show'), 1, 'admin need not wait'); -- Checks: admins aren't held back.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Tidies up so later tests start clean.
delete from public.sessions where id in (:'early', :'waited', :'for_admin'); -- removes the test sessions.

-- Prints that every check in this file passed.
\echo '  no-show wait: all checks passed'
