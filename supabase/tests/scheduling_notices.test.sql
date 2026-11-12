-- Reminders and notices. Runs after scheduling_away.test.sql and reuses its
-- people: tutors T3 (...13) and T4 (...14), parents P3 (...03, Sam Three's
-- parent) and P4 (...04).

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset

-- Quiet hours (the shared setting, 9pm to 5am): checked here in Adelaide time;
-- scheduling_quiet_hours.test.sql checks other time zones and the setting.
select tests.eq((private.outside_quiet_hours(timestamptz '2026-11-03 21:00 Australia/Adelaide', 'Australia/Adelaide') = timestamptz '2026-11-04 05:00 Australia/Adelaide')::int, 1, '9pm moves to 5am next day'); -- Checks: 9pm moves to 5am next day.
select tests.eq((private.outside_quiet_hours(timestamptz '2026-11-03 20:30 Australia/Adelaide', 'Australia/Adelaide') = timestamptz '2026-11-03 20:30 Australia/Adelaide')::int, 1, '8:30pm is not quiet'); -- Checks: 8:30pm is not quiet.
select tests.eq((private.outside_quiet_hours(timestamptz '2026-11-04 04:30 Australia/Adelaide', 'Australia/Adelaide') = timestamptz '2026-11-04 05:00 Australia/Adelaide')::int, 1, '4:30am moves to 5am'); -- Checks: 4:30am moves to 5am.
select tests.eq((private.outside_quiet_hours(timestamptz '2026-11-04 05:30 Australia/Adelaide', 'Australia/Adelaide') = timestamptz '2026-11-04 05:30 Australia/Adelaide')::int, 1, '5:30am is no longer quiet'); -- Checks: 5:30am is no longer quiet (it was until 12 Nov 2026).
select tests.eq((private.outside_quiet_hours(timestamptz '2026-11-04 15:00 Australia/Adelaide', 'Australia/Adelaide') = timestamptz '2026-11-04 15:00 Australia/Adelaide')::int, 1, 'daytime unchanged'); -- Checks: daytime unchanged.

