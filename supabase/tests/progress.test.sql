-- Progress tracking tests. Runs after access_rules.test.sql and reuses its
-- helpers and people: owner ...a0, tutor T1 ...11 (teaches Cara One),
-- tutor T2 ...12 (teaches Vic Two), parent P1 ...01 (Cara's parent),
-- parent P2 ...02 (Vic's parent).

select id as cara from public.students where full_name = 'Cara One' \gset

-- ===========================================================================
-- Skill library
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails($$insert into public.curriculum_frameworks (code, name, version) values ('X', 'X', '1')$$, 'parent adds framework');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
insert into public.curriculum_frameworks (id, code, name, version)
  values ('00000000-0000-0000-0000-00000000f001', 'AC9', 'Australian Curriculum', '9.0');
insert into public.curriculum_skills (id, framework_id, subject, level_band, code, description) values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000f001', 'Mathematics', 'Year 5', 'M5-1', 'Fractions skill'),
  ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-00000000f001', 'Mathematics', 'Year 4', 'M4-1', 'Place value skill'),
  ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-00000000f001', 'English', 'Year 3', 'E3-1', 'Spelling skill');
-- A new curriculum is a draft until confirmed.
select tests.fails($$insert into public.student_frameworks (student_id, framework_id) values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000f001')$$, 'draft curriculum cannot be set for a student');
select tests.fails($$update public.curriculum_frameworks set confirmed_at = now()$$, 'confirming by direct edit');
select tests.eq((select public.confirm_curriculum('00000000-0000-0000-0000-00000000f001'))::int, 1, 'admin confirms curriculum');
select tests.eq((select count(*) from public.curriculum_frameworks where confirmed_by = '00000000-0000-0000-0000-0000000000a0'), 1, 'confirmation stamped');
insert into public.student_frameworks (student_id, framework_id) values (:'cara', '00000000-0000-0000-0000-00000000f001');
select tests.eq((select count(*) from public.student_frameworks where set_by = '00000000-0000-0000-0000-0000000000a0'), 1, 'framework assignment stamped');
select tests.fails($$delete from public.curriculum_skills where code = 'E3-1'$$, 'skills cannot be deleted');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.curriculum_skills), 3, 'anyone signed in reads the skill library');
select tests.eq((select count(*) from public.student_frameworks), 0, 'other parent cannot see Cara''s curriculum');
reset role;

-- ===========================================================================
-- Goals
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
insert into public.learning_goals (id, student_id, subject, title)
  values ('00000000-0000-0000-0000-00000000a001', :'cara', 'Mathematics', 'Add and compare simple fractions');
insert into public.goal_skills (goal_id, skill_id) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000c001'),
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000c002');
select tests.eq((select count(*) from public.learning_goals where created_by = '00000000-0000-0000-0000-000000000011'), 1, 'goal stamped with tutor');
insert into public.learning_goals (student_id, subject, title) values
  (:'cara', 'Mathematics', 'Second maths goal'),
  (:'cara', 'Mathematics', 'Third maths goal');
select tests.fails(format($$insert into public.learning_goals (student_id, subject, title) values (%L, 'Mathematics', 'Fourth maths goal')$$, :'cara'), 'fourth active goal in a subject');
update public.learning_goals set status = 'achieved' where title = 'Third maths goal';
select tests.eq((select count(*) from public.learning_goals where title = 'Third maths goal' and closed_at is not null), 1, 'closing a goal records when');
insert into public.learning_goals (student_id, subject, title) values (:'cara', 'Mathematics', 'Replacement goal');
select tests.fails($$delete from public.learning_goals$$, 'goals cannot be deleted');
reset role;

-- Without two-step login, the tutor has no access.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1');
set role authenticated;
select tests.eq((select count(*) from public.learning_goals), 0, 'tutor without two-step sees no goals');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2');
set role authenticated;
select tests.fails(format($$insert into public.learning_goals (student_id, subject, title) values (%L, 'Mathematics', 'Not my student')$$, :'cara'), 'other tutor adds goal');
select tests.eq((select count(*) from public.learning_goals), 0, 'other tutor sees no goals');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails(format($$insert into public.learning_goals (student_id, subject, title) values (%L, 'Mathematics', 'Parent goal')$$, :'cara'), 'parent adds goal');
select tests.eq((select count(*) from public.learning_goals where status = 'active'), 3, 'parent sees child''s goals');
reset role;

-- ===========================================================================
-- Session notes and skill levels
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select public.save_session_note(:'cara', current_date, 60, 'attended',
  'You compared fractions with the same denominator on your own.',
  'Try comparing 2/3 and 3/4 by drawing them.',
  'Worksheet 3', current_date + 7,
  'Seemed tired today.',
  '[{"skill_id":"00000000-0000-0000-0000-00000000c001","level":"learning"}]'::jsonb) as note1 \gset
select tests.eq((select count(*) from public.student_skill_levels where level = 'learning'), 1, 'skill level moved');
select tests.eq((select count(*) from public.session_note_skills where level_before = 'not_started' and level_after = 'learning'), 1, 'note records before and after');
select tests.eq((select count(*) from public.session_staff_notes), 1, 'tutor reads staff note');
-- Rules on skills
select tests.fails(format($$select public.save_session_note(%L, current_date, 60, 'attended', 'ok', 'next',
  null, null, null, '[{"skill_id":"00000000-0000-0000-0000-00000000c001","level":"secure_on_own"}]')$$, :'cara'), 'skill jumps two steps');
select tests.fails(format($$select public.save_session_note(%L, current_date, 60, 'attended', 'ok', 'next',
  null, null, null, '[{"skill_id":"00000000-0000-0000-0000-00000000c003","level":"learning"}]')$$, :'cara'), 'skill outside current goals');
select tests.fails(format($$select public.save_session_note(%L, current_date, 60, 'attended', 'ok', null)$$, :'cara'), 'attended session without a next step');
select tests.fails(format($$select public.save_session_note(%L, current_date + 2, 60, 'attended', 'ok', 'next')$$, :'cara'), 'note dated in the future');
select public.save_session_note(:'cara', current_date, 0, 'absent', null, null);
-- Direct writes are blocked; corrections to own note are allowed.
select tests.fails(format($$insert into public.student_skill_levels (student_id, skill_id, level) values (%L, '00000000-0000-0000-0000-00000000c002', 'secure_on_own')$$, :'cara'), 'tutor writes level directly');
select tests.fails($$insert into public.session_staff_notes (note_id, body) select id, 'x' from public.session_notes limit 1$$, 'tutor writes staff note directly');
update public.session_notes set next_step = 'Compare 2/3 and 3/4 by drawing them.' where id = :'note1';
select tests.eq((select count(*) from public.session_notes where next_step like 'Compare%'), 1, 'tutor corrects own note');
select tests.fails(format($$update public.session_notes set student_id = (select id from public.students where full_name = 'Ada Learner') where id = %L$$, :'note1'), 'note moved to another student');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1');
set role authenticated;
select tests.fails(format($$select public.save_session_note(%L, current_date, 60, 'attended', 'ok', 'next')$$, :'cara'), 'tutor without two-step writes note');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2');
set role authenticated;
select tests.fails(format($$select public.save_session_note(%L, current_date, 60, 'attended', 'ok', 'next')$$, :'cara'), 'other tutor writes note');
select tests.eq((select count(*) from public.session_notes), 0, 'other tutor sees no notes');
select tests.eq((select count(*) from public.session_staff_notes), 0, 'other tutor sees no staff notes');
reset role;

-- ===========================================================================
-- What families see, and reflections
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.session_notes), 2, 'parent sees child''s notes');
select tests.eq((select count(*) from public.student_skill_levels), 1, 'parent sees skill levels');
select tests.eq((select count(*) from public.session_note_skills), 1, 'parent sees skills worked on');
select tests.eq((select count(*) from public.session_staff_notes), 0, 'parent never sees staff notes');
update public.session_notes set went_well = 'changed' where id = :'note1';
select tests.eq((select count(*) from public.session_notes where went_well = 'changed'), 0, 'parent cannot edit a note');
insert into public.student_reflections (note_id, student_id, confidence, what_was_hard, what_i_will_try)
  values (:'note1', :'cara', 3, 'Different denominators', 'Draw the fractions');
