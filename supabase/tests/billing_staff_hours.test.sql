-- Staff log their own admin hours; an admin approves or declines them.
-- Reuses access_rules.test.sql people: owner (...a0), staff admin (...b0),
-- tutor T1 (...11), parent P1 (...01). Rolled back at the end.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
begin; -- Starts a transaction, so everything below can be undone at the end.
-- Runs the database change 20261029230100_billing_staff_hours.sql first, as this test needs it.
\ir ../migrations/20261029230100_billing_staff_hours.sql
-- Re-running an older billing file resets its rules, so apply admin levels again.
-- Runs the database change 20261029900200_admin_levels.sql first, as this test needs it.
\ir ../migrations/20261029900200_admin_levels.sql
-- Then the newer version of logging (tutoring work or office admin).
-- Runs the database change 20261105230100_billing_tutoring_hours.sql first, as this test needs it.
\ir ../migrations/20261105230100_billing_tutoring_hours.sql

insert into public.billing_staff_pay (account_id, employment, school_rate_cents, admin_rate_cents) values -- Sets pay rates for two staff:
  ('00000000-0000-0000-0000-000000000011', 'casual', 3400, 3400), -- tutor T1, casual, with both rates,
  ('00000000-0000-0000-0000-0000000000b0', 'casual', null, 3400) -- and the staff admin, casual, with an admin rate only.
on conflict (account_id) do update set school_rate_cents = excluded.school_rate_cents, admin_rate_cents = excluded.admin_rate_cents; -- (if they already have rates, replaces them)
-- Keeps yesterday's date as yday.
select private.billing_today() - 1 as yday \gset

-- Logging
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- Signs in as test account ...11.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Progress notes', 'tutoring')$$, :'yday'), 'logging without two-step login'); -- Checks this is refused: logging without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Logs 90 minutes of tutoring work and keeps its id as log1.
select public.billing_log_my_hours(:'yday', 90, 'Progress summaries', 'tutoring') as log1 \gset
-- Logs 30 minutes and keeps its id as log2.
select public.billing_log_my_hours(:'yday', 30, 'Parent emails', 'tutoring') as log2 \gset
-- Logs 45 minutes and keeps its id as log3.
select public.billing_log_my_hours(:'yday', 45, 'Lesson planning', 'tutoring') as log3 \gset
select tests.fails($$select public.billing_log_my_hours(private.billing_today() + 1, 60, 'Future work', 'tutoring')$$, 'hours in the future'); -- Checks this is refused: hours in the future.
select tests.fails(format($$select public.billing_log_my_hours(%L, 5, 'Too short', 'tutoring')$$, :'yday'), 'under 15 minutes'); -- Checks this is refused: under 15 minutes.
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, '', 'tutoring')$$, :'yday'), 'no note'); -- Checks this is refused: no note.
select tests.fails($$insert into public.billing_hour_logs (account_id, work_date, minutes, note) values (auth.uid(), current_date, 60, 'By hand')$$, 'logging by hand'); -- Checks this is refused: logging by hand.
select tests.fails(format($$select public.billing_review_hours(%L, true)$$, :'log1'), 'tutor approves own hours'); -- Checks this is refused: tutor approves own hours.
select tests.eq((select count(*) from public.billing_hour_logs), 3, 'tutor sees own entries'); -- Checks: tutor sees own entries.
select public.billing_withdraw_my_hours(:'log3'); -- Withdraws the third log.
select tests.eq((select count(*) from public.billing_hour_logs), 2, 'tutor takes back an entry'); -- Checks: tutor takes back an entry.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_log_my_hours(%L, 60, 'Not staff', 'admin')$$, :'yday'), 'parent logs hours'); -- Checks this is refused: parent logs hours.
select tests.eq((select count(*) from public.billing_hour_logs), 0, 'parent sees no hours'); -- Checks: parent sees no hours.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Approving
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Logs an hour of office admin and keeps its id as log4.
select public.billing_log_my_hours(:'yday', 60, 'Enrolments', 'admin') as log4 \gset
select tests.fails(format($$select public.billing_review_hours(%L, true)$$, :'log4'), 'staff admin approves own hours'); -- Checks this is refused: staff admin approves own hours.
-- Operations sees hours but only the owner or Finance approves them.
select tests.fails(format($$select public.billing_review_hours(%L, true)$$, :'log1'), 'operations approves hours'); -- Checks this is refused: operations approves hours.
select tests.eq((select count(*) from public.billing_hour_logs where status = 'submitted'), 3, 'operations sees what is waiting'); -- Checks: operations sees what is waiting.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.billing_review_hours(:'log1', true); -- Approves the first log.
select tests.fails(format($$select public.billing_review_hours(%L, false, '')$$, :'log2'), 'declined without a reason'); -- Checks this is refused: declined without a reason.
select public.billing_review_hours(:'log2', false, 'Included in session time'); -- Declines the second log, with a reason.
select tests.fails(format($$select public.billing_review_hours(%L, true)$$, :'log2'), 'reviewed twice'); -- Checks this is refused: reviewed twice.
select public.billing_review_hours(:'log4', true); -- Approves the admin log.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

select tests.eq((select count(*) from public.billing_pay_lines l join public.billing_hour_logs h on h.pay_line_id = l.id -- Checks approved hours become pay lines:
  where l.kind in ('admin', 'tutoring_work') and l.status = 'pending'), 2, 'approved hours become pay lines'); -- (two pending lines, one per approved log).
select tests.eq((select amount_cents from public.billing_pay_lines l join public.billing_hour_logs h on h.pay_line_id = l.id where h.id = :'log1'), 5100, '1.5 hr at $34'); -- Checks: 1.5 hr at $34.
select tests.eq((select count(*) from public.billing_pay_lines where note = 'Parent emails'), 0, 'declined hours are not paid'); -- Checks: declined hours are not paid.

rollback; -- Undoes everything this file did, leaving the test database as it was.
-- Prints that every check in this file passed.
\echo '  billing staff hours: all checks passed'
