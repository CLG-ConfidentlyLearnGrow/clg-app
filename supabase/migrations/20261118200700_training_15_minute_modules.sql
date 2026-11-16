-- Training (module: training): every module is now 15 minutes (Carla,
-- 16 Nov 2026: "There should be numerous short modules which should only
-- take 15 minutes"). The seven starter drafts, plus the four new modules
-- from 20261118200200 (assessment drafting, families and communication,
-- learning support, term reviews), become 25 short modules:
--   1-8   safety (everyone; compulsory; hold new matches; due before any sit-in)
--   9-16  the rest of the starting course (tutors; compulsory)
--   17    the yearly refresher (everyone; holds new matches; every 12 months)
--   18-25 ongoing (tutors; compulsory once published; count towards CLG certified)
-- Each module uses one or two lessons and a 2 or 3 question quiz.
--
-- How it's done: the existing draft lessons and questions are MOVED into
-- the new modules (not deleted and rewritten), so any edits made in
-- Training setup are kept. Modules 1-11 reuse the existing rows with new
-- titles (their lessons move to wherever they now belong). Everything stays a DRAFT until an admin publishes it.
--
-- Only runs if all eleven modules are still drafts. If any has been
-- published, nothing here changes and a notice says so. Safe to run more
-- than once: once module 25 exists, the move is skipped, and content is
-- only added where it isn't there yet.
--
-- Run after 20261118200600_training_wording_6_hours.sql.

-- ---------------------------------------------------------------------------
-- Part 1: the 25 modules, and moving the starter lessons and questions.
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
begin -- start
  if exists (select 1 from public.training_modules where id = '7a000000-0000-4000-8000-000000000025') then -- already split before:
    return; -- nothing more to do
  end if; -- (end of the check)
  if exists (select 1 from public.training_modules where id in ('7a000000-0000-4000-8000-000000000001', '7a000000-0000-4000-8000-000000000002', '7a000000-0000-4000-8000-000000000003', '7a000000-0000-4000-8000-000000000004', '7a000000-0000-4000-8000-000000000005', '7a000000-0000-4000-8000-000000000006', '7a000000-0000-4000-8000-000000000007', '7a000000-0000-4000-8000-000000000008', '7a000000-0000-4000-8000-000000000009', '7a000000-0000-4000-8000-000000000010', '7a000000-0000-4000-8000-000000000011') and status <> 'draft') then -- one of the eleven modules is published:
    raise notice 'Training: a starter module is already published, so the 15-minute split was skipped. Split it by hand in Training setup.'; -- says why
    return; -- leaves everything as it is
  end if; -- (end of the check)
  if not exists (select 1 from public.training_modules where id = '7a000000-0000-4000-8000-000000000001') then -- the drafts aren't there (for example a fresh copy without them):
    return; -- nothing to split; part 2 still adds the new content
  end if; -- (end of the check)


  -- The module details: modules 1-11 reuse the existing rows, 12-25 are new.
  insert into public.training_modules (id, title, summary, audience, stage, required, holds_matching, counts_toward_certified, minutes, renew_months, status, position) values -- adds or updates each module:
    ('7a000000-0000-4000-8000-000000000001', 'Child safety: spotting harm', 'What harm can look like, and why a reasonable suspicion is enough to act.', 'everyone', 'starting', true, true, false, 15, null, 'draft', 10), -- 1. Child safety: spotting harm
    ('7a000000-0000-4000-8000-000000000002', 'Child safety: the three steps', 'If you are worried about a child: 000, report to the child protection line, then tell CLG.', 'everyone', 'starting', true, true, false, 15, null, 'draft', 20), -- 2. Child safety: the three steps
    ('7a000000-0000-4000-8000-000000000003', 'Child safety: your duty, and if a child tells you', 'Your duty to report, and what to do when a child tells you something.', 'everyone', 'starting', true, true, false, 15, null, 'draft', 30), -- 3. Child safety: your duty, and if a child tells you
    ('7a000000-0000-4000-8000-000000000004', 'Professional and honest', 'How CLG staff behave, and why you never write a student''s work.', 'everyone', 'starting', true, true, false, 15, null, 'draft', 40), -- 4. Professional and honest
    ('7a000000-0000-4000-8000-000000000005', 'Boundaries with students and families', 'All contact through the CLG App, and the boundaries that keep students and you safe.', 'everyone', 'starting', true, true, false, 15, null, 'draft', 50), -- 5. Boundaries with students and families
    ('7a000000-0000-4000-8000-000000000006', 'Safe online sessions', 'Running online sessions safely, and what to do if something worrying happens on camera.', 'everyone', 'starting', true, true, false, 15, null, 'draft', 60), -- 6. Safe online sessions
    ('7a000000-0000-4000-8000-000000000007', 'Keeping student information safe', 'What student information you can see, and how to keep it safe.', 'everyone', 'starting', true, true, false, 15, null, 'draft', 70), -- 7. Keeping student information safe
    ('7a000000-0000-4000-8000-000000000008', 'When something goes wrong', 'What to do straight away after a privacy slip.', 'everyone', 'starting', true, true, false, 15, null, 'draft', 80), -- 8. When something goes wrong
    ('7a000000-0000-4000-8000-000000000009', 'Setting up in the app', 'Your dashboard, child safety checks, subjects and hours.', 'tutor', 'starting', true, false, true, 15, null, 'draft', 90), -- 9. Setting up in the app
    ('7a000000-0000-4000-8000-000000000010', 'Where to go when', 'Where to find things in the app, and who to contact at CLG.', 'tutor', 'starting', true, false, true, 15, null, 'draft', 100), -- 10. Where to go when
    ('7a000000-0000-4000-8000-000000000011', 'Before and during a session', 'Planning a session, signing on and off, and recording times.', 'tutor', 'starting', true, false, true, 15, null, 'draft', 110), -- 11. Before and during a session
    ('7a000000-0000-4000-8000-000000000012', 'The session summary', 'A short, specific summary within 6 hours of the session ending.', 'tutor', 'starting', true, false, true, 15, null, 'draft', 120), -- 12. The session summary
    ('7a000000-0000-4000-8000-000000000013', 'Your first three sessions with a new student', 'Getting to know a new student, finding their level and agreeing goals.', 'tutor', 'starting', true, false, true, 15, null, 'draft', 130), -- 13. Your first three sessions with a new student
    ('7a000000-0000-4000-8000-000000000014', 'Explain, show, practise', 'What the research says works in tutoring, and explicit teaching.', 'tutor', 'starting', true, false, true, 15, null, 'draft', 140), -- 14. Explain, show, practise
    ('7a000000-0000-4000-8000-000000000015', 'Feedback and remembering', 'Feedback that helps, and bringing learning back from memory.', 'tutor', 'starting', true, false, true, 15, null, 'draft', 150), -- 15. Feedback and remembering
    ('7a000000-0000-4000-8000-000000000016', 'Building confidence and independence', 'Helping students learn without you.', 'tutor', 'starting', true, false, true, 15, null, 'draft', 160), -- 16. Building confidence and independence
    ('7a000000-0000-4000-8000-000000000017', 'Yearly refresher: safety, privacy and the handbook', 'A short refresher each year: the key steps, and finding the answers in the handbook.', 'everyone', 'refresher', true, true, false, 15, 12, 'draft', 170), -- 17. Yearly refresher: safety, privacy and the handbook
    ('7a000000-0000-4000-8000-000000000018', 'Drafting: what it is and how to review', 'What assessment drafting is, and how to review a draft without writing any of it.', 'tutor', 'ongoing', true, false, true, 15, null, 'draft', 180), -- 18. Drafting: what it is and how to review
    ('7a000000-0000-4000-8000-000000000019', 'Drafting: comments that help', 'Writing drafting comments that point to the rubric and keep the work the student''s own.', 'tutor', 'ongoing', true, false, true, 15, null, 'draft', 190), -- 19. Drafting: comments that help
    ('7a000000-0000-4000-8000-000000000020', 'Keeping families informed', 'How families hear from you, all through the CLG App, and using notes from home.', 'tutor', 'ongoing', true, false, true, 15, null, 'draft', 200), -- 20. Keeping families informed
    ('7a000000-0000-4000-8000-000000000021', 'A worried or unhappy parent', 'What to do when a parent is worried or unhappy, and what to pass to CLG.', 'tutor', 'ongoing', true, false, true, 15, null, 'draft', 210), -- 21. A worried or unhappy parent
    ('7a000000-0000-4000-8000-000000000022', 'Learning support: know the student, and when to ask', 'Knowing a student''s learning needs, and when to ask CLG for help.', 'tutor', 'ongoing', true, false, true, 15, null, 'draft', 220), -- 22. Learning support: know the student, and when to ask
    ('7a000000-0000-4000-8000-000000000023', 'Learning support: adjustments that help', 'Simple adjustments that help students who learn differently.', 'tutor', 'ongoing', true, false, true, 15, null, 'draft', 230), -- 23. Learning support: adjustments that help
    ('7a000000-0000-4000-8000-000000000024', 'Term reviews: what they are and who checks them', 'What a term review includes, and what happens after you send it.', 'tutor', 'ongoing', true, false, true, 15, null, 'draft', 240), -- 24. Term reviews: what they are and who checks them
    ('7a000000-0000-4000-8000-000000000025', 'Term reviews: writing it well', 'Writing a term review that is specific, honest and kind.', 'tutor', 'ongoing', true, false, true, 15, null, 'draft', 250) -- 25. Term reviews: writing it well
  on conflict (id) do update set -- a starter module already there: gets its new details
    title = excluded.title, summary = excluded.summary, audience = excluded.audience, stage = excluded.stage, -- name, summary, who it's for and stage,
    required = excluded.required, holds_matching = excluded.holds_matching, counts_toward_certified = excluded.counts_toward_certified, -- compulsory, holds matches, counts for certification,
    minutes = excluded.minutes, renew_months = excluded.renew_months, position = excluded.position -- 15 minutes, redo time and order
  where public.training_modules.status = 'draft'; -- only while it's a draft

  -- Move each starter lesson to its new module and place (old module, old place -> new module, new place).
  update public.training_lessons l -- changes lessons:
  set module_id = m.new_mod::uuid, position = m.new_pos -- to their new module and place
  from (values -- the moves:
    ('7a000000-0000-4000-8000-000000000001', 1, '7a000000-0000-4000-8000-000000000001', 1),
    ('7a000000-0000-4000-8000-000000000001', 2, '7a000000-0000-4000-8000-000000000002', 1),
    ('7a000000-0000-4000-8000-000000000001', 3, '7a000000-0000-4000-8000-000000000003', 1),
    ('7a000000-0000-4000-8000-000000000001', 4, '7a000000-0000-4000-8000-000000000003', 2),
    ('7a000000-0000-4000-8000-000000000002', 1, '7a000000-0000-4000-8000-000000000004', 1),
    ('7a000000-0000-4000-8000-000000000002', 4, '7a000000-0000-4000-8000-000000000004', 2),
    ('7a000000-0000-4000-8000-000000000002', 2, '7a000000-0000-4000-8000-000000000005', 1),
    ('7a000000-0000-4000-8000-000000000002', 3, '7a000000-0000-4000-8000-000000000006', 1),
    ('7a000000-0000-4000-8000-000000000003', 1, '7a000000-0000-4000-8000-000000000007', 1),
    ('7a000000-0000-4000-8000-000000000003', 2, '7a000000-0000-4000-8000-000000000007', 2),
    ('7a000000-0000-4000-8000-000000000003', 3, '7a000000-0000-4000-8000-000000000008', 1),
    ('7a000000-0000-4000-8000-000000000004', 1, '7a000000-0000-4000-8000-000000000009', 1),
    ('7a000000-0000-4000-8000-000000000004', 2, '7a000000-0000-4000-8000-000000000009', 2),
    ('7a000000-0000-4000-8000-000000000004', 3, '7a000000-0000-4000-8000-000000000010', 1),
    ('7a000000-0000-4000-8000-000000000005', 1, '7a000000-0000-4000-8000-000000000011', 1),
    ('7a000000-0000-4000-8000-000000000005', 2, '7a000000-0000-4000-8000-000000000011', 2),
    ('7a000000-0000-4000-8000-000000000005', 3, '7a000000-0000-4000-8000-000000000012', 1),
    ('7a000000-0000-4000-8000-000000000005', 4, '7a000000-0000-4000-8000-000000000013', 1),
    ('7a000000-0000-4000-8000-000000000006', 1, '7a000000-0000-4000-8000-000000000014', 1),
    ('7a000000-0000-4000-8000-000000000006', 2, '7a000000-0000-4000-8000-000000000014', 2),
    ('7a000000-0000-4000-8000-000000000006', 3, '7a000000-0000-4000-8000-000000000015', 1),
    ('7a000000-0000-4000-8000-000000000006', 4, '7a000000-0000-4000-8000-000000000016', 1),
    ('7a000000-0000-4000-8000-000000000007', 1, '7a000000-0000-4000-8000-000000000017', 1),
    ('7a000000-0000-4000-8000-000000000008', 1, '7a000000-0000-4000-8000-000000000018', 1),
    ('7a000000-0000-4000-8000-000000000008', 2, '7a000000-0000-4000-8000-000000000018', 2),
    ('7a000000-0000-4000-8000-000000000008', 3, '7a000000-0000-4000-8000-000000000019', 1),
    ('7a000000-0000-4000-8000-000000000009', 1, '7a000000-0000-4000-8000-000000000020', 1),
    ('7a000000-0000-4000-8000-000000000009', 2, '7a000000-0000-4000-8000-000000000020', 2),
    ('7a000000-0000-4000-8000-000000000009', 3, '7a000000-0000-4000-8000-000000000021', 1),
    ('7a000000-0000-4000-8000-000000000010', 1, '7a000000-0000-4000-8000-000000000022', 1),
    ('7a000000-0000-4000-8000-000000000010', 3, '7a000000-0000-4000-8000-000000000022', 2),
    ('7a000000-0000-4000-8000-000000000010', 2, '7a000000-0000-4000-8000-000000000023', 1),
    ('7a000000-0000-4000-8000-000000000011', 1, '7a000000-0000-4000-8000-000000000024', 1),
    ('7a000000-0000-4000-8000-000000000011', 3, '7a000000-0000-4000-8000-000000000024', 2),
    ('7a000000-0000-4000-8000-000000000011', 2, '7a000000-0000-4000-8000-000000000025', 1) -- (old module, old place, new module, new place)
  ) as m(old_mod, old_pos, new_mod, new_pos) -- (the columns)
  where l.module_id = m.old_mod::uuid and l.position = m.old_pos; -- matched on where each lesson is now

  -- Move each starter quiz question the same way.
  update public.training_questions qn -- changes questions:
  set module_id = m.new_mod::uuid, position = m.new_pos -- to their new module and place
  from (values -- the moves:
    ('7a000000-0000-4000-8000-000000000001', 1, '7a000000-0000-4000-8000-000000000002', 1),
    ('7a000000-0000-4000-8000-000000000001', 2, '7a000000-0000-4000-8000-000000000002', 2),
    ('7a000000-0000-4000-8000-000000000001', 3, '7a000000-0000-4000-8000-000000000002', 3),
    ('7a000000-0000-4000-8000-000000000001', 4, '7a000000-0000-4000-8000-000000000003', 1),
    ('7a000000-0000-4000-8000-000000000001', 5, '7a000000-0000-4000-8000-000000000003', 2),
    ('7a000000-0000-4000-8000-000000000001', 6, '7a000000-0000-4000-8000-000000000003', 3),
    ('7a000000-0000-4000-8000-000000000002', 1, '7a000000-0000-4000-8000-000000000005', 1),
    ('7a000000-0000-4000-8000-000000000002', 2, '7a000000-0000-4000-8000-000000000005', 2),
    ('7a000000-0000-4000-8000-000000000002', 4, '7a000000-0000-4000-8000-000000000005', 3),
    ('7a000000-0000-4000-8000-000000000002', 5, '7a000000-0000-4000-8000-000000000004', 1),
    ('7a000000-0000-4000-8000-000000000002', 3, '7a000000-0000-4000-8000-000000000006', 1),
    ('7a000000-0000-4000-8000-000000000003', 1, '7a000000-0000-4000-8000-000000000007', 1),
    ('7a000000-0000-4000-8000-000000000003', 3, '7a000000-0000-4000-8000-000000000007', 2),
    ('7a000000-0000-4000-8000-000000000003', 2, '7a000000-0000-4000-8000-000000000008', 1),
    ('7a000000-0000-4000-8000-000000000004', 1, '7a000000-0000-4000-8000-000000000010', 1),
    ('7a000000-0000-4000-8000-000000000004', 2, '7a000000-0000-4000-8000-000000000010', 2),
    ('7a000000-0000-4000-8000-000000000004', 3, '7a000000-0000-4000-8000-000000000010', 3),
    ('7a000000-0000-4000-8000-000000000005', 2, '7a000000-0000-4000-8000-000000000011', 1),
    ('7a000000-0000-4000-8000-000000000005', 1, '7a000000-0000-4000-8000-000000000012', 1),
    ('7a000000-0000-4000-8000-000000000005', 3, '7a000000-0000-4000-8000-000000000012', 2),
    ('7a000000-0000-4000-8000-000000000006', 1, '7a000000-0000-4000-8000-000000000014', 1),
    ('7a000000-0000-4000-8000-000000000006', 2, '7a000000-0000-4000-8000-000000000015', 1),
    ('7a000000-0000-4000-8000-000000000006', 3, '7a000000-0000-4000-8000-000000000015', 2),
    ('7a000000-0000-4000-8000-000000000007', 1, '7a000000-0000-4000-8000-000000000017', 1),
    ('7a000000-0000-4000-8000-000000000007', 2, '7a000000-0000-4000-8000-000000000017', 2),
    ('7a000000-0000-4000-8000-000000000007', 3, '7a000000-0000-4000-8000-000000000017', 3),
    ('7a000000-0000-4000-8000-000000000008', 2, '7a000000-0000-4000-8000-000000000018', 1),
    ('7a000000-0000-4000-8000-000000000008', 3, '7a000000-0000-4000-8000-000000000018', 2),
    ('7a000000-0000-4000-8000-000000000008', 1, '7a000000-0000-4000-8000-000000000019', 1),
    ('7a000000-0000-4000-8000-000000000009', 1, '7a000000-0000-4000-8000-000000000020', 1),
    ('7a000000-0000-4000-8000-000000000009', 3, '7a000000-0000-4000-8000-000000000020', 2),
    ('7a000000-0000-4000-8000-000000000009', 2, '7a000000-0000-4000-8000-000000000021', 1),
    ('7a000000-0000-4000-8000-000000000010', 1, '7a000000-0000-4000-8000-000000000022', 1),
    ('7a000000-0000-4000-8000-000000000010', 3, '7a000000-0000-4000-8000-000000000022', 2),
    ('7a000000-0000-4000-8000-000000000010', 2, '7a000000-0000-4000-8000-000000000023', 1),
    ('7a000000-0000-4000-8000-000000000011', 3, '7a000000-0000-4000-8000-000000000024', 1),
    ('7a000000-0000-4000-8000-000000000011', 1, '7a000000-0000-4000-8000-000000000025', 1),
    ('7a000000-0000-4000-8000-000000000011', 2, '7a000000-0000-4000-8000-000000000025', 2) -- (old module, old place, new module, new place)
  ) as m(old_mod, old_pos, new_mod, new_pos) -- (the columns)
  where qn.module_id = m.old_mod::uuid and qn.position = m.old_pos; -- matched on where each question is now
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- Part 2: lessons for modules 18-25, only if a module has none (they are
-- normally moved there in part 1 from the four review modules), and only
-- while it is a draft.
-- ---------------------------------------------------------------------------

-- Module 18: Drafting: what it is and how to review.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000018'::uuid, v.pos, v.title, v.body from (values -- for module 18:
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
- Step 5: Check you haven't rewritten anything. If a comment includes a full sentence the student could paste in, turn it into a question or a hint.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000018' and m.status = 'draft') -- only while the module is a draft
  and not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000018'); -- only if it has no lessons yet

