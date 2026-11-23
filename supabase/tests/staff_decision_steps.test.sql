-- Summary: tests the decision steps record and decisions log (Carla, 22 Nov
-- 2026). Reuses tutors T1 (...11) and T3 (...13), parent P1 (...01), the
-- owner (...a0) and the Operations admin (...b0). Everything is undone at
-- the end. Checks: the guide's starting rows, who can read a record, only
-- the owner moves steps, Operations adds notes for tutors, probation shows
-- Step 1, and the person's own decisions log.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the file again, to check it is safe to run more than once.
\ir ../migrations/20261124711700_decision_steps.sql

begin; -- Starts a change that is undone at the end, so nothing is left behind.

-- 1. The guide's starting rows are loaded once.
select tests.eq((select count(*) from public.decision_kinds where key like 'admin_%'), 10, 'the 10 admin starting rows are loaded'); -- Checks: admin rows.
select tests.eq((select count(*) from public.decision_kinds where key like 'tutor_%'), 7, 'the 7 tutor starting rows are loaded'); -- Checks: tutor rows.
delete from public.staff_probations where account_id in ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000013'); -- Starts the tutors off probation, so the steps are their own.
select id as late from public.decision_kinds where key = 'tutor_late_no_show' \gset
select id as plan from public.decision_kinds where key = 'tutor_change_plan' \gset
select id as admin_kind from public.decision_kinds where key = 'admin_chasing' \gset

-- 2. Tutor T1 reads their own record: the tutor rows at their starting steps.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.decision_record(auth.uid())), 7, 'a tutor sees the 7 tutor rows'); -- Checks: only their role's rows.
select tests.eq((select step from public.decision_record(auth.uid()) where kind_id = :'late'), 2, 'a row starts at the guide''s starting step'); -- Checks: starting step.
select tests.fails($$select * from public.decision_record('00000000-0000-0000-0000-000000000013')$$, 'a tutor cannot read another tutor''s record'); -- Checks: private.
select tests.fails(format($$select public.decision_step_move(auth.uid(), %L, 4, 'Moving myself')$$, :'late'), 'a tutor cannot move their own step'); -- Checks: owner only.
select tests.fails(format($$select public.decision_note_add('00000000-0000-0000-0000-000000000013', %L, 'Note on a peer')$$, :'late'), 'a tutor cannot add notes'); -- Checks: notes are for Carla and Operations.
select public.decision_log_add(:'late', 'Student did not join by 10 minutes past.', 'Wait longer; message the parent; mark a no-show.', 'Messaged the parent, waited 15 minutes, then marked a no-show as the policy says.', true) as entry \gset
select tests.fails_with(format($$select public.decision_log_add(%L, 'Problem', 'Options', 'Choice', true)$$, :'admin_kind'), 'not part of your record', 'a tutor cannot log against an admin kind'); -- Checks: their own kinds.
select tests.eq((select count(*) from public.decision_log where account_id = auth.uid()), 1, 'the tutor sees their own log'); -- Checks: saved.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- 3. The Operations admin reads T1's record and adds a note, but cannot move steps.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the Operations admin.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.decision_record('00000000-0000-0000-0000-000000000011')), 7, 'Operations can read a tutor''s record'); -- Checks: Emma reads tutors.
select tests.eq((select count(*) from public.decision_log where account_id = '00000000-0000-0000-0000-000000000011'), 1, 'Operations can read a tutor''s decisions log'); -- Checks: log.
select public.decision_note_add('00000000-0000-0000-0000-000000000011', :'late', 'Handled two no-shows well this week.'); -- Adds a note.
select tests.fails(format($$select public.decision_step_move('00000000-0000-0000-0000-000000000011', %L, 3, 'Ready')$$, :'late'), 'Operations cannot move steps'); -- Checks: only Carla moves steps.
select tests.fails($$select * from public.decision_record('00000000-0000-0000-0000-0000000000a0')$$, 'Operations cannot read the owner''s record'); -- Checks: tutors only.
select tests.eq((select count(*) from public.decision_record_people() where account_id = '00000000-0000-0000-0000-000000000011'), 1, 'T1 is in the Operations list'); -- Checks: the list.
reset role; -- Back to the test user.

-- 4. The owner moves T1's step; T1 is told and sees the note.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner.
set role authenticated; -- Acts as a signed-in user.
select public.decision_step_move('00000000-0000-0000-0000-000000000011', :'late', 3, 'Consistently the choices I would make.'); -- Moves it up.
select tests.fails_with(format($$select public.decision_step_move('00000000-0000-0000-0000-000000000011', %L, 6, null)$$, :'late'), 'step from 1 to 5', 'a step above 5 is refused'); -- Checks: real steps.
select tests.fails_with(format($$select public.decision_step_move('00000000-0000-0000-0000-000000000011', %L, 2, null)$$, :'admin_kind'), 'not part of this person', 'an admin kind cannot be set for a tutor-only person'); -- Checks: matching role.
reset role; -- Back to the test user.
select tests.eq((select count(*) from public.decision_step_moves where account_id = '00000000-0000-0000-0000-000000000011' and kind_id = :'late' and from_step = 2 and to_step = 3), 1, 'the move is recorded from 2 to 3'); -- Checks: history.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000011' and title = 'Your decision steps record changed'), 1, 'the tutor is told'); -- Checks: notice.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select step from public.decision_record(auth.uid()) where kind_id = :'late'), 3, 'the tutor sees the new step'); -- Checks: updated.
select tests.eq((select count(*) from public.decision_notes where account_id = auth.uid()), 1, 'the tutor sees notes on their record'); -- Checks: open record.
reset role; -- Back to the test user.

-- 5. During probation every row shows Step 1.
insert into public.staff_probations (account_id, kind, started_on) values ('00000000-0000-0000-0000-000000000011', 'tutor', current_date); -- Puts T1 on probation.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.decision_record(auth.uid()) where step = 1 and on_probation), 7, 'on probation, every row is Step 1'); -- Checks: probation.
reset role; -- Back to the test user.

-- 6. Families see nothing.
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- Signs in as parent P1.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.decision_kinds), 0, 'families do not see the kinds'); -- Checks: staff only.
select tests.eq((select count(*) from public.decision_log), 0, 'families do not see any log'); -- Checks: staff only.
reset role; -- Back to the test user.

rollback; -- Undoes everything above.
\echo '  decision steps record: all checks passed'
