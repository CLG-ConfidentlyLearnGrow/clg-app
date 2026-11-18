-- Training (module: training): Carla's additions of 18 Nov 2026.
--   * Three new modules for the starting course, done before a tutor's first
--     student: 26 Measurable goals, 27 The yearly and term plan, 28 The
--     weekly plan. They start as drafts, like the others.
--   * Module 11 gets a new first lesson, "The CLG session routine": the
--     session routine is the same every week; the content and how it is
--     presented change as the student develops and with how they are on the
--     day. Module 23's "Routine" bullet now points to it.
--   * Term reviews (modules 24 and 25): allow about 1 hour; go through every
--     goal (reached, in progress, changed or dropped); the work and the
--     direction; what helped most, including what the family reports from
--     home; then next term's focus and the recommendation.
--   * The module list follows Carla's priority order: safety 1 to 8, then
--     9 to 13 and 26 to 28, then 14 to 16, then 18 and 19 (drafting), 24 and
--     25 (term reviews), 20 to 23, and 17 (yearly refresher) last.
--
-- Each lesson change swaps one exact piece of text, so anything Carla has
-- changed in Training setup is kept (a swap that finds nothing changes
-- nothing). New modules, lessons and questions are only added once.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. The three new modules (drafts, compulsory, for tutors).
-- ---------------------------------------------------------------------------
insert into public.training_modules (id, title, summary, audience, stage, required, holds_matching, counts_toward_certified, minutes, renew_months, status, position) values -- adds the modules:
  ('7a000000-0000-4000-8000-000000000026', 'Measurable goals', 'How to write goals that you and the family can tell have been reached.', 'tutor', 'starting', true, false, true, 15, null, 'draft', 135), -- 26. Measurable goals
  ('7a000000-0000-4000-8000-000000000027', 'The yearly and term plan', 'Agreeing year goals with a new student, and breaking them into a plan for each term.', 'tutor', 'starting', true, false, true, 15, null, 'draft', 136), -- 27. The yearly and term plan
  ('7a000000-0000-4000-8000-000000000028', 'The weekly plan', 'What happens before, during and between sessions each week.', 'tutor', 'starting', true, false, true, 15, null, 'draft', 137) -- 28. The weekly plan
on conflict (id) do nothing; -- already added before: left as it is

-- Their lessons (only when the module has none yet).
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select v.mod::uuid, v.pos, v.title, v.body -- to its module, in order, with its heading and text
from (values -- the lessons (module, order, heading, text):
  ('7a000000-0000-4000-8000-000000000026', 1, 'Goals you can measure', $t$A goal is only useful if you and the family can tell when it has been reached. Every goal on a student's Progress page should say:
- What the student will be able to do (a skill, not a topic).
- How well (accuracy, independence or a grade).
- By when (a date, usually the end of term).
- How you will check (a quiz, a piece of marked work, a timed task).

## Examples
- Not measurable: "Get better at fractions". Measurable: "Add and subtract fractions with different denominators, 8 out of 10 correct without help, by week 8".
- Not measurable: "Improve essay writing". Measurable: "Write a paragraph with a topic sentence, two pieces of evidence and a link back to the question, by the end of term, checked against the school rubric".
- Not measurable: "More confident in maths". Measurable: "Attempt every question on a weekly practice sheet before asking for help, for four weeks in a row".

Confidence and effort goals can be measurable too: count what the student does.$t$),
  ('7a000000-0000-4000-8000-000000000027', 1, 'The yearly plan', $t$In the first three sessions, agree with the student (and family) where they want to be by the end of the school year.

Write two or three measurable year goals (module 26) on the Progress page, linked to the school curriculum and any upcoming assessments the family has added.$t$),
  ('7a000000-0000-4000-8000-000000000027', 2, 'The term plan', $t$At the start of each term, break the year goals into term goals: what needs to happen this term to stay on track.

- Add the term's school assessments as roadmap targets with their dates, with task sheets and rubrics if the family uploaded them.
- Use "Plan study steps for me" to spread the work out.
- Review the term plan at the end of term, ready for the term review.$t$),
  ('7a000000-0000-4000-8000-000000000028', 1, 'Each week', $t$The weekly plan is what happens in and between sessions:
- Before the session, check last week's next step, roadmap steps due and any notes from home.
- Plan the session using the CLG session routine (module 11).
- End with one next step. The app adds it to the roadmap automatically, due by the next session.
- Add any extra steps the student agreed to, with dates, so they and their parents can tick them off.$t$)
) as v(mod, pos, title, body) -- (the columns of the list above)
where not exists (select 1 from public.training_lessons l where l.module_id = v.mod::uuid); -- only for a module with no lessons yet

