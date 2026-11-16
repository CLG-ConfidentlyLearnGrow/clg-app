-- Summary: tests what families pay and tutors get when a session is cancelled and made up (Carla, 16 Nov 2026).
-- Runs after billing_pay.test.sql (which puts back older billing files), so
-- it applies the new rules again first. Reuses Cara One (from
-- access_rules.test.sql), tutor T1 (...11) and the owner admin (...a0).
-- Checks: family credit with and without a make-up, waiting while times are
-- open, and tutor late-cancel pay only under 2 hr notice.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the database change 20261118100300_makeup_cancel_pay_rules.sql again, as billing_pay.test.sql put back older billing rules.
\ir ../migrations/20261118100300_makeup_cancel_pay_rules.sql

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset

-- A cancelled session for these tests, written straight in, with how much notice was given.
create function tests.cancelled_session( -- A test helper that adds a cancelled session and gives back its id. It takes:
  p_student uuid, p_day date, p_start time, p_notice interval, p_role text -- the student, day, start time, notice given, and who cancelled.
) returns uuid language sql as $$ -- (gives back the new session's id)
  insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at, -- Adds the session:
                               status, cancelled_at, cancelled_by_role) -- (cancelled)
  select p_student, '00000000-0000-0000-0000-000000000011', s.family_id, 'General Maths', 'school', 'online', -- for this student with tutor T1, online,
         (p_day + p_start) at time zone 'Australia/Adelaide', (p_day + p_start + interval '1 hour') at time zone 'Australia/Adelaide', -- for 1 hr at the given time,
         'cancelled', ((p_day + p_start) at time zone 'Australia/Adelaide') - p_notice, p_role -- cancelled with that much notice, by that side
  from public.students s where s.id = p_student -- (using the student's family)
  returning id -- and hands back its id.
$$; -- (end of the helper)

-- A make-up offer for a cancelled session, in the given stage, written straight in.
create function tests.makeup_offer(p_session uuid, p_status text) returns void language sql as $$ -- A test helper that adds an offer (takes the session and its stage).
  insert into public.session_makeup_offers (session_id, student_id, tutor_id, offered_by_role, answer_by, option_1, option_2, status, picked_at) -- Adds the offer:
  select x.id, x.student_id, x.tutor_id, 'family', 'tutor', x.starts_at + interval '1 day', x.starts_at + interval '2 days', p_status, -- offered by the family, two times, in that stage,
         case when p_status in ('picked', 'confirming') then x.starts_at + interval '1 day' end -- with the first time picked where it has been
  from public.sessions x where x.id = p_session -- (for that session)
$$; -- (end of the helper)

-- ---------------------------------------------------------------------------
-- Family credit (sessions in the week of Monday 21 September 2026)
-- ---------------------------------------------------------------------------
-- Family cancels 1 hr before and a make-up is booked; keeps it as late_made_up.
select tests.cancelled_session(:'cara', '2026-09-21', '16:00', interval '1 hour', 'family') as late_made_up \gset
-- Family cancels 10 hr before and a make-up is booked; keeps it as early_made_up.
select tests.cancelled_session(:'cara', '2026-09-22', '16:00', interval '10 hours', 'family') as early_made_up \gset
-- Family cancels 10 hr before with no make-up; keeps it as early_none.
select tests.cancelled_session(:'cara', '2026-09-23', '16:00', interval '10 hours', 'family') as early_none \gset
-- Family cancels 1 hr before with no make-up; keeps it as late_none.
select tests.cancelled_session(:'cara', '2026-09-24', '16:00', interval '1 hour', 'family') as late_none \gset
-- Family cancels 3 days before, times still waiting for an answer; keeps it as waiting.
select tests.cancelled_session(:'cara', '2026-09-25', '16:00', interval '3 days', 'family') as waiting \gset
-- Tutor cancels 1 hr before and a make-up is booked; keeps it as tutor_made_up.
select tests.cancelled_session(:'cara', '2026-09-26', '10:00', interval '1 hour', 'tutor') as tutor_made_up \gset
select tests.makeup_offer(:'late_made_up', 'picked'); -- A make-up was booked for the late cancel.
select tests.makeup_offer(:'early_made_up', 'picked'); -- A make-up was booked for the earlier cancel.
select tests.makeup_offer(:'early_none', 'declined'); -- Neither time worked for this one.
select tests.makeup_offer(:'waiting', 'waiting'); -- These times haven't been answered yet.
select tests.makeup_offer(:'tutor_made_up', 'picked'); -- A make-up was booked after the tutor cancelled.

select tests.eq(private.billing_session_credit_percent(:'late_made_up'), 50, 'under 2 hr, made up: family pays half'); -- Checks: under 2 hr notice with a make-up gives 50% credit.
select tests.eq(private.billing_session_credit_percent(:'early_made_up'), 100, '2 hr or more, made up: nothing more to pay'); -- Checks: 2 hr or more with a make-up gives full credit.
select tests.eq(private.billing_session_credit_percent(:'early_none'), 50, 'no make-up: usual 24 to 2 hr rule'); -- Checks: without a make-up the usual rules apply (50%).
select tests.eq(private.billing_session_credit_percent(:'late_none'), 0, 'no make-up, under 2 hr: no credit'); -- Checks: without a make-up, under 2 hr gives no credit.
select tests.eq((private.billing_session_credit_percent(:'waiting') is null)::int, 1, 'credit waits while times are open'); -- Checks: no credit is worked out while times wait for an answer.
select tests.eq(private.billing_session_credit_percent(:'tutor_made_up'), 100, 'tutor cancels: full credit'); -- Checks: a tutor's cancel is still a full credit.
select tests.eq((strpos(pg_get_functiondef('public.billing_credit_cancellations()'::regprocedure), -- Checks the daily credit run uses the new rule:
  'private.billing_session_credit_percent(se.id) is not null') > 0)::int, 1, 'daily credit run uses the new rule'); -- (and skips sessions still waiting).

-- ---------------------------------------------------------------------------
-- Tutor late-cancel pay: only under 2 hr notice
-- ---------------------------------------------------------------------------
insert into public.billing_staff_pay (account_id, employment, school_rate_cents) values ('00000000-0000-0000-0000-000000000011', 'casual', 3400); -- Gives tutor T1 a casual school rate.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner admin with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.billing_build_pay('2026-09-21', '2026-09-27'); -- Works out pay for that week.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select coalesce(sum(minutes), 0) from public.billing_pay_lines where session_id = :'late_made_up' and kind = 'late_cancel'), 30, 'under 2 hr: tutor paid half'); -- Checks: under 2 hr notice pays the tutor 50% (30 min).
select tests.eq((select coalesce(sum(minutes), 0) from public.billing_pay_lines where session_id = :'late_none' and kind = 'late_cancel'), 30, 'under 2 hr, no make-up: tutor paid half'); -- Checks: the same without a make-up.
select tests.eq((select count(*) from public.billing_pay_lines where session_id = :'early_made_up'), 0, '10 hr notice: no tutor pay'); -- Checks: 10 hr notice no longer pays the tutor.
select tests.eq((select count(*) from public.billing_pay_lines where session_id = :'early_none'), 0, '10 hr notice, no make-up: no tutor pay'); -- Checks: the same without a make-up.
select tests.eq((select count(*) from public.billing_pay_lines where session_id = :'tutor_made_up'), 0, 'tutor cancels: no pay'); -- Checks: a tutor's own cancel is unpaid, as before.

-- Clean up for later tests.
delete from public.billing_pay_lines; -- Clears the pay lines.
delete from public.billing_staff_pay; -- Clears the pay rates.
delete from public.sessions where id in (:'late_made_up', :'early_made_up', :'early_none', :'late_none', :'waiting', :'tutor_made_up'); -- Removes the test sessions (their offers go with them).
drop function tests.cancelled_session(uuid, date, time, interval, text); -- Removes the session helper.
drop function tests.makeup_offer(uuid, text); -- Removes the offer helper.

-- Prints that every check in this file passed.
\echo '  make-up credit and tutor late-cancel pay: all checks passed'
