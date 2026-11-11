-- Sending notices by email. Runs after the scheduling, progress and billing
-- tests and reuses their people: parent P3 (...03, Sam Three's parent),
-- parent P4 (...04) and tutor T3 (...13).

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset

-- Start clean: everything from earlier tests counts as already sent.
update public.session_notices set email_sent_at = now() where email_sent_at is null; -- Marks earlier session notices as emailed.
update public.progress_notices set email_sent_at = now() where email_sent_at is null; -- Marks earlier progress notices as emailed.
update public.billing_tutor_notices set sent_at = now() where sent_at is null; -- Marks earlier tutor billing notices as sent.
update public.security_alerts set sent_at = now() where sent_at is null; -- Marks earlier security alerts as sent.
select tests.eq(private.emails_waiting()::int, 0, 'nothing waiting'); -- Checks: nothing waiting.

-- Notices: one due now, one not due yet, one from 2 days ago, one for a
-- person who turned email off, and a reminder for a session that started.
insert into public.session_notices (account_id, kind, title, body, deliver_at) values -- Adds four session notices:
  ('00000000-0000-0000-0000-000000000003', 'booking_confirmed', 'Booking confirmed', 'Due now', now() - interval '1 minute'), -- one due now,
  ('00000000-0000-0000-0000-000000000003', 'booking_confirmed', 'Booking confirmed', 'Not yet', now() + interval '1 hour'), -- one due in an hour,
  ('00000000-0000-0000-0000-000000000003', 'booking_confirmed', 'Booking confirmed', 'Too old', now() - interval '2 days'), -- one two days old (too old to email),
  ('00000000-0000-0000-0000-000000000004', 'booking_confirmed', 'Booking confirmed', 'Email off', now() - interval '1 minute'); -- and one for someone who turned emails off.
insert into public.notice_settings (account_id, by_email) values ('00000000-0000-0000-0000-000000000004', false) -- Turns emails off for account ...04:
  on conflict (account_id) do update set by_email = false; -- (or updates their setting if they have one).
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) -- Adds a session for Sam with tutor T3:
  values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', -- (online),
          now() - interval '10 minutes', now() + interval '50 minutes'); -- that started 10 minutes ago.
-- Keeps its id as started.
select id as started from public.sessions where starts_at > now() - interval '11 minutes' and starts_at <= now() order by created_at desc limit 1 \gset
insert into public.session_notices (account_id, session_id, kind, title, body, deliver_at) -- Adds a final reminder for that session:
  values ('00000000-0000-0000-0000-000000000003', :'started', 'reminder_final', 'Session in 1 hour', 'Started', now() - interval '5 minutes'); -- (due 5 minutes ago, after the session started).

insert into public.progress_notices (account_id, student_id, kind, title, body, deliver_at) -- Adds a progress update notice:
  values ('00000000-0000-0000-0000-000000000003', :'sam', 'session_update', 'Update', 'Progress due now', now() - interval '1 minute'); -- (due now).

-- Keeps a tutor's id as tutor.
select account_id as tutor from public.tutor_profiles limit 1 \gset
insert into public.billing_tutor_notices (tutor_id, student_id, kind, created_at) -- Adds an "on hold" notice for that tutor:
  values (:'tutor', :'sam', 'on_hold', ((current_date - 1) + time '12:00') at time zone 'Australia/Adelaide'); -- (made yesterday at noon).

-- App notices only (2 Nov 2026): these no longer wake the email sender.
select tests.eq(private.emails_waiting()::int, 0, 'notification emails no longer wake the sender'); -- Checks: notification emails no longer wake the sender.
select tests.eq((select count(*) from public.notice_settings where by_email), 0, 'nobody has email reminders switched on'); -- Checks: nobody has email reminders switched on.

