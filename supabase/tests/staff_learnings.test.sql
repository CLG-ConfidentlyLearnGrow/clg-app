-- Summary: tests personal and team learnings (Carla, 22 Nov 2026). Reuses
-- tutors T1 (...11) and T3 (...13), parent P1 (...01), the owner (...a0)
-- and the Operations admin (...b0). Everything is undone at the end.
-- Checks: who can add, privacy of personal learnings, suggesting, adapting
-- into a team learning, declining, and who sees team learnings.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the file again, to check it is safe to run more than once.
\ir ../migrations/20261124711500_personal_team_learnings.sql

begin; -- Starts a change that is undone at the end, so nothing is left behind.

-- 1. Tutor T1 writes two personal learnings.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.learning_save(null, 'Start with a quick win', 'Opening with a question the student can answer builds confidence for the harder work.') as one \gset
select public.learning_save(null, 'Check the link early', 'Test the meeting link 10 minutes before an online session.') as two \gset
select tests.eq((select count(*) from public.learnings where author_id = auth.uid()), 2, 'a tutor sees their own learnings'); -- Checks: saved and visible.
select tests.fails_with($$select public.learning_save(null, 'x', 'y')$$, 'short title', 'a learning with no real title is refused'); -- Checks: plain refusal.
select tests.fails($$insert into public.learnings (kind, author_id, title, body) values ('team', auth.uid(), 'Sneaky', 'Straight in')$$, 'learnings cannot be written straight into the table'); -- Checks: only through the functions.
select tests.fails($$select public.learning_adopt(null, 'Own team learning', 'Tutors cannot publish')$$, 'a tutor cannot publish a team learning'); -- Checks: approvers only.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- 2. Personal learnings are private until suggested.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the Operations admin.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.learnings where author_id = '00000000-0000-0000-0000-000000000011'), 0, 'an approver cannot see a personal learning that was not suggested'); -- Checks: private.
reset role; -- Back to the test user.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.learnings where author_id = '00000000-0000-0000-0000-000000000011'), 0, 'another tutor cannot see them'); -- Checks: private.
reset role; -- Back to the test user.

-- 3. T1 suggests both for the team.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user.
select public.learning_suggest(:'one'); -- Suggests the first.
select public.learning_suggest(:'two'); -- Suggests the second.
reset role; -- Back to the test user.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Learning suggested for the team'), 2, 'the owner is told about each suggestion'); -- Checks: notices.

-- 4. The Operations admin adapts one and declines the other.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the Operations admin.
set role authenticated; -- Acts as a signed-in user.
select tests.eq(public.learnings_waiting_count(), 2, 'two suggestions wait'); -- Checks: the menu number.
select public.learning_adopt(:'one', 'Open with a quick win', 'Start each session with a question the student can answer. It builds confidence before harder work.') as team \gset
select public.learning_decline(:'two', 'Already in the handbook.'); -- Declines the second.
select tests.eq(public.learnings_waiting_count(), 0, 'none wait after answering'); -- Checks: cleared.
select tests.fails(format($$select public.learning_adopt(%L, 'Again', 'Twice')$$, :'one'), 'a suggestion cannot be adopted twice'); -- Checks: answered once.
reset role; -- Back to the test user.
select tests.eq((select count(*) from public.learnings where id = :'team' and kind = 'team' and source_id = :'one'), 1, 'the team learning links to where it came from'); -- Checks: linked.
select tests.eq((select count(*) from public.learnings where id = :'one' and review_status = 'adopted'), 1, 'the personal learning is marked adopted'); -- Checks: adopted.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000011' and title in ('Your learning is now a team learning', 'About your suggested learning')), 2, 'the tutor is told about both answers'); -- Checks: notices.

-- 5. Who sees the team learning.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.learnings where id = :'team'), 1, 'every tutor sees team learnings'); -- Checks: shared.
reset role; -- Back to the test user.
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- Signs in as parent P1.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.learnings), 0, 'families do not see learnings'); -- Checks: staff only.
select tests.fails_with($$select public.learning_save(null, 'Parent note', 'Parents cannot add learnings')$$, 'Only CLG tutors and admin staff', 'a parent cannot add one'); -- Checks: staff only.
reset role; -- Back to the test user.

-- 6. T1 can still change the declined one and suggest it again, but not the adopted one.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user.
select public.learning_save(:'two', 'Check the link early', 'Test the meeting link 10 minutes before, and have the phone number ready.'); -- Changes the declined one.
select public.learning_suggest(:'two'); -- Suggests it again.
select tests.eq((select count(*) from public.learnings where id = :'two' and review_status = 'suggested' and review_note is null), 1, 'a declined learning can be improved and suggested again'); -- Checks: suggested again.
select tests.fails_with(format($$select public.learning_save(%L, 'Changed', 'Too late now')$$, :'one'), 'could not be changed', 'an adopted learning cannot be changed'); -- Checks: locked.
reset role; -- Back to the test user.

rollback; -- Undoes everything this test added.
\echo '  personal and team learnings: all checks passed'
