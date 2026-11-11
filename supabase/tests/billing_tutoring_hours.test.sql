-- Tutoring work hours and guaranteed hours top-ups. People from
-- access_rules.test.sql: owner (...a0), operations admin (...b0), tutor T1
-- (...11). Rolled back at the end.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
begin; -- Starts a transaction, so everything below can be undone at the end.
-- Runs the database change 20261105230100_billing_tutoring_hours.sql first, as this test needs it.
\ir ../migrations/20261105230100_billing_tutoring_hours.sql

insert into public.billing_staff_pay (account_id, employment, school_rate_cents, admin_rate_cents, guaranteed_weekly_minutes) values -- Sets pay details for two staff:
  ('00000000-0000-0000-0000-000000000011', 'part_time', 4000, null, 600), -- tutor T1, part-time, $40/hr school rate, 10 hr a week guaranteed,
  ('00000000-0000-0000-0000-0000000000b0', 'casual', null, 3400, null) -- the staff admin, casual, $34/hr admin rate.
on conflict (account_id) do update set employment = excluded.employment, school_rate_cents = excluded.school_rate_cents, -- (if they already have details, replaces them)
  admin_rate_cents = excluded.admin_rate_cents, guaranteed_weekly_minutes = excluded.guaranteed_weekly_minutes; -- (all four values)
-- Keeps yesterday's date as yday.
select private.billing_today() - 1 as yday \gset

-- Who can log which kind of hours
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Office filing', 'admin')$$, :'yday'), 'tutor (not admin) logs office admin'); -- Checks this is refused: tutor (not admin) logs office admin.
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, '  ', 'tutoring')$$, :'yday'), 'tutoring work without a description'); -- Checks this is refused: tutoring work without a description.
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Something', 'other')$$, :'yday'), 'unknown kind of hours'); -- Checks this is refused: unknown kind of hours.
-- Logs an hour of tutoring work and keeps its id as t1.
select public.billing_log_my_hours(:'yday', 60, 'Made fraction worksheets', 'tutoring') as t1 \gset
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Worksheets', 'tutoring')$$, :'yday'), 'admin (not tutor) logs tutoring work'); -- Checks this is refused: admin (not tutor) logs tutoring work.
-- Logs half an hour of office admin and keeps its id as a1.
select public.billing_log_my_hours(:'yday', 30, 'Answered enquiries', 'admin') as a1 \gset
select tests.fails(format($$select public.billing_check_guaranteed_hours(%L)$$, :'yday'), 'operations checks guaranteed hours'); -- Checks this is refused: operations checks guaranteed hours.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Approved tutoring work is paid at the tutor's school rate.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.billing_review_hours(:'t1', true); -- Approves the tutoring work.
select public.billing_review_hours(:'a1', true); -- Approves the office admin.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.billing_pay_lines l join public.billing_hour_logs h on h.pay_line_id = l.id -- Checks tutoring work is paid at the school rate:
  where h.id = :'t1' and l.kind = 'tutoring_work' and l.work_kind = 'school' and l.amount_cents = 4000), 1, 'tutoring work at the school rate'); -- ($40 for the hour).
select tests.eq((select count(*) from public.billing_pay_lines l join public.billing_hour_logs h on h.pay_line_id = l.id -- Checks office admin is paid at the admin rate:
  where h.id = :'a1' and l.kind = 'admin' and l.work_kind = 'admin' and l.amount_cents = 1700), 1, 'office admin at the admin rate'); -- ($17 for half an hour).

-- Guaranteed hours: a quiet pay period well in the past.
select period_start as ps, period_end as pe, (period_end - period_start + 1) as len -- Keeps the start, end and length of an earlier pay period:
-- (the one from 40 days ago).
from public.billing_pay_period(private.billing_today() - 40) \gset
insert into public.billing_pay_lines (account_id, staff_name, work_date, kind, work_kind, minutes, rate_cents, amount_cents) -- Adds a 2-hr session pay line for tutor T1:
values ('00000000-0000-0000-0000-000000000011', 'T1', :'ps', 'session', 'school', 120, 4000, 8000); -- (at the start of that period).
select tests.eq((select count(*) from public.billing_hour_logs where source = 'guaranteed'), 0, 'no top-ups yet'); -- Checks: no top-ups yet.
select tests.eq(public.billing_check_guaranteed_hours(:'ps'), 1, 'one top-up for the part-time tutor'); -- Checks: one top-up for the part-time tutor.
select tests.eq((select minutes from public.billing_hour_logs where source = 'guaranteed' and period_start = :'ps'), -- Checks the top-up covers the hours short:
  round(600 * :len / 7.0)::int - 120, 'top-up covers the hours short'); -- (guaranteed hours for the period, less the 2 hr worked).
select tests.eq((select count(*) from public.billing_hour_logs where source = 'guaranteed' and work_type = 'tutoring' and status = 'submitted' and not logged_late), 1, 'waits for approval, at the tutoring rate'); -- Checks: waits for approval, at the tutoring rate.
select tests.eq(public.billing_check_guaranteed_hours(:'ps'), 0, 'not added twice'); -- Checks: not added twice.
select tests.eq(public.billing_check_guaranteed_hours(private.billing_today()), 0, 'nothing for a pay period still running'); -- Checks: nothing for a pay period still running.
-- Keeps the top-up's id as g1.
select id as g1 from public.billing_hour_logs where source = 'guaranteed' \gset

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_withdraw_my_hours(%L)$$, :'g1'), 'tutor removes a top-up'); -- Checks this is refused: tutor removes a top-up.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.billing_review_hours(:'g1', true); -- Approves the top-up.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.billing_pay_lines where kind = 'guaranteed' and account_id = '00000000-0000-0000-0000-000000000011'), 1, 'approved top-up becomes a pay line'); -- Checks: approved top-up becomes a pay line.
-- Once paid, a later check sees the hours as covered.
delete from public.billing_hour_logs where id = :'g1'; -- Removes the top-up.
select tests.eq(public.billing_check_guaranteed_hours(:'ps'), 0, 'top-up already paid counts'); -- Checks: top-up already paid counts.

rollback; -- Undoes everything this file did, leaving the test database as it was.
-- Prints that every check in this file passed.
\echo '  billing tutoring hours: all checks passed'
