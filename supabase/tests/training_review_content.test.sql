-- Training content: checks Carla's 16 Nov 2026 review reached the draft
-- modules and handbook pages, the four new modules are drafts, running the
-- changes again doesn't double anything up, and a published module is
-- never changed by them. Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Acts as the database itself.
select tests.claims(null);

-- The four new modules are there, as drafts, and hold no matches.
select tests.eq((select count(*) from public.training_modules where id in ('7a000000-0000-4000-8000-000000000008', '7a000000-0000-4000-8000-000000000009', '7a000000-0000-4000-8000-000000000010', '7a000000-0000-4000-8000-000000000011') and status = 'draft' and not holds_matching), 4::bigint, 'four new draft modules'); -- checks modules 8 to 11
-- Each new module has three lessons and three questions.
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000008'), 3::bigint, 'module 8 has 3 lessons'); -- checks module 8's lessons
select tests.eq((select count(*) from public.training_questions where module_id = '7a000000-0000-4000-8000-000000000011'), 3::bigint, 'module 11 has 3 questions'); -- checks module 11's quiz

-- No "Carla to check" notes are left in the draft lessons or handbook pages.
select tests.eq((select count(*) from public.training_lessons where body like '%Carla to check%'), 0::bigint, 'no open questions in lessons'); -- checks lessons
select tests.eq((select count(*) from public.handbook_pages where body like '%Carla to check%'), 0::bigint, 'no open questions in handbook pages'); -- checks handbook pages

-- Carla's answers are in place.
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000002' and position = 2 and body like '%only through the CLG App%' and body not like '%Teams%'), 1::bigint, 'contact only through the app'); -- answer 1
select tests.eq((select count(*) from public.handbook_pages where id = '7b000000-0000-4000-8000-000000000001' and body like '%Phone CLG (Lauren first, or Carla), who will call the parent%'), 1::bigint, 'phone CLG to reach a parent'); -- answer 2
select tests.eq((select count(*) from public.handbook_pages where id = '7b000000-0000-4000-8000-000000000005' and body like '%under 12 are dropped off and collected by a parent%'), 1::bigint, 'under-12s collected by a parent'); -- answer 5
select tests.eq((select count(*) from public.handbook_pages where id = '7b000000-0000-4000-8000-000000000008' and body like '%Lauren, CLG''s Student Success Coordinator, is your first point of contact%'), 1::bigint, 'Lauren first point of contact'); -- answer 6
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000002' and title = 'Honest work' and body like '%Not a sentence, a paragraph or a conclusion%'), 1::bigint, 'never write the work'); -- integrity rule
select tests.eq((select count(*) from public.training_lessons where body like '%9pm and 6am%'), 0::bigint, 'quiet hours say 5am'); -- answer 7

-- Remember how much there is now, then run both changes again.
select count(*) as lessons_before from public.training_lessons \gset
select count(*) as questions_before from public.training_questions \gset
select md5(string_agg(body, '' order by module_id, position)) as bodies_before from public.training_lessons \gset
\ir ../migrations/20261118200100_training_review_edits.sql
\ir ../migrations/20261118200200_training_new_modules.sql
-- Nothing was added or changed the second time.
select tests.eq((select count(*) from public.training_lessons), :lessons_before::bigint, 'running again adds no lessons'); -- checks lessons
select tests.eq((select count(*) from public.training_questions), :questions_before::bigint, 'running again adds no questions'); -- checks questions
select tests.eq((select count(*) from (select md5(string_agg(body, '' order by module_id, position)) as h from public.training_lessons) x where x.h = :'bodies_before'), 1::bigint, 'running again changes no lesson text'); -- checks lesson text

-- A published module is never touched: put the old text back, publish it, and run again.
update public.training_lessons set body = 'Published text.' where module_id = '7a000000-0000-4000-8000-000000000003' and position = 2; -- module 3, lesson 2 gets other text
update public.training_modules set status = 'published' where id = '7a000000-0000-4000-8000-000000000003'; -- and module 3 is published
\ir ../migrations/20261118200100_training_review_edits.sql
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000003' and position = 2 and body = 'Published text.'), 1::bigint, 'a published module is left alone'); -- checks nothing was added

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  training review content: all checks passed'
