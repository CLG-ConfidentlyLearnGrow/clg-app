-- Training: goals for every student (modules 27 and 28 rewritten) and the
-- study plan add-on (module 29). Checks the new content is there, that
-- nothing is assigned while study plans are free, that a tutor of a student
-- with the paid add-on gets module 29 (paid, with notices), that a tutor who
-- has done it gets nothing, and that readiness shows study plans.
-- Reuses access_rules.test.sql people: operations admin (...b0), tutor T1
-- (...11, and the student they teach), tutor T2 (...12). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the changes this relies on again (an earlier test may have re-run older files), then this one twice.
\ir ../migrations/20261121300100_training_plans_routine.sql
-- Module 29 is needed before study plans, which the older file's rule does not know yet, so it is cleared while that file runs again.
update public.training_modules set needed_for = null where needed_for = 'study_plan'; -- clears it for now
\ir ../migrations/20261121300200_training_assign_order_jobs.sql
-- Puts back the rule that knows study plans, and module 29's job.
\ir ../migrations/20261123300100_training_goals_study_plans.sql
update public.training_modules set needed_for = 'study_plan' where id = '7a000000-0000-4000-8000-000000000029'; -- module 29 is needed before study plans again
\ir ../migrations/20261121300300_training_screenshots_tasks.sql
\ir ../migrations/20261123300100_training_goals_study_plans.sql
\ir ../migrations/20261123300100_training_goals_study_plans.sql

-- Acts as the database itself, to set up.
select tests.claims(null);

-- ---------------------------------------------------------------------------
-- The content.
-- ---------------------------------------------------------------------------
select tests.eq((select count(*) from public.training_modules where id = '7a000000-0000-4000-8000-000000000027' and title = 'Setting a student''s goals' and practice_task like 'Write two measurable goals%'), 1::bigint, 'module 27 is about goals, with its task'); -- checks module 27
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000027'), 1::bigint, 'module 27 has one lesson'); -- the old two lessons are gone
select tests.eq((select count(*) from public.training_questions where module_id = '7a000000-0000-4000-8000-000000000027' and prompt like 'A goal no longer fits%'), 1::bigint, 'module 27 has the new question'); -- checks a question
select tests.eq((select count(*) from public.training_modules where id = '7a000000-0000-4000-8000-000000000028' and title = 'Each week''s next step'), 1::bigint, 'module 28 is about the next step'); -- checks module 28
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000028' and body like '%student or parent ticks it off%'), 1::bigint, 'module 28 has the new lesson'); -- checks its lesson
select tests.eq((select count(*) from public.training_modules where id = '7a000000-0000-4000-8000-000000000029' and status = 'draft' and not required and needed_for = 'study_plan' and practice_task like 'Set up a term plan%'), 1::bigint, 'module 29 is an optional draft needed before study plans'); -- checks module 29
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000029'), 2::bigint, 'module 29 has two lessons'); -- checks its lessons
select tests.eq((select count(*) from public.training_questions where module_id = '7a000000-0000-4000-8000-000000000029'), 2::bigint, 'module 29 has two questions'); -- checks its questions
-- A published or renamed module is never rewritten: renaming 27 and running the file again keeps it.
update public.training_modules set title = 'Carla''s own title' where id = '7a000000-0000-4000-8000-000000000028'; -- Carla renames module 28
\ir ../migrations/20261123300100_training_goals_study_plans.sql
select tests.eq((select count(*) from public.training_modules where id = '7a000000-0000-4000-8000-000000000028' and title = 'Carla''s own title'), 1::bigint, 'a renamed module is kept'); -- checks it was kept

-- ---------------------------------------------------------------------------
-- Assigning module 29 to tutors of a student with the paid add-on.
-- ---------------------------------------------------------------------------
update public.training_modules set status = 'published' where id = '7a000000-0000-4000-8000-000000000029'; -- module 29 is published
select ta.student_id as cara from public.tutor_assignments ta where ta.tutor_id = '00000000-0000-0000-0000-000000000011' and private.assignment_is_current(ta.starts_on, ta.ends_on) limit 1 \gset
delete from public.training_assignments; -- starts with no assignments
delete from public.add_on_members where add_on = 'study_plans'; -- and nobody with the add-on

