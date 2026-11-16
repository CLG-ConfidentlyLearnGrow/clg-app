-- Training (module: training): four new ongoing modules, as DRAFTS for
-- Carla to check and publish (16 Nov 2026): 8 Assessment drafting,
-- 9 Families and communication, 10 Learning support, 11 Term reviews.
--
-- They come from the training plan's "still missing" list. Each counts
-- towards the 3 hours a quarter for CLG certified. They are marked
-- compulsory (as suggested in the review), but nothing is due until a
-- module is published, and Carla can change that in Training setup first.
-- Once published, a compulsory module is due within the usual 4 weeks.
-- None of them hold new matches.
--
-- Added only once: if a module with the same id already exists, it is left
-- as it is, and lessons or questions are only added to a module that has
-- none yet. Safe to run more than once. Run after 20261118200100_training_review_edits.sql.

-- ---------------------------------------------------------------------------
-- The modules (drafts).
-- ---------------------------------------------------------------------------
insert into public.training_modules (id, title, summary, audience, stage, required, holds_matching, counts_toward_certified, minutes, renew_months, status, position) values -- adds four draft modules:
  ('7a000000-0000-4000-8000-000000000008', 'Assessment drafting', 'How CLG reviews a student''s draft: helpful feedback that keeps the work the student''s own.', 'tutor', 'ongoing', true, false, true, 30, null, 'draft', 80), -- 8. assessment drafting
  ('7a000000-0000-4000-8000-000000000009', 'Families and communication', 'How you keep families informed and work with them, all through the CLG App.', 'tutor', 'ongoing', true, false, true, 30, null, 'draft', 90), -- 9. families and communication
  ('7a000000-0000-4000-8000-000000000010', 'Learning support', 'Adjusting your tutoring for students who learn differently, and knowing when to ask for help.', 'tutor', 'ongoing', true, false, true, 40, null, 'draft', 100), -- 10. learning support
  ('7a000000-0000-4000-8000-000000000011', 'Term reviews', 'Writing a term review that shows a family real progress and a clear plan.', 'tutor', 'ongoing', true, false, true, 20, null, 'draft', 110) -- 11. term reviews
on conflict (id) do nothing; -- already added before: left as it is

-- ---------------------------------------------------------------------------
-- Lessons. Each insert adds one module's lessons, only if it has none yet.
-- ---------------------------------------------------------------------------

