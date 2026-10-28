-- Tutor and staff pay. Runs after access_rules.test.sql and reuses its
-- people: owner (...a0), staff admin (...b0), tutors T1 (...11) and T2
-- (...12), parent P1 (...01).

\set QUIET on
\ir ../migrations/20261028230100_billing_tutor_pay.sql

select id as cara from public.students where full_name = 'Cara One' \gset

-- A past session for tests, written straight in as scheduling would.
create function tests.pay_session(
  p_tutor uuid, p_student uuid, p_day date, p_start time, p_minutes int, p_level text default 'school'
) returns uuid language sql as $$
  insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at)
  select p_student, p_tutor, s.family_id, 'General Maths', p_level, 'online',
         (p_day + p_start) at time zone 'Australia/Adelaide',
         (p_day + p_start + make_interval(mins => p_minutes)) at time zone 'Australia/Adelaide'
  from public.students s where s.id = p_student
  returning id
$$;

-- ---------------------------------------------------------------------------
-- Pay rates
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
insert into public.billing_staff_pay (account_id, employment, school_rate_cents, tertiary_rate_cents) values
  ('00000000-0000-0000-0000-000000000011', 'casual', 3400, 6288),
  ('00000000-0000-0000-0000-000000000012', 'part_time', 2000, null);
select tests.fails($$select public.billing_add_admin_time('00000000-0000-0000-0000-000000000011', '2026-09-08', 60, 'Notes')$$, 'admin hours need an admin rate first');
update public.billing_staff_pay set admin_rate_cents = 3400 where account_id = '00000000-0000-0000-0000-000000000011';
select tests.eq((select count(*) from public.billing_award_rates), 9, 'staff admin reads award rates');
update public.billing_award_rates set min_rate_cents = 1 where work_kind = 'school';
select tests.eq((select count(*) from public.billing_award_rates where min_rate_cents = 1), 0, 'only the owner changes award rates');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.billing_staff_pay), 1, 'tutor sees own pay settings only');
update public.billing_staff_pay set school_rate_cents = 9999;
select tests.eq((select count(*) from public.billing_staff_pay where school_rate_cents = 9999), 0, 'tutor cannot change own rate');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1');
set role authenticated;
select tests.eq((select count(*) from public.billing_staff_pay), 0, 'no pay details without two-step login');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.billing_staff_pay), 0, 'parent sees no pay');
reset role;
select tests.claims(null);

-- ---------------------------------------------------------------------------
-- Sessions to pay lines. Week of Monday 7 September 2026.
-- ---------------------------------------------------------------------------
-- Mon: 1 hr worked. Casual, so topped up to 2 hr.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-07', '16:00', 60) as mon \gset
update public.sessions set status = 'completed', worked_from = starts_at, worked_to = ends_at where id = :'mon';
-- Tue: 90 min booked, tutor 10 min late: 80 min worked, plus 1 hr admin.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-08', '16:00', 90) as tue \gset
update public.sessions set status = 'completed', worked_from = starts_at + interval '10 minutes', worked_to = ends_at where id = :'tue';
-- Wed: family cancels 10 hr before a 1 hr session: 30 min pay, no top-up.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-09', '16:00', 60) as wed \gset
update public.sessions set status = 'cancelled', cancelled_by_role = 'family', cancelled_at = starts_at - interval '10 hours' where id = :'wed';
-- Thu: 90 min no-show before the tutor signed on: 45 min (50%, under 1 hr).
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-10', '16:00', 90) as thu \gset
update public.sessions set status = 'no_show' where id = :'thu';
-- Fri: no-show after the tutor signed on: the hour they had to be there,
-- topped up to 2 hr.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-11', '16:00', 60) as fri \gset
update public.sessions set status = 'no_show', signed_on_at = starts_at where id = :'fri';
-- Sat: tutor cancels (no pay) and family cancels 2 days ahead (no pay).
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-12', '09:00', 60) as sat1 \gset
update public.sessions set status = 'cancelled', cancelled_by_role = 'tutor', cancelled_at = starts_at - interval '1 hour' where id = :'sat1';
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-12', '11:00', 60) as sat2 \gset
update public.sessions set status = 'cancelled', cancelled_by_role = 'family', cancelled_at = starts_at - interval '48 hours' where id = :'sat2';
-- Sun: 2 hr tertiary at the tertiary rate.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-13', '10:00', 120, 'tertiary') as sun \gset
update public.sessions set status = 'completed', worked_from = starts_at, worked_to = ends_at where id = :'sun';
-- A session still waiting for an admin to confirm the times isn't paid yet.
select tests.pay_session('00000000-0000-0000-0000-000000000011', :'cara', '2026-09-13', '14:00', 60) as waiting \gset
update public.sessions set status = 'completed' where id = :'waiting';
-- T2 is part-time on a rate under the award: no top-up, flagged.
select tests.pay_session('00000000-0000-0000-0000-000000000012', :'cara', '2026-09-07', '10:00', 60) as t2 \gset
update public.sessions set status = 'completed', worked_from = starts_at, worked_to = ends_at where id = :'t2';

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.billing_add_admin_time('00000000-0000-0000-0000-000000000011', '2026-09-08', 60, 'Progress summaries');
select tests.fails($$select public.billing_add_admin_time('00000000-0000-0000-0000-000000000011', current_date + 7, 60, 'Future')$$, 'admin hours in the future');
select tests.fails($$select public.billing_add_admin_time('00000000-0000-0000-0000-000000000011', '2026-09-08', 5, 'Too short')$$, 'admin hours too short');
select public.billing_build_pay('2026-09-07', '2026-09-13');
reset role;
select tests.claims(null);

