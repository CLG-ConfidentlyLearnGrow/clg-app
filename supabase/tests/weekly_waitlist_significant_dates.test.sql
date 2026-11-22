-- Summary: tests three changes from Carla's notes on Emma's Job Proposal
-- (22 Nov 2026): weekly waitlist check-ins, admins told when a family adds
-- a significant date, and "My pay" renamed "My Pay" in training and
-- handbook text. Reuses earlier tests' people: owner (...a0), parent P1
-- (...01, Cara One's parent), tutor T1 (...11, teaches Cara), parent P3
-- (...03, Sam Three's parent). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the three database changes again (checks each can run twice).
\ir ../migrations/20261124710100_my_pay_name.sql
\ir ../migrations/20261124710200_waitlist_weekly_check_ins.sql
\ir ../migrations/20261124710300_significant_dates_tell_admins.sql

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset

-- ---------------------------------------------------------------------------
-- Weekly waitlist check-ins
-- ---------------------------------------------------------------------------
-- Puts Sam on the waitlist 10 days ago with no check-in yet, and keeps the place's id as wait.
insert into public.waitlist (student_id, subject, minutes, online, created_at) -- the place:
values (:'sam', 'Check-in Test Subject', 60, true, now() - interval '10 days') -- Sam, online, joined 10 days ago
returning id as wait \gset

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_waitlist() where id = :'wait' and check_in_due), 1::bigint, 'a check-in is due after 7 days with none'); -- Checks: due (10 days, no check-in).
select tests.eq((select n::bigint from public.to_do_counts() where area = 'sessions' and section = 'waitlist'), (select count(*) from public.waitlist where closed_at is null and private.waitlist_check_in_due(created_at, checked_in_at)), 'the Waitlist tab counts the check-ins due'); -- Checks: the to-do number matches.
select public.waitlist_checked_in(:'wait'); -- The owner records a check-in.
select tests.eq((select count(*) from public.list_waitlist() where id = :'wait' and not check_in_due and checked_in_at is not null), 1::bigint, 'after a check-in, none is due for 7 days'); -- Checks: not due now, with the date saved.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000003', 'aal2'); -- Signs in as parent P3 (Sam's parent).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with(format($$select public.waitlist_checked_in(%L)$$, :'wait'), 'Only CLG admins', 'a parent cannot record a check-in'); -- Checks this is refused: a parent recording a check-in.
reset role; -- Goes back to the all-powerful test user (access rules off).

update public.waitlist set checked_in_at = now() - interval '8 days' where id = :'wait'; -- The last check-in is now 8 days ago.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_waitlist() where id = :'wait' and check_in_due), 1::bigint, 'a check-in is due again 7 days after the last one'); -- Checks: due again.
reset role; -- Goes back to the all-powerful test user (access rules off).
update public.waitlist set closed_at = now(), closed_reason = 'other' where id = :'wait'; -- Closes the place.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with(format($$select public.waitlist_checked_in(%L)$$, :'wait'), 'no longer open', 'a closed place cannot be checked in'); -- Checks this is refused: a closed place.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Admins told when a family adds a significant date
-- ---------------------------------------------------------------------------
-- Keeps how many of these notices the owner has so far as before.
select count(*) as before from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'New significant date from a family' \gset

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as parent P1 (Cara's parent).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.roadmap_targets (student_id, kind, subject, title, due_on) -- P1 adds a test to Cara's roadmap:
values (:'cara', 'assessment', 'Maths', 'Fractions test', current_date + 14); -- a maths test in two weeks
insert into public.roadmap_targets (student_id, kind, subject, title) -- P1 adds a goal (not a significant date):
values (:'cara', 'goal', 'Maths', 'Know my times tables'); -- a goal with no date
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'New significant date from a family'), :before + 1, 'admins are told once when a family adds a significant date (not for a goal)'); -- Checks: one new notice.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'New significant date from a family' and body like '%Fractions test%'), 1::bigint, 'the notice names the significant date'); -- Checks: the notice says what it is.

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1 (Cara's tutor).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.roadmap_targets (student_id, kind, subject, title, due_on) -- T1 adds an assignment to Cara's roadmap:
values (:'cara', 'assessment', 'Maths', 'Tutor added assignment', current_date + 21); -- due in three weeks
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'New significant date from a family'), :before + 1, 'no notice when the tutor adds a significant date'); -- Checks: still just the one.

-- ---------------------------------------------------------------------------
-- "My Pay" in training and handbook text
-- ---------------------------------------------------------------------------
select tests.eq((select count(*) from public.training_lessons where body like '%My pay%') + (select count(*) from public.handbook_pages where body like '%My pay%') + (select count(*) from public.training_questions where array_to_string(options, '|') like '%My pay%'), 0::bigint, 'no training or handbook text still says My pay'); -- Checks: the old name is gone.

-- Signs out and undoes everything this file did.
select tests.claims(null); -- Signs out, so no one is signed in.
rollback; -- Throws away every change made in this file.

-- Prints that every check in this file passed.
\echo '  weekly waitlist check-ins, significant dates and My Pay: all checks passed'
