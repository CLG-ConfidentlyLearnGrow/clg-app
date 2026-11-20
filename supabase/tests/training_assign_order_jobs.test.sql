-- Training: assigning modules with a due date (and paying for them),
-- "done in order" modules, and readiness for a term review. Checks only full
-- admins assign, that an assigned optional module shows as to do and is paid,
-- that an in-order module waits for the earlier ones, and that a term review
-- given to a tutor who needs modules assigns them and tells everyone.
-- Reuses access_rules.test.sql people: operations admin (...b0), tutor T1
-- (...11), tutor T2 (...12), and the student Cara One. Everything is rolled
-- back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this change again (an earlier test may have re-run the training file, and it must run twice).
-- Module 29 is needed before study plans, which the older file's rule does not know yet, so it is cleared while that file runs again.
update public.training_modules set needed_for = null where needed_for = 'study_plan'; -- clears it for now
\ir ../migrations/20261121300200_training_assign_order_jobs.sql
-- Puts back the rule that knows study plans, and module 29's job.
\ir ../migrations/20261123300100_training_goals_study_plans.sql
update public.training_modules set needed_for = 'study_plan' where id = '7a000000-0000-4000-8000-000000000029'; -- module 29 is needed before study plans again

-- Acts as the database itself, to set up.
select tests.claims(null);
-- Starts with no modules, completions or assignments, so only the ones below count.
delete from public.training_assignments; -- removes assignments
delete from public.training_completions; -- removes completions
delete from public.training_modules; -- removes modules (lessons and questions go with them)
-- Four published tutor modules with no quiz: two done in order, one optional, one needed before term reviews.
insert into public.training_modules (id, title, audience, stage, required, holds_matching, counts_toward_certified, minutes, status, position, in_order, needed_for) values -- the modules:
  ('30000000-0000-0000-0000-000000000001', 'Order one', 'tutor', 'starting', true, false, true, 15, 'published', 1, true, null), -- first in order
  ('30000000-0000-0000-0000-000000000002', 'Order two', 'tutor', 'starting', true, false, true, 15, 'published', 2, true, null), -- second in order
  ('30000000-0000-0000-0000-000000000003', 'Optional extra', 'tutor', 'ongoing', false, false, true, 15, 'published', 3, false, null), -- optional
  ('30000000-0000-0000-0000-000000000004', 'Term reviews', 'tutor', 'ongoing', true, false, true, 15, 'published', 4, false, 'term_review'), -- needed before term reviews
  ('30000000-0000-0000-0000-000000000005', 'Admin only', 'admin', 'ongoing', false, false, true, 15, 'published', 5, false, null), -- for admins only
  ('30000000-0000-0000-0000-000000000006', 'A draft', 'tutor', 'ongoing', false, false, true, 15, 'draft', 6, false, null); -- not published

-- ---------------------------------------------------------------------------
-- Assigning: only full admins, only published modules made for the person.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails($$select public.training_assign('00000000-0000-0000-0000-000000000011', '30000000-0000-0000-0000-000000000003', current_date + 7)$$, 'tutor assigns training'); -- refused
select tests.fails($$insert into public.training_assignments (account_id, module_id, due_on) values ('00000000-0000-0000-0000-000000000011', '30000000-0000-0000-0000-000000000003', current_date)$$, 'tutor writes assignments directly'); -- refused
reset role; -- back to the test runner

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.fails($$select public.training_assign('00000000-0000-0000-0000-000000000011', '30000000-0000-0000-0000-000000000005', current_date + 7)$$, 'admin-only module to a tutor'); -- not made for them
select tests.fails($$select public.training_assign('00000000-0000-0000-0000-000000000011', '30000000-0000-0000-0000-000000000006', current_date + 7)$$, 'draft module'); -- not published
select tests.fails($$select public.training_assign('00000000-0000-0000-0000-000000000011', '30000000-0000-0000-0000-000000000003', current_date - 1)$$, 'due date in the past'); -- refused
select public.training_assign('00000000-0000-0000-0000-000000000011', '30000000-0000-0000-0000-000000000003', private.training_today() + 7, 'Practice for next term'); -- assigns the optional module to T1
select tests.eq((select count(*) from public.training_assignments where account_id = '00000000-0000-0000-0000-000000000011'), 1::bigint, 'admin assigns a module'); -- checks it is there
reset role; -- back to the test runner

-- The tutor was told.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000011' and title = 'Training assigned: Optional extra'), 1::bigint, 'tutor told about the assignment'); -- checks the notice

-- T1 sees it as to do, due on the date; T2 sees nothing of T1's.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_my_modules() where module_id = '30000000-0000-0000-0000-000000000003' and state = 'to_do' and due_on = private.training_today() + 7), 1::bigint, 'assigned optional module is to do'); -- checks the state
select tests.eq((select count(*) from public.training_assignments), 1::bigint, 'tutor sees own assignment'); -- sees their own
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- acting as tutor T2
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_assignments), 0::bigint, 'another tutor sees no assignments'); -- sees nothing
select tests.eq((select count(*) from public.training_my_modules() where module_id = '30000000-0000-0000-0000-000000000003' and state = 'optional'), 1::bigint, 'still optional for others'); -- unchanged for T2
reset role; -- back to the test runner

