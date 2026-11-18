-- Training content: checks Carla's 18 Nov 2026 additions are in place
-- (modules 26 to 28, the session routine lesson, the term review changes and
-- the priority order), and that running the change again adds or changes
-- nothing. Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Acts as the database itself.
select tests.claims(null);
-- Runs the change again first (an earlier test may have re-run older content files).
\ir ../migrations/20261121300100_training_plans_routine.sql

-- Modules 26 to 28 are there as drafts, each with lessons and two questions.
select tests.eq((select count(*) from public.training_modules m where m.id in ('7a000000-0000-4000-8000-000000000026', '7a000000-0000-4000-8000-000000000027', '7a000000-0000-4000-8000-000000000028') and m.status = 'draft' and m.audience = 'tutor' and m.required and (select count(*) from public.training_lessons l where l.module_id = m.id) >= 1 and (select count(*) from public.training_questions q where q.module_id = m.id) = 2), 3::bigint, 'modules 26 to 28 added'); -- checks the new modules

-- Module 11 starts with the session routine, and has its question.
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000011' and position = 1 and title = 'The CLG session routine'), 1::bigint, 'routine lesson first in module 11'); -- checks the lesson
select tests.eq((select count(*) from public.training_questions where module_id = '7a000000-0000-4000-8000-000000000011' and prompt = 'Which is true of CLG sessions?'), 1::bigint, 'routine question in module 11'); -- checks the question

-- Module 23 points to the routine; module 24 allows 1 hour and has four parts; module 25 has the new tips.
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000023' and body like '%keep to the CLG session routine every week%'), 1::bigint, 'module 23 routine bullet'); -- checks module 23
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000024' and body like '%Allow about 1 hour to write it.%' and body like '%You write four parts:%' and body like '%What helped most%'), 1::bigint, 'module 24 term review parts'); -- checks module 24
select tests.eq((select count(*) from public.training_questions where module_id = '7a000000-0000-4000-8000-000000000024' and prompt = 'How long should a term review take to write?'), 1::bigint, 'module 24 time question'); -- checks the new question
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000025' and body like '%This is most of the hour.%'), 1::bigint, 'module 25 tips'); -- checks module 25

-- The priority order: 28 comes before 14, drafting before term reviews, and the refresher last.
select tests.eq((select count(*) from public.training_modules a, public.training_modules b where a.id = '7a000000-0000-4000-8000-000000000028' and b.id = '7a000000-0000-4000-8000-000000000014' and a.position < b.position), 1::bigint, 'plans before effective tutoring'); -- checks 28 before 14
select tests.eq((select count(*) from public.training_modules a, public.training_modules b where a.id = '7a000000-0000-4000-8000-000000000019' and b.id = '7a000000-0000-4000-8000-000000000024' and a.position < b.position), 1::bigint, 'drafting before term reviews'); -- checks 19 before 24
select tests.eq((select count(*) from public.training_modules where id::text like '7a000000-0000-4000-8000-0000000000%' and position > (select position from public.training_modules where id = '7a000000-0000-4000-8000-000000000017')), 0::bigint, 'refresher last'); -- checks 17 is last

-- No lesson text uses short forms such as "it's" or "you'll" (Carla's rule).
select tests.eq((select count(*) from public.training_lessons where module_id in ('7a000000-0000-4000-8000-000000000026', '7a000000-0000-4000-8000-000000000027', '7a000000-0000-4000-8000-000000000028') and body ~* '\m(it''s|you''ll|don''t|can''t|doesn''t)\M'), 0::bigint, 'no short forms in new lessons'); -- checks wording

-- Running it again changes nothing.
select md5(string_agg(m.id::text || m.position, ',' order by m.id)) as mods_before from public.training_modules m \gset
select md5(string_agg(l.module_id::text || l.position || l.title || l.body, ',' order by l.module_id, l.position)) as lessons_before from public.training_lessons l \gset
select count(*) as questions_before from public.training_questions \gset
\ir ../migrations/20261121300100_training_plans_routine.sql
select tests.eq((select count(*) from (select md5(string_agg(m.id::text || m.position, ',' order by m.id)) as h from public.training_modules m) x where x.h = :'mods_before'), 1::bigint, 'running again keeps the order'); -- checks modules
select tests.eq((select count(*) from (select md5(string_agg(l.module_id::text || l.position || l.title || l.body, ',' order by l.module_id, l.position)) as h from public.training_lessons l) x where x.h = :'lessons_before'), 1::bigint, 'running again changes no lessons'); -- checks lessons
select tests.eq((select count(*) from public.training_questions), :questions_before::bigint, 'running again adds no questions'); -- checks questions

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  training plans and routine: all checks passed'
