-- Summary: checks quiet hours (Carla, 12 Nov 2026): one shared setting,
-- 9pm to 5am, in each person's own local time. Covers the setting and who
-- may change it, whose time zone is used, the check itself, the trigger on
-- the notice tables, and the early-session reminder fallback. Runs after
-- scheduling_notices.test.sql and reuses earlier people: owner admin (...a0),
-- tutor T2 (...12, works in Victoria), tutor T3 (...13, no work state),
-- parent P3 (...03) and Sam Three (lives in SA).

select tests.claims(null); -- acts as the database itself while setting up
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
update public.tutor_work_settings set work_state = 'VIC' where tutor_id = '00000000-0000-0000-0000-000000000012'; -- makes sure tutor T2 works in Victoria

-- 1. The setting starts at 9pm to 5am.
select tests.eq(((select starts_at from public.quiet_hours_settings) = time '21:00')::int, 1, 'quiet hours start at 9pm'); -- checks the start time
select tests.eq(((select ends_at from public.quiet_hours_settings) = time '05:00')::int, 1, 'quiet hours end at 5am'); -- checks the end time

-- 2. Whose local time is used.
select tests.eq((private.account_timezone('00000000-0000-0000-0000-000000000003') = 'Australia/Adelaide')::int, 1, 'a parent uses their child''s state (SA)'); -- checks P3 (Sam is in SA)
select tests.eq((private.account_timezone('00000000-0000-0000-0000-000000000012') = 'Australia/Melbourne')::int, 1, 'a tutor uses their work state (VIC)'); -- checks T2
select tests.eq((private.account_timezone('00000000-0000-0000-0000-0000000000a0') = 'Australia/Adelaide')::int, 1, 'someone with no state uses Adelaide time'); -- checks the owner admin

-- 3. The check in other time zones.
select tests.eq((private.outside_quiet_hours(timestamptz '2026-11-03 21:30 Australia/Melbourne', 'Australia/Melbourne') -- 9:30pm in Melbourne
  = timestamptz '2026-11-04 05:00 Australia/Melbourne')::int, 1, 'Melbourne 9:30pm waits until 5am Melbourne time'); -- moves to 5am there
select tests.eq((private.outside_quiet_hours(timestamptz '2026-11-03 20:30 Australia/Perth', 'Australia/Perth') -- 8:30pm in Perth (11pm in Adelaide)
  = timestamptz '2026-11-03 20:30 Australia/Perth')::int, 1, 'Perth 8:30pm is not quiet, even though it is late in Adelaide'); -- left alone
select tests.eq((private.outside_quiet_hours(null, 'Australia/Adelaide') is null)::int, 1, 'no time stays no time'); -- a missing time isn't invented

-- 4. The trigger: a new notice is held until the person's quiet hours end.
-- Keeps 8:45pm Adelaide in 5 days' time as late (it is 9:15pm in Melbourne).
select ((current_date + 5) + time '20:45') at time zone 'Australia/Adelaide' as late \gset
insert into public.session_notices (account_id, kind, title, body, deliver_at) values -- adds two test notices at that moment:
  ('00000000-0000-0000-0000-000000000012', 'booking_confirmed', 'Quiet test', 'Victoria', :'late'), -- one for T2 in Victoria,
  ('00000000-0000-0000-0000-000000000003', 'booking_confirmed', 'Quiet test', 'South Australia', :'late'); -- and one for P3 in SA
select tests.eq((select count(*) from public.session_notices where title = 'Quiet test' and body = 'Victoria' -- the Victorian tutor's notice
  and deliver_at = ((current_date + 6) + time '05:00') at time zone 'Australia/Melbourne'), 1::bigint, 'Victorian tutor''s notice waits until 5am Melbourne time'); -- is held until 5am there
select tests.eq((select count(*) from public.session_notices where title = 'Quiet test' and body = 'South Australia' -- the SA parent's notice
  and deliver_at = :'late'::timestamptz), 1::bigint, 'SA parent''s notice at 8:45pm is not held'); -- goes at 8:45pm as asked
-- A progress notice saved at 4am Adelaide time waits until 5am.
insert into public.progress_notices (account_id, student_id, kind, title, body, deliver_at) -- adds a test progress notice:
  values ('00000000-0000-0000-0000-000000000003', :'sam', 'session_update', 'Quiet test', 'Early', ((current_date + 5) + time '04:00') at time zone 'Australia/Adelaide'); -- due at 4am in 5 days
