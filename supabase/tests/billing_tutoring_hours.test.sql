-- Tutoring work hours and guaranteed hours top-ups. People from
-- access_rules.test.sql: owner (...a0), operations admin (...b0), tutor T1
-- (...11). Rolled back at the end.

\set QUIET on
begin;
\ir ../migrations/20261105230100_billing_tutoring_hours.sql

insert into public.billing_staff_pay (account_id, employment, school_rate_cents, admin_rate_cents, guaranteed_weekly_minutes) values
  ('00000000-0000-0000-0000-000000000011', 'part_time', 4000, null, 600),
  ('00000000-0000-0000-0000-0000000000b0', 'casual', null, 3400, null)
on conflict (account_id) do update set employment = excluded.employment, school_rate_cents = excluded.school_rate_cents,
  admin_rate_cents = excluded.admin_rate_cents, guaranteed_weekly_minutes = excluded.guaranteed_weekly_minutes;
select private.billing_today() - 1 as yday \gset

-- Who can log which kind of hours
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Office filing', 'admin')$$, :'yday'), 'tutor (not admin) logs office admin');
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, '  ', 'tutoring')$$, :'yday'), 'tutoring work without a description');
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Something', 'other')$$, :'yday'), 'unknown kind of hours');
select public.billing_log_my_hours(:'yday', 60, 'Made fraction worksheets', 'tutoring') as t1 \gset
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Worksheets', 'tutoring')$$, :'yday'), 'admin (not tutor) logs tutoring work');
select public.billing_log_my_hours(:'yday', 30, 'Answered enquiries', 'admin') as a1 \gset
select tests.fails(format($$select public.billing_check_guaranteed_hours(%L)$$, :'yday'), 'operations checks guaranteed hours');
reset role;

-- Approved tutoring work is paid at the tutor's school rate.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.billing_review_hours(:'t1', true);
select public.billing_review_hours(:'a1', true);
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.billing_pay_lines l join public.billing_hour_logs h on h.pay_line_id = l.id
  where h.id = :'t1' and l.kind = 'tutoring_work' and l.work_kind = 'school' and l.amount_cents = 4000), 1, 'tutoring work at the school rate');
select tests.eq((select count(*) from public.billing_pay_lines l join public.billing_hour_logs h on h.pay_line_id = l.id
  where h.id = :'a1' and l.kind = 'admin' and l.work_kind = 'admin' and l.amount_cents = 1700), 1, 'office admin at the admin rate');

-- Guaranteed hours: a quiet pay period well in the past.
select period_start as ps, period_end as pe, (period_end - period_start + 1) as len
from public.billing_pay_period(private.billing_today() - 40) \gset
insert into public.billing_pay_lines (account_id, staff_name, work_date, kind, work_kind, minutes, rate_cents, amount_cents)
values ('00000000-0000-0000-0000-000000000011', 'T1', :'ps', 'session', 'school', 120, 4000, 8000);
select tests.eq((select count(*) from public.billing_hour_logs where source = 'guaranteed'), 0, 'no top-ups yet');
select tests.eq(public.billing_check_guaranteed_hours(:'ps'), 1, 'one top-up for the part-time tutor');
select tests.eq((select minutes from public.billing_hour_logs where source = 'guaranteed' and period_start = :'ps'),
  round(600 * :len / 7.0)::int - 120, 'top-up covers the hours short');
select tests.eq((select count(*) from public.billing_hour_logs where source = 'guaranteed' and work_type = 'tutoring' and status = 'submitted' and not logged_late), 1, 'waits for approval, at the tutoring rate');
select tests.eq(public.billing_check_guaranteed_hours(:'ps'), 0, 'not added twice');
select tests.eq(public.billing_check_guaranteed_hours(private.billing_today()), 0, 'nothing for a pay period still running');
select id as g1 from public.billing_hour_logs where source = 'guaranteed' \gset

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.fails(format($$select public.billing_withdraw_my_hours(%L)$$, :'g1'), 'tutor removes a top-up');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.billing_review_hours(:'g1', true);
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.billing_pay_lines where kind = 'guaranteed' and account_id = '00000000-0000-0000-0000-000000000011'), 1, 'approved top-up becomes a pay line');
-- Once paid, a later check sees the hours as covered.
delete from public.billing_hour_logs where id = :'g1';
select tests.eq(public.billing_check_guaranteed_hours(:'ps'), 0, 'top-up already paid counts');

rollback;
\echo '  billing tutoring hours: all checks passed'
