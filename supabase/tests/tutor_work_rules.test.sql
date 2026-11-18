-- Summary: tests for the tutor work rules (Carla, 18 Nov 2026):
--   1. casual tutors give available times in blocks of at least 2 hours;
--   2. hours outside sessions need the kind of work and what was achieved,
--      and time during a no-show is checked without being paid twice;
--   3. a tutor's "running late" notice reaches the family and CLG, late
--      sign-ons are recorded by themselves, and only CLG reviews them;
--   4. the yearly reminder to enter new award pay rates.
-- Reuses access_rules.test.sql people: owner (...a0), tutor T1 (...11),
-- tutor T2 (...12) and parent P1 (...01, Cara One's parent).
-- Everything is rolled back at the end.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs each update again: they must be safe to run twice.
-- (2-hour availability blocks)
\ir ../migrations/20261120800100_availability_two_hour_blocks.sql
-- (work outside sessions)
\ir ../migrations/20261120800200_work_outside_sessions.sql
-- (running late)
\ir ../migrations/20261120800300_tutor_running_late.sql
-- (award rates reminder)
\ir ../migrations/20261120800400_award_rates_yearly_reminder.sql

-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset
-- Gives T1 casual pay details with a school rate (no agreed hours).
insert into public.billing_staff_pay (account_id, employment, school_rate_cents) values ('00000000-0000-0000-0000-000000000011', 'casual', 4000) -- T1's pay details
on conflict (account_id) do update set employment = 'casual', school_rate_cents = 4000, guaranteed_weekly_minutes = null; -- or update them if T1 already has some

-- ---------------------------------------------------------------------------
-- 1. Available times of at least 2 hours for casual tutors
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(public.my_availability_min_minutes(), 120, 'a casual tutor needs at least 2 hours'); -- Checks the minimum a casual tutor sees.
select tests.fails($$insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at) values ('00000000-0000-0000-0000-000000000011', 3, '15:00', '16:30')$$, 'casual tutor adds a 90-minute time'); -- Checks a 90-minute time is refused.
-- Adds a 2-hour Wednesday time (allowed) and keeps its id as wed.
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at) values ('00000000-0000-0000-0000-000000000011', 3, '15:00', '17:00') returning id as wed \gset
select tests.fails(format($$update public.tutor_availability set ends_at = '16:00' where id = %L$$, :'wed'), 'casual tutor shortens a time to 1 hour'); -- Checks shortening it below 2 hours is refused.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Part-time with agreed weekly hours: no minimum.
update public.billing_staff_pay set employment = 'part_time', guaranteed_weekly_minutes = 600 where account_id = '00000000-0000-0000-0000-000000000011'; -- T1 becomes part-time with 10 hours a week.
select tests.claims('00000000-0000-0000-0000-000000000011'); -- Signs in as tutor T1 again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(public.my_availability_min_minutes(), 0, 'part-time with agreed hours has no minimum'); -- Checks the minimum is gone.
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at) values ('00000000-0000-0000-0000-000000000011', 4, '15:00', '16:00'); -- A 1-hour time is now allowed.
reset role; -- Goes back to the all-powerful test user (access rules off).
update public.billing_staff_pay set employment = 'casual', guaranteed_weekly_minutes = null where account_id = '00000000-0000-0000-0000-000000000011'; -- T1 is casual again for the rest of the tests.

-- ---------------------------------------------------------------------------
-- 2. Hours outside sessions
-- ---------------------------------------------------------------------------
-- A no-show session for T1 yesterday, and one that went ahead.
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status) -- adds the no-show session
values (:'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', -- Cara with T1, online
        ((private.billing_today() - 1) + time '16:00') at time zone 'Australia/Adelaide', ((private.billing_today() - 1) + time '17:00') at time zone 'Australia/Adelaide', 'no_show') -- yesterday 4pm to 5pm, a no-show
-- (keeps its id as noshow)
returning id as noshow \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status) -- adds the completed session
values (:'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', -- Cara with T1, online
        ((private.billing_today() - 1) + time '18:00') at time zone 'Australia/Adelaide', ((private.billing_today() - 1) + time '19:00') at time zone 'Australia/Adelaide', 'completed') -- yesterday 6pm to 7pm, went ahead