-- The modules' claim functions are kept (unused) for if email comes back.
-- Check they still work, with P3 switched back on for the test.
update public.notice_settings set by_email = true where account_id = '00000000-0000-0000-0000-000000000003'; -- Turns emails on for account ...03.
-- No pg_net or Vault here, so waking the sender quietly does nothing.
select tests.eq(private.wake_email_sender()::int, 0, 'no sender call without pg_net and Vault'); -- Checks: no sender call without pg_net and Vault.

-- Families, tutors and admins can't take emails from the queue.
select tests.claims('00000000-0000-0000-0000-000000000003', 'aal2'); -- Signs in as test account ...03 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select * from public.session_notice_emails_claim()$$, 'family takes session emails'); -- Checks this is refused: family takes session emails.
select tests.fails($$select * from public.progress_notice_emails_claim()$$, 'family takes progress emails'); -- Checks this is refused: family takes progress emails.
select tests.fails($$select * from public.billing_tutor_notice_emails_claim()$$, 'family takes billing emails'); -- Checks this is refused: family takes billing emails.
select tests.fails($$select public.session_notice_emails_release(array[gen_random_uuid()])$$, 'family puts emails back'); -- Checks this is refused: family puts emails back.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The app's sender (server key).
select tests.claims(null); -- Signs out, so no one is signed in.
set role service_role; -- Acts as the server's own key.
create temp table got as select * from public.session_notice_emails_claim(); -- Claims the session notices due to be emailed, keeping them in a short-lived table.
select tests.eq((select count(*) from got), 1, 'only the due notice is emailed'); -- Checks: only the due notice is emailed.
select tests.eq((select count(*) from got where body = 'Due now' and email is not null and link = '/schedule'), 1, 'email address and link included'); -- Checks: email address and link included.
select tests.eq((select count(*) from public.session_notice_emails_claim()), 0, 'each notice emailed once'); -- Checks: each notice emailed once.
select public.session_notice_emails_release(array(select id from got)); -- Hands them back as not sent.
select tests.eq((select count(*) from public.session_notice_emails_claim()), 1, 'put back after a failed send, tried again'); -- Checks: put back after a failed send, tried again.

select tests.eq((select count(*) from public.progress_notice_emails_claim() where link = '/students/' || :'sam' || '/progress'), 1, 'progress update emailed with link'); -- Checks: progress update emailed with link.
select tests.eq((select count(*) from public.progress_notice_emails_claim()), 0, 'progress update emailed once'); -- Checks: progress update emailed once.

create temp table hold as select * from public.billing_tutor_notice_emails_claim(); -- Claims the tutor billing notices due, keeping them in a short-lived table.
select tests.eq((select count(*) from hold where subject like 'Sessions on hold:%' and body not like '%$%'), 1, 'tutor emailed about the pause, no money details'); -- Checks: tutor emailed about the pause, no money details.
select public.billing_tutor_notice_emails_release(array(select id from hold)); -- Hands them back as not sent.
select tests.eq((select count(*) from public.billing_tutor_notice_emails_claim()), 1, 'pause email tried again'); -- Checks: pause email tried again.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.eq((select count(*) from public.session_notices where body = 'Email off' and email_sent_at is null), 1, 'email off: stays in the app only'); -- Checks: email off: stays in the app only.
select tests.eq((select count(*) from public.session_notices where body = 'Started' and email_sent_at is null), 1, 'no reminder once the session started'); -- Checks: no reminder once the session started.
select tests.eq((select count(*) from public.session_notices where body = 'Too old' and email_sent_at is null), 1, 'old notices not emailed'); -- Checks: old notices not emailed.
select tests.eq(private.emails_waiting()::int, 0, 'nothing left waiting'); -- Checks: nothing left waiting.

-- The app's sender only asks for security emails now.
select tests.eq(position('session_notice_emails_claim' in pg_get_functiondef('private.emails_waiting()'::regprocedure)), 0, 'sender check ignores session notices'); -- Checks: sender check ignores session notices.