-- While study plans are free for everyone, nothing is assigned.
update public.add_ons set mode = 'free' where code = 'study_plans'; -- free for everyone
insert into public.add_on_members (add_on, student_id) values ('study_plans', :'cara'); -- Cara is given it anyway
select tests.eq((select count(*) from public.training_assignments), 0::bigint, 'nothing assigned while study plans are free'); -- checks nothing

-- Study plans become paid: T1 (Cara's tutor) gets module 29.
update public.add_ons set mode = 'paid', price_cents = 2000 where code = 'study_plans'; -- now families pay
select tests.eq((select count(*) from public.training_assignments where account_id = '00000000-0000-0000-0000-000000000011' and module_id = '7a000000-0000-4000-8000-000000000029' and due_on >= private.training_today()), 1::bigint, 'Cara''s tutor is assigned module 29'); -- checks the assignment
select tests.eq((select count(*) from public.training_assignments where account_id = '00000000-0000-0000-0000-000000000012'), 0::bigint, 'another tutor is not'); -- T2 does not teach Cara
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000011' and title = 'Training to do before study plan work'), 1::bigint, 'the tutor is told'); -- checks the tutor's notice
select tests.eq((select count(*) from public.session_notices where title = 'Training needed: ' || (select full_name from public.accounts where id = '00000000-0000-0000-0000-000000000011')), (select count(*) from public.account_roles ar left join public.admin_profiles ap on ap.account_id = ar.account_id where ar.role = 'admin' and coalesce(ap.level, 'owner') in ('owner', 'operations')), 'admins told'); -- checks each full admin was told

-- Checking again adds nothing and tells nobody again.
select count(*) as notices_before from public.session_notices \gset
update public.add_on_members set note = 'Paid for Term 1' where add_on = 'study_plans' and student_id = :'cara'; -- a change to Cara's add-on
select tests.eq((select count(*) from public.session_notices), :notices_before::bigint, 'no repeat notices'); -- checks no new notices

-- T1 sees it as to do and it is paid when finished.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_my_modules() where module_id = '7a000000-0000-4000-8000-000000000029' and state = 'to_do'), 1::bigint, 'module 29 is to do for the tutor'); -- checks the state
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- acting as tutor T2
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_my_modules() where module_id = '7a000000-0000-4000-8000-000000000029' and state = 'optional'), 1::bigint, 'module 29 is optional for other tutors'); -- checks the state
reset role; -- back to the test runner

-- Readiness shows study plans for full admins.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_job_readiness() where account_id = '00000000-0000-0000-0000-000000000011' and job = 'study_plan' and missing = array['Term and weekly study plans']), 1::bigint, 'readiness shows study plans'); -- checks the list
reset role; -- back to the test runner

-- A tutor who has done module 29 gets nothing: T1's assignment is removed, a completion is recorded, and the check runs again.
select tests.claims(null); -- acting as the database itself
delete from public.training_assignments; -- no assignments
insert into public.training_completions (account_id, module_id, module_version, module_title, audience, minutes, paid, counts_toward_certified, completed_on, certificate_no) -- T1 has done module 29:
values ('00000000-0000-0000-0000-000000000011', '7a000000-0000-4000-8000-000000000029', 1, 'Term and weekly study plans', 'tutor', 15, true, true, private.training_today(), 'T-29'); -- (a completion)
update public.add_on_members set note = 'Paid for Term 2' where add_on = 'study_plans' and student_id = :'cara'; -- a change that checks again
select tests.eq((select count(*) from public.training_assignments), 0::bigint, 'a ready tutor is not assigned'); -- checks nothing was assigned

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  training goals and study plans: all checks passed'
