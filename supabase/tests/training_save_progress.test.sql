-- Training: saving a module part way through. Checks a tutor can mark
-- lessons done and save quiz answers for a published module made for them,
-- only through the save step; that they see only their own saved place; that
-- admins can see it; and that drafts, other people's modules, other modules'
-- lessons and parents are refused.
-- Reuses access_rules.test.sql people: operations admin (...b0), tutor T1
-- (...11), tutor T2 (...12), parent P1 (...01). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this change again (checks it can run twice).
\ir ../migrations/20261120700100_training_save_progress.sql

-- Acts as the database itself, to set up the modules.
select tests.claims(null);
-- Adds three modules: a published tutor module, a published admin-only module, and a draft.
insert into public.training_modules (id, title, audience, stage, required, holds_matching, counts_toward_certified, minutes, status, position) values -- the modules:
  ('20000000-0000-0000-0000-000000000001', 'Save test: tutor module', 'tutor', 'ongoing', false, false, true, 30, 'published', 901), -- for tutors, published
  ('20000000-0000-0000-0000-000000000002', 'Save test: admin module', 'admin', 'ongoing', false, false, true, 15, 'published', 902), -- for admins only
  ('20000000-0000-0000-0000-000000000003', 'Save test: draft', 'tutor', 'ongoing', false, false, true, 15, 'draft', 903); -- not published yet
-- Adds two lessons to the tutor module and one to the admin module.
insert into public.training_lessons (id, module_id, position, title, body) values -- the lessons:
  ('21000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 1, 'Lesson one', 'First.'), -- tutor module, lesson 1
  ('21000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 2, 'Lesson two', 'Second.'), -- tutor module, lesson 2
  ('21000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000002', 1, 'Admin lesson', 'Admin.'); -- admin module, lesson 1
-- Adds two quiz questions to the tutor module.
insert into public.training_questions (module_id, position, prompt, options, correct_option) values -- the questions:
  ('20000000-0000-0000-0000-000000000001', 1, 'Question one?', array['A', 'B'], 1), -- question 1
  ('20000000-0000-0000-0000-000000000001', 2, 'Question two?', array['A', 'B'], 2); -- question 2

-- ---------------------------------------------------------------------------
-- Tutor T1 saves their place.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1 with two-step login
set role authenticated; -- as a signed-in person
select public.training_save_progress('20000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', null); -- marks lesson 1 done
select public.training_save_progress('20000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', null); -- marks lesson 1 done again (should not double up)
select public.training_save_progress('20000000-0000-0000-0000-000000000001', null, array[2, 0]); -- saves answer B for question 1, question 2 not answered yet
select tests.eq((select cardinality(done_lessons)::bigint from public.training_progress where module_id = '20000000-0000-0000-0000-000000000001'), 1::bigint, 'lesson saved once'); -- checks the lesson is there once
select tests.eq((select count(*) from public.training_progress where module_id = '20000000-0000-0000-0000-000000000001' and saved_answers = array[2, 0]), 1::bigint, 'answers saved'); -- checks the answers
select public.training_save_progress('20000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000002', null); -- marks lesson 2 done, without new answers
select tests.eq((select count(*) from public.training_progress where module_id = '20000000-0000-0000-0000-000000000001' and cardinality(done_lessons) = 2 and saved_answers = array[2, 0]), 1::bigint, 'second lesson added, answers kept'); -- checks both lessons, answers unchanged
select public.training_save_progress('20000000-0000-0000-0000-000000000001', null, '{}'); -- clears the answers (as after passing)
select tests.eq((select count(*) from public.training_progress where module_id = '20000000-0000-0000-0000-000000000001' and saved_answers = '{}'), 1::bigint, 'answers cleared'); -- checks they are gone
-- Refusals for T1.
select tests.fails($$select public.training_save_progress('20000000-0000-0000-0000-000000000002', null, null)$$, 'tutor saves an admin-only module'); -- not for them
select tests.fails($$select public.training_save_progress('20000000-0000-0000-0000-000000000003', null, null)$$, 'tutor saves a draft'); -- not published
select tests.fails($$select public.training_save_progress('20000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000003', null)$$, 'lesson from another module'); -- wrong lesson
select tests.fails($$select public.training_save_progress('20000000-0000-0000-0000-000000000001', null, array[1, 1, 1])$$, 'more answers than questions'); -- too many answers
select tests.fails($$insert into public.training_progress (account_id, module_id) values ('00000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000001')$$, 'tutor writes the table directly'); -- only the step writes
select tests.fails($$update public.training_progress set done_lessons = '{}'$$, 'tutor changes the table directly'); -- only the step writes
reset role; -- back to the test runner

-- Without two-step login, T1 cannot save or see their place.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- acting as T1 without two-step login
set role authenticated; -- as a signed-in person
select tests.fails($$select public.training_save_progress('20000000-0000-0000-0000-000000000001', null, null)$$, 'saving without two-step login'); -- refused
select tests.eq((select count(*) from public.training_progress), 0::bigint, 'no two-step login, nothing seen'); -- sees nothing
reset role; -- back to the test runner

-- ---------------------------------------------------------------------------
-- Other people.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- acting as tutor T2
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_progress), 0::bigint, 'another tutor sees nothing'); -- cannot see T1's place
reset role; -- back to the test runner

select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- acting as parent P1
set role authenticated; -- as a signed-in person
select tests.fails($$select public.training_save_progress('20000000-0000-0000-0000-000000000001', null, null)$$, 'parent saves training'); -- refused
select tests.eq((select count(*) from public.training_progress), 0::bigint, 'parent sees nothing'); -- sees nothing
reset role; -- back to the test runner

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_progress where account_id = '00000000-0000-0000-0000-000000000011'), 1::bigint, 'admin sees the tutor''s place'); -- admins can see it
reset role; -- back to the test runner

-- The handbook's pay page says only the set time is paid (when the page is there).
select tests.eq((select count(*) from public.handbook_pages where id = '7b000000-0000-4000-8000-000000000007' and body not like '%only the set time is paid%'), 0::bigint, 'handbook says only the set time is paid'); -- checks the new line

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  training save progress: all checks passed'
