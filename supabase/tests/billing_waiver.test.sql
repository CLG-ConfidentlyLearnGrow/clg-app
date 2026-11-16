-- Summary: tests the once-a-year late-cancel waiver (Carla, 16 Nov 2026).
-- Runs after billing_pay.test.sql (which puts back older billing files), so
-- it applies the make-up credit rules and the waiver again first. Reuses
-- Cara One (from access_rules.test.sql), tutor T1 (...11) and the owner
-- admin (...a0).
-- Checks: who may waive, which sessions, once a year then proof, the full
-- credit (also when credit was already given), and who can see waivers.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs 20261118100300_makeup_cancel_pay_rules.sql again, as billing_pay.test.sql put back older billing rules.
\ir ../migrations/20261118100300_makeup_cancel_pay_rules.sql
-- Runs the waiver change being tested.
\ir ../migrations/20261118410100_late_cancel_waiver.sql

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset

-- A cancelled (or no-show) session for these tests, written straight in.
create function tests.waiver_session( -- A test helper that adds a session and gives back its id. It takes:
  p_student uuid, p_day date, p_notice interval, p_role text, p_status text default 'cancelled' -- the student, day, notice given, who cancelled, and its status.
) returns uuid language sql as $$ -- (gives back the new session's id)
  insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at, -- Adds the session:
                               status, cancelled_at, cancelled_by_role) -- (with how it ended)
  select p_student, '00000000-0000-0000-0000-000000000011', s.family_id, 'General Maths', 'school', 'online', -- for this student with tutor T1, online,
         (p_day + time '16:00') at time zone 'Australia/Adelaide', (p_day + time '17:00') at time zone 'Australia/Adelaide', -- 4 to 5pm that day,
         p_status::public.session_status, -- cancelled or no-show,
         case when p_status = 'cancelled' then ((p_day + time '16:00') at time zone 'Australia/Adelaide') - p_notice end, -- cancelled with that much notice,
         case when p_status = 'cancelled' then p_role end -- by that side
  from public.students s where s.id = p_student -- (using the student's family)
  returning id -- and hands back its id.
$$; -- (end of the helper)

-- Sessions in October 2026 (one learner, one year) and January 2027 (the next year).
select tests.waiver_session(:'cara', '2026-10-05', interval '1 hour', 'family') as late_1 \gset
select tests.waiver_session(:'cara', '2026-10-06', interval '1 hour', 'family') as late_2 \gset
select tests.waiver_session(:'cara', '2026-10-07', interval '1 hour', 'family') as late_3 \gset
select tests.waiver_session(:'cara', '2026-10-08', null, null, 'no_show') as no_show \gset
select tests.waiver_session(:'cara', '2026-10-09', interval '1 hour', 'tutor') as tutor_cancel \gset
select tests.waiver_session(:'cara', '2026-10-12', interval '3 days', 'family') as early \gset
select tests.waiver_session(:'cara', '2027-01-11', interval '1 hour', 'family') as next_year \gset

-- ---------------------------------------------------------------------------
-- Who may waive
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_waive_late_cancel(%L, 'Sick on the day')$$, :'late_1'), 'tutor cannot waive'); -- Checks this is refused: a tutor waiving.
select tests.eq((select count(*) from public.billing_waiver_list()), 0, 'tutor gets no waiver list'); -- Checks: a tutor sees no list.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal1'); -- Signs in as the owner without two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_waive_late_cancel(%L, 'Sick on the day')$$, :'late_1'), 'owner needs two-step sign-in'); -- Checks this is refused without two-step sign-in.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Which sessions, once a year, then proof
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_waive_late_cancel(%L, 'Sick on the day')$$, :'tutor_cancel'), 'tutor cancel cannot be waived'); -- Checks this is refused: the tutor cancelled (already full credit).
select tests.fails(format($$select public.billing_waive_late_cancel(%L, 'Sick on the day')$$, :'early'), 'full credit: nothing to waive'); -- Checks this is refused: 3 days' notice already gets full credit.
select tests.fails(format($$select public.billing_waive_late_cancel(%L, 'ill')$$, :'late_1'), 'reason needed'); -- Checks this is refused: the reason is too short.
reset role; -- Steps out of the signed-in role to read the private credit rule.
select tests.eq(private.billing_session_credit_percent(:'late_1'), 0, 'before: no credit under 2 hr'); -- Checks: before the waiver, under 2 hr gets no credit.
set role authenticated; -- Back to acting as the signed-in owner.
select public.billing_waive_late_cancel(:'late_1', 'Suddenly unwell'); -- The yearly waiver for Cara.
reset role; -- Steps out of the signed-in role to read the private credit rule.
select tests.eq(private.billing_session_credit_percent(:'late_1'), 100, 'waived: full credit'); -- Checks: the waived session gets full credit.
set role authenticated; -- Back to acting as the signed-in owner.
select tests.fails(format($$select public.billing_waive_late_cancel(%L, 'Suddenly unwell')$$, :'late_1'), 'never waived twice'); -- Checks this is refused: the same session again.
select tests.fails(format($$select public.billing_waive_late_cancel(%L, 'Family emergency')$$, :'late_2'), 'second waiver needs proof'); -- Checks this is refused: a second waiver in 2026 without proof.
select public.billing_waive_late_cancel(:'late_2', 'Family emergency, explained to Carla', true); -- With proof seen, it goes through.
select tests.eq((select count(*) from public.billing_cancel_waivers where session_id = :'late_2' and proof_seen), 1, 'proof seen is recorded'); -- Checks: the waiver records that proof was seen.
select public.billing_waive_late_cancel(:'next_year', 'Sick on the day'); -- January 2027: a new year, so no proof needed.
select tests.eq((select waiver_year from public.billing_cancel_waivers where session_id = :'next_year'), 2027, 'new year counts separately'); -- Checks: it counts against 2027.
select tests.eq((select count(*) from public.billing_cancel_waivers), 3, 'owner sees waivers'); -- Checks: the owner can read the waivers.
select tests.eq((select used_this_year from public.billing_waiver_list() where session_id = :'late_3'), 2, 'list shows waivers used'); -- Checks: the list shows Cara has had 2 waivers in 2026.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1 again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_cancel_waivers), 0, 'tutor sees no waivers'); -- Checks: the tutor can't see waivers or their reasons.
select tests.fails($$insert into public.billing_cancel_waivers (session_id, student_id, waiver_year, reason) select id, student_id, 2026, 'Made up' from public.sessions limit 1$$, 'nobody writes waivers directly'); -- Checks this is refused: writing the table directly.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Credit already given: the rest is added
-- ---------------------------------------------------------------------------
-- An invoice for the no-show session, written straight in; keeps its id as inv.
insert into public.billing_invoices (family_id, family_name, plan, method, period_start, period_end, first_session_on, send_on, due_on, charge_on, status) -- Adds an invoice:
select s.family_id, 'One family', 'weekly', 'card', '2026-10-05', '2026-10-11', '2026-10-08', '2026-09-24', '2026-10-04', '2026-10-04', 'paid' -- a paid weekly invoice for that week,
from public.students s where s.id = :'cara' -- for Cara's family,
returning id as inv \gset
insert into public.billing_invoice_lines (invoice_id, session_id, student_id, line_date, description, minutes, billed_minutes, hourly_cents, amount_cents) -- Adds the session's line:
values (:'inv', :'no_show', :'cara', '2026-10-08', 'Thu 8 Oct 4:00pm Cara General Maths', 60, 60, 9500, 9500); -- $95 for the hour.
select tests.claims(null); -- Signs out, as the background job does.
select public.billing_credit_cancellations(); -- The daily credit run: a no-show gets no credit (0).
select tests.eq((select sum(amount_cents) from public.billing_credits where session_id = :'no_show'), 0, 'no-show: nothing credited yet'); -- Checks: nothing is credited before the waiver.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.billing_waive_late_cancel(:'no_show', 'Learner unwell, explained to Lauren', true); -- Waives the no-show (third waiver in 2026, so proof seen).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select sum(amount_cents) from public.billing_credits where session_id = :'no_show'), 9500, 'waived no-show: full credit added'); -- Checks: the whole $95 is now credited.
select tests.eq((select count(*) from public.billing_credits where session_id = :'no_show' and kind = 'goodwill'), 1, 'added as one goodwill credit'); -- Checks: the rest came as one goodwill credit.

-- Tidies up so later tests start clean.
delete from public.billing_credits where session_id in (:'late_1', :'late_2', :'late_3', :'no_show', :'tutor_cancel', :'early', :'next_year'); -- removes the test credits,
delete from public.billing_invoices where id = :'inv'; -- the test invoice (and its line),
delete from public.sessions where id in (:'late_1', :'late_2', :'late_3', :'no_show', :'tutor_cancel', :'early', :'next_year'); -- and the test sessions (their waivers go with them).
drop function tests.waiver_session(uuid, date, interval, text, text); -- Removes the helper.

-- Prints that every check in this file passed.
\echo '  late-cancel waiver: all checks passed'
