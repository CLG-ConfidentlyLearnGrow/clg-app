-- Summary: tests staff reports of work outside CLG (Carla, 22 Nov 2026;
-- contract clause 6.7). Reuses tutors T1 (...11) and T3 (...13), parent P1
-- (...01), the owner (...a0) and the Operations admin (...b0). Everything is
-- undone at the end.
-- Checks: who can add reports, the rules, who can see them, changing and
-- ending them, the owner's notice, and marking them as seen.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the file again, to check it is safe to run more than once.
\ir ../migrations/20261124711300_outside_work_reports.sql

begin; -- Starts a change that is undone at the end, so nothing is left behind.

-- 1. Tutor T1 reports private tutoring.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.outside_work_save(null, 'tutoring', 'Private maths tutor', null, 'Two Year 9 students on Saturdays.', true, current_date + 7) as report \gset
select tests.eq((select count(*) from public.outside_work_reports where id = :'report'), 1, 'a tutor can report work outside CLG and see it'); -- Checks: saved and visible to them.
select tests.fails_with($$select public.outside_work_save(null, 'gardening', 'Something', null, null, true, current_date)$$, 'kind of role', 'an unknown kind is refused'); -- Checks: plain refusal.
select tests.fails_with($$select public.outside_work_save(null, 'admin', 'Office help', null, null, false, current_date, current_date - 1)$$, 'cannot be before', 'an end before the start is refused'); -- Checks: plain refusal.
select tests.fails($$insert into public.outside_work_reports (account_id, kind, role_title, paid, starts_on) values (auth.uid(), 'other', 'Direct', true, current_date)$$, 'reports cannot be written straight into the table'); -- Checks: only through the functions.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Work outside CLG reported'), 1, 'the owner is told'); -- Checks: one notice for the owner.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000b0' and title like 'Work outside CLG%'), 0, 'Operations admins are not told'); -- Checks: owner only.

-- 2. Who can see it.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.outside_work_reports), 0, 'another tutor cannot see it'); -- Checks: hidden.
select tests.fails_with(format($$select public.outside_work_end(%L, current_date + 30)$$, :'report'), 'could not be found', 'another tutor cannot end it'); -- Checks: refused.
reset role; -- Back to the test user.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the Operations admin.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.outside_work_reports), 0, 'an Operations admin cannot see it'); -- Checks: hidden.
reset role; -- Back to the test user.
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- Signs in as parent P1.
set role authenticated; -- Acts as a signed-in user.
select tests.fails_with($$select public.outside_work_save(null, 'tutoring', 'Tutor', null, null, true, current_date)$$, 'Only CLG tutors and admin staff', 'a parent cannot report'); -- Checks: staff only.
reset role; -- Back to the test user.

-- 3. The owner sees it and marks it as seen.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.outside_work_reports where id = :'report'), 1, 'the owner can see it'); -- Checks: visible.
select public.outside_work_mark_seen(:'report', 'Fine: no CLG families.'); -- Marks it seen with a note.
select tests.eq((select count(*) from public.outside_work_reports where id = :'report' and owner_seen_at is not null and owner_note = 'Fine: no CLG families.'), 1, 'marked as seen with a note'); -- Checks: saved.
reset role; -- Back to the test user.

-- 4. The tutor changes it, then ends it: the owner is told each time and looks again.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user.
select tests.fails($$select public.outside_work_mark_seen((select id from public.outside_work_reports limit 1), 'mine')$$, 'a tutor cannot mark their own report as seen'); -- Checks: owner only.
select public.outside_work_save(:'report', 'tutoring', 'Private maths and English tutor', null, null, true, current_date + 7); -- Changes it.
select tests.eq((select count(*) from public.outside_work_reports where id = :'report' and role_title = 'Private maths and English tutor' and owner_seen_at is null), 1, 'a change is saved and needs the owner to look again'); -- Checks: changed.
select public.outside_work_end(:'report', current_date + 60); -- Ends it.
select tests.eq((select count(*) from public.outside_work_reports where id = :'report' and ends_on = current_date + 60), 1, 'it can be ended'); -- Checks: ended.
reset role; -- Back to the test user.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title in ('Work outside CLG changed', 'Work outside CLG ended')), 2, 'the owner is told about the change and the end'); -- Checks: two more notices.

rollback; -- Undoes everything this test added.
\echo '  work outside CLG: all checks passed'
