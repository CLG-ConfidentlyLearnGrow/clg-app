-- Training content: checks Carla's 16 Nov 2026 review reached the draft
-- modules and handbook pages, the training is split into 25 draft modules
-- of 15 minutes, running the
-- changes again doesn't double anything up, and a published module is
-- never changed by them. Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Acts as the database itself.
select tests.claims(null);

-- There are 25 modules, all drafts of 15 minutes, numbered in order.
select tests.eq((select count(*) from public.training_modules where id::text like '7a000000-0000-4000-8000-0000000000%' and status = 'draft' and minutes = 15), 25::bigint, '25 draft modules of 15 minutes'); -- checks the split
-- The safety modules (1 to 8) and the refresher (17) hold new matches; the others don't.
select tests.eq((select count(*) from public.training_modules where id::text like '7a000000-0000-4000-8000-0000000000%' and holds_matching), 9::bigint, 'modules 1-8 and 17 hold new matches'); -- checks the matching hold
-- Every module has at least one lesson and two quiz questions.
select tests.eq((select count(*) from public.training_modules m where m.id::text like '7a000000-0000-4000-8000-0000000000%' and (select count(*) from public.training_lessons l where l.module_id = m.id) >= 1 and (select count(*) from public.training_questions q where q.module_id = m.id) >= 2), 25::bigint, 'every module has lessons and a quiz'); -- checks content
-- Lessons moved to the right place: "Honest work" is in module 4, the first three sessions in module 13.
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000004' and title = 'Honest work'), 1::bigint, 'honest work in module 4'); -- checks a move
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000013' and title = 'Your first three sessions with a new student'), 1::bigint, 'first three sessions in module 13'); -- checks a move
-- No module has two lessons or questions in the same place.
select tests.eq((select count(*) from (select module_id, position from public.training_lessons group by 1, 2 having count(*) > 1) d), 0::bigint, 'no lesson places doubled'); -- checks lesson order
select tests.eq((select count(*) from (select module_id, position from public.training_questions group by 1, 2 having count(*) > 1) d), 0::bigint, 'no question places doubled'); -- checks quiz order

-- No "Carla to check" notes are left in the draft lessons or handbook pages.
select tests.eq((select count(*) from public.training_lessons where body like '%Carla to check%'), 0::bigint, 'no open questions in lessons'); -- checks lessons
select tests.eq((select count(*) from public.handbook_pages where body like '%Carla to check%'), 0::bigint, 'no open questions in handbook pages'); -- checks handbook pages

-- Carla's answers are in place.
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000005' and body like '%only through the CLG App%' and body not like '%Teams%'), 1::bigint, 'contact only through the app'); -- answer 1
select tests.eq((select count(*) from public.handbook_pages where id = '7b000000-0000-4000-8000-000000000001' and body like '%Phone CLG (Lauren first, or Carla), who will call the parent%'), 1::bigint, 'phone CLG to reach a parent'); -- answer 2
select tests.eq((select count(*) from public.handbook_pages where id = '7b000000-0000-4000-8000-000000000005' and body like '%under 12 are dropped off and collected by a parent%'), 1::bigint, 'under-12s collected by a parent'); -- answer 5
select tests.eq((select count(*) from public.handbook_pages where id = '7b000000-0000-4000-8000-000000000008' and body like '%Lauren, CLG''s Student Success Coordinator, is your first point of contact%'), 1::bigint, 'Lauren first point of contact'); -- answer 6
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000004' and title = 'Honest work' and body like '%Not a sentence, a paragraph or a conclusion%'), 1::bigint, 'never write the work'); -- integrity rule
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000012' and body like '%within 6 hours of the session ending%'), 1::bigint, 'summary within 6 hours'); -- Carla's later rule
select tests.eq((select count(*) from public.training_lessons where body like '%9pm and 6am%'), 0::bigint, 'quiet hours say 5am'); -- answer 7

-- Carla's later rules reached the quiz too: 6 hours, and the essay-writing question sits in module 4.
select tests.eq((select count(*) from public.training_questions where 'Within 6 hours of the session ending' = any(options) and module_id = '7a000000-0000-4000-8000-000000000012'), 1::bigint, 'summary question says 6 hours'); -- checks the 6-hour answer
select tests.eq((select count(*) from public.training_questions where options::text like '%within 48 hours%'), 0::bigint, 'no quiz answer says 48 hours'); -- checks the old answer is gone
select tests.eq((select count(*) from public.training_questions where module_id = '7a000000-0000-4000-8000-000000000004'), 2::bigint, 'module 4 has its 2 questions'); -- checks the honest-work quiz

-- Remember how much there is now, then run both changes again.
select count(*) as lessons_before from public.training_lessons \gset
select count(*) as questions_before from public.training_questions \gset
select md5(string_agg(body, '' order by module_id, position)) as bodies_before from public.training_lessons \gset
\ir ../migrations/20261118200600_training_wording_6_hours.sql
\ir ../migrations/20261118200700_training_15_minute_modules.sql
-- Nothing was added or changed the second time.
select tests.eq((select count(*) from public.training_lessons), :lessons_before::bigint, 'running again adds no lessons'); -- checks lessons
select tests.eq((select count(*) from public.training_questions), :questions_before::bigint, 'running again adds no questions'); -- checks questions
select tests.eq((select count(*) from (select md5(string_agg(body, '' order by module_id, position)) as h from public.training_lessons) x where x.h = :'bodies_before'), 1::bigint, 'running again changes no lesson text'); -- checks lesson text

-- A published module is never touched: give module 25 other words, publish it, and run again.
update public.training_lessons set body = 'Published text.' where module_id = '7a000000-0000-4000-8000-000000000025'; -- module 25's lesson gets other text
delete from public.training_questions where module_id = '7a000000-0000-4000-8000-000000000025'; -- and loses its questions
update public.training_modules set status = 'published' where id = '7a000000-0000-4000-8000-000000000025'; -- and module 25 is published
\ir ../migrations/20261118200700_training_15_minute_modules.sql
select tests.eq((select count(*) from public.training_lessons where module_id = '7a000000-0000-4000-8000-000000000025' and body = 'Published text.'), 1::bigint, 'a published module''s lessons are left alone'); -- checks nothing was changed
select tests.eq((select count(*) from public.training_questions where module_id = '7a000000-0000-4000-8000-000000000025'), 0::bigint, 'nothing is added to a published module'); -- checks nothing was added

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  training review content: all checks passed'
