-- Sending notices by email. Runs after the scheduling, progress and billing
-- tests and reuses their people: parent P3 (...03, Sam Three's parent),
-- parent P4 (...04) and tutor T3 (...13).

select tests.claims(null);
select id as sam from public.students where full_name = 'Sam Three' \gset

-- Start clean: everything from earlier tests counts as already sent.
update public.session_notices set email_sent_at = now() where email_sent_at is null;
update public.progress_notices set email_sent_at = now() where email_sent_at is null;
update public.billing_tutor_notices set sent_at = now() where sent_at is null;
update public.security_alerts set sent_at = now() where sent_at is null;
select tests.eq(private.emails_waiting()::int, 0, 'nothing waiting');

-- Notices: one due now, one not due yet, one from 2 days ago, one for a
-- person who turned email off, and a reminder for a session that started.
insert into public.session_notices (account_id, kind, title, body, deliver_at) values
  ('00000000-0000-0000-0000-000000000003', 'booking_confirmed', 'Booking confirmed', 'Due now', now() - interval '1 minute'),
  ('00000000-0000-0000-0000-000000000003', 'booking_confirmed', 'Booking confirmed', 'Not yet', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-000000000003', 'booking_confirmed', 'Booking confirmed', 'Too old', now() - interval '2 days'),
  ('00000000-0000-0000-0000-000000000004', 'booking_confirmed', 'Booking confirmed', 'Email off', now() - interval '1 minute');
insert into public.notice_settings (account_id, by_email) values ('00000000-0000-0000-0000-000000000004', false)
  on conflict (account_id) do update set by_email = false;
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at)
  values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online',
          now() - interval '10 minutes', now() + interval '50 minutes');
select id as started from public.sessions where starts_at > now() - interval '11 minutes' and starts_at <= now() order by created_at desc limit 1 \gset
insert into public.session_notices (account_id, session_id, kind, title, body, deliver_at)
  values ('00000000-0000-0000-0000-000000000003', :'started', 'reminder_final', 'Session in 1 hour', 'Started', now() - interval '5 minutes');

insert into public.progress_notices (account_id, student_id, kind, title, body, deliver_at)
  values ('00000000-0000-0000-0000-000000000003', :'sam', 'session_update', 'Update', 'Progress due now', now() - interval '1 minute');

select account_id as tutor from public.tutor_profiles limit 1 \gset
insert into public.billing_tutor_notices (tutor_id, student_id, kind, created_at)
  values (:'tutor', :'sam', 'on_hold', ((current_date - 1) + time '12:00') at time zone 'Australia/Adelaide');

select tests.eq(private.emails_waiting()::int, 1, 'emails waiting');
-- No pg_net or Vault here, so waking the sender quietly does nothing.
select tests.eq(private.wake_email_sender()::int, 0, 'no sender call without pg_net and Vault');

-- Families, tutors and admins can't take emails from the queue.
select tests.claims('00000000-0000-0000-0000-000000000003', 'aal2');
set role authenticated;
select tests.fails($$select * from public.session_notice_emails_claim()$$, 'family takes session emails');
select tests.fails($$select * from public.progress_notice_emails_claim()$$, 'family takes progress emails');
select tests.fails($$select * from public.billing_tutor_notice_emails_claim()$$, 'family takes billing emails');
select tests.fails($$select public.session_notice_emails_release(array[gen_random_uuid()])$$, 'family puts emails back');
reset role;

-- The app's sender (server key).
select tests.claims(null);
set role service_role;
create temp table got as select * from public.session_notice_emails_claim();
select tests.eq((select count(*) from got), 1, 'only the due notice is emailed');
select tests.eq((select count(*) from got where body = 'Due now' and email is not null and link = '/schedule'), 1, 'email address and link included');
select tests.eq((select count(*) from public.session_notice_emails_claim()), 0, 'each notice emailed once');
select public.session_notice_emails_release(array(select id from got));
select tests.eq((select count(*) from public.session_notice_emails_claim()), 1, 'put back after a failed send, tried again');

select tests.eq((select count(*) from public.progress_notice_emails_claim() where link = '/students/' || :'sam' || '/progress'), 1, 'progress update emailed with link');
select tests.eq((select count(*) from public.progress_notice_emails_claim()), 0, 'progress update emailed once');

create temp table hold as select * from public.billing_tutor_notice_emails_claim();
select tests.eq((select count(*) from hold where subject like 'Sessions on hold:%' and body not like '%$%'), 1, 'tutor emailed about the pause, no money details');
select public.billing_tutor_notice_emails_release(array(select id from hold));
select tests.eq((select count(*) from public.billing_tutor_notice_emails_claim()), 1, 'pause email tried again');
reset role;

select tests.eq((select count(*) from public.session_notices where body = 'Email off' and email_sent_at is null), 1, 'email off: stays in the app only');
select tests.eq((select count(*) from public.session_notices where body = 'Started' and email_sent_at is null), 1, 'no reminder once the session started');
select tests.eq((select count(*) from public.session_notices where body = 'Too old' and email_sent_at is null), 1, 'old notices not emailed');
select tests.eq(private.emails_waiting()::int, 0, 'nothing left waiting');
