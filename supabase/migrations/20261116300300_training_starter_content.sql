-- Training (module: training): a first draft of the starting course and
-- the tutor handbook, for Carla to edit (16 Nov 2026).
--
-- Everything here is added as a DRAFT, so tutors see nothing until an admin
-- checks it and publishes it (Training setup in the admin menu). It is
-- added only once: if a module or page with the same id already exists, it
-- is left as it is, so running this file again never overwrites edits.
--
-- Sources: CLG's Child safety concern page and policy drafts, the CLG app
-- guide for tutors (docs/guides/tutors.md), SA DCP mandated notifier
-- guidance, the National Principles for Child Safe Organisations, and the
-- EEF's tutoring and feedback guidance. Lines marked "Carla to check" need
-- her decision before publishing.
--
-- Safe to run more than once. Run after 20261116300200_billing_training_pay.sql.

-- ---------------------------------------------------------------------------
-- The modules (drafts).
-- ---------------------------------------------------------------------------
insert into public.training_modules (id, title, summary, audience, stage, required, holds_matching, counts_toward_certified, minutes, renew_months, status, position) values -- adds seven draft modules:
  ('7a000000-0000-4000-8000-000000000001', 'Child safety and reporting', 'Keeping children safe at CLG: what to look for, what to do if you are worried, and your duty to report.', 'everyone', 'starting', true, true, false, 45, null, 'draft', 10), -- 1. child safety (holds new matches)
  ('7a000000-0000-4000-8000-000000000002', 'Code of conduct and professional boundaries', 'How CLG staff behave with students and families, online and in person.', 'everyone', 'starting', true, true, false, 30, null, 'draft', 20), -- 2. code of conduct (holds new matches)
  ('7a000000-0000-4000-8000-000000000003', 'Privacy and student information', 'What student information you can see, how to keep it safe, and what to do if something goes wrong.', 'everyone', 'starting', true, true, false, 30, null, 'draft', 30), -- 3. privacy (holds new matches)
  ('7a000000-0000-4000-8000-000000000004', 'How the CLG app works and where to go', 'A tour of the app for tutors: your dashboard, sessions, notices, training and the handbook.', 'tutor', 'starting', true, false, true, 45, null, 'draft', 40), -- 4. the app tour
  ('7a000000-0000-4000-8000-000000000005', 'Running a session and writing the summary', 'Before, during and after a CLG session, including signing on and off and the session summary.', 'tutor', 'starting', true, false, true, 45, null, 'draft', 50), -- 5. running a session
  ('7a000000-0000-4000-8000-000000000006', 'Effective tutoring practice', 'What the research says works in tutoring, and how to use it in your sessions.', 'tutor', 'starting', true, false, true, 60, null, 'draft', 60), -- 6. effective tutoring
  ('7a000000-0000-4000-8000-000000000007', 'Yearly refresher: safety, privacy and the handbook', 'A short refresher each year: the key steps, and finding the answers in the handbook.', 'everyone', 'refresher', true, true, false, 20, 12, 'draft', 70) -- 7. the yearly refresher (holds new matches)
on conflict (id) do nothing; -- already added before: left as it is

-- ---------------------------------------------------------------------------
-- Lessons. Each insert adds one module's lessons, only if that module has
-- none yet (so edits are never doubled up).
-- ---------------------------------------------------------------------------

