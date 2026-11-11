-- Tutor and staff pay. Runs after access_rules.test.sql and reuses its
-- people: owner (...a0), staff admin (...b0), tutors T1 (...11) and T2
-- (...12), parent P1 (...01).

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the database change 20261028230100_billing_tutor_pay.sql first, as this test needs it.
\ir ../migrations/20261028230100_billing_tutor_pay.sql
-- Runs the database change 20261028230300_billing_casual_min_off.sql first, as this test needs it.
\ir ../migrations/20261028230300_billing_casual_min_off.sql
-- Re-running an older billing file resets its rules, so apply admin levels again.
-- Runs the database change 20261029900200_admin_levels.sql first, as this test needs it.
\ir ../migrations/20261029900200_admin_levels.sql

-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset

-- A past session for tests, written straight in as scheduling would.
create function tests.pay_session( -- A test helper that adds a session and gives back its id. It takes:
  p_tutor uuid, p_student uuid, p_day date, p_start time, p_minutes int, p_level text default 'school' -- the tutor, student, day, start time, minutes, and level (school unless given).
) returns uuid language sql as $$ -- (gives back the new session's id)
  insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) -- Adds the session:
  select p_student, p_tutor, s.family_id, 'General Maths', p_level, 'online', -- for this student and tutor, General Maths, online,
         (p_day + p_start) at time zone 'Australia/Adelaide', -- starting at the given time in Adelaide,
         (p_day + p_start + make_interval(mins => p_minutes)) at time zone 'Australia/Adelaide' -- ending the given minutes later,
  from public.students s where s.id = p_student -- (using the student's family),
  returning id -- and hands back its id.
$$; -- (end of the helper)

-- ---------------------------------------------------------------------------
-- Pay rates
-- ---------------------------------------------------------------------------
-- Operations can see pay but not change it; the owner and finance can.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$insert into public.billing_staff_pay (account_id, employment, school_rate_cents) values ('00000000-0000-0000-0000-000000000011', 'casual', 3400)$$, 'operations sets a pay rate'); -- Checks this is refused: operations sets a pay rate.
select tests.fails($$select public.billing_build_pay('2026-09-07', '2026-09-13')$$, 'operations works out pay'); -- Checks this is refused: operations works out pay.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.billing_staff_pay (account_id, employment, school_rate_cents, tertiary_rate_cents) values -- Sets pay rates for two tutors:
  ('00000000-0000-0000-0000-000000000011', 'casual', 3400, 6288), -- tutor T1, casual, school and tertiary rates,
  ('00000000-0000-0000-0000-000000000012', 'part_time', 2000, null); -- tutor T2, part-time, school rate only.