-- Their quiz questions (only when the module has none yet).
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select v.mod::uuid, v.pos, v.prompt, v.options, v.correct -- to its module, in order, with the question, choices and right answer
from (values -- the questions (module, order, question, choices, right answer):
  ('7a000000-0000-4000-8000-000000000026', 1, 'Which goal is measurable?', array['Be better at spelling', 'Spell 18 of the 20 Year 5 list words correctly in a weekly check, by week 9', 'Enjoy reading more', 'Work hard this term'], 2),
  ('7a000000-0000-4000-8000-000000000026', 2, 'What four things does every goal need?', array['What, how well, by when, and how you will check', 'A topic, a textbook, a worksheet and a test', 'The parent''s wish, the school''s report, the grade and the tutor''s name', 'Nothing, goals can be general'], 1),
  ('7a000000-0000-4000-8000-000000000027', 1, 'When do you agree a new student''s year goals?', array['By the end of the first three sessions', 'At the end of the year', 'Only if the family asks', 'Before you meet the student'], 1),
  ('7a000000-0000-4000-8000-000000000027', 2, 'Where do the term''s school assessments go?', array['In your own notes', 'On the Progress page, as roadmap targets with their dates', 'In a message to the family', 'Nowhere'], 2),
  ('7a000000-0000-4000-8000-000000000028', 1, 'What happens to the next step in your session summary?', array['Nothing', 'It becomes a roadmap step due by the next session', 'It is emailed to the school', 'It is deleted after a week'], 2),
  ('7a000000-0000-4000-8000-000000000028', 2, 'What do you check before each session?', array['Last week''s next step, roadmap steps due and notes from home', 'Only the time', 'The family''s invoices', 'Nothing, plan on the day'], 1)
) as v(mod, pos, prompt, options, correct) -- (the columns of the list above)
where not exists (select 1 from public.training_questions q where q.module_id = v.mod::uuid); -- only for a module with no questions yet

-- ---------------------------------------------------------------------------
-- 2. Module 11: a new first lesson on the CLG session routine.
-- ---------------------------------------------------------------------------
-- Moves module 11's lessons down one place to make room (only if the new lesson isn't there yet).
update public.training_lessons l set position = l.position + 1 -- moves each lesson down one
where l.module_id = '7a000000-0000-4000-8000-000000000011' -- in module 11
  and not exists (select 1 from public.training_lessons x where x.module_id = l.module_id and x.title = 'The CLG session routine'); -- before the new lesson is added

-- Adds the lesson in first place (only once).
insert into public.training_lessons (module_id, position, title, body) -- adds the lesson:
select '7a000000-0000-4000-8000-000000000011', 1, 'The CLG session routine', $t$Every CLG session follows the same routine, every week. What changes is the content, and how you present it, as the student develops and depending on how they are on the day.

## The routine (for a 1-hour session)
- 1. Check in (2 to 3 minutes): How has the week been? How are they today? Gauge their capacity for this session.
- 2. Warm-up recall (5 minutes): a few quick questions on earlier learning, from memory.
- 3. Review (5 minutes): last week's next step and any work from home or school.
- 4. New learning (15 to 20 minutes): explain, show, do one together (module 14).
- 5. Practice (15 to 20 minutes): the student does most of the work while you watch, prompt and give feedback.
- 6. Reflect and next step (5 minutes): What did they learn? Agree one clear next step.

Stretch or shrink parts 4 and 5 for longer or shorter sessions.

## Why the same routine?
A predictable routine lets students settle quickly and know what is expected. This matters even more for anxious students and those with learning needs. Your energy goes into the learning, not into deciding what happens next.

## What changes each week
The content, the difficulty, how much support you give, and the way you present it (examples, visuals, talking it through, practice questions). On a low-energy day, keep the routine but make the new learning smaller and the practice shorter.$t$ -- the lesson's text
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000011') -- module 11 is there
  and not exists (select 1 from public.training_lessons x where x.module_id = '7a000000-0000-4000-8000-000000000011' and x.title = 'The CLG session routine'); -- and the lesson isn't yet

