-- Progress tracking tests. Runs after access_rules.test.sql and reuses its
-- helpers and people: owner ...a0, tutor T1 ...11 (teaches Cara One),
-- tutor T2 ...12 (teaches Vic Two), parent P1 ...01 (Cara's parent),
-- parent P2 ...02 (Vic's parent).

-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset

-- ===========================================================================
-- Skill library
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$insert into public.curriculum_frameworks (code, name, version) values ('X', 'X', '1')$$, 'parent adds framework'); -- Checks this is refused: parent adds framework.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.curriculum_frameworks (id, code, name, version) -- Adds a test curriculum:
  values ('00000000-0000-0000-0000-00000000f001', 'AC9', 'Australian Curriculum', '9.0'); -- (Australian Curriculum 9.0).
insert into public.curriculum_skills (id, framework_id, subject, level_band, code, description) values -- Adds three skills to it:
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000f001', 'Mathematics', 'Year 5', 'M5-1', 'Fractions skill'), -- Year 5 fractions,
  ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-00000000f001', 'Mathematics', 'Year 4', 'M4-1', 'Place value skill'), -- Year 4 place value,
  ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-00000000f001', 'English', 'Year 3', 'E3-1', 'Spelling skill'); -- Year 3 spelling.
-- A new curriculum is a draft until confirmed.
select tests.fails($$insert into public.student_frameworks (student_id, framework_id) values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000f001')$$, 'draft curriculum cannot be set for a student'); -- Checks this is refused: draft curriculum cannot be set for a student.
select tests.fails($$update public.curriculum_frameworks set confirmed_at = now()$$, 'confirming by direct edit'); -- Checks this is refused: confirming by direct edit.
select tests.eq((select public.confirm_curriculum('00000000-0000-0000-0000-00000000f001'))::int, 1, 'admin confirms curriculum'); -- Checks: admin confirms curriculum.
select tests.eq((select count(*) from public.curriculum_frameworks where confirmed_by = '00000000-0000-0000-0000-0000000000a0'), 1, 'confirmation stamped'); -- Checks: confirmation stamped.
insert into public.student_frameworks (student_id, framework_id) values (:'cara', '00000000-0000-0000-0000-00000000f001'); -- Puts Cara on that curriculum.
select tests.eq((select count(*) from public.student_frameworks where set_by = '00000000-0000-0000-0000-0000000000a0'), 1, 'framework assignment stamped'); -- Checks: framework assignment stamped.
select tests.fails($$delete from public.curriculum_skills where code = 'E3-1'$$, 'skills cannot be deleted'); -- Checks this is refused: skills cannot be deleted.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.curriculum_skills), 3, 'anyone signed in reads the skill library'); -- Checks: anyone signed in reads the skill library.
select tests.eq((select count(*) from public.student_frameworks), 0, 'other parent cannot see Cara''s curriculum'); -- Checks: other parent cannot see Cara's curriculum.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Goals
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.learning_goals (id, student_id, subject, title) -- Adds a maths goal for Cara:
  values ('00000000-0000-0000-0000-00000000a001', :'cara', 'Mathematics', 'Add and compare simple fractions'); -- (comparing fractions).
insert into public.goal_skills (goal_id, skill_id) values -- Adds two skills to the goal:
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000c001'), -- fractions,
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000c002'); -- and place value.
select tests.eq((select count(*) from public.learning_goals where created_by = '00000000-0000-0000-0000-000000000011'), 1, 'goal stamped with tutor'); -- Checks: goal stamped with tutor.
insert into public.learning_goals (student_id, subject, title) values -- Adds two more maths goals:
  (:'cara', 'Mathematics', 'Second maths goal'), -- a second,
  (:'cara', 'Mathematics', 'Third maths goal'); -- and a third.
