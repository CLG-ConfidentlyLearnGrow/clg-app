-- Summary time pay: each completed session earns paid time to write the
-- session summary. Reuses access_rules.test.sql people: owner (...a0),
-- operations admin (...b0), tutor T1 (...11). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the summary pay database change (also checks it can run twice).
\ir ../migrations/20261112230100_billing_summary_pay.sql

-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset
-- Gives T1 a school tutoring rate of $40/hr.
insert into public.billing_staff_pay (account_id, employment, school_rate_cents) values ('00000000-0000-0000-0000-000000000011', 'casual', 4000) -- T1's rate
on conflict (account_id) do update set school_rate_cents = 4000; -- or update it if T1 already has pay details
-- Keeps the summary minutes per session as mins (15 until scheduling sets it).
select private.billing_summary_minutes() as mins \gset

-- A test helper that adds a past session for T1 and gives back its id.
create function tests.summary_session(p_day date, p_status text) returns uuid language sql as $$ -- takes the day and the session's status
  insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at, status, worked_from, worked_to) -- adds the session
  select s.id, '00000000-0000-0000-0000-000000000011', s.family_id, 'General Maths', 'school', 'online', -- Cara with T1, school maths, online
         (p_day + time '16:00') at time zone 'Australia/Adelaide', (p_day + time '17:00') at time zone 'Australia/Adelaide', -- 4pm to 5pm Adelaide time
         p_status::public.session_status, -- the status given
         case when p_status = 'completed' then (p_day + time '16:00') at time zone 'Australia/Adelaide' end, -- signed on at the start if it went ahead
         case when p_status = 'completed' then (p_day + time '17:00') at time zone 'Australia/Adelaide' end -- signed off at the end if it went ahead
  from public.students s where s.full_name = 'Cara One' -- Cara's student record
  returning id -- hands back the new session's id
$$;

-- One completed session and one cancelled session in the same week.
select tests.summary_session('2026-08-03', 'completed') as done \gset
select tests.summary_session('2026-08-04', 'scheduled') as cancelled \gset
update public.sessions set status = 'cancelled', cancelled_by_role = 'family', cancelled_at = starts_at - interval '2 hours' where id = :'cancelled'; -- the family cancelled it 2 hours before

-- Only the owner, Finance or the daily run can work out summary pay.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails($$select public.billing_build_summary_pay('2026-08-03', '2026-08-09')$$, 'tutor works out summary pay'); -- checks this is refused
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.fails($$select public.billing_build_summary_pay('2026-08-03', '2026-08-09')$$, 'operations works out summary pay'); -- checks this is refused
reset role; -- back to the test runner

-- The owner works it out.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.eq(public.billing_build_summary_pay('2026-08-03', '2026-08-09'), 1, 'one summary line for the one completed session'); -- checks the count
select tests.eq(public.billing_build_summary_pay('2026-08-03', '2026-08-09'), 1, 'working it out again does not double up'); -- checks it can be re-run
reset role; -- back to the test runner
select tests.claims(null); -- clears who is signed in

-- The line is paid at the tutor's rate for the summary minutes.
select tests.eq((select minutes from public.billing_pay_lines where session_id = :'done' and kind = 'summary'), :mins, 'summary minutes from the setting'); -- checks the minutes
select tests.eq((select amount_cents from public.billing_pay_lines where session_id = :'done' and kind = 'summary'), round(4000 * :mins / 60.0)::int, 'paid at the school rate'); -- checks the pay
select tests.eq((select count(*) from public.billing_pay_lines where session_id = :'cancelled' and kind = 'summary'), 0, 'no summary time for a cancelled session'); -- checks the cancelled one

-- A line already sent to Xero is kept and not added twice.
update public.billing_pay_lines set status = 'sent' where session_id = :'done' and kind = 'summary'; -- pretend it went to Xero
select tests.eq(public.billing_build_summary_pay('2026-08-03', '2026-08-09'), 0, 'nothing new once sent'); -- checks nothing is waiting
select tests.eq((select count(*) from public.billing_pay_lines where session_id = :'done' and kind = 'summary'), 1, 'sent line kept'); -- checks the sent line is still there

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  billing summary pay: all checks passed'