select tests.eq((select count(*) from public.progress_notices where title = 'Quiet test' -- that notice
  and deliver_at = ((current_date + 5) + time '05:00') at time zone 'Australia/Adelaide'), 1::bigint, 'progress notices follow quiet hours too'); -- is held until 5am
-- A time that has already passed is left alone (it counts as delivered).
insert into public.session_notices (account_id, kind, title, body, deliver_at) -- adds a test notice in the past:
  values ('00000000-0000-0000-0000-000000000003', 'booking_confirmed', 'Quiet test', 'Past', now() - interval '1 minute'); -- a minute ago
select tests.eq((select count(*) from public.session_notices where title = 'Quiet test' and body = 'Past' -- that notice
  and deliver_at < now()), 1::bigint, 'a time already passed is not moved'); -- stays in the past
delete from public.session_notices where title = 'Quiet test'; -- tidies up the test session notices
delete from public.progress_notices where title = 'Quiet test'; -- tidies up the test progress notice

-- 5. Reminders: a 4:30am session's "1 hr before" reminder would wait until
-- 5am (after the session's start), so it comes at 8:30pm the evening before.
-- Keeps 4:30am Adelaide in 4 days' time as dawn.
select ((current_date + 4) + time '04:30') at time zone 'Australia/Adelaide' as dawn \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) -- adds a session for Sam with T3:
  values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', :'dawn', :'dawn'::timestamptz + interval '1 hour') -- at 4:30am, online
  returning id as s_dawn \gset
-- (keeps the new session's id as s_dawn)
select private.queue_reminders(); -- queues the reminders
select tests.eq((select count(*) from public.session_notices where session_id = :'s_dawn' and kind = 'reminder_final' -- the final reminders
  and deliver_at = ((current_date + 3) + time '20:30') at time zone 'Australia/Adelaide'), 2::bigint, '4:30am session: final reminder at 8:30pm the evening before'); -- one each for P3 and T3
select tests.eq((select count(*) from public.session_notices where session_id = :'s_dawn' and kind = 'reminder_first' -- the parent's first reminder (24 hr before, 4:30am)
  and account_id = '00000000-0000-0000-0000-000000000003' -- (for P3)
  and deliver_at = ((current_date + 3) + time '05:00') at time zone 'Australia/Adelaide'), 1::bigint, 'first reminder at 4:30am waits until 5am'); -- is held until 5am
delete from public.sessions where id = :'s_dawn'; -- tidies up the test session (its reminders go with it)

-- 6. Who can change the hours.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- signs in as tutor T3
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq((select count(*) from public.quiet_hours_settings), 1::bigint, 'signed-in people can read quiet hours'); -- reading is fine
select tests.fails($q$select public.set_quiet_hours('22:00', '06:00')$q$, 'tutors can''t change quiet hours'); -- refused for a tutor
select tests.fails($q$update public.quiet_hours_settings set ends_at = '07:00'$q$, 'nobody edits the setting directly'); -- only through the function
reset role; -- back to the database itself
select tests.claims(null); -- signs out
set role anon; -- acts as someone not signed in
select tests.fails($q$select * from public.quiet_hours_settings$q$, 'signed-out visitors can''t read quiet hours'); -- refused for anon
reset role; -- back to the database itself

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person
select tests.fails($q$select public.set_quiet_hours('21:00', '21:00')$q$, 'start and end can''t be the same'); -- refused: same time
select tests.fails($q$select public.set_quiet_hours('21:15', '05:00')$q$, 'only on the hour or half hour'); -- refused: 9:15pm
select public.set_quiet_hours('22:00', '06:00'); -- the owner changes them to 10pm to 6am
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
select tests.eq((private.outside_quiet_hours(timestamptz '2026-11-03 21:30 Australia/Adelaide', 'Australia/Adelaide') -- 9:30pm Adelaide
  = timestamptz '2026-11-03 21:30 Australia/Adelaide')::int, 1, 'after the change, 9:30pm is not quiet'); -- uses the new start
select tests.eq((private.outside_quiet_hours(timestamptz '2026-11-04 05:30 Australia/Adelaide', 'Australia/Adelaide') -- 5:30am Adelaide
  = timestamptz '2026-11-04 06:00 Australia/Adelaide')::int, 1, 'after the change, 5:30am waits until 6am'); -- uses the new end
update public.quiet_hours_settings set starts_at = '21:00', ends_at = '05:00' where id; -- puts back 9pm to 5am for later tests