-- Adds its quiz question at the end of module 11's quiz (only once).
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the question:
select '7a000000-0000-4000-8000-000000000011', -- to module 11,
  (select coalesce(max(q.position), 0) + 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000011'), -- after its last question,
  'Which is true of CLG sessions?', -- the question,
  array['Every session has a different structure to keep it interesting', 'The routine is the same every week; the content and how it is presented change', 'The student chooses the structure each week', 'Only the first session follows the routine'], -- the choices,
  2 -- and the right answer
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000011') -- module 11 is there
  and not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000011' and q.prompt = 'Which is true of CLG sessions?'); -- and the question isn't yet

-- ---------------------------------------------------------------------------
-- 3. Module 23: the "Routine" bullet points to the CLG session routine.
-- ---------------------------------------------------------------------------
update public.training_lessons l -- changes a lesson:
set body = replace(l.body, -- swaps one exact bullet:
  $t$- Routine: a predictable session shape helps anxious students settle.$t$, -- the old bullet
  $t$- Routine: keep to the CLG session routine every week (module 11). It helps anxious students settle.$t$) -- the new bullet
where l.module_id = '7a000000-0000-4000-8000-000000000023'; -- in module 23

-- ---------------------------------------------------------------------------
-- 4. Module 24: allow about 1 hour, and the new parts of a term review.
-- ---------------------------------------------------------------------------
update public.training_lessons l -- changes a lesson:
set body = replace(replace(l.body, -- swaps two exact pieces:
  $t$It is an optional paid service, so you only write one when the family has asked for it. You will get a notice$t$, -- the old opening
  $t$It is an optional paid service, so you only write one when the family has asked for it. Allow about 1 hour to write it. You will get a notice$t$), -- now with the time allowed
  $t$The app fills in each goal's skills at the start of term and now. You write three short parts:
- How the term went: what the student worked on and what improved, with one specific example.
- Focus for next term: the one or two things that matter most next.
- Your recommendation, and why: continue as now, change focus, more or fewer sessions, or a break.$t$, -- the old three parts
  $t$The app fills in each goal's skills at the start of term and now. You write four parts:
- The goals: go through each of the term's goals. Say which were reached, which are still in progress and how far along, and any that were changed or dropped, with why.
- The work and the direction: what the student worked on, with one or two specific examples, and where it is heading.
- What helped most: what made the biggest difference this term. Include anything the family or student reported doing outside sessions, such as practice at home, roadmap steps ticked off, or school results they uploaded.
- Focus for next term and your recommendation, and why: continue as now, change focus, more or fewer sessions, or a break.$t$) -- the new four parts
where l.module_id = '7a000000-0000-4000-8000-000000000024'; -- in module 24

-- The quiz answer about what goes in a review matches the new parts.
update public.training_questions q -- changes a question:
set options = array_replace(q.options, -- swaps one exact choice:
  'How the term went, the focus for next term, and your recommendation with why', -- the old right answer
  'Each goal (reached, in progress, changed or dropped), the work and direction, what helped most, and next term''s focus and recommendation') -- the new right answer
where q.module_id = '7a000000-0000-4000-8000-000000000024' and q.prompt = 'What do you write in a term review?'; -- module 24's question

-- A new quiz question: how long a review takes (only once).
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the question:
select '7a000000-0000-4000-8000-000000000024', -- to module 24,
  (select coalesce(max(q.position), 0) + 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000024'), -- after its last question,
  'How long should a term review take to write?', -- the question,
  array['10 minutes', 'About 1 hour', 'Half a day', 'It does not matter'], -- the choices,
  2 -- and the right answer
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000024') -- module 24 is there
  and not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000024' and q.prompt = 'How long should a term review take to write?'); -- and the question isn't yet

-- ---------------------------------------------------------------------------
-- 5. Module 25: two more tips for writing a review.
-- ---------------------------------------------------------------------------
update public.training_lessons l -- changes a lesson:
set body = l.body || $t$
- Before you start, reread the term's session summaries, the goals and roadmap, and any notes from home and uploads. This is most of the hour.
- Every goal you mention should be measurable (module 26), so the family can see the progress for themselves.$t$ -- adds the two tips at the end
where l.module_id = '7a000000-0000-4000-8000-000000000025' and l.title = 'Writing it well' -- module 25's lesson
  and l.body not like '%This is most of the hour.%'; -- only once

-- ---------------------------------------------------------------------------
-- 6. The module list follows the priority order. Only modules still in
-- their first place (number x 10) are moved, so any order Carla set
-- herself in Training setup is kept.
-- ---------------------------------------------------------------------------
update public.training_modules m -- changes a module's place in the list:
set position = v.pos -- to its new place
from (values -- (module number, new place):
  (9, 90), (10, 100), (11, 110), (12, 120), (13, 130), -- the app, the session, summaries and the first three sessions
  (14, 140), (15, 150), (16, 160), -- effective tutoring
  (18, 170), (19, 180), -- drafting (before the first drafting job)
  (24, 190), (25, 200), -- term reviews (before the first term review)
  (20, 210), (21, 220), (22, 230), (23, 240), -- families and learning support (first term)
  (17, 250) -- the yearly refresher, last
) as v(n, pos) -- (the columns of the list above)
where m.id = ('7a000000-0000-4000-8000-0000000000' || lpad(v.n::text, 2, '0'))::uuid -- the module with that number
  and m.position = v.n * 10; -- still in its first place