select tests.eq((select count(*) from public.student_reflections where written_by = '00000000-0000-0000-0000-000000000001'), 1, 'parent writes reflection for young child');
select tests.fails(format($$insert into public.student_reflections (note_id, student_id, confidence) values (%L, (select id from public.students where full_name = 'Vic Two'), 2)$$, :'note1'), 'reflection attached to another student');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.session_notes), 0, 'other parent sees no notes');
select tests.eq((select count(*) from public.student_skill_levels), 0, 'other parent sees no levels');
select tests.eq((select count(*) from public.student_reflections), 0, 'other parent sees no reflections');
select tests.fails(format($$insert into public.student_reflections (note_id, student_id, confidence) values (%L, %L, 1)$$, :'note1', :'cara'), 'other parent writes reflection');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.student_reflections), 1, 'tutor reads reflections');
select tests.fails(format($$insert into public.student_reflections (note_id, student_id, confidence) values (%L, %L, 1)$$, :'note1', :'cara'), 'tutor writes reflection');
reset role;

set role anon;
select tests.fails($$select * from public.session_notes$$, 'anon reads notes');
select tests.fails($$select * from public.curriculum_skills$$, 'anon reads skills');
reset role;
select tests.claims(null);

-- A session counts as activity for automatic deletion.
update public.students set last_activity_at = now() - interval '5 years', created_at = now() - interval '5 years' where id = :'cara';
select tests.eq((select (private.student_last_activity(:'cara') >= current_date::timestamptz)::int), 1, 'session note counts as recent activity');
update public.students set last_activity_at = now(), created_at = now() where id = :'cara';

\echo '  progress: all checks passed'