select tests.fails(format($$insert into public.learning_goals (student_id, subject, title) values (%L, 'Mathematics', 'Fourth maths goal')$$, :'cara'), 'fourth active goal in a subject'); -- Checks this is refused: fourth active goal in a subject.
update public.learning_goals set status = 'achieved' where title = 'Third maths goal'; -- Marks the third goal achieved.
select tests.eq((select count(*) from public.learning_goals where title = 'Third maths goal' and closed_at is not null), 1, 'closing a goal records when'); -- Checks: closing a goal records when.
insert into public.learning_goals (student_id, subject, title) values (:'cara', 'Mathematics', 'Replacement goal'); -- Adds a replacement goal.
select tests.fails($$delete from public.learning_goals$$, 'goals cannot be deleted'); -- Checks this is refused: goals cannot be deleted.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Without two-step login, the tutor has no access.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- Signs in as test account ...11.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.learning_goals), 0, 'tutor without two-step sees no goals'); -- Checks: tutor without two-step sees no goals.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- Signs in as test account ...12 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$insert into public.learning_goals (student_id, subject, title) values (%L, 'Mathematics', 'Not my student')$$, :'cara'), 'other tutor adds goal'); -- Checks this is refused: other tutor adds goal.
select tests.eq((select count(*) from public.learning_goals), 0, 'other tutor sees no goals'); -- Checks: other tutor sees no goals.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$insert into public.learning_goals (student_id, subject, title) values (%L, 'Mathematics', 'Parent goal')$$, :'cara'), 'parent adds goal'); -- Checks this is refused: parent adds goal.
select tests.eq((select count(*) from public.learning_goals where status = 'active'), 3, 'parent sees child''s goals'); -- Checks: parent sees child's goals.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Session notes and skill levels
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.save_session_note(:'cara', current_date, 60, 'attended', -- The tutor saves a session note for Cara:
  'You compared fractions with the same denominator on your own.', -- what went well,
  'Try comparing 2/3 and 3/4 by drawing them.', -- the next step,
  'Worksheet 3', current_date + 7, -- homework, due in a week,
  'Seemed tired today.', -- a staff-only note,
  -- and one skill moved to "learning"; keeps the note's id as note1.
  '[{"skill_id":"00000000-0000-0000-0000-00000000c001","level":"learning"}]'::jsonb) as note1 \gset
select tests.eq((select count(*) from public.student_skill_levels where level = 'learning'), 1, 'skill level moved'); -- Checks: skill level moved.
select tests.eq((select count(*) from public.session_note_skills where level_before = 'not_started' and level_after = 'learning'), 1, 'note records before and after'); -- Checks: note records before and after.
select tests.eq((select count(*) from public.session_staff_notes), 1, 'tutor reads staff note'); -- Checks: tutor reads staff note.
-- Rules on skills
select tests.fails(format($$select public.save_session_note(%L, current_date, 60, 'attended', 'ok', 'next', -- Checks a skill can't jump two steps:
  null, null, null, '[{"skill_id":"00000000-0000-0000-0000-00000000c001","level":"secure_on_own"}]')$$, :'cara'), 'skill jumps two steps'); -- (straight to "secure on own").
select tests.fails(format($$select public.save_session_note(%L, current_date, 60, 'attended', 'ok', 'next', -- Checks a skill outside the current goals is refused:
  null, null, null, '[{"skill_id":"00000000-0000-0000-0000-00000000c003","level":"learning"}]')$$, :'cara'), 'skill outside current goals'); -- (the spelling skill).