create function tests.pay(p_kind text, p_day date, p_tutor text default '11') returns bigint language sql as $$
  select coalesce(sum(minutes), 0) from public.billing_pay_lines
  where kind = p_kind and work_date = p_day and account_id = ('00000000-0000-0000-0000-0000000000' || p_tutor)::uuid
$$;

select tests.eq(tests.pay('session', '2026-09-07'), 60, 'Mon: hour worked');
select tests.eq(tests.pay('min_topup', '2026-09-07'), 60, 'Mon: topped up to 2 hr');
select tests.eq(tests.pay('session', '2026-09-08'), 80, 'Tue: tutor late, paid time worked');
select tests.eq(tests.pay('admin', '2026-09-08'), 60, 'Tue: admin hours');
select tests.eq(tests.pay('min_topup', '2026-09-08'), 0, 'Tue: admin hours fill the day');
select tests.eq(tests.pay('late_cancel', '2026-09-09'), 30, 'Wed: late cancel pays half');
select tests.eq(tests.pay('min_topup', '2026-09-09'), 0, 'Wed: late cancel alone is not a day at work');
select tests.eq(tests.pay('late_cancel', '2026-09-10'), 45, 'Thu: no-show before sign on');
select tests.eq(tests.pay('session', '2026-09-11'), 60, 'Fri: no-show after sign on, paid the time');
select tests.eq(tests.pay('min_topup', '2026-09-11'), 60, 'Fri: topped up');
select tests.eq((select count(*) from public.billing_pay_lines where work_date = '2026-09-12'), 0, 'Sat: tutor cancel and early cancel: no pay');
select tests.eq((select amount_cents from public.billing_pay_lines where session_id = :'sun'), 12576, 'Sun: tertiary rate');
select tests.eq((select count(*) from public.billing_pay_lines where session_id = :'waiting'), 0, 'times not confirmed: not paid yet');
select tests.eq((select amount_cents from public.billing_pay_lines where session_id = :'mon'), 3400, 'school rate');
select tests.eq(tests.pay('min_topup', '2026-09-07', '12'), 0, 'part-time: no casual top-up');
select tests.eq((select count(*) from public.billing_pay_lines where session_id = :'t2' and under_award), 1, 'rate under the award is flagged');
select tests.eq((select count(*) from public.billing_pay_lines where account_id = '00000000-0000-0000-0000-000000000011' and under_award), 0, 'award rates met');

-- Running again gives the same lines.
select count(*) as before_count from public.billing_pay_lines \gset
select public.billing_build_pay('2026-09-07', '2026-09-13');
select tests.eq((select count(*) from public.billing_pay_lines), :before_count, 're-run makes no duplicates');

-- Lines sent to Xero are never changed by a re-run.
select public.billing_mark_pay_sent(array(select id from public.billing_pay_lines where session_id = :'mon'), 'ts_1');
update public.sessions set worked_to = ends_at + interval '30 minutes' where id = :'mon';
select public.billing_build_pay('2026-09-07', '2026-09-13');
select tests.eq((select minutes from public.billing_pay_lines where session_id = :'mon'), 60, 'sent line unchanged');

-- ---------------------------------------------------------------------------
-- Who sees pay lines
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.billing_pay_lines where account_id <> '00000000-0000-0000-0000-000000000011'), 0, 'tutor sees own pay lines only');
select tests.eq(((select count(*) from public.billing_pay_lines) > 0)::int, 1, 'tutor sees own pay lines');
select tests.fails($$insert into public.billing_pay_lines (account_id, staff_name, work_date, kind, work_kind, minutes, rate_cents, amount_cents) values ('00000000-0000-0000-0000-000000000011', 'x', '2026-09-07', 'admin', 'admin', 600, 9999, 99990)$$, 'tutor adds own pay');
select tests.fails($$select public.billing_build_pay('2026-09-07', '2026-09-13')$$, 'tutor works out pay');
select tests.fails($$select public.billing_add_admin_time('00000000-0000-0000-0000-000000000011', '2026-09-08', 600, 'Lots')$$, 'tutor records own admin hours');
select tests.fails($$select public.billing_mark_pay_sent(array[]::uuid[], 'x')$$, 'browser marks pay sent');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.billing_pay_lines), 0, 'parent sees no pay lines');
reset role;

select tests.claims(null);
set role anon;
select tests.fails($$select * from public.billing_pay_lines$$, 'anon reads pay');
select tests.fails($$select * from public.billing_staff_pay$$, 'anon reads rates');
reset role;

-- Clean up for later tests.
delete from public.billing_pay_lines;
delete from public.billing_staff_pay;
delete from public.sessions where student_id = :'cara';
drop function tests.pay(text, date, text);
drop function tests.pay_session(uuid, uuid, date, time, int, text);

\echo '  billing pay: all checks passed'
