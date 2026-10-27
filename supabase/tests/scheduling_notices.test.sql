-- Reminders and notices. Runs after scheduling_away.test.sql and reuses its
-- people: tutors T3 (...13) and T4 (...14), parents P3 (...03, Sam Three's
-- parent) and P4 (...04).

select tests.claims(null);
select id as sam from public.students where full_name = 'Sam Three' \gset

-- Quiet hours: nothing between 8pm and 8am Adelaide time.
select tests.eq((private.outside_quiet_hours(timestamptz '2026-11-03 21:00 Australia/Adelaide') = timestamptz '2026-11-04 08:00 Australia/Adelaide')::int, 1, '9pm moves to 8am next day');
select tests.eq((private.outside_quiet_hours(timestamptz '2026-11-04 06:30 Australia/Adelaide') = timestamptz '2026-11-04 08:00 Australia/Adelaide')::int, 1, '6:30am moves to 8am');
select tests.eq((private.outside_quiet_hours(timestamptz '2026-11-04 15:00 Australia/Adelaide') = timestamptz '2026-11-04 15:00 Australia/Adelaide')::int, 1, 'daytime unchanged');

-- Notices from the earlier booking tests.
select tests.eq(least((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000013' and kind = 'booking_requested'), 1), 1, 'tutor told about requests');
select tests.eq(least((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003' and kind = 'booking_confirmed'), 1), 1, 'family told about confirmations');
select tests.eq(least((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003' and kind = 'booking_declined'), 1), 1, 'family told about a decline');
select tests.eq((select count(*) from public.session_notices n join public.sessions x on x.id = n.session_id
  where n.kind = 'session_cancelled' and n.account_id = x.cancelled_by), 0, 'whoever cancels isn''t told about it');

-- P3 wants the first reminder 24 hr before.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
insert into public.notice_settings (account_id, first_reminder_hours) values ('00000000-0000-0000-0000-000000000003', 24);
select tests.fails($$insert into public.notice_settings (account_id) values ('00000000-0000-0000-0000-000000000004')$$, 'settings for someone else');
select tests.fails($$update public.notice_settings set first_reminder_hours = 1$$, 'under 2 hours');
reset role;

-- Two sessions in 3 days' time: 4pm, and 7:30am.
select tests.claims(null);
select ((current_date + 3) + time '16:00') at time zone 'Australia/Adelaide' as afternoon \gset
select ((current_date + 3) + time '07:30') at time zone 'Australia/Adelaide' as morning \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) values
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', :'afternoon', :'afternoon'::timestamptz + interval '1 hour'),
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', :'morning', :'morning'::timestamptz + interval '1 hour');
select id as s_pm from public.sessions where starts_at = :'afternoon' \gset
select id as s_am from public.sessions where starts_at = :'morning' \gset

select private.queue_reminders();
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm'), 4, 'tutor and parent each get two reminders');
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm' and kind = 'reminder_final'
  and deliver_at = :'afternoon'::timestamptz - interval '1 hour'), 2, 'final reminder 1 hr before');
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm' and kind = 'reminder_first'
  and account_id = '00000000-0000-0000-0000-000000000003' and deliver_at = :'afternoon'::timestamptz - interval '24 hours'), 1, 'parent''s first reminder at 24 hr');
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm' and kind = 'reminder_first'
  and account_id = '00000000-0000-0000-0000-000000000013' and deliver_at = :'afternoon'::timestamptz - interval '48 hours'), 1, 'tutor''s first reminder at 48 hr (default)');
select tests.eq((select count(*) from public.session_notices where session_id = :'s_am' and kind = 'reminder_final'
  and deliver_at = ((current_date + 2) + time '19:30') at time zone 'Australia/Adelaide'), 2, '7:30am session: final reminder the evening before');
select tests.eq((select count(*) from public.session_notices where session_id = :'s_am' and kind = 'reminder_first'
  and account_id = '00000000-0000-0000-0000-000000000003'
  and deliver_at = ((current_date + 2) + time '08:00') at time zone 'Australia/Adelaide'), 1, 'first reminder moved out of quiet hours');
select private.queue_reminders();
select tests.eq((select count(*) from public.session_notices where session_id in (:'s_pm', :'s_am')), 8, 'queued only once');

-- Only your own notices, and only once they are due.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm'), 0, 'reminders not shown before they are due');
select tests.eq((select count(*) from public.session_notices where account_id <> '00000000-0000-0000-0000-000000000003'), 0, 'only own notices');
select tests.fails($$update public.session_notices set read_at = now()$$, 'family edits notices directly');
select public.mark_notices_read();
select tests.eq((select count(*) from public.session_notices where read_at is null), 0, 'marked read');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.eq((select count(*) from public.session_notices), 0, 'other parent sees none');
reset role;
select tests.claims(null);
set role anon;
select tests.fails($$select * from public.session_notices$$, 'anon');
reset role;

-- Cancelling: the tutor is told, and reminders not yet due are withdrawn.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.cancel_session(:'s_pm', 'Sick');
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm' and kind = 'session_cancelled'
  and account_id = '00000000-0000-0000-0000-000000000013' and body like '%(Sick)%'), 1, 'tutor told about the cancellation');
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm' and kind = 'session_cancelled'
  and account_id = '00000000-0000-0000-0000-000000000003'), 0, 'parent who cancelled not told');
select private.queue_reminders();
select tests.eq((select count(*) from public.session_notices where session_id = :'s_pm' and kind like 'reminder%'), 0, 'reminders withdrawn');

-- Leave the extra sessions out of the later tests.
delete from public.sessions where id in (:'s_am', :'s_pm');

\echo '  scheduling reminders and notices: all checks passed'
