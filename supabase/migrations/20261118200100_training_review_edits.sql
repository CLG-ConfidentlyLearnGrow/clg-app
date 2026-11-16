-- Training (module: training): Carla's review of the seven draft modules
-- and the draft tutor handbook (16 Nov 2026).
--
-- What this changes, from Carla's answers to the 8 review questions:
--   * All tutor contact with families goes through the CLG App (summaries,
--     comments, replies to feedback notes, offering another session time).
--     Never phone, text, personal email or social media.
--   * A tutor who needs to reach a parent urgently phones CLG, who calls
--     the parent (000 first in an emergency).
--   * Wait 15 minutes before recording a no-show.
--   * Students under 12 are dropped off and collected by a parent.
--   * Lauren is tutors' first point of contact. Carla can see those
--     contacts and help, and Lauren can see Carla's contacts with tutors.
--   * Tutors never write any of the student's work (academic integrity).
--   * Summaries are due within 6 hours of the session ending (families are
--     promised 48 hours), and only a finish more than 15 minutes early is
--     recorded (Carla's later message, 16 Nov 2026).
-- Plus the additions from the review doc: telling CLG even when unsure,
-- what to write down, no private tutoring, blocking a match, not keeping
-- copies, medical details in notes, Requests and Blocks in the app tour,
-- summaries within 6 hours, honest session times, the first three
-- sessions and building independence.
--
-- Only DRAFT modules and pages are changed, and module changes only run
-- before the 15-minute split (20261118200200), which moves these lessons. If Carla has already published
-- one, it is left exactly as it is. Each change swaps one exact piece of
-- text, or adds text only if it isn't there yet, so edits made in Admin >
-- Training elsewhere in a lesson are kept, and running this file again
-- changes nothing.
--
-- Safe to run more than once. Run after 20261116300300_training_starter_content.sql.

-- ---------------------------------------------------------------------------
-- Module 1: Child safety and reporting.
-- ---------------------------------------------------------------------------

-- Lesson 2 (the three steps): add "tell CLG even if you're unsure" at the end.
update public.training_lessons l -- changes a lesson:
set body = l.body || E'\n\n' || $t$Not sure it's serious enough? Tell CLG anyway with the red Child safety button. Small worries can add up, and the Child Safety Officer can see the whole picture.$t$ -- adds the new paragraph at the end
where l.module_id = '7a000000-0000-4000-8000-000000000001' and l.position = 2 -- module 1, lesson 2
  and position('Not sure it''s serious enough?' in l.body) = 0 -- only if it isn't there yet
  and exists (select 1 from public.training_modules m where m.id = l.module_id and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025'); -- only while the module is a draft, and before the 15-minute split

-- New quiz question: what to write down.
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds a question:
select '7a000000-0000-4000-8000-000000000001'::uuid, -- to module 1,
  (select coalesce(max(q.position), 0) + 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000001'), -- after its last question,
  'After a child tells you something worrying, what do you write down?', -- the question,
  array['Your opinion of what is happening', 'The facts: what you saw or heard, in the child''s own words, with the date and time', 'Nothing, in case it is wrong', 'A summary for the family'], -- the choices,
  2 -- the facts, in the child's words
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000001' and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025') -- only while the module is a draft, and before the 15-minute split
  and not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000001' and q.prompt like 'After a child tells you something worrying%'); -- only once

-- ---------------------------------------------------------------------------
-- Module 2: Code of conduct and professional boundaries.
-- ---------------------------------------------------------------------------

-- Lesson 2 (boundaries): contact only through the app (Carla: "No, all
-- contact through the app"), and contact outside the app goes to CLG.
update public.training_lessons l -- changes a lesson:
set body = replace(replace(l.body, -- swaps two exact lines:
  $t$- Contact students and families only through CLG's channels (the app and CLG's Teams). Don't use personal phone numbers, personal email or social media. (Carla to check: CLG's exact rule for parents' phone contact.)$t$, -- the old contact rule,
  $t$- Contact students and families only through the CLG App: session summaries, comments, replies to feedback notes and offering another session time. Never use phone, text, personal email or social media. Anything else goes through CLG, starting with Lauren.$t$), -- becomes the app-only rule;
  $t$- If a student contacts you outside CLG's channels, don't reply privately. Tell CLG.$t$, -- and the old "outside CLG's channels" line
  $t$- If a student or parent contacts you outside the app, don't reply. Tell CLG.$t$) -- becomes "outside the app"
where l.module_id = '7a000000-0000-4000-8000-000000000002' and l.position = 2 -- module 2, lesson 2
  and exists (select 1 from public.training_modules m where m.id = l.module_id and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025'); -- only while the module is a draft, and before the 15-minute split

-- Lesson 2: add "no private tutoring" and "Block a student".
update public.training_lessons l -- changes a lesson:
set body = l.body || E'\n' || $t$- Never arrange tutoring privately with a CLG family, even if they ask. CLG's terms promise families this, and it keeps everyone covered by child safety checks.
- If a match doesn't feel right, use Block a student and give a reason. Only CLG sees it, and CLG will talk it through with you.$t$ -- adds two bullet points at the end
where l.module_id = '7a000000-0000-4000-8000-000000000002' and l.position = 2 -- module 2, lesson 2
  and position('Never arrange tutoring privately' in l.body) = 0 -- only if they aren't there yet
  and exists (select 1 from public.training_modules m where m.id = l.module_id and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025'); -- only while the module is a draft, and before the 15-minute split

-- New lesson 4: honest work (Carla: "You never write the work").
insert into public.training_lessons (module_id, position, title, body) -- adds a lesson:
select '7a000000-0000-4000-8000-000000000002'::uuid, 4, 'Honest work', $t$You never write the student's work. Not a sentence, a paragraph or a conclusion.

Schools have rules about how much help students can have, and the student may have to declare it. If the work isn't theirs, they can lose marks or face an integrity investigation, and CLG's name suffers. It also isn't real learning: the student only grows by doing the thinking and the writing themselves.

- In assessment drafting, you suggest, check and correct. You never write any part of the work.
- In sessions, help the student do the thinking. Don't do homework or assessments for them.
- Record session times honestly. Families are always charged the booked time.$t$ -- the lesson's heading and text
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000002' and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025') -- only while the module is a draft, and before the 15-minute split
  and not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000002' and l.position = 4); -- only if there's no lesson 4 yet

-- New quiz question: contact through the app.
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds questions:
select '7a000000-0000-4000-8000-000000000002'::uuid, -- to module 2,
  (select coalesce(max(q.position), 0) from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000002') + v.n, -- after its last question,
  v.prompt, v.options, v.correct -- the question, choices and right answer
from (values -- the new questions:
  (1, 'A parent asks for your mobile number so they can text you about sessions. What do you do?', array['Give it to them, it''s quicker', 'Explain that all contact goes through the CLG App, and let Lauren know', 'Give them your personal email instead', 'Ask the student to pass messages on'], 2) -- through the app
) as v(n, prompt, options, correct) -- (each question's order, words, choices and right answer)
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000002' and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025') -- only while the module is a draft, and before the 15-minute split
  and not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000002' and q.prompt like 'A parent asks for your mobile number%'); -- only once

-- ---------------------------------------------------------------------------
-- Module 3: Privacy and student information.
-- ---------------------------------------------------------------------------

-- Lesson 2: no private copies, and medical details in notes go to CLG.
update public.training_lessons l -- changes a lesson:
set body = l.body || E'\n' || $t$- Don't keep your own lists, spreadsheets or copies of student information. The app keeps what's needed and deletes old records automatically.
- If a family writes medical details or a safety concern in an app note, don't reply in the note. Tell CLG, who will move it somewhere protected.$t$ -- adds two bullet points at the end
where l.module_id = '7a000000-0000-4000-8000-000000000003' and l.position = 2 -- module 3, lesson 2
  and position('Don''t keep your own lists' in l.body) = 0 -- only if they aren't there yet
  and exists (select 1 from public.training_modules m where m.id = l.module_id and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025'); -- only while the module is a draft, and before the 15-minute split

-- ---------------------------------------------------------------------------
-- Module 4: How the CLG app works and where to go.
-- ---------------------------------------------------------------------------

-- Lesson 3 (where to go when): add Requests, Blocks and who to contact,
-- just before the notices line. Quiet hours stay 9pm to 5am.
update public.training_lessons l -- changes a lesson:
set body = replace(l.body, -- swaps one exact line:
  $t$- Notices from CLG: Sessions, then Notices.$t$, -- the notices line
  $t$- A family asks for an extra session before a test: Sessions, then Requests.
- A match doesn't feel right: Sessions, then Blocks.
- A question about sessions, bookings or families: Lauren, CLG's Student Success Coordinator, is your first point of contact.
- Notices from CLG: Sessions, then Notices.$t$) -- gets three new lines in front of it
where l.module_id = '7a000000-0000-4000-8000-000000000004' and l.position = 3 -- module 4, lesson 3
  and position('Sessions, then Requests' in l.body) = 0 -- only if they aren't there yet
  and exists (select 1 from public.training_modules m where m.id = l.module_id and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025'); -- only while the module is a draft, and before the 15-minute split

-- Lesson 3: make sure the quiet hours read 9pm to 5am (Carla, 16 Nov 2026).
update public.training_lessons l -- changes a lesson:
set body = replace(l.body, 'between 9pm and 6am', 'between 9pm and 5am') -- the old hours become the new ones
where l.module_id = '7a000000-0000-4000-8000-000000000004' -- any lesson in module 4
  and position('between 9pm and 6am' in l.body) > 0 -- only where the old hours appear
  and exists (select 1 from public.training_modules m where m.id = l.module_id and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025'); -- only while the module is a draft, and before the 15-minute split

-- ---------------------------------------------------------------------------
-- Module 5: Running a session and writing the summary.
-- ---------------------------------------------------------------------------

-- Lesson 2 (signing on and off): families pay the booked time; only a
-- finish more than 15 minutes early (or running over) is recorded.
update public.training_lessons l -- changes a lesson:
set body = l.body || E'\n' || $t$- Families are always charged the booked time. If a session finishes more than 15 minutes early, or runs over, record the real end time. CLG checks these under Times to check. Finishing up to 15 minutes early counts as on time.
- If a student doesn't turn up, wait 15 minutes (online or at the library), then record it as a no-show. CLG follows up with the family.$t$ -- adds two bullet points at the end
where l.module_id = '7a000000-0000-4000-8000-000000000005' and l.position = 2 -- module 5, lesson 2
  and position('always charged the booked time' in l.body) = 0 -- only if they aren't there yet
  and exists (select 1 from public.training_modules m where m.id = l.module_id and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025'); -- only while the module is a draft, and before the 15-minute split

-- Lesson 3 (the summary): within 6 hours of the session ending, with one
-- clear next step. Families are promised it within 48 hours.
update public.training_lessons l -- changes a lesson:
set body = replace(l.body, -- swaps one exact line:
  $t$Write it yourself, in plain words a parent can follow.$t$, -- the "write it yourself" line
  $t$Write it straight after the session, and always within 6 hours of the session ending. Families are promised it within 48 hours, and the 6 hours gives CLG time to follow up if one is missing. End every summary with one clear next step, written so the student knows exactly what to do.

Write it yourself, in plain words a parent can follow.$t$) -- gets the timing paragraph in front of it
where l.module_id = '7a000000-0000-4000-8000-000000000005' and l.position = 3 -- module 5, lesson 3
  and position('within 6 hours of the session ending' in l.body) = 0 -- only if it isn't there yet
  and exists (select 1 from public.training_modules m where m.id = l.module_id and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025'); -- only while the module is a draft, and before the 15-minute split

-- New lesson 4: the first three sessions with a new student.
insert into public.training_lessons (module_id, position, title, body) -- adds a lesson:
select '7a000000-0000-4000-8000-000000000005'::uuid, 4, 'Your first three sessions with a new student', $t$Every new student starts with at least three sessions. Use them to get to know the student before you push ahead.

- Session 1: get to know them. Ask about school, what they enjoy, what feels hard and what they want to get better at. Look at their goals and any uploads on the Progress page.
- Session 1 or 2: find their level. Use a few short questions or a task to see what they can already do. Start a little below where you think they are, so they feel some success.
- By session 3: agree two or three goals with the student, linked to what they're learning at school, and add them to the Progress page.
- After sessions 1 and 2, the app asks you and the family how it went. Answer honestly. It helps CLG fix small problems early.$t$ -- the lesson's heading and text
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000005' and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025') -- only while the module is a draft, and before the 15-minute split
  and not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000005' and l.position = 4); -- only if there's no lesson 4 yet

-- New quiz question: when the summary is due (6 hours).
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds a question:
select '7a000000-0000-4000-8000-000000000005'::uuid, -- to module 5,
  (select coalesce(max(q.position), 0) + 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000005'), -- after its last question,
  'When must the session summary be written?', -- the question,
  array['By the end of the week', 'Within 6 hours of the session ending', 'Only when the family asks', 'Before the next session'], -- the choices,
  2 -- within 6 hours
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000005' and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025') -- only while the module is a draft, and before the 15-minute split
  and not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000005' and q.prompt = 'When must the session summary be written?'); -- only once

-- ---------------------------------------------------------------------------
-- Module 6: Effective tutoring practice.
-- ---------------------------------------------------------------------------

-- New lesson 4: building confidence and independence.
insert into public.training_lessons (module_id, position, title, body) -- adds a lesson:
select '7a000000-0000-4000-8000-000000000006'::uuid, 4, 'Building confidence and independence', $t$CLG stands for Confidently Learn and Grow. Our aim is a student who can learn without us.

- Ask the student to explain their thinking out loud, and to say how they will check their answer.
- Before helping, ask "What have you tried?" and "What could you try next?"
- Name the strategy that worked, so they can use it again on their own.
- Point out progress against their goals, using their own earlier work.
- Hand over a little more each week: hints instead of answers, then just a nudge.

The EEF finds that teaching students to plan, monitor and evaluate their own learning (metacognition) adds about seven months' progress: https://educationendowmentfoundation.org.uk/education-evidence/teaching-learning-toolkit/metacognition-and-self-regulation$t$ -- the lesson's heading and text
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000006' and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025') -- only while the module is a draft, and before the 15-minute split
  and not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000006' and l.position = 4); -- only if there's no lesson 4 yet

-- ---------------------------------------------------------------------------
-- Module 7: Yearly refresher. Its first quiz question now matches the
-- handbook's "running late" page (tell the family through the app).
-- ---------------------------------------------------------------------------
update public.training_questions q -- changes a question:
set options = array_replace(q.options, -- swaps one exact choice:
  'Message the family through CLG''s channels and tell CLG as soon as you know', -- the old wording
  'Let the family know through the app and tell CLG as soon as you know') -- the new wording
where q.module_id = '7a000000-0000-4000-8000-000000000007' and q.position = 1 -- module 7, question 1
  and exists (select 1 from public.training_modules m where m.id = q.module_id and m.status = 'draft') and not exists (select 1 from public.training_modules s where s.id = '7a000000-0000-4000-8000-000000000025'); -- only while the module is a draft, and before the 15-minute split

-- ---------------------------------------------------------------------------
-- Handbook pages (drafts only).
-- ---------------------------------------------------------------------------

-- "Something's happened": urgent contact, no-show wait, technology problems.
update public.handbook_pages h -- changes a page:
set body = replace(replace(replace(h.body, -- swaps three exact lines:
  $t$- Contact the parent through CLG's channels, then tell CLG. (Carla to check: how tutors reach a parent urgently.)$t$, -- the old urgent-contact line
  $t$- Phone CLG (Lauren first, or Carla), who will call the parent. Don't phone or text the parent yourself.$t$), -- becomes "phone CLG";
  $t$ (Carla to check: the wait time.)$t$, ''), -- the no-show wait is confirmed at 15 minutes;
  $t$If that fails, contact the family through CLG's channels and tell CLG.$t$, -- the old tech-problem line
  $t$If that fails, let the family know through the app and tell CLG.$t$) -- becomes "through the app"
where h.id = '7b000000-0000-4000-8000-000000000001' and h.status = 'draft'; -- only while the page is a draft

-- "Running late, sick or can't make it": through the app, Lauren first.
update public.handbook_pages h -- changes a page:
set body = replace(replace(h.body, -- swaps two exact lines:
  $t$- Message the family through CLG's channels as soon as you know, with your new arrival time.$t$, -- the old "message the family" line
  $t$- Let the family know through the app as soon as you know, with your new arrival time.$t$), -- becomes "through the app";
  $t$- Tell CLG. (Carla to check: whether tutors message families directly or CLG does.)$t$, -- the old "tell CLG" line
  $t$- Tell CLG, starting with Lauren. If it's less than an hour before the session, phone CLG.$t$) -- becomes "Lauren first"
where h.id = '7b000000-0000-4000-8000-000000000003' and h.status = 'draft'; -- only while the page is a draft

-- "In-person sessions at libraries": under-12s are dropped off and collected.
update public.handbook_pages h -- changes a page:
set body = replace(h.body, -- swaps one exact line:
  $t$- At the end, make sure the student is collected or leaves as the family arranged. (Carla to check: CLG's rule for collecting younger students.)$t$, -- the old line
  $t$- Students under 12 are dropped off and collected by a parent, who stays nearby. Older students leave as the family arranged.
- Never leave the library with a student, or give a student a lift.$t$) -- becomes the confirmed rule
where h.id = '7b000000-0000-4000-8000-000000000005' and h.status = 'draft'; -- only while the page is a draft

-- "Who to contact at CLG": Lauren first, Carla can see, all family contact through the app.
update public.handbook_pages h -- changes a page:
set body = replace(h.body, -- swaps one exact line:
  $t$- Sessions, bookings and families: CLG admin. (Carla to check: the best contact and hours.)$t$, -- the old line
  $t$- Sessions, bookings and families: Lauren, CLG's Student Success Coordinator, is your first point of contact (mostly Mondays and Thursdays). Carla can see these contacts and helps when time permits, and Lauren can see Carla's contacts with tutors, so you never have to repeat yourself.
- A parent needs to be reached urgently (for example a student is unwell): phone CLG, who will call the parent. Call 000 first in an emergency.
- Families: all contact goes through the app (session summaries, comments, replies to feedback notes, offering another session time). Never phone, text, email or message a family yourself.$t$) -- becomes the confirmed contacts
where h.id = '7b000000-0000-4000-8000-000000000008' and h.status = 'draft'; -- only while the page is a draft