-- Module 8: Assessment drafting.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000008'::uuid, v.pos, v.title, v.body from (values -- for module 8:
  (1, 'What drafting is, and isn''t', $t$In assessment drafting, a family uploads the student's draft, the task sheet and the marking rubric in the CLG App. You review the draft and send it back with comments and tracked changes.

## You do
- Suggest improvements to structure, argument and use of evidence.
- Check the content is accurate, and point out what's missing against the rubric.
- Correct grammar, spelling and layout.

## You never write the work
Not a sentence, a paragraph or a conclusion. Schools have rules about how much help students can have, and the student may have to declare it. If the work isn't theirs, they can lose marks or face an integrity investigation, and CLG's name suffers.

It also isn't real learning: the student only grows by doing the thinking and the writing themselves.$t$),
  (2, 'How to review a draft', $t$- Step 1: Read the task sheet and rubric first, so you know what the marker wants.
- Step 2: Read the whole draft once without commenting.
- Step 3: Note the two or three biggest improvements against the rubric. Put these in a short summary comment at the top.
- Step 4: Go through again and add comments where they're needed. Use tracked changes only for grammar, spelling and layout.
- Step 5: Check you haven't rewritten anything. If a comment includes a full sentence the student could paste in, turn it into a question or a hint.$t$),
  (3, 'Writing comments that help', $t$Good comments point to the rubric and say how to improve, without doing it for them.

- Instead of "Rewrite this as: The Treaty of Versailles caused...", write "Your argument is here, but it's buried. Which sentence states it most clearly? Move it to the start of the paragraph."
- Instead of "Good.", write "This quote supports your point well. Explain how it links back to the question."
- Instead of "Needs more analysis.", write "The rubric asks you to evaluate. Add a sentence on how strong this evidence is, and why."

Keep the tone encouraging. Start the summary comment with what's working.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000008'); -- only if the module has no lessons yet

-- Module 9: Families and communication.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000009'::uuid, v.pos, v.title, v.body from (values -- for module 9:
  (1, 'How families hear from you', $t$Families trust CLG when they can see progress. Most of what they hear from you comes from:
- Session summaries: what you worked on, how it went and the next step. For many parents, this is the only part of the session they see.
- The Progress page: the student's goals and how they're moving.
- Term reviews, when the family has asked for one (module 11).

All contact goes through the app. Families never see your phone number or email, and you never see theirs. This keeps everyone safe and keeps a record of what was agreed.

You keep in touch through session summaries, comments, replies to feedback notes, and offering another session time when one is needed. Anything else goes through CLG, starting with Lauren. If a parent needs to be reached urgently, phone CLG, who will call them.$t$),
  (2, 'Notes from home and feedback', $t$Families can send you "Feedback" or "Progress at home" notes, and upload reports and marked work. CLG sees these too.
- Read them before the next session and use them. If a parent says a test is coming, plan for it.
- Mention them in your next summary, so the family knows they were read.
- If a note raises a complaint, a worry about the student's wellbeing, or medical details, don't reply in the note. Tell CLG.

After the first two sessions, the app asks you and the family privately how it went. Only CLG sees the answers. Be honest, as it helps CLG sort out small problems early.$t$),
  (3, 'When a parent is worried or unhappy', $t$- Listen, and thank them for telling you.
- Don't argue, and don't promise results, grades or dates. Progress depends on many things.
- Fix what's yours to fix, such as the session's focus or materials.
- Pass anything about times, money, changing tutor or complaints to CLG. It's not yours to sort out alone.
- Tell CLG about any conversation that felt difficult, even if it ended well.

If a family blocks you, the app tells CLG, not you. CLG will follow up if needed.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000009'); -- only if the module has no lessons yet

-- Module 10: Learning support.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000010'::uuid, v.pos, v.title, v.body from (values -- for module 10:
  (1, 'Know the student', $t$Some students have a diagnosed learning need, such as dyslexia, ADHD or autism. Others simply find some things harder. Either way, good tutoring starts with knowing the student.
- Read the learning needs and support strategies on the student's profile before the first session. Families write these in their own words. The app records each time they're viewed.
- Ask the student what helps them, and what doesn't. Older students often know best.
- Use what the school already does, if the family has shared it (for example a learning plan or report).
- Never diagnose or suggest a diagnosis. If you notice something, tell CLG. Don't raise it with the family yourself.$t$),
  (2, 'Adjustments that help most students', $t$The EEF's guidance on supporting students with additional needs finds that great teaching for them is mostly great teaching for everyone, done more deliberately. Try:
- Small steps: break tasks into short chunks and check each one before moving on.
- Show, then do: model with a worked example, then do one together before the student tries alone.
- Scaffolds: sentence starters, checklists, number lines or visual organisers. Remove them gradually.
- Less load: fewer questions done well beats a full page. Let them talk an answer before writing it.
- Routine: a predictable session shape helps anxious students settle.
- Breaks: a short movement or brain break when focus drops. Agree on a signal.

Source: EEF, Special Educational Needs in Mainstream Schools: https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/send$t$),
  (3, 'When to ask CLG', $t$Tell CLG if:
- the student isn't making progress after several sessions, despite adjustments;
- the student's needs are beyond your experience;
- you notice signs of distress, anxiety or a wellbeing concern (for a child safety concern, follow module 1);
- the family asks for help you can't give, such as an assessment or a diagnosis.

Asking for help is part of the job. It may lead to a different approach, extra support, or a tutor with more experience in that area.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000010'); -- only if the module has no lessons yet

-- Module 11: Term reviews.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000011'::uuid, v.pos, v.title, v.body from (values -- for module 11:
  (1, 'What a term review is', $t$A term review is a written report on a student's progress at the end of a term or semester. It's an optional paid service, so you only write one when the family has asked for it. You'll get a notice when one is due, with the date to send it by.

For many families, the review is the moment they decide whether to keep going. A good one shows what the student can do now that they couldn't before, and what comes next.

The app fills in each goal's skills at the start of term and now. You write three short parts:
- How the term went: what the student worked on and what improved, with one specific example.
- Focus for next term: the one or two things that matter most next.
- Your recommendation, and why: continue as now, change focus, more or fewer sessions, or a break.

Add one thing the student can practise over the holidays.$t$),
  (2, 'Writing it well', $t$- Be specific. "Can now solve two-step equations without prompts" beats "is improving in maths".
- Be honest and kind. Name what's still hard, and how you'll work on it.
- Write to the parent, in plain words, without jargon.
- Use your session summaries to remind yourself of the term.
- Write it yourself. Never put student information into ChatGPT, Copilot, Gemini or any other AI tool.
- Leave out health or diagnosis details. The review is about learning.$t$),
  (3, 'What happens next', $t$Lauren checks every review before the family sees it. She either approves it or sends it back with what to change. Fix it and send it again promptly.

The family reads it on the Progress page. They can reply, or tick "I'd like a call". Replies go to CLG and to you together.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000011'); -- only if the module has no lessons yet

-- ---------------------------------------------------------------------------
-- Quiz questions. Each insert adds one module's questions, only if it has
-- none yet. Choices count from 1.
-- ---------------------------------------------------------------------------

-- Module 8 quiz.
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select '7a000000-0000-4000-8000-000000000008'::uuid, v.pos, v.prompt, v.options, v.correct from (values -- for module 8:
  (1, 'A student''s conclusion is weak and due tomorrow. What do you do?', array['Write a better conclusion for them to use', 'Comment on what the conclusion needs, linked to the rubric, and let them rewrite it', 'Leave it, as it''s too late', 'Send them a sample conclusion from another student'], 2), -- comment, they rewrite
  (2, 'What should you read first?', array['The draft', 'The task sheet and rubric', 'The student''s previous grades', 'Nothing, just start editing'], 2), -- task sheet and rubric
  (3, 'What can you change directly with tracked changes?', array['Whole paragraphs', 'The student''s argument', 'Grammar, spelling and layout', 'Anything, if the student agrees'], 3) -- grammar, spelling, layout
) as v(pos, prompt, options, correct) -- (each question's order, words, choices and right answer)
where not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000008'); -- only if the module has no questions yet

-- Module 9 quiz.
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select '7a000000-0000-4000-8000-000000000009'::uuid, v.pos, v.prompt, v.options, v.correct from (values -- for module 9:
  (1, 'A parent writes in a Progress at home note that their child has been diagnosed with anxiety. What do you do?', array['Reply in the note with advice', 'Don''t reply in the note, and tell CLG', 'Ignore it', 'Ask the student about it in the next session'], 2), -- tell CLG
  (2, 'A parent asks if their child will get an A this term. What do you say?', array['"Yes, definitely"', 'Explain what you''re working on and how they''re progressing, without promising a grade', '"That''s not my job"', '"Only if you book more sessions"'], 2), -- no promises
  (3, 'A parent wants to change their session time and pay differently. Who sorts this out?', array['You, by private message', 'CLG, through the app', 'The student', 'Nobody, times can''t change'], 2) -- CLG
) as v(pos, prompt, options, correct) -- (each question's order, words, choices and right answer)
where not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000009'); -- only if the module has no questions yet

-- Module 10 quiz.
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select '7a000000-0000-4000-8000-000000000010'::uuid, v.pos, v.prompt, v.options, v.correct from (values -- for module 10:
  (1, 'You think a student might have dyslexia. What do you do?', array['Tell the parent your view', 'Tell CLG what you''ve noticed, and keep adjusting your sessions', 'Ask the student if they have dyslexia', 'Nothing'], 2), -- tell CLG
  (2, 'A student gets overwhelmed by a full worksheet. Which is the best adjustment?', array['Give them more time on the full sheet', 'Do three questions well, one step at a time, checking each', 'Skip the topic', 'Do the worksheet for them'], 2), -- fewer, step by step
  (3, 'Where do you find a student''s learning needs?', array['Ask the school', 'On the student''s profile in the app', 'Search online', 'The family''s emails'], 2) -- the profile
) as v(pos, prompt, options, correct) -- (each question's order, words, choices and right answer)
where not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000010'); -- only if the module has no questions yet

-- Module 11 quiz.
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select '7a000000-0000-4000-8000-000000000011'::uuid, v.pos, v.prompt, v.options, v.correct from (values -- for module 11:
  (1, 'Which sentence belongs in a term review?', array['"Sam is doing great!"', '"Sam can now write a paragraph with a clear topic sentence and two pieces of evidence, without prompts."', '"Sam needs to try harder."', '"Sam has ADHD, which affects his focus."'], 2), -- specific progress
  (2, 'Can you use an AI tool to help write a review if you remove the student''s name?', array['Yes', 'No, never put student information into AI tools', 'Only for the recommendation', 'Only if Lauren agrees'], 2), -- never
  (3, 'Who sees the review before the family?', array['Nobody', 'Lauren, who checks and approves it', 'The student''s school', 'Other tutors'], 2) -- Lauren
) as v(pos, prompt, options, correct) -- (each question's order, words, choices and right answer)
where not exists (select 1 from public.training_questions q where q.module_id = '7a000000-0000-4000-8000-000000000011'); -- only if the module has no questions yet
