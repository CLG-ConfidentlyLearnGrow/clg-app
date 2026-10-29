-- Staff log their own admin hours; an admin approves or declines them.
-- Reuses access_rules.test.sql people: owner (...a0), staff admin (...b0),
-- tutor T1 (...11), parent P1 (...01). Rolled back at the end.

\set QUIET on
begin;
\ir ../migrations/20261029230100_billing_staff_hours.sql

insert into public.billing_staff_pay (account_id, employment, admin_rate_cents) values
  ('00000000-0000-0000-0000-000000000011', 'casual', 3400),
  ('00000000-0000-0000-0000-0000000000b0', 'casual', 3400)
on conflict (account_id) do update set admin_rate_cents = excluded.admin_rate_cents;
select private.billing_today() - 1 as yday \gset

-- Logging
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1');
set role authenticated;
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Progress notes')$$, :'yday'), 'logging without two-step login');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select public.billing_log_my_hours(:'yday', 90, 'Progress summaries') as log1 \gset
select public.billing_log_my_hours(:'yday', 30, 'Parent emails') as log2 \gset
select public.billing_log_my_hours(:'yday', 45, 'Lesson planning') as log3 \gset
select tests.fails($$select public.billing_log_my_hours(private.billing_today() + 1, 60, 'Future work')$$, 'hours in the future');
select tests.fails(format($$select public.billing_log_my_hours(%L, 5, 'Too short')$$, :'yday'), 'under 15 minutes');
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, '')$$, :'yday'), 'no note');
select tests.fails($$insert into public.billing_hour_logs (account_id, work_date, minutes, note) values (auth.uid(), current_date, 60, 'By hand')$$, 'logging by hand');
select tests.fails(format($$select public.billing_review_hours(%L, true)$$, :'log1'), 'tutor approves own hours');
select tests.eq((select count(*) from public.billing_hour_logs), 3, 'tutor sees own entries');
select public.billing_withdraw_my_hours(:'log3');
select tests.eq((select count(*) from public.billing_hour_logs), 2, 'tutor takes back an entry');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Not staff')$$, :'yday'), 'parent logs hours');
select tests.eq((select count(*) from public.billing_hour_logs), 0, 'parent sees no hours');
reset role;

-- Approving
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.billing_log_my_hours(:'yday', 60, 'Enrolments') as log4 \gset
select tests.fails(format($$select public.billing_review_hours(%L, true)$$, :'log4'), 'staff admin approves own hours');
select public.billing_review_hours(:'log1', true);
select tests.fails(format($$select public.billing_review_hours(%L, false, '')$$, :'log2'), 'declined without a reason');
select public.billing_review_hours(:'log2', false, 'Included in session time');
select tests.fails(format($$select public.billing_review_hours(%L, true)$$, :'log2'), 'reviewed twice');
select tests.eq((select count(*) from public.billing_hour_logs where status = 'submitted'), 1, 'admin sees what is waiting');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.billing_review_hours(:'log4', true);
reset role;
select tests.claims(null);

select tests.eq((select count(*) from public.billing_pay_lines l join public.billing_hour_logs h on h.pay_line_id = l.id
  where l.kind = 'admin' and l.status = 'pending'), 2, 'approved hours become admin pay lines');
select tests.eq((select amount_cents from public.billing_pay_lines l join public.billing_hour_logs h on h.pay_line_id = l.id where h.id = :'log1'), 5100, '1.5 hr at $34');
select tests.eq((select count(*) from public.billing_pay_lines where note = 'Parent emails'), 0, 'declined hours are not paid');

rollback;
\echo '  billing staff hours: all checks passed'