-- (keeps its id as went)
returning id as went \gset
-- Keeps yesterday's date as yday.
select (private.billing_today() - 1) as yday \gset

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1 with two-step login.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Planned two lessons', 'preparation', '')$$, :'yday'), 'no achievement written'); -- Checks an entry without what was achieved is refused.
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Planned two lessons', 'unknown', 'Two lesson plans ready')$$, :'yday'), 'unknown kind of work'); -- Checks an unknown kind is refused.
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Filing and emails', 'office_admin', 'Inbox cleared and filed')$$, :'yday'), 'tutor (not admin) logs office admin'); -- Checks office admin is refused for a tutor only.
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Made worksheets in the gap', 'no_show_time', 'Three worksheets finished')$$, :'yday'), 'no-show time without a session'); -- Checks no-show time needs a session.
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Made worksheets in the gap', 'no_show_time', 'Three worksheets finished', %L)$$, :'yday', :'went'), 'no-show time for a session that went ahead'); -- Checks the session must be a no-show.
select tests.fails(format($$select public.billing_log_my_hours(%L, 90, 'Made worksheets in the gap', 'no_show_time', 'Three worksheets finished', %L)$$, :'yday', :'noshow'), 'no-show time longer than the session'); -- Checks it cannot be longer than the session.
select tests.eq((select count(*) from public.my_no_show_sessions() where id = :'noshow'), 1, 'the no-show is offered to choose'); -- Checks the no-show is in the list to choose from.
-- Logs an hour of preparation, and keeps its id as prep.
select public.billing_log_my_hours(:'yday', 60, 'Planned the next two lessons for Cara', 'preparation', 'Two lesson plans with fraction practice ready') as prep \gset
-- Logs 45 minutes of work during the no-show, and keeps its id as gap.
select public.billing_log_my_hours(:'yday', 45, 'Made fraction worksheets while Cara did not come', 'no_show_time', 'Three Year 5 fraction worksheets', :'noshow') as gap \gset
select tests.fails(format($$select public.billing_log_my_hours(%L, 30, 'More work in the gap', 'no_show_time', 'Another worksheet finished', %L)$$, :'yday', :'noshow'), 'the same no-show logged twice'); -- Checks a session's no-show time is logged once.
select tests.eq((select count(*) from public.my_no_show_sessions() where id = :'noshow'), 0, 'a logged no-show is no longer offered'); -- Checks it leaves the list once logged.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The owner approves both: preparation is paid, the no-show time is only checked.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step login.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.billing_review_hours(:'prep', true); -- Approves the preparation.
select public.billing_review_hours(:'gap', true, 'Worksheets checked'); -- Approves the no-show time.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.billing_hour_logs where id = :'prep' and status = 'approved' and pay_line_id is not null), 1, 'preparation approved with a pay line'); -- Checks preparation was paid.
select tests.eq((select count(*) from public.billing_hour_logs where id = :'gap' and status = 'approved' and pay_line_id is null), 1, 'no-show time approved without a second pay line'); -- Checks the no-show time was not paid again.
select tests.eq((select count(*) from public.billing_hour_logs where id = :'gap' and achieved = 'Three Year 5 fraction worksheets' and work_category = 'no_show_time'), 1, 'what was achieved is kept'); -- Checks the achievement is saved.

-- ---------------------------------------------------------------------------
-- 3. Running late
-- ---------------------------------------------------------------------------
-- A session starting in an hour, and one in 5 hours.
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) -- adds the session soon
values (:'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', now() + interval '1 hour', now() + interval '2 hours') -- in an hour, online
-- (keeps its id as soon)
returning id as soon \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) -- adds the later session
values (:'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', now() + interval '5 hours', now() + interval '6 hours') -- in 5 hours, online
-- (keeps its id as later)
returning id as later \gset

