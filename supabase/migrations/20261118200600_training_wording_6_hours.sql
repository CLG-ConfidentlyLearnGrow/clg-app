-- Training (module: training): Carla's later rules in the draft lessons
-- (16 Nov 2026), fixing wording that 20261118200100_training_review_edits.sql
-- loaded before she gave them:
--   * session summaries are due within 6 hours of the session ending
--     (families are still promised 48 hours);
--   * only a finish more than 15 minutes early is recorded.
--
-- Only DRAFT modules change, and only before the 15-minute split
-- (20261118200700), which moves these lessons into new modules. Each change
-- swaps one exact piece of text, so edits made elsewhere are kept.
-- Safe to run more than once.

-- Module 5, lesson 3 (the summary): 6 hours, not 48.
update public.training_lessons l -- changes a lesson:
set body = replace(l.body, -- swaps one exact paragraph:
  $t$Write it straight after the session if you can, and always within 48 hours. CLG promises families this.$t$, -- the old timing
  $t$Write it straight after the session, and always within 6 hours of the session ending. Families are promised it within 48 hours, and the 6 hours gives CLG time to follow up if one is missing.$t$) -- the new timing
where l.module_id = '7a000000-0000-4000-8000-000000000005' and l.position = 3 -- module 5, lesson 3
  and exists (select 1 from public.training_modules m where m.id = l.module_id and m.status = 'draft') -- only while the module is a draft
  and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025'); -- and before the 15-minute split

-- Module 5, lesson 2 (signing on and off): only a finish more than 15 minutes early is recorded.
update public.training_lessons l -- changes a lesson:
set body = replace(l.body, -- swaps one exact bullet point:
  $t$- Families are always charged the booked time. If a session finishes early or late, record the real end time anyway. CLG checks these under Times to check.$t$, -- the old rule
  $t$- Families are always charged the booked time. If a session finishes more than 15 minutes early, or runs over, record the real end time. CLG checks these under Times to check. Finishing up to 15 minutes early counts as on time.$t$) -- the new rule
where l.module_id = '7a000000-0000-4000-8000-000000000005' and l.position = 2 -- module 5, lesson 2
  and exists (select 1 from public.training_modules m where m.id = l.module_id and m.status = 'draft') -- only while the module is a draft
  and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025'); -- and before the 15-minute split

-- Module 5 quiz: the summary question's right answer is now 6 hours.
update public.training_questions q -- changes a question:
set options = array_replace(q.options, -- swaps one exact choice:
  'Straight after the session if possible, and always within 48 hours', -- the old right answer
  'Within 6 hours of the session ending') -- the new right answer
where q.module_id = '7a000000-0000-4000-8000-000000000005' and q.prompt = 'When must the session summary be written?' -- module 5's summary question
  and exists (select 1 from public.training_modules m where m.id = q.module_id and m.status = 'draft') -- only while the module is a draft
  and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025'); -- and before the 15-minute split