-- Finishing the assigned module records it as paid.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select public.training_finish('30000000-0000-0000-0000-000000000003', '{}'); -- finishes it (no quiz)
reset role; -- back to the test runner
select tests.eq((select count(*) from public.training_completions where account_id = '00000000-0000-0000-0000-000000000011' and module_id = '30000000-0000-0000-0000-000000000003' and paid), 1::bigint, 'assigned module is paid'); -- checks paid

-- An optional module that is not assigned is not paid (T2).
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- acting as tutor T2
set role authenticated; -- as a signed-in person
select public.training_finish('30000000-0000-0000-0000-000000000003', '{}'); -- finishes it (no quiz)
reset role; -- back to the test runner
select tests.eq((select count(*) from public.training_completions where account_id = '00000000-0000-0000-0000-000000000012' and module_id = '30000000-0000-0000-0000-000000000003' and not paid), 1::bigint, 'unassigned optional module is not paid'); -- checks not paid

-- ---------------------------------------------------------------------------
-- Done in order: "Order two" waits for "Order one".
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails($$select public.training_finish('30000000-0000-0000-0000-000000000002', '{}')$$, 'second in-order module before the first'); -- refused
select public.training_finish('30000000-0000-0000-0000-000000000001', '{}'); -- finishes the first
select public.training_finish('30000000-0000-0000-0000-000000000002', '{}'); -- now the second works
select tests.eq((select count(*) from public.training_completions where account_id = '00000000-0000-0000-0000-000000000011' and module_id in ('30000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002')), 2::bigint, 'in-order modules finished in order'); -- checks both done
reset role; -- back to the test runner

-- ---------------------------------------------------------------------------
-- Ready for a term review.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_job_readiness() where account_id = '00000000-0000-0000-0000-000000000011' and job = 'term_review' and missing = array['Term reviews']), 1::bigint, 'readiness shows what is missing'); -- checks the list
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails($$select * from public.training_job_readiness()$$, 'tutor reads readiness'); -- only admins
reset role; -- back to the test runner

-- A term review is made for T1, who has not done "Term reviews".
select tests.claims(null); -- acting as the database itself
select id as cara from public.students where full_name = 'Cara One' \gset
insert into public.term_reviews (student_id, tutor_id, term_label, term_starts_on, term_ends_on, due_on) -- makes a draft review for T1:
values (:'cara', '00000000-0000-0000-0000-000000000011', 'Term 9 2099', current_date - 60, current_date + 20, current_date + 20); -- (a made-up term)
select tests.eq((select count(*) from public.training_assignments where account_id = '00000000-0000-0000-0000-000000000011' and module_id = '30000000-0000-0000-0000-000000000004' and due_on = (current_date + 19)), 1::bigint, 'needed module assigned before the review'); -- checks the assignment
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000011' and title = 'Training to do before your term review'), 1::bigint, 'tutor told what to finish'); -- checks the tutor's notice
select tests.eq((select count(*) from public.session_notices where title = 'Training needed: ' || (select full_name from public.accounts where id = '00000000-0000-0000-0000-000000000011')), (select count(*) from public.account_roles ar left join public.admin_profiles ap on ap.account_id = ar.account_id where ar.role = 'admin' and coalesce(ap.level, 'owner') in ('owner', 'operations')), 'admins told'); -- checks each full admin was told

-- A tutor who is ready gets no assignment: T1 finishes it, and a second review adds nothing.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select public.training_finish('30000000-0000-0000-0000-000000000004', '{}'); -- finishes "Term reviews"
reset role; -- back to the test runner
select tests.claims(null); -- acting as the database itself
select count(*) as notices_before from public.session_notices \gset
insert into public.term_reviews (student_id, tutor_id, term_label, term_starts_on, term_ends_on, due_on) -- another review for T1:
values (:'cara', '00000000-0000-0000-0000-000000000011', 'Term 10 2099', current_date - 60, current_date + 21, current_date + 21); -- (another made-up term)
select tests.eq((select count(*) from public.session_notices), :notices_before::bigint, 'ready tutor: nobody told'); -- checks no new notices

-- Only full admins remove assignments.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails($$select public.training_unassign('00000000-0000-0000-0000-000000000011', '30000000-0000-0000-0000-000000000003')$$, 'tutor removes an assignment'); -- refused
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select public.training_unassign('00000000-0000-0000-0000-000000000011', '30000000-0000-0000-0000-000000000003'); -- removes it
reset role; -- back to the test runner
select tests.eq((select count(*) from public.training_assignments where module_id = '30000000-0000-0000-0000-000000000003'), 0::bigint, 'admin removes an assignment'); -- checks it is gone

-- The handbook's pay page says assigned modules are paid (when the page is there).
select tests.eq((select count(*) from public.handbook_pages where id = '7b000000-0000-4000-8000-000000000007' and body not like '%Modules CLG assigns to you are paid%'), 0::bigint, 'handbook says assigned modules are paid'); -- checks the new line

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  training assign, order and jobs: all checks passed'
