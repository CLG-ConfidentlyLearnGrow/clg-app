-- Training: screenshot questions and practice tasks checked by CLG. Checks
-- a question's picture can be read with the question; that a module with a
-- practice task waits for an approved task; that only full admins check
-- tasks (and not their own); that sending back needs a reason; that
-- approving after the quiz finishes the module; and who can see what.
-- Reuses access_rules.test.sql people: operations admin (...b0), tutor T1
-- (...11), tutor T2 (...12), parent P1 (...01). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the changes this relies on again (an earlier test may have re-run the training file), then this one twice.
\ir ../migrations/20261121300200_training_assign_order_jobs.sql
\ir ../migrations/20261121300300_training_screenshots_tasks.sql
\ir ../migrations/20261121300300_training_screenshots_tasks.sql

-- Acts as the database itself, to set up.
select tests.claims(null);
-- One published tutor module with a practice task and one quiz question with a picture.
insert into public.training_modules (id, title, audience, stage, required, holds_matching, counts_toward_certified, minutes, status, position, practice_task) values -- the module:
  ('40000000-0000-0000-0000-000000000001', 'Task test', 'tutor', 'starting', true, false, true, 15, 'published', 990, 'Write a summary for the made-up student.'); -- with a task
insert into public.training_questions (module_id, position, prompt, options, correct_option, image_path, image_alt) values -- the question:
  ('40000000-0000-0000-0000-000000000001', 1, 'Which button do you press?', array['Sign on', 'Cancel'], 1, 'questions/test.png', 'The Sessions list'); -- with a picture

-- ---------------------------------------------------------------------------
-- The picture can be read with the question.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_questions where module_id = '40000000-0000-0000-0000-000000000001' and image_path = 'questions/test.png' and image_alt = 'The Sessions list'), 1::bigint, 'tutor reads the question picture'); -- checks the columns

-- The quiz is passed, but the module waits for the task.
select tests.eq((select count(*) from (select public.training_finish('40000000-0000-0000-0000-000000000001', array[1]) r) x where (x.r->>'waiting_task')::boolean), 1::bigint, 'quiz passed, waiting for the task'); -- checks the reply
select tests.eq((select count(*) from public.training_completions where module_id = '40000000-0000-0000-0000-000000000001'), 0::bigint, 'not finished before the task'); -- no completion yet

-- Sending the task: too short is refused, then a proper one is sent.
select tests.fails($$select public.training_submit_task('40000000-0000-0000-0000-000000000001', 'too short')$$, 'task too short'); -- refused
select public.training_submit_task('40000000-0000-0000-0000-000000000001', 'Mia worked on equivalent fractions today and went from 6 to 9 out of 10.'); -- sends it
select tests.eq((select count(*) from public.training_task_submissions where status = 'submitted'), 1::bigint, 'task sent'); -- checks it is there
select tests.fails($$insert into public.training_task_submissions (account_id, module_id, module_version, answer) values ('00000000-0000-0000-0000-000000000011', '40000000-0000-0000-0000-000000000001', 1, 'Written straight into the table.')$$, 'tutor writes submissions directly'); -- only the steps write
select tests.fails($$select public.training_review_task((select id from public.training_task_submissions limit 1), true)$$, 'tutor checks a task'); -- only admins
reset role; -- back to the test runner
select id as sub from public.training_task_submissions where module_id = '40000000-0000-0000-0000-000000000001' \gset

-- Admins were told.
select tests.eq((select count(*) from public.session_notices where title like 'Practice task to check: %'), (select count(*) from public.account_roles ar left join public.admin_profiles ap on ap.account_id = ar.account_id where ar.role = 'admin' and coalesce(ap.level, 'owner') in ('owner', 'operations')), 'admins told about the task'); -- checks each full admin was told

-- Other people cannot see it.
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- acting as tutor T2
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_task_submissions), 0::bigint, 'another tutor sees no tasks'); -- sees nothing
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- acting as parent P1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_task_submissions), 0::bigint, 'parent sees no tasks'); -- sees nothing
select tests.fails($$select public.training_submit_task('40000000-0000-0000-0000-000000000001', 'A parent trying to send a training task.')$$, 'parent sends a task'); -- refused
reset role; -- back to the test runner

-- ---------------------------------------------------------------------------
-- Checking: sending back needs a reason; approving finishes the module.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_task_submissions where status = 'submitted'), 1::bigint, 'admin sees the task'); -- admins can see it
select tests.fails(format($$select public.training_review_task(%L, false, '')$$, :'sub'), 'sent back without a reason'); -- refused
select public.training_review_task(:'sub', false, 'Add one clear next step.'); -- sends it back
reset role; -- back to the test runner
select tests.eq((select count(*) from public.training_task_submissions where id = :'sub' and status = 'returned' and feedback = 'Add one clear next step.'), 1::bigint, 'task sent back with feedback'); -- checks it
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000011' and title = 'Practice task to redo: Task test'), 1::bigint, 'tutor told to redo'); -- checks the notice

-- T1 sends it again; it waits again (the same row).
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select public.training_submit_task('40000000-0000-0000-0000-000000000001', 'Mia went from 6 to 9 out of 10. Next step: simplify 5 fractions without help.'); -- sends it again
reset role; -- back to the test runner
select tests.eq((select count(*) from public.training_task_submissions where module_id = '40000000-0000-0000-0000-000000000001' and status = 'submitted'), 1::bigint, 'sent again, one submission waiting'); -- checks it

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select public.training_review_task(:'sub', true, 'Good.'); -- approves it
reset role; -- back to the test runner
select tests.eq((select count(*) from public.training_completions where account_id = '00000000-0000-0000-0000-000000000011' and module_id = '40000000-0000-0000-0000-000000000001' and paid), 1::bigint, 'approving finishes the module (paid)'); -- checks the completion
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000011' and title = 'Practice task approved: Task test'), 1::bigint, 'tutor told it is approved'); -- checks the notice

-- An approved task cannot be sent again or checked again.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails($$select public.training_submit_task('40000000-0000-0000-0000-000000000001', 'Trying to send it again after approval.')$$, 'sending again after approval'); -- refused
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.training_review_task(%L, true)$$, :'sub'), 'checking twice'); -- refused
reset role; -- back to the test runner

-- An admin cannot check their own task: the operations admin sends one (as staff), then tries to approve it.
select tests.claims(null); -- acting as the database itself
update public.training_modules set audience = 'everyone' where id = '40000000-0000-0000-0000-000000000001'; -- the module is now for admins too
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select public.training_submit_task('40000000-0000-0000-0000-000000000001', 'The admin writing their own practice task for the module.'); -- sends their own
select tests.fails($$select public.training_review_task((select id from public.training_task_submissions where account_id = '00000000-0000-0000-0000-0000000000b0'), true)$$, 'checking your own task'); -- refused
reset role; -- back to the test runner

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  training screenshots and tasks: all checks passed'