select tests.fails($$select public.billing_add_admin_time('00000000-0000-0000-0000-000000000011', '2026-09-08', 60, 'Notes')$$, 'admin hours need an admin rate first'); -- Checks this is refused: admin hours need an admin rate first.
update public.billing_staff_pay set admin_rate_cents = 3400 where account_id = '00000000-0000-0000-0000-000000000011'; -- Gives tutor T1 an admin rate too.
select tests.eq((select count(*) from public.billing_award_rates), 9, 'owner reads award rates'); -- Checks: owner reads award rates.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_award_rates), 9, 'operations reads award rates'); -- Checks: operations reads award rates.
update public.billing_award_rates set min_rate_cents = 1 where work_kind = 'school'; -- Lowers the award minimum for school work, for this test.
select tests.eq((select count(*) from public.billing_award_rates where min_rate_cents = 1), 0, 'only the owner changes award rates'); -- Checks: only the owner changes award rates.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_staff_pay), 1, 'tutor sees own pay settings only'); -- Checks: tutor sees own pay settings only.
update public.billing_staff_pay set school_rate_cents = 9999; -- Tries to change every tutor's school rate.
select tests.eq((select count(*) from public.billing_staff_pay where school_rate_cents = 9999), 0, 'tutor cannot change own rate'); -- Checks: tutor cannot change own rate.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- Signs in as test account ...11.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_staff_pay), 0, 'no pay details without two-step login'); -- Checks: no pay details without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_staff_pay), 0, 'parent sees no pay'); -- Checks: parent sees no pay.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- ---------------------------------------------------------------------------
-- Sessions to pay lines. Week of Monday 7 September 2026.
-- ---------------------------------------------------------------------------
-- Mon: 1 hr worked. Casual, so topped up to 2 hr.
-- A completed 1-hr Monday session, kept as mon.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-07', '16:00', 60) as mon \gset
update public.sessions set status = 'completed', worked_from = starts_at, worked_to = ends_at where id = :'mon'; -- (completed on time)
-- Tue: 90 min booked, tutor 10 min late: 80 min worked, plus 1 hr admin.
-- A 1.5-hr Tuesday session, kept as tue.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-08', '16:00', 90) as tue \gset
update public.sessions set status = 'completed', worked_from = starts_at + interval '10 minutes', worked_to = ends_at where id = :'tue'; -- (completed, started 10 minutes late)
-- Wed: family cancels 10 hr before a 1 hr session: 30 min pay, no top-up.
-- A Wednesday session, kept as wed.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-09', '16:00', 60) as wed \gset
update public.sessions set status = 'cancelled', cancelled_by_role = 'family', cancelled_at = starts_at - interval '10 hours' where id = :'wed'; -- (cancelled by the family 10 hours before)
-- Thu: 90 min no-show before the tutor signed on: 45 min (50%, under 1 hr).
-- A 1.5-hr Thursday session, kept as thu.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-10', '16:00', 90) as thu \gset
update public.sessions set status = 'no_show' where id = :'thu'; -- (the student didn't come; tutor didn't sign on)
-- Fri: no-show after the tutor signed on: the hour they had to be there,
-- topped up to 2 hr.
-- A Friday session, kept as fri.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-11', '16:00', 60) as fri \gset
update public.sessions set status = 'no_show', signed_on_at = starts_at where id = :'fri'; -- (the student didn't come; tutor signed on)
-- Sat: tutor cancels (no pay) and family cancels 2 days ahead (no pay).
-- A Saturday 9am session, kept as sat1.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-12', '09:00', 60) as sat1 \gset
update public.sessions set status = 'cancelled', cancelled_by_role = 'tutor', cancelled_at = starts_at - interval '1 hour' where id = :'sat1'; -- (cancelled by the tutor an hour before)
-- A Saturday 11am session, kept as sat2.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-12', '11:00', 60) as sat2 \gset
update public.sessions set status = 'cancelled', cancelled_by_role = 'family', cancelled_at = starts_at - interval '48 hours' where id = :'sat2'; -- (cancelled by the family 2 days before)
-- Sun: 2 hr tertiary at the tertiary rate.
-- A 2-hr tertiary session on Sunday, kept as sun.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-13', '10:00', 120, 'tertiary') as sun \gset
update public.sessions set status = 'completed', worked_from = starts_at, worked_to = ends_at where id = :'sun'; -- (completed on time)
-- A session still waiting for an admin to confirm the times isn't paid yet.
-- A Sunday 2pm session, kept as waiting.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-13', '14:00', 60) as waiting \gset
update public.sessions set status = 'completed' where id = :'waiting'; -- (completed, but the times aren't confirmed yet)
-- T2 is part-time on a rate under the award: no top-up, flagged.
-- A Monday session for tutor T2, kept as t2.
select tests.pay_session('00000000-0000-0000-0000-000000000012', :'cara', '2026-09-07', '10:00', 60) as t2 \gset
update public.sessions set status = 'completed', worked_from = starts_at, worked_to = ends_at where id = :'t2'; -- (completed on time)

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.billing_add_admin_time('00000000-0000-0000-0000-000000000011', '2026-09-08', 60, 'Progress summaries'); -- Adds an hour of admin time for tutor T1.
select tests.fails($$select public.billing_add_admin_time('00000000-0000-0000-0000-000000000011', current_date + 7, 60, 'Future')$$, 'admin hours in the future'); -- Checks this is refused: admin hours in the future.
select tests.fails($$select public.billing_add_admin_time('00000000-0000-0000-0000-000000000011', '2026-09-08', 5, 'Too short')$$, 'admin hours too short'); -- Checks this is refused: admin hours too short.
select public.billing_build_pay('2026-09-07', '2026-09-13'); -- Builds the pay for that week.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- The casual top-up is off by default (Carla, 2026-10-28).
select tests.eq((select count(*) from public.billing_pay_lines where kind = 'min_topup'), 0, 'no top-ups while switched off'); -- Checks: no top-ups while switched off.
update public.billing_settings set casual_min_enabled = true; -- Turns on the casual 2-hr minimum.
select public.billing_build_pay('2026-09-07', '2026-09-13'); -- Builds the pay again.

create function tests.pay(p_kind text, p_day date, p_tutor text default '11') returns bigint language sql as $$ -- A test helper that adds up the paid minutes of one kind on one day, for one tutor:
  select coalesce(sum(minutes), 0) from public.billing_pay_lines -- (adds up the minutes)
  where kind = p_kind and work_date = p_day and account_id = ('00000000-0000-0000-0000-0000000000' || p_tutor)::uuid -- (of that kind, on that day, for that tutor).
$$; -- (end of the helper)

select tests.eq(tests.pay('session', '2026-09-07'), 60, 'Mon: hour worked'); -- Checks: Mon: hour worked.
select tests.eq(tests.pay('min_topup', '2026-09-07'), 60, 'Mon: topped up to 2 hr'); -- Checks: Mon: topped up to 2 hr.
select tests.eq(tests.pay('session', '2026-09-08'), 80, 'Tue: tutor late, paid time worked'); -- Checks: Tue: tutor late, paid time worked.
select tests.eq(tests.pay('admin', '2026-09-08'), 60, 'Tue: admin hours'); -- Checks: Tue: admin hours.
select tests.eq(tests.pay('min_topup', '2026-09-08'), 0, 'Tue: admin hours fill the day'); -- Checks: Tue: admin hours fill the day.
select tests.eq(tests.pay('late_cancel', '2026-09-09'), 30, 'Wed: late cancel pays half'); -- Checks: Wed: late cancel pays half.
select tests.eq(tests.pay('min_topup', '2026-09-09'), 0, 'Wed: late cancel alone is not a day at work'); -- Checks: Wed: late cancel alone is not a day at work.
select tests.eq(tests.pay('late_cancel', '2026-09-10'), 45, 'Thu: no-show before sign on'); -- Checks: Thu: no-show before sign on.
select tests.eq(tests.pay('session', '2026-09-11'), 60, 'Fri: no-show after sign on, paid the time'); -- Checks: Fri: no-show after sign on, paid the time.
select tests.eq(tests.pay('min_topup', '2026-09-11'), 60, 'Fri: topped up'); -- Checks: Fri: topped up.
select tests.eq((select count(*) from public.billing_pay_lines where work_date = '2026-09-12'), 0, 'Sat: tutor cancel and early cancel: no pay'); -- Checks: Sat: tutor cancel and early cancel: no pay.
select tests.eq((select amount_cents from public.billing_pay_lines where session_id = :'sun'), 12576, 'Sun: tertiary rate'); -- Checks: Sun: tertiary rate.
select tests.eq((select count(*) from public.billing_pay_lines where session_id = :'waiting'), 0, 'times not confirmed: not paid yet'); -- Checks: times not confirmed: not paid yet.
select tests.eq((select amount_cents from public.billing_pay_lines where session_id = :'mon'), 3400, 'school rate'); -- Checks: school rate.
select tests.eq(tests.pay('min_topup', '2026-09-07', '12'), 0, 'part-time: no casual top-up'); -- Checks: part-time: no casual top-up.
select tests.eq((select count(*) from public.billing_pay_lines where session_id = :'t2' and under_award), 1, 'rate under the award is flagged'); -- Checks: rate under the award is flagged.
select tests.eq((select count(*) from public.billing_pay_lines where account_id = '00000000-0000-0000-0000-000000000011' and under_award), 0, 'award rates met'); -- Checks: award rates met.

select tests.eq(((select period_start from public.billing_pay_period('2026-09-10')) = '2026-09-07')::int, 1, 'pay week starts Monday'); -- Checks: pay week starts Monday.
select tests.eq(((select period_end from public.billing_pay_period('2026-09-06')) = '2026-09-06')::int, 1, 'day before the anchor ends the earlier week'); -- Checks: day before the anchor ends the earlier week.

-- Running again gives the same lines.
-- Keeps how many pay lines there are as before_count.
select count(*) as before_count from public.billing_pay_lines \gset
select public.billing_build_pay('2026-09-07', '2026-09-13'); -- Builds the pay again (should not add any).
select tests.eq((select count(*) from public.billing_pay_lines), :before_count, 're-run makes no duplicates'); -- Checks: re-run makes no duplicates.

-- Lines sent to Xero are never changed by a re-run.
select public.billing_mark_pay_sent(array(select id from public.billing_pay_lines where session_id = :'mon'), 'ts_1'); -- Marks Monday's pay as sent to Xero.
update public.sessions set worked_to = ends_at + interval '30 minutes' where id = :'mon'; -- Monday's session ran 30 minutes over.
select public.billing_build_pay('2026-09-07', '2026-09-13'); -- Builds the pay again.
select tests.eq((select minutes from public.billing_pay_lines where session_id = :'mon'), 60, 'sent line unchanged'); -- Checks: sent line unchanged.

-- ---------------------------------------------------------------------------
-- Who sees pay lines
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_pay_lines where account_id <> '00000000-0000-0000-0000-000000000011'), 0, 'tutor sees own pay lines only'); -- Checks: tutor sees own pay lines only.
select tests.eq(((select count(*) from public.billing_pay_lines) > 0)::int, 1, 'tutor sees own pay lines'); -- Checks: tutor sees own pay lines.
select tests.fails($$insert into public.billing_pay_lines (account_id, staff_name, work_date, kind, work_kind, minutes, rate_cents, amount_cents) values ('00000000-0000-0000-0000-000000000011', 'x', '2026-09-07', 'admin', 'admin', 600, 9999, 99990)$$, 'tutor adds own pay'); -- Checks this is refused: tutor adds own pay.
select tests.fails($$select public.billing_build_pay('2026-09-07', '2026-09-13')$$, 'tutor works out pay'); -- Checks this is refused: tutor works out pay.
select tests.fails($$select public.billing_add_admin_time('00000000-0000-0000-0000-000000000011', '2026-09-08', 600, 'Lots')$$, 'tutor records own admin hours'); -- Checks this is refused: tutor records own admin hours.
select tests.fails($$select public.billing_mark_pay_sent(array[]::uuid[], 'x')$$, 'browser marks pay sent'); -- Checks this is refused: browser marks pay sent.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_pay_lines), 0, 'parent sees no pay lines'); -- Checks: parent sees no pay lines.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.billing_pay_lines$$, 'anon reads pay'); -- Checks this is refused: anon reads pay.
select tests.fails($$select * from public.billing_staff_pay$$, 'anon reads rates'); -- Checks this is refused: anon reads rates.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Switching it off again removes top-ups not yet sent.
update public.billing_settings set casual_min_enabled = false; -- Turns the casual minimum off.
select public.billing_build_pay('2026-09-07', '2026-09-13'); -- Builds the pay again.
select tests.eq((select count(*) from public.billing_pay_lines where kind = 'min_topup' and status = 'pending'), 0, 'top-ups removed when switched off'); -- Checks: top-ups removed when switched off.

-- Clean up for later tests.
delete from public.billing_pay_lines; -- Clears the pay lines.
delete from public.billing_staff_pay; -- Clears the pay rates.
delete from public.sessions where student_id = :'cara'; -- Removes Cara's sessions.
drop function tests.pay(text, date, text); -- Removes the minutes helper.
drop function tests.pay_session(uuid, uuid, date, time, int, text); -- Removes the session helper.

-- Prints that every check in this file passed.
\echo '  billing pay: all checks passed'