-- Notices from the earlier booking tests.
select tests.eq(least((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000013' and kind = 'booking_requested'), 1), 1, 'tutor told about requests'); -- Checks: tutor told about requests.
select tests.eq(least((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003' and kind = 'booking_confirmed'), 1), 1, 'family told about confirmations'); -- Checks: family told about confirmations.
select tests.eq(least((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003' and kind = 'booking_declined'), 1), 1, 'family told about a decline'); -- Checks: family told about a decline.
select tests.eq((select count(*) from public.session_notices n join public.sessions x on x.id = n.session_id -- Checks whoever cancels isn't told about it:
  where n.kind = 'session_cancelled' and n.account_id = x.cancelled_by), 0, 'whoever cancels isn''t told about it'); -- (no notice to the person who cancelled).

-- P3 wants the first reminder 24 hr before.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.notice_settings (account_id, first_reminder_hours) values ('00000000-0000-0000-0000-000000000003', 24); -- Sets the parent's first reminder to 24 hr before.
select tests.fails($$insert into public.notice_settings (account_id) values ('00000000-0000-0000-0000-000000000004')$$, 'settings for someone else'); -- Checks this is refused: settings for someone else.
select tests.fails($$update public.notice_settings set first_reminder_hours = 1$$, 'under 2 hours'); -- Checks this is refused: under 2 hours.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Two sessions in 3 days' time: 4pm, and 6am.
select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps 4pm in three days as afternoon.
select ((current_date + 3) + time '16:00') at time zone 'Australia/Adelaide' as afternoon \gset
-- Keeps 6am in three days as morning.
select ((current_date + 3) + time '06:00') at time zone 'Australia/Adelaide' as morning \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) values -- Adds two sessions for Sam with tutor T3:
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', :'afternoon', :'afternoon'::timestamptz + interval '1 hour'), -- one at 4pm,
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', :'morning', :'morning'::timestamptz + interval '1 hour'); -- and one at 6am.
-- Keeps the 4pm one's id as s_pm.
select id as s_pm from public.sessions where starts_at = :'afternoon' \gset
-- Keeps the 6am one's id as s_am.
select id as s_am from public.sessions where starts_at = :'morning' \gset

select private.queue_reminders(); -- Queues the reminders.
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm'), 4, 'tutor and parent each get two reminders'); -- Checks: tutor and parent each get two reminders.
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm' and kind = 'reminder_final' -- Checks the final reminder comes 1 hr before:
  and deliver_at = :'afternoon'::timestamptz - interval '1 hour'), 2, 'final reminder 1 hr before'); -- (two, one each for parent and tutor).
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm' and kind = 'reminder_first' -- Checks the parent's first reminder is 24 hr before:
  and account_id = '00000000-0000-0000-0000-000000000003' and deliver_at = :'afternoon'::timestamptz - interval '24 hours'), 1, 'parent''s first reminder at 24 hr'); -- (their setting).
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm' and kind = 'reminder_first' -- Checks the tutor's first reminder is 48 hr before:
  and account_id = '00000000-0000-0000-0000-000000000013' and deliver_at = :'afternoon'::timestamptz - interval '48 hours'), 1, 'tutor''s first reminder at 48 hr (default)'); -- (the default).
select tests.eq((select count(*) from public.session_notices where session_id = :'s_am' and kind = 'reminder_final' -- Checks a 6am session's final reminder comes 1 hr before, at 5am:
  and deliver_at = :'morning'::timestamptz - interval '1 hour'), 2, '6am session: final reminder at 5am, as quiet hours end at 5am'); -- (two, one each for parent and tutor).
select tests.eq((select count(*) from public.session_notices where session_id = :'s_am' and kind = 'reminder_first' -- Checks the first reminder for the 6am session stays at 6am:
  and account_id = '00000000-0000-0000-0000-000000000003' -- (for the parent)
  and deliver_at = ((current_date + 2) + time '06:00') at time zone 'Australia/Adelaide'), 1, 'first reminder 24 hr before a 6am session is outside quiet hours'); -- (6am is outside quiet hours).
select private.queue_reminders(); -- Queues the reminders again (should not repeat).
select tests.eq((select count(*) from public.session_notices where session_id in (:'s_pm', :'s_am')), 8, 'queued only once'); -- Checks: queued only once.

-- Only your own notices, and only once they are due.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm'), 0, 'reminders not shown before they are due'); -- Checks: reminders not shown before they are due.
select tests.eq((select count(*) from public.session_notices where account_id <> '00000000-0000-0000-0000-000000000003'), 0, 'only own notices'); -- Checks: only own notices.
select tests.fails($$update public.session_notices set read_at = now()$$, 'family edits notices directly'); -- Checks this is refused: family edits notices directly.
select public.mark_notices_read(); -- Marks the notices as read.
select tests.eq((select count(*) from public.session_notices where read_at is null), 0, 'marked read'); -- Checks: marked read.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as test account ...04.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.session_notices), 0, 'other parent sees none'); -- Checks: other parent sees none.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.session_notices$$, 'anon'); -- Checks this is refused: anon.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Cancelling: the tutor is told, and reminders not yet due are withdrawn.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.cancel_session(:'s_pm', 'Sick'); -- Cancels the 4pm session because of sickness.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm' and kind = 'session_cancelled' -- Checks the tutor is told about the cancellation:
  and account_id = '00000000-0000-0000-0000-000000000013' and body like '%(Sick)%'), 1, 'tutor told about the cancellation'); -- (with the reason).
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm' and kind = 'session_cancelled' -- Checks the parent who cancelled isn't told:
  and account_id = '00000000-0000-0000-0000-000000000003'), 0, 'parent who cancelled not told'); -- (no notice to them).
select private.queue_reminders(); -- Queues the reminders again.
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm' and kind like 'reminder%'), 0, 'reminders withdrawn'); -- Checks: reminders withdrawn.

-- Leave the extra sessions out of the later tests.
delete from public.sessions where id in (:'s_am', :'s_pm'); -- Removes the test sessions.

-- Prints that every check in this file passed.
\echo '  scheduling reminders and notices: all checks passed'