-- Module 19: Drafting: comments that help.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000019'::uuid, v.pos, v.title, v.body from (values -- for module 19:
  (1, 'Writing comments that help', $t$Good comments point to the rubric and say how to improve, without doing it for them.

- Instead of "Rewrite this as: The Treaty of Versailles caused...", write "Your argument is here, but it's buried. Which sentence states it most clearly? Move it to the start of the paragraph."
- Instead of "Good.", write "This quote supports your point well. Explain how it links back to the question."
- Instead of "Needs more analysis.", write "The rubric asks you to evaluate. Add a sentence on how strong this evidence is, and why."

Keep the tone encouraging. Start the summary comment with what's working.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000019' and m.status = 'draft') -- only while the module is a draft
  and not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000019'); -- only if it has no lessons yet

-- Module 20: Keeping families informed.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000020'::uuid, v.pos, v.title, v.body from (values -- for module 20:
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

After the first two sessions, the app asks you and the family privately how it went. Only CLG sees the answers. Be honest, as it helps CLG sort out small problems early.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000020' and m.status = 'draft') -- only while the module is a draft
  and not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000020'); -- only if it has no lessons yet

-- Module 21: A worried or unhappy parent.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000021'::uuid, v.pos, v.title, v.body from (values -- for module 21:
  (1, 'When a parent is worried or unhappy', $t$- Listen, and thank them for telling you.
- Don't argue, and don't promise results, grades or dates. Progress depends on many things.
- Fix what's yours to fix, such as the session's focus or materials.
- Pass anything about times, money, changing tutor or complaints to CLG. It's not yours to sort out alone.
- Tell CLG about any conversation that felt difficult, even if it ended well.

If a family blocks you, the app tells CLG, not you. CLG will follow up if needed.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000021' and m.status = 'draft') -- only while the module is a draft
  and not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000021'); -- only if it has no lessons yet

-- Module 22: Learning support: know the student, and when to ask.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000022'::uuid, v.pos, v.title, v.body from (values -- for module 22:
  (1, 'Know the student', $t$Some students have a diagnosed learning need, such as dyslexia, ADHD or autism. Others simply find some things harder. Either way, good tutoring starts with knowing the student.
- Read the learning needs and support strategies on the student's profile before the first session. Families write these in their own words. The app records each time they're viewed.
- Ask the student what helps them, and what doesn't. Older students often know best.
- Use what the school already does, if the family has shared it (for example a learning plan or report).
- Never diagnose or suggest a diagnosis. If you notice something, tell CLG. Don't raise it with the family yourself.$t$),
  (2, 'When to ask CLG', $t$Tell CLG if:
- the student isn't making progress after several sessions, despite adjustments;
- the student's needs are beyond your experience;
- you notice signs of distress, anxiety or a wellbeing concern (for a child safety concern, follow module 1);
- the family asks for help you can't give, such as an assessment or a diagnosis.

Asking for help is part of the job. It may lead to a different approach, extra support, or a tutor with more experience in that area.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000022' and m.status = 'draft') -- only while the module is a draft
  and not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000022'); -- only if it has no lessons yet

-- Module 23: Learning support: adjustments that help.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000023'::uuid, v.pos, v.title, v.body from (values -- for module 23:
  (1, 'Adjustments that help most students', $t$The EEF's guidance on supporting students with additional needs finds that great teaching for them is mostly great teaching for everyone, done more deliberately. Try:
- Small steps: break tasks into short chunks and check each one before moving on.
- Show, then do: model with a worked example, then do one together before the student tries alone.
- Scaffolds: sentence starters, checklists, number lines or visual organisers. Remove them gradually.
- Less load: fewer questions done well beats a full page. Let them talk an answer before writing it.
- Routine: a predictable session shape helps anxious students settle.
- Breaks: a short movement or brain break when focus drops. Agree on a signal.

Source: EEF, Special Educational Needs in Mainstream Schools: https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/send$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000023' and m.status = 'draft') -- only while the module is a draft
  and not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000023'); -- only if it has no lessons yet

-- Module 24: Term reviews: what they are and who checks them.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000024'::uuid, v.pos, v.title, v.body from (values -- for module 24:
  (1, 'What a term review is', $t$A term review is a written report on a student's progress at the end of a term or semester. It's an optional paid service, so you only write one when the family has asked for it. You'll get a notice when one is due, with the date to send it by.

For many families, the review is the moment they decide whether to keep going. A good one shows what the student can do now that they couldn't before, and what comes next.

The app fills in each goal's skills at the start of term and now. You write three short parts:
- How the term went: what the student worked on and what improved, with one specific example.
- Focus for next term: the one or two things that matter most next.
- Your recommendation, and why: continue as now, change focus, more or fewer sessions, or a break.

Add one thing the student can practise over the holidays.$t$),
  (2, 'What happens next', $t$Lauren checks every review before the family sees it. She either approves it or sends it back with what to change. Fix it and send it again promptly.

The family reads it on the Progress page. They can reply, or tick "I'd like a call". Replies go to CLG and to you together.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000024' and m.status = 'draft') -- only while the module is a draft
  and not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000024'); -- only if it has no lessons yet

-- Module 25: Term reviews: writing it well.
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select '7a000000-0000-4000-8000-000000000025'::uuid, v.pos, v.title, v.body from (values -- for module 25:
  (1, 'Writing it well', $t$- Be specific. "Can now solve two-step equations without prompts" beats "is improving in maths".
- Be honest and kind. Name what's still hard, and how you'll work on it.
- Write to the parent, in plain words, without jargon.
- Use your session summaries to remind yourself of the term.
- Write it yourself. Never put student information into ChatGPT, Copilot, Gemini or any other AI tool.
- Leave out health or diagnosis details. The review is about learning.$t$)
) as v(pos, title, body) -- (the lessons' order, heading and text)
where exists (select 1 from public.training_modules m where m.id = '7a000000-0000-4000-8000-000000000025' and m.status = 'draft') -- only while the module is a draft
  and not exists (select 1 from public.training_lessons l where l.module_id = '7a000000-0000-4000-8000-000000000025'); -- only if it has no lessons yet

-- ---------------------------------------------------------------------------
-- Part 3: quiz questions. For modules 18-25, the review's questions; and the
-- new questions for the 15-minute modules. Each is added only if that
-- module doesn't already have a question with the same words, and only
-- while it is a draft. Choices count from 1.
-- ---------------------------------------------------------------------------

insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select v.mod::uuid, -- to its module,
  (select coalesce(max(x.position), 0) from public.training_questions x where x.module_id = v.mod::uuid) + v.n, -- after that module's last question,
  v.prompt, v.options, v.correct -- the question, choices and right answer
from (values -- the questions (module, order among the new ones, question, choices, right answer):
  ('7a000000-0000-4000-8000-000000000001', 1, 'Do you need proof before you act on a worry about a child?', array['Yes, always', 'No, a reasonable suspicion is enough', 'Only if the child tells you directly', 'Only if a parent agrees'], 2), -- module 1: a reasonable suspicion
  ('7a000000-0000-4000-8000-000000000001', 2, 'Which could be a sign of grooming?', array['A student who is tired after school', 'An adult asking a child to keep secrets or giving them gifts', 'A student who finds maths hard', 'A parent who asks lots of questions'], 2), -- module 1: secrets or gifts
  ('7a000000-0000-4000-8000-000000000004', 1, 'A session finishes 20 minutes early. What do you record?', array['The booked end time', 'The real end time', 'Nothing', 'Whatever the family prefers'], 2), -- module 4: the real end time
  ('7a000000-0000-4000-8000-000000000006', 1, 'During an online session, someone in the student''s room behaves inappropriately. What do you do?', array['Keep going and ignore it', 'End the session calmly and tell CLG straight away', 'Record the session as evidence', 'Message the parent on your phone'], 2), -- module 6: end calmly, tell CLG
  ('7a000000-0000-4000-8000-000000000008', 1, 'A parent writes a medical detail in a Progress at home note. What do you do?', array['Reply in the note', 'Copy it into your own notes', 'Don''t reply in the note, and tell CLG', 'Ignore it'], 3), -- module 8: tell CLG
  ('7a000000-0000-4000-8000-000000000009', 1, 'Why can''t you be matched with students straight after you join?', array['CLG matches tutors once a term', 'Your child safety checks must be confirmed first', 'You must tutor for free first', 'Families choose tutors themselves'], 2), -- module 9: checks first
  ('7a000000-0000-4000-8000-000000000009', 2, 'Where do you set the times you can tutor and your maximum hours each week?', array['My pay', 'Hours and availability', 'Training', 'Notices'], 2), -- module 9: Hours and availability
  ('7a000000-0000-4000-8000-000000000011', 1, 'When is an early finish flagged for CLG to check?', array['Any time a session ends early', 'When it finishes more than 15 minutes early', 'Only if the family complains', 'Never'], 2), -- module 11: more than 15 minutes early
  ('7a000000-0000-4000-8000-000000000013', 1, 'What is the main aim of your first session with a new student?', array['Cover as much of the syllabus as possible', 'Get to know them: school, what they enjoy, what feels hard and their goals', 'Give them a full test', 'Set homework for the term'], 2), -- module 13: get to know them
  ('7a000000-0000-4000-8000-000000000013', 2, 'By when should you agree two or three goals with a new student?', array['Their first session', 'By their third session', 'The end of term', 'Only if the family asks'], 2), -- module 13: by session 3
  ('7a000000-0000-4000-8000-000000000014', 1, 'What is the best order when teaching something new?', array['Practise alone, then explain', 'Explain one small step, show a worked example, do one together, then they try alone', 'Give a worksheet and check it at the end', 'Show the answer and move on'], 2), -- module 14: explain, show, together, alone
  ('7a000000-0000-4000-8000-000000000016', 1, 'A student is stuck. What is the best first thing to say?', array['"Here''s the answer"', '"What have you tried, and what could you try next?"', '"This is easy"', '"We''ll skip this one"'], 2), -- module 16: what have you tried
  ('7a000000-0000-4000-8000-000000000016', 2, 'How do you help a student learn without you over time?', array['Give answers faster', 'Hand over a little more each week: hints instead of answers, then just a nudge', 'Keep every session the same', 'Do their homework with them every week'], 2), -- module 16: hand over a little more
  ('7a000000-0000-4000-8000-000000000018', 1, 'What should you read first?', array['The draft', 'The task sheet and rubric', 'The student''s previous grades', 'Nothing, just start editing'], 2), -- module 18: task sheet and rubric
  ('7a000000-0000-4000-8000-000000000018', 2, 'What can you change directly with tracked changes?', array['Whole paragraphs', 'The student''s argument', 'Grammar, spelling and layout', 'Anything, if the student agrees'], 3), -- module 18: grammar, spelling, layout
  ('7a000000-0000-4000-8000-000000000019', 1, 'A student''s conclusion is weak and due tomorrow. What do you do?', array['Write a better conclusion for them to use', 'Comment on what the conclusion needs, linked to the rubric, and let them rewrite it', 'Leave it, as it''s too late', 'Send them a sample conclusion from another student'], 2), -- module 19: comment, they rewrite
  ('7a000000-0000-4000-8000-000000000019', 2, 'Which comment helps a student most?', array['"Good."', '"The rubric asks you to evaluate. Add a sentence on how strong this evidence is, and why."', '"Rewrite this paragraph like this: ..."', '"Needs work."'], 2), -- module 19: points to the rubric
  ('7a000000-0000-4000-8000-000000000020', 1, 'A parent writes in a Progress at home note that their child has been diagnosed with anxiety. What do you do?', array['Reply in the note with advice', 'Don''t reply in the note, and tell CLG', 'Ignore it', 'Ask the student about it in the next session'], 2), -- module 20: tell CLG
  ('7a000000-0000-4000-8000-000000000020', 2, 'A parent wants to change their session time and pay differently. Who sorts this out?', array['You, by private message', 'CLG, through the app', 'The student', 'Nobody, times can''t change'], 2), -- module 20: CLG
  ('7a000000-0000-4000-8000-000000000021', 1, 'A parent asks if their child will get an A this term. What do you say?', array['"Yes, definitely"', 'Explain what you''re working on and how they''re progressing, without promising a grade', '"That''s not my job"', '"Only if you book more sessions"'], 2), -- module 21: no promises
  ('7a000000-0000-4000-8000-000000000021', 2, 'A parent is unhappy about the session time. What do you do?', array['Change it yourself by private message', 'Listen, then pass it to CLG', 'Tell them it can''t change', 'Ignore it'], 2), -- module 21: pass it to CLG
  ('7a000000-0000-4000-8000-000000000022', 1, 'You think a student might have dyslexia. What do you do?', array['Tell the parent your view', 'Tell CLG what you''ve noticed, and keep adjusting your sessions', 'Ask the student if they have dyslexia', 'Nothing'], 2), -- module 22: tell CLG
  ('7a000000-0000-4000-8000-000000000022', 2, 'Where do you find a student''s learning needs?', array['Ask the school', 'On the student''s profile in the app', 'Search online', 'The family''s emails'], 2), -- module 22: the profile
  ('7a000000-0000-4000-8000-000000000023', 1, 'A student gets overwhelmed by a full worksheet. Which is the best adjustment?', array['Give them more time on the full sheet', 'Do three questions well, one step at a time, checking each', 'Skip the topic', 'Do the worksheet for them'], 2), -- module 23: fewer, step by step
  ('7a000000-0000-4000-8000-000000000023', 2, 'What helps an anxious student settle?', array['A different session shape every week', 'A predictable routine for each session', 'Longer sessions with no breaks', 'More homework'], 2), -- module 23: routine
  ('7a000000-0000-4000-8000-000000000024', 1, 'Who sees the review before the family?', array['Nobody', 'Lauren, who checks and approves it', 'The student''s school', 'Other tutors'], 2), -- module 24: Lauren
  ('7a000000-0000-4000-8000-000000000024', 2, 'What do you write in a term review?', array['Only the student''s grades', 'How the term went, the focus for next term, and your recommendation with why', 'A copy of your session summaries', 'Health details the family told you'], 2), -- module 24: the three parts
  ('7a000000-0000-4000-8000-000000000025', 1, 'Which sentence belongs in a term review?', array['"Sam is doing great!"', '"Sam can now write a paragraph with a clear topic sentence and two pieces of evidence, without prompts."', '"Sam needs to try harder."', '"Sam has ADHD, which affects his focus."'], 2), -- module 25: specific progress
  ('7a000000-0000-4000-8000-000000000025', 2, 'Can you use an AI tool to help write a review if you remove the student''s name?', array['Yes', 'No, never put student information into AI tools', 'Only for the recommendation', 'Only if Lauren agrees'], 2) -- module 25: never
) as v(mod, n, prompt, options, correct) -- (the columns)
where exists (select 1 from public.training_modules m where m.id = v.mod::uuid and m.status = 'draft') -- only while the module is a draft
  and not exists (select 1 from public.training_questions x where x.module_id = v.mod::uuid and x.prompt = v.prompt); -- only if that question isn't there yet
