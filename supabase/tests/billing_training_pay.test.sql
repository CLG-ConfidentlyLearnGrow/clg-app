-- Training pay: each compulsory training completion becomes a "Training"
-- hours entry waiting for approval, at the rate of the job the training is
-- for, and it counts towards agreed hours (so it fills the top-up first).
-- Reuses access_rules.test.sql people: owner (...a0), operations admin
-- (...b0), tutor T1 (...11). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the training pay database change again (checks it can run twice).
\ir ../migrations/20261116300200_billing_training_pay.sql

-- Starts with no training (in case any was added).
delete from public.training_completions; -- removes completions
delete from public.training_modules; -- removes modules

-- Pay details: T1 is part-time with 2 hr a week agreed and a $40/hr school rate; the operations admin has a $35/hr admin rate.
insert into public.billing_staff_pay (account_id, employment, school_rate_cents, guaranteed_weekly_minutes) values ('00000000-0000-0000-0000-000000000011', 'part_time', 4000, 120) -- T1's details
on conflict (account_id) do update set employment = 'part_time', school_rate_cents = 4000, guaranteed_weekly_minutes = 120; -- (or update them)
insert into public.billing_staff_pay (account_id, employment, admin_rate_cents) values ('00000000-0000-0000-0000-0000000000b0', 'casual', 3500) -- the admin's details
on conflict (account_id) do update set admin_rate_cents = 3500; -- (or update them)

-- Three modules: a compulsory tutor module, a compulsory one for everyone, and an optional one.
insert into public.training_modules (id, title, audience, required, minutes, status) values -- adds them:
  ('20000000-0000-0000-0000-000000000001', 'Running a great session', 'tutor', true, 60, 'published'), -- compulsory, tutors, 60 min
  ('20000000-0000-0000-0000-000000000002', 'Privacy basics', 'everyone', true, 30, 'published'), -- compulsory, everyone, 30 min
  ('20000000-0000-0000-0000-000000000003', 'Extra reading', 'tutor', false, 20, 'published'); -- optional, 20 min

-- Keeps a past pay period's first and last day (the one containing 4 Aug 2026).
select period_start as p_start, period_end as p_end from public.billing_pay_period('2026-08-04') \gset

-- Completions on 4 Aug 2026 (written directly, as the test runner).
insert into public.training_completions (id, account_id, module_id, module_version, module_title, audience, minutes, paid, counts_toward_certified, completed_on, certificate_no) values -- adds them:
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000001', 1, 'Running a great session', 'tutor', 60, true, true, '2026-08-04', 'T-1'), -- T1, compulsory tutor module
  ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000003', 1, 'Extra reading', 'tutor', 20, false, true, '2026-08-04', 'T-2'), -- T1, optional module (not paid)
  ('30000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000000b0', '20000000-0000-0000-0000-000000000002', 1, 'Privacy basics', 'everyone', 30, true, false, '2026-08-04', 'T-3'); -- the admin, compulsory module for everyone

-- Only the owner, Finance or the daily run can add training hours.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails($$select public.billing_build_training_hours('2026-08-01', '2026-08-10')$$, 'tutor adds training hours'); -- checks this is refused
reset role; -- back to the test runner

-- The owner adds them: two paid completions, the optional one skipped.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.eq(public.billing_build_training_hours('2026-08-01', '2026-08-10'), 2, 'two training entries added'); -- checks the count
select tests.eq(public.billing_build_training_hours('2026-08-01', '2026-08-10'), 0, 'adding again does not double up'); -- checks it can be re-run
reset role; -- back to the test runner
select tests.eq((select count(*) from public.billing_hour_logs where training_completion_id = '30000000-0000-0000-0000-000000000002'), 0, 'optional module not paid automatically'); -- checks the optional one was skipped
select tests.eq((select count(*) from public.billing_hour_logs where training_completion_id = '30000000-0000-0000-0000-000000000001' and work_type = 'tutoring' and minutes = 60 and status = 'submitted'), 1, 'tutor training at the tutor rate, waiting for approval'); -- checks T1's entry
select tests.eq((select count(*) from public.billing_hour_logs where training_completion_id = '30000000-0000-0000-0000-000000000003' and work_type = 'admin'), 1, 'training for everyone, for admin staff who don''t tutor: admin rate'); -- checks the admin's entry

-- Training counts towards agreed hours: the top-up is the agreed time less the training.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select public.billing_check_guaranteed_hours('2026-08-04'); -- checks agreed hours for that pay period
reset role; -- back to the test runner
select tests.eq((select minutes from public.billing_hour_logs where account_id = '00000000-0000-0000-0000-000000000011' and source = 'guaranteed' and period_start = :'p_start'), -- checks T1's top-up minutes:
  round(120 * (:'p_end'::date - :'p_start'::date + 1) / 7.0)::int - 60 - coalesce((select sum(minutes) from public.billing_pay_lines where account_id = '00000000-0000-0000-0000-000000000011' and work_date between :'p_start' and :'p_end'), 0), -- agreed minutes less the 60 training minutes (and any other pay)
  'training fills the top-up first'); -- (the label)

-- Approving the training entry makes a "training" pay line at the school rate.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select public.billing_review_hours((select id from public.billing_hour_logs where training_completion_id = '30000000-0000-0000-0000-000000000001'), true); -- approves T1's training
reset role; -- back to the test runner
select tests.eq((select amount_cents from public.billing_pay_lines where account_id = '00000000-0000-0000-0000-000000000011' and kind = 'training'), 4000, 'one hour of training at $40/hr'); -- checks the pay line
select tests.claims(null); -- clears who is signed in

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  billing training pay: all checks passed'