select tests.fails(format($$select public.save_session_note(%L, current_date, 60, 'attended', 'ok', null)$$, :'cara'), 'attended session without a next step'); -- Checks this is refused: attended session without a next step.
select tests.fails(format($$select public.save_session_note(%L, current_date + 2, 60, 'attended', 'ok', 'next')$$, :'cara'), 'note dated in the future'); -- Checks this is refused: note dated in the future.
select public.save_session_note(:'cara', current_date, 0, 'absent', null, null); -- Saves a note for an absent session.
-- Direct writes are blocked; corrections to own note are allowed.
select tests.fails(format($$insert into public.student_skill_levels (student_id, skill_id, level) values (%L, '00000000-0000-0000-0000-00000000c002', 'secure_on_own')$$, :'cara'), 'tutor writes level directly'); -- Checks this is refused: tutor writes level directly.
select tests.fails($$insert into public.session_staff_notes (note_id, body) select id, 'x' from public.session_notes limit 1$$, 'tutor writes staff note directly'); -- Checks this is refused: tutor writes staff note directly.
update public.session_notes set next_step = 'Compare 2/3 and 3/4 by drawing them.' where id = :'note1'; -- Tries to change the next step.
select tests.eq((select count(*) from public.session_notes where next_step like 'Compare%'), 1, 'tutor corrects own note'); -- Checks: tutor corrects own note.
select tests.fails(format($$update public.session_notes set student_id = (select id from public.students where full_name = 'Ada Learner') where id = %L$$, :'note1'), 'note moved to another student'); -- Checks this is refused: note moved to another student.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- Signs in as test account ...11.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.save_session_note(%L, current_date, 60, 'attended', 'ok', 'next')$$, :'cara'), 'tutor without two-step writes note'); -- Checks this is refused: tutor without two-step writes note.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- Signs in as test account ...12 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.save_session_note(%L, current_date, 60, 'attended', 'ok', 'next')$$, :'cara'), 'other tutor writes note'); -- Checks this is refused: other tutor writes note.
select tests.eq((select count(*) from public.session_notes), 0, 'other tutor sees no notes'); -- Checks: other tutor sees no notes.
select tests.eq((select count(*) from public.session_staff_notes), 0, 'other tutor sees no staff notes'); -- Checks: other tutor sees no staff notes.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- What families see, and reflections
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.session_notes), 2, 'parent sees child''s notes'); -- Checks: parent sees child's notes.
select tests.eq((select count(*) from public.student_skill_levels), 1, 'parent sees skill levels'); -- Checks: parent sees skill levels.
select tests.eq((select count(*) from public.session_note_skills), 1, 'parent sees skills worked on'); -- Checks: parent sees skills worked on.
select tests.eq((select count(*) from public.session_staff_notes), 0, 'parent never sees staff notes'); -- Checks: parent never sees staff notes.
update public.session_notes set went_well = 'changed' where id = :'note1'; -- Tries to change what went well.
select tests.eq((select count(*) from public.session_notes where went_well = 'changed'), 0, 'parent cannot edit a note'); -- Checks: parent cannot edit a note.
insert into public.student_reflections (note_id, student_id, confidence, what_was_hard, what_i_will_try) -- Adds Cara's reflection on the note:
  values (:'note1', :'cara', 3, 'Different denominators', 'Draw the fractions'); -- (fairly confident, with what was hard and what she'll try).
select tests.eq((select count(*) from public.student_reflections where written_by = '00000000-0000-0000-0000-000000000001'), 1, 'parent writes reflection for young child'); -- Checks: parent writes reflection for young child.
select tests.fails(format($$insert into public.student_reflections (note_id, student_id, confidence) values (%L, (select id from public.students where full_name = 'Vic Two'), 2)$$, :'note1'), 'reflection attached to another student'); -- Checks this is refused: reflection attached to another student.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.session_notes), 0, 'other parent sees no notes'); -- Checks: other parent sees no notes.
select tests.eq((select count(*) from public.student_skill_levels), 0, 'other parent sees no levels'); -- Checks: other parent sees no levels.
select tests.eq((select count(*) from public.student_reflections), 0, 'other parent sees no reflections'); -- Checks: other parent sees no reflections.
select tests.fails(format($$insert into public.student_reflections (note_id, student_id, confidence) values (%L, %L, 1)$$, :'note1', :'cara'), 'other parent writes reflection'); -- Checks this is refused: other parent writes reflection.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.student_reflections), 1, 'tutor reads reflections'); -- Checks: tutor reads reflections.
select tests.fails(format($$insert into public.student_reflections (note_id, student_id, confidence) values (%L, %L, 1)$$, :'note1', :'cara'), 'tutor writes reflection'); -- Checks this is refused: tutor writes reflection.
reset role; -- Goes back to the all-powerful test user (access rules off).

set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.session_notes$$, 'anon reads notes'); -- Checks this is refused: anon reads notes.
select tests.fails($$select * from public.curriculum_skills$$, 'anon reads skills'); -- Checks this is refused: anon reads skills.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- A session counts as activity for automatic deletion.
update public.students set last_activity_at = now() - interval '5 years', created_at = now() - interval '5 years' where id = :'cara'; -- Makes Cara look inactive for 5 years.
select tests.eq((select (private.student_last_activity(:'cara') >= current_date::timestamptz)::int), 1, 'session note counts as recent activity'); -- Checks: session note counts as recent activity.
update public.students set last_activity_at = now(), created_at = now() where id = :'cara'; -- Makes her active again.

-- Prints that every check in this file passed.
\echo '  progress: all checks passed'