select tests.claims('00000000-0000-0000-0000-000000000012'); -- Signs in as tutor T2 (not Cara's tutor).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.tell_running_late(%L, 10, 'Traffic')$$, :'soon'), 'another tutor sends a running late notice'); -- Checks another tutor cannot.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.tell_running_late(%L, 10, 'Traffic')$$, :'later'), 'running late more than 3 hours before'); -- Checks it is refused more than 3 hours ahead.
select tests.fails(format($$select public.tell_running_late(%L, 10, '')$$, :'soon'), 'running late without a reason'); -- Checks a reason is needed.
select tests.fails(format($$select public.tell_running_late(%L, 200, 'Traffic')$$, :'soon'), 'running late by 200 minutes'); -- Checks the minutes must be sensible.
select public.tell_running_late(:'soon', 10, 'Traffic on the freeway'); -- Sends the notice.
select tests.eq((select count(*) from public.session_lateness where session_id = :'soon' and told_minutes = 10 and told_before_start), 1, 'the tutor sees their own lateness line'); -- Checks the line was made and the tutor can read it.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.eq((select count(*) from public.session_notices where session_id = :'soon' and kind = 'running_late' and account_id = '00000000-0000-0000-0000-000000000001'), 1, 'the parent gets a running late notice'); -- Checks the parent got an app notice.
select tests.eq((select count(*) from public.session_notices where session_id = :'soon' and kind = 'running_late' and account_id = '00000000-0000-0000-0000-000000000011'), 0, 'the tutor does not get their own notice'); -- Checks the tutor is not sent one.
select tests.eq((select count(*) from public.session_notices where kind = 'running_late' and session_id = :'soon' and body like '%Traffic%'), 0, 'the reason is not sent to the family'); -- Checks the reason stays with CLG.
select tests.eq((select count(*) from public.session_notices where kind = 'staff_alert' and account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Tutor running late'), 1, 'the owner gets an alert'); -- Checks CLG was told.
select tests.eq((select count(*) from public.session_lateness_emails e join public.session_lateness l on l.id = e.lateness_id where l.session_id = :'soon' and e.account_id = '00000000-0000-0000-0000-000000000001'), 1, 'an email to the parent is queued'); -- Checks the email is waiting.
select tests.eq((select count(*)::bigint from (select 1 where private.lateness_emails_waiting()) w), 1, 'the email sender is told an email is waiting'); -- Checks the waiting check sees it.
set role service_role; -- Acts as the server's email sender.
select tests.eq((select count(*) from public.lateness_emails_claim(50) where body like '%10 minutes late%'), 1, 'the email is handed to the sender'); -- Checks the sender collects it.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The parent cannot read the lateness record.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as parent P1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.session_lateness), 0, 'the family cannot read lateness lines'); -- Checks the table is hidden.
select tests.eq((select count(*) from public.list_session_lateness(180)), 0, 'the family gets nothing from the lateness list'); -- Checks the list is empty for them.
select tests.fails(format($$select public.tell_running_late(%L, 10, 'Traffic')$$, :'soon'), 'a parent sends a running late notice'); -- Checks a parent cannot send one.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Signing on 12 minutes after the start records the late start by itself.
update public.sessions set starts_at = now() - interval '12 minutes', ends_at = now() + interval '48 minutes' where id = :'soon'; -- Moves the session so it started 12 minutes ago.
update public.sessions set signed_on_at = now() where id = :'soon'; -- The tutor signs on now.
select tests.eq((select signed_on_late_minutes from public.session_lateness where session_id = :'soon'), 12, 'the late sign-on is recorded'); -- Checks the minutes late were saved.
-- Signing on on time for a session with no notice records nothing.
update public.sessions set signed_on_at = starts_at + interval '2 minutes' where id = :'later'; -- Signs on 2 minutes after the start of the later session.
select tests.eq((select count(*) from public.session_lateness where session_id = :'later'), 0, 'an on-time sign-on records nothing'); -- Checks no line was made.

-- Only CLG reviews the record. Keeps the line's id as late_line.
select id as late_line from public.session_lateness where session_id = :'soon' \gset
select tests.claims('00000000-0000-0000-0000-000000000011'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.review_session_lateness(%L, 'All fine')$$, :'late_line'), 'the tutor reviews their own lateness'); -- Checks the tutor cannot review it.
select tests.eq((select count(*) from public.list_session_lateness(180) where id = :'late_line' and review_note is null), 1, 'the tutor sees their own line in the list'); -- Checks the tutor sees their line (without any note).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step login.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.review_session_lateness(%L, '')$$, :'late_line'), 'a review without a note'); -- Checks a note is needed.
select public.review_session_lateness(:'late_line', 'Talked with the tutor about leaving earlier'); -- Reviews it.
select tests.eq((select count(*) from public.list_session_lateness(180) where id = :'late_line' and review_status = 'reviewed' and review_note like 'Talked%'), 1, 'the owner sees the reviewed line'); -- Checks the review was saved.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- 4. The yearly award rates reminder
-- ---------------------------------------------------------------------------
delete from public.billing_award_rates where effective_from >= '2027-01-01'; -- Makes sure no rates for July 2027 are there yet.
select tests.eq((select count(*)::bigint from (select 1 where private.award_rates_due_on('2026-11-17') is null) x), 1, 'not due while this year''s rates are in'); -- Checks November 2026 is not due (the July 2026 rates are in).
select tests.eq((select count(*)::bigint from (select 1 where private.award_rates_due_on('2027-05-31') is null) x), 1, 'not due before 1 June'); -- Checks 31 May is not due.
select tests.eq((select count(*)::bigint from (select 1 where private.award_rates_due_on('2027-06-01') = '2027-07-01') x), 1, 'due from 1 June for the coming 1 July'); -- Checks 1 June is due.
select tests.eq((select count(*)::bigint from (select 1 where private.award_rates_due_on('2027-09-01') = '2027-07-01') x), 1, 'still due in September if never entered'); -- Checks missing rates keep being asked for.
insert into public.billing_award_rates (work_kind, employment, min_rate_cents, award, effective_from) values ('school', 'casual', 3500, 'Test rate', '2027-07-01'); -- Uploads a July 2027 rate.
select tests.eq((select count(*)::bigint from (select 1 where private.award_rates_due_on('2027-06-15') is null) x), 1, 'not due once the new rates are in'); -- Checks the reminder clears.
select tests.claims('00000000-0000-0000-0000-000000000011'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*)::bigint from (select 1 where public.award_rates_due() is null) x), 1, 'a tutor never sees the reminder'); -- Checks only pay admins see it.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  tutor work rules: all checks passed'