-- Module 1: Child safety and reporting.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000001'::uuid, v.pos, v.title, v.body from (values -- for module 1:
  (1, 'Why child safety comes first', $t$Every CLG tutor and staff member helps keep children and young people safe. CLG follows the National Principles for Child Safe Organisations, which expect everyone who works with children to know the signs of harm and what to do.

Your Working With Children Check and RRHAN-EC training are the starting point. This module explains how CLG does things, so you know exactly where to go.

## What harm can look like
- Physical harm: unexplained injuries, or injuries that don't match the story.
- Emotional harm: a child who seems very anxious, withdrawn, or frightened of someone.
- Sexual abuse or grooming: secrets, gifts, or an adult seeking time alone with a child.
- Neglect: a child often hungry, unwashed, unwell without care, or left alone.
- Online harm: someone contacting a child in ways that make them uncomfortable.

You don't need proof. A reasonable suspicion is enough to act.$t$),
  (2, 'The three steps: 000, report, tell CLG', $t$If you are worried about a child, the order is always:

## 1. Is a child in immediate danger? Call 000 now.
Police or ambulance come first, before anything else.

## 2. Report to the child protection line for the child's state.
In South Australia that is the Child Abuse Report Line (CARL): 13 14 78, open 24/7. Serious concerns must be phoned, not sent online. For non-urgent concerns, mandated notifiers can use e-CARL: https://ecarl.sa.gov.au/

## 3. Tell CLG.
Press the red Child safety button at the top of every page in the app. Your concern goes to CLG's Child Safety Officer. If your concern is about the Child Safety Officer, choose to send it to the deputy instead.

Write down what you saw or heard, in the child's own words where you can, with the date and time.$t$),
  (3, 'Your duty to report', $t$In South Australia, people who provide education services to children are mandated notifiers under the Children and Young People (Safety) Act 2017. That includes CLG tutors.

If you suspect on reasonable grounds that a child is, or may be, at risk of harm, and you formed that suspicion through your work, you must report it to the Department for Child Protection as soon as reasonably practicable. Telling CLG does not replace your report.

CLG's rule is simple: every worker reports, then tells CLG. You will never be in trouble for raising a concern in good faith.$t$),
  (4, 'If a child tells you something', $t$If a child tells you they are being hurt:
- Stay calm and listen. Let them talk in their own words.
- Don't ask leading questions, and don't investigate.
- Don't promise to keep it a secret. Say you need to tell people whose job is to help keep them safe.
- Tell them they did the right thing by telling you.
- Write down what they said, as soon as you can, in their words.
- Then follow the three steps: 000 if in danger, report to CARL, tell CLG.

Look after yourself too. Hearing this is hard. You can talk to CLG's Child Safety Officer about how you are going.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000001'); -- only if the module has no lessons yet

-- Module 2: Code of conduct and professional boundaries.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000002'::uuid, v.pos, v.title, v.body from (values -- for module 2:
  (1, 'Professional at all times', $t$CLG's Code of Conduct sets out how we work with students and families. The key points:
- Treat every student with respect, patience and care, whatever their age, background or ability.
- Be on time, prepared, and focused on the student's learning.
- Keep your language, clothing and online background appropriate.
- Never use alcohol or drugs before or during work.
- Speak about students, families and colleagues respectfully, including outside work.

Read the full Code of Conduct linked in the handbook.$t$),
  (2, 'Boundaries with students', $t$Clear boundaries protect students and you.
- Contact students and families only through CLG's channels (the app and CLG's Teams). Don't use personal phone numbers, personal email or social media. (Carla to check: CLG's exact rule for parents' phone contact.)
- Don't connect with students on social media or gaming platforms.
- Don't give gifts, lifts or money, or accept anything more than a small token gift. Tell CLG if offered.
- In-person sessions happen only at public libraries CLG has confirmed, in open areas, inside opening hours. Sessions anywhere else are arranged by CLG only.
- Never be alone with a student behind a closed door.
- If a student contacts you outside CLG's channels, don't reply privately. Tell CLG.$t$),
  (3, 'Online sessions', $t$- Use the Teams link CLG made for the session. Don't create your own links or meetings.
- Keep your camera on, in a quiet, neutral space.
- Don't record sessions unless CLG has arranged it with the family's consent.
- If a student's camera shows something worrying, or someone behaves inappropriately, end the session calmly and tell CLG straight away.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000002'); -- only if the module has no lessons yet

-- Module 3: Privacy and student information.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000003'::uuid, v.pos, v.title, v.body from (values -- for module 3:
  (1, 'Only what you need', $t$CLG holds children's information, so privacy matters a great deal. The app only shows you students you are matched with, and only what you need to tutor them. You never see financial details.

Privacy law (the Privacy Act 1988 and its Australian Privacy Principles) says information can only be used for the reason it was collected. For you, that means: use student information only to tutor that student.$t$),
  (2, 'Keeping information safe', $t$- Keep your app login to yourself, and always use two-step sign in.
- Don't download, screenshot or copy student information outside the app.
- Don't put any student information into ChatGPT, Copilot, Gemini or any other AI tool.
- Don't talk about students where others can hear, and don't post about them anywhere.
- Lock your device when you step away, and don't leave printed work with names in public.
- Use CLG materials only for your CLG sessions.$t$),
  (3, 'If something goes wrong', $t$A privacy slip is when information goes somewhere it shouldn't. For example, a message sent to the wrong parent, a lost device, or a screen shared with the wrong file open.

Tell CLG straight away, the same day. Don't try to hide it or fix it alone. CLG has a plan to check how serious it is and to tell the people affected if the law requires it. Acting quickly is what keeps harm small.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000003'); -- only if the module has no lessons yet

-- Module 4: How the CLG app works and where to go.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000004'::uuid, v.pos, v.title, v.body from (values -- for module 4:
  (1, 'Why the app helps you', $t$The CLG app keeps everything for your tutoring in one place, so you spend your time teaching, not chasing details. It also keeps students safe: only matched tutors see a student, and every check is up to date.

Your tutor dashboard has a side menu. The main tabs are:
- Your students: who you tutor, and their progress.
- Sessions: your bookings, sessions, requests, away dates and notices.
- Weekly calendar: your week at a glance, with Teams links.
- What you teach, Child safety checks, Hours and availability.
- CLG materials, Training, Handbook and My pay.$t$),
  (2, 'Before you start: checks, subjects and hours', $t$- Child safety checks: add your Working With Children Check for each state, and your RRHAN-EC certificate, with a copy. CLG confirms each one. You'll get reminders before they expire.
- What you teach: choose your subjects and the year levels for each. CLG only matches you with students who fit.
- Hours and availability: add the times you can tutor and your maximum hours each week.
- Where you teach: online, in person at confirmed libraries, or both.$t$),
  (3, 'Where to go when', $t$- A new request or offer: Sessions, then Bookings. Answer within the time shown.
- You're away: Sessions, then Away dates.
- Something's happened: Handbook (the red page at the top).
- You're worried about a child: the red Child safety button at the top of every page.
- Pay and hours: My pay.
- Training due: Training (the number on the tab shows what's due).
- Notices from CLG: Sessions, then Notices. Notices are never sent between 9pm and 5am.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000004'); -- only if the module has no lessons yet

-- Module 5: Running a session and writing the summary.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000005'::uuid, v.pos, v.title, v.body from (values -- for module 5:
  (1, 'Before the session', $t$- Check the student's progress page: their goals, last session's next step and any learning needs.
- Plan one clear goal for the session, linked to what they're learning at school.
- Get your materials ready from CLG materials.
- Online: open the Teams link a few minutes early. In person: arrive early at the library.$t$),
  (2, 'Signing on and off', $t$- In person: choose Sign on when you arrive. The app checks you're at the library.
- After the session, record it as completed or a no-show, and confirm the end time.
- Your pay comes from these times, so record them on the day.$t$),
  (3, 'The session summary', $t$You're paid time after each session to write the summary and plan the next one.

A good summary is short and specific:
- What you worked on (the skill, not just the topic).
- How the student went: what they can now do, and what's still tricky.
- The next step for next session, and anything to practise.

Write it yourself, in plain words a parent can follow. Never use AI tools with student information.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000005'); -- only if the module has no lessons yet

-- Module 6: Effective tutoring practice.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000006'::uuid, v.pos, v.title, v.body from (values -- for module 6:
  (1, 'What the research says', $t$Tutoring is one of the best-supported ways to help students catch up and get ahead. The Education Endowment Foundation (EEF) finds one-to-one tuition adds about five months' progress on average, and small group tuition about four months.

It works best when:
- sessions are regular and focused (often, short and consistent);
- the tutor knows what the student is learning in class and links to it;
- the tutor checks what the student already knows and builds on it;
- feedback is specific and the student acts on it.

Read more: https://educationendowmentfoundation.org.uk/education-evidence/teaching-learning-toolkit/one-to-one-tuition$t$),
  (2, 'Explain, show, practise', $t$Explicit teaching helps most students, especially when something is new:
- Explain one small step at a time, in plain words.
- Show a worked example, thinking out loud.
- Do one together, then let the student try one alone.
- Check understanding with a quick question before moving on (not "Does that make sense?", but "Show me how you'd start this one").

Australia's education research body, AERO, describes these as core effective teaching practices: https://www.edresearch.edu.au/$t$),
  (3, 'Feedback and remembering', $t$- Good feedback says what was right, what to fix, and how. Keep it about the task, not the person.
- Give the student time to use the feedback straight away.
- Start sessions with a few quick questions on earlier work. Bringing things back from memory (retrieval practice) helps them stick.
- Spread practice over weeks, not all at once.
- Praise effort and strategies, so students learn that they can improve.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000006'); -- only if the module has no lessons yet

-- Module 7: Yearly refresher.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000007'::uuid, v.pos, v.title, v.body from (values -- for module 7:
  (1, 'The key steps, again', $t$A quick reminder of the steps that matter most:
- A child in danger right now: call 000.
- Worried about a child: report to the child protection line (SA: CARL 13 14 78), then tell CLG with the red Child safety button.
- A privacy slip: tell CLG the same day.
- Anything else that's happened: open the Handbook. The red page at the top tells you what to do.

The quiz asks you to find answers in the handbook. Open it in another tab while you answer.$t$)
) as v(pos, title, body) -- (the lesson's order, heading and text)
where not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000007'); -- only if the module has no lessons yet

-- ---------------------------------------------------------------------------
-- Quiz questions. Each insert adds one module's questions, only if that
-- module has none yet. Choices count from 1.
-- ---------------------------------------------------------------------------

-- Module 1 quiz.
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select '7a000000-0000-4000-8000-000000000001'::uuid, v.pos, v.prompt, v.options, v.correct from (values -- for module 1:
  (1, 'A child tells you during a session that they are scared to go home tonight because someone will hurt them. What do you do first?', array['Message CLG and wait for a reply', 'Call 000', 'Ask the child lots of questions to find out more', 'Finish the session and think about it'], 2), -- 000 first
  (2, 'In South Australia, which number do you phone to report a serious concern about a child?', array['13 14 78 (CARL)', '1800 55 1800', '13 11 14', '000 only'], 1), -- CARL
  (3, 'After reporting, how do you tell CLG?', array['Post in the family''s Teams channel', 'The red Child safety button at the top of every page in the app', 'Email the parent', 'Wait until your next team meeting'], 2), -- the Child safety button
  (4, 'A child asks you to promise to keep what they tell you a secret. What do you say?', array['Yes, I promise', 'You can''t promise; you need to tell people whose job is to keep them safe', 'Tell them to talk to their parents instead', 'Change the subject'], 2), -- don't promise
  (5, 'Does telling CLG replace your own duty to report as a mandated notifier?', array['Yes, CLG reports for you', 'No, you report to the child protection line, then tell CLG', 'Only if the child is under 12', 'Only if you are sure abuse happened'], 2) -- you still report
) as v(pos, prompt, options, correct) -- (each question's order, words, choices and right answer)
where not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000001'); -- only if the module has no questions yet

-- Module 2 quiz.
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select '7a000000-0000-4000-8000-000000000002'::uuid, v.pos, v.prompt, v.options, v.correct from (values -- for module 2:
  (1, 'A student sends you a friend request on Instagram. What do you do?', array['Accept it, it builds rapport', 'Don''t accept, and tell CLG', 'Accept but don''t post anything', 'Block them without saying anything'], 2), -- don't accept, tell CLG
  (2, 'Where can in-person sessions happen?', array['At the student''s home, if the parent agrees', 'At public libraries CLG has confirmed, in open areas, inside opening hours', 'At a café near the student', 'Anywhere quiet'], 2), -- confirmed libraries
  (3, 'Which Teams link do you use for an online session?', array['The link CLG made for the session', 'Your own personal meeting link', 'Whatever the parent sends', 'A Zoom link'], 1) -- CLG's link
) as v(pos, prompt, options, correct) -- (each question's order, words, choices and right answer)
where not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000002'); -- only if the module has no questions yet

-- Module 3 quiz.
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select '7a000000-0000-4000-8000-000000000003'::uuid, v.pos, v.prompt, v.options, v.correct from (values -- for module 3:
  (1, 'Can you paste a student''s work or progress notes into ChatGPT to help write a summary?', array['Yes, if you remove their surname', 'No, never put student information into AI tools', 'Yes, if the parent agrees by text', 'Only for tertiary students'], 2), -- never
  (2, 'You accidentally message one parent about another family''s child. What do you do?', array['Delete it and hope they didn''t see', 'Tell CLG the same day', 'Ask the parent to keep it quiet', 'Wait to see if anyone complains'], 2), -- tell CLG the same day
  (3, 'What student information can you use?', array['Anything in the app, for any reason', 'Only what you need to tutor that student', 'Anything the student posts online', 'Their parents'' bank details for invoices'], 2) -- only what's needed
) as v(pos, prompt, options, correct) -- (each question's order, words, choices and right answer)
where not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000003'); -- only if the module has no questions yet

-- Module 4 quiz.
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select '7a000000-0000-4000-8000-000000000004'::uuid, v.pos, v.prompt, v.options, v.correct from (values -- for module 4:
  (1, 'Where do you answer a new booking request or offer?', array['Sessions, then Bookings', 'My pay', 'Your students', 'Email CLG'], 1), -- Sessions > Bookings
  (2, 'Something has happened in a session and you''re not sure what to do. Where do you look first?', array['The Handbook, starting with the red page at the top', 'Google', 'Ask the student', 'Wait until your next pay run'], 1), -- the Handbook
  (3, 'Where do you tell CLG you will be away?', array['Sessions, then Away dates', 'What you teach', 'A Teams message to the family', 'My pay'], 1) -- Away dates
) as v(pos, prompt, options, correct) -- (each question's order, words, choices and right answer)
where not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000004'); -- only if the module has no questions yet

-- Module 5 quiz.
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select '7a000000-0000-4000-8000-000000000005'::uuid, v.pos, v.prompt, v.options, v.correct from (values -- for module 5:
  (1, 'Which is the best next step to write in a session summary?', array['Keep practising maths', 'Practise adding fractions with different denominators: 5 questions from page 12', 'Good session', 'Do homework'], 2), -- specific next step
  (2, 'Why should you record the session''s end time on the day?', array['Your pay comes from these times', 'It isn''t needed', 'So the student gets a certificate', 'To book the next room'], 1) -- pay
) as v(pos, prompt, options, correct) -- (each question's order, words, choices and right answer)
where not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000005'); -- only if the module has no questions yet

-- Module 6 quiz.
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select '7a000000-0000-4000-8000-000000000006'::uuid, v.pos, v.prompt, v.options, v.correct from (values -- for module 6:
  (1, 'Which is the better way to check understanding?', array['"Does that make sense?"', '"Show me how you''d start this one."', '"Are you sure?"', '"Any questions?"'], 2), -- ask them to show
  (2, 'What is retrieval practice?', array['Re-reading notes', 'Bringing earlier learning back from memory, for example quick questions at the start', 'Copying out examples', 'Watching a video twice'], 2), -- recall from memory
  (3, 'What makes feedback most useful?', array['It''s about the person ("You''re clever")', 'It says what was right, what to fix and how, and the student uses it straight away', 'It''s saved for the end of term', 'It''s a mark out of 10'], 2) -- specific and acted on
) as v(pos, prompt, options, correct) -- (each question's order, words, choices and right answer)
where not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000006'); -- only if the module has no questions yet

-- Module 7 quiz ("find it in the handbook").
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select '7a000000-0000-4000-8000-000000000007'::uuid, v.pos, v.prompt, v.options, v.correct from (values -- for module 7:
  (1, 'Use the handbook: you are running 15 minutes late to an in-person session. What does the "Running late, sick or can''t make it" page say to do?', array['Nothing, just arrive', 'Message the family through CLG''s channels and tell CLG as soon as you know', 'Cancel the session', 'Ask the student to wait outside'], 2), -- tell the family and CLG
  (2, 'Use the handbook: which page is pinned in red at the top?', array['Pay and hours', 'Something''s happened: what to do', 'Online sessions', 'Who to contact at CLG'], 2), -- the urgent page
  (3, 'Use the handbook: a student becomes unwell during a session. What is the first thing to check?', array['Whether it''s an emergency (call 000 if so)', 'Whether they''ve paid', 'Whether to finish the topic', 'Their next booking'], 1) -- emergency first
) as v(pos, prompt, options, correct) -- (each question's order, words, choices and right answer)
where not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000007'); -- only if the module has no questions yet

-- ---------------------------------------------------------------------------
-- Handbook pages (drafts).
-- ---------------------------------------------------------------------------
insert into public.handbook_pages (id, title, urgent, audience, status, position, body) values -- adds draft handbook pages:
  ('7b000000-0000-4000-8000-000000000001', 'Something''s happened: what to do', true, 'everyone', 'draft', 1, $t$Find what's happened below. If a child is in danger right now, call 000 first.

## A child is in danger right now
- Call 000.
- Then report to the child protection line (SA: CARL 13 14 78).
- Then tell CLG with the red Child safety button at the top of every page.

## You're worried about a child, or a child tells you something
- Follow the three steps: 000 if in danger, report to the child protection line, tell CLG.
- Don't promise secrecy. Write down what was said, in the child's words.
- See the page "If a child tells you something".

## A student is unwell or hurt in a session
- Is it an emergency? Call 000.
- In person: stay with the student, and ask library staff for first aid if needed.
- Contact the parent through CLG's channels, then tell CLG. (Carla to check: how tutors reach a parent urgently.)

## You're running late, sick or can't make it
- See the page "Running late, sick or can't make it".

## A student doesn't turn up
- Online: wait 15 minutes in the Teams meeting. In person: wait 15 minutes at the library. (Carla to check: the wait time.)
- Record the session as a no-show in the app. CLG follows up with the family.

## Someone behaves inappropriately (a student, parent or member of the public)
- Keep yourself and the student safe. End an online session calmly if needed.
- Tell CLG the same day. If it involves a child's safety, use the Child safety button.

## A privacy slip (information sent to the wrong person, a lost device)
- Tell CLG the same day. Don't try to fix it alone.

## Technology problems in an online session
- Try leaving and rejoining the Teams meeting. If that fails, contact the family through CLG's channels and tell CLG.

## A parent complains or is upset
- Listen, stay calm and polite, and don't argue. Say you'll pass it to CLG, and do so the same day.$t$),
  ('7b000000-0000-4000-8000-000000000002', 'If a child tells you something', false, 'everyone', 'draft', 10, $t$If a child or young person tells you they are being hurt, or someone is worrying them:
- Stay calm. Listen and let them speak in their own words.
- Don't ask leading questions or try to investigate.
- Don't promise to keep it a secret.
- Tell them they did the right thing by telling you.
- Write it down as soon as you can: what they said, in their words, and the date and time.
- Act: 000 if they're in danger, report to the child protection line (SA: CARL 13 14 78), then tell CLG with the red Child safety button.

You're a mandated notifier. Telling CLG doesn't replace your own report.

Other states' child protection lines are listed on the Child safety page.

Young people can also call Kids Helpline on 1800 55 1800, any time.$t$),
  ('7b000000-0000-4000-8000-000000000003', 'Running late, sick or can''t make it', false, 'tutor', 'draft', 20, $t$## Running late
- Message the family through CLG's channels as soon as you know, with your new arrival time.
- Tell CLG. (Carla to check: whether tutors message families directly or CLG does.)

## Sick, or can't make a session
- Tell CLG as soon as you can, before the session.
- For planned time away, use Sessions, then Away dates. Sessions on those days are cancelled 2 hours after you save, and families are told politely.

## Late cancellations
- CLG's cancellation rules decide credits for families and any pay for you. Ask CLG if you're unsure.$t$),
  ('7b000000-0000-4000-8000-000000000004', 'Online sessions', false, 'tutor', 'draft', 30, $t$- Use the Teams link CLG made for the session. Join a few minutes early.
- Camera on, in a quiet, neutral space.
- Don't record sessions unless CLG has arranged it with consent.
- Keep chat and file sharing to the session's work.
- If something worrying happens on camera, end the session calmly and tell CLG straight away.$t$),
  ('7b000000-0000-4000-8000-000000000005', 'In-person sessions at libraries', false, 'tutor', 'draft', 40, $t$- Sessions are only at public libraries CLG has confirmed, inside opening hours.
- Sit in an open, visible area. Never in a closed room alone with a student.
- Choose Sign on when you arrive. The app checks you're at the library.
- At the end, make sure the student is collected or leaves as the family arranged. (Carla to check: CLG's rule for collecting younger students.)$t$),
  ('7b000000-0000-4000-8000-000000000006', 'Privacy: do and don''t', false, 'everyone', 'draft', 50, $t$## Do
- Use two-step sign in, and keep your login to yourself.
- Use student information only to tutor that student.
- Lock your device when you step away.
- Tell CLG the same day if information goes somewhere it shouldn't.

## Don't
- Put any student information into ChatGPT, Copilot, Gemini or any other AI tool.
- Screenshot, download or copy student information outside the app.
- Talk about students where others can hear, or post about them anywhere.
- Share CLG materials outside your CLG sessions.$t$),
  ('7b000000-0000-4000-8000-000000000007', 'Pay, hours and training', false, 'tutor', 'draft', 60, $t$- My pay shows your rates and the last 8 weeks of pay.
- Log work outside sessions (tutoring work, or office admin if you're admin staff) under My pay, by the day after each pay week ends.
- Compulsory training is paid for its set time once you finish it. It also counts towards your agreed weekly hours.
- Optional training is paid only if CLG agreed to it first. Log it under My pay.
- To stay CLG certified, finish 3 hr of training each quarter (safety modules don't count towards this).$t$),
  ('7b000000-0000-4000-8000-000000000008', 'Who to contact at CLG', false, 'everyone', 'draft', 70, $t$- Worried about a child: the red Child safety button. It goes to the Child Safety Officer, or the deputy if you choose.
- A problem with the app: Report a problem (in the menu).
- Sessions, bookings and families: CLG admin. (Carla to check: the best contact and hours.)
- Pay: CLG admin, through My pay.$t$)
on conflict (id) do nothing; -- already added before: left as it is
