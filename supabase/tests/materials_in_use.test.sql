-- Materials in use: booklets, recording use from a session note, materials
-- for a student, and the skill picker's year filter. Runs after
-- access_rules.test.sql: owner ...a0, tutor T1 ...11 (General Maths Years 3
-- to 6, tutors Cara One, Year 5), tutor T2 ...12, parent P1 ...01.
-- Cleans up after itself.

-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset

insert into public.curriculum_frameworks (id, code, name, version, confirmed_at) values -- Adds a confirmed test curriculum:
  ('00000000-0000-0000-0000-00000000f611', 'MUSE', 'Materials in use test', '1', now()); -- (called "Materials in use test").
insert into public.curriculum_skills (id, framework_id, subject, level_band, code, description) values -- Adds three maths skills to it:
  ('00000000-0000-0000-0000-00000000c611', '00000000-0000-0000-0000-00000000f611', 'Mathematics', 'Year 5', 'MU5-1', 'Compare fractions'), -- Year 5 comparing fractions,
  ('00000000-0000-0000-0000-00000000c612', '00000000-0000-0000-0000-00000000f611', 'Mathematics', 'Year 4', 'MU4-1', 'Place value'), -- Year 4 place value,
  ('00000000-0000-0000-0000-00000000c613', '00000000-0000-0000-0000-00000000f611', 'Mathematics', 'Year 6', 'MU6-1', 'Decimals'); -- Year 6 decimals.

-- Booklets are a kind of material.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.materials (id, title, kind, subject, from_level, to_level, file_path, file_type, file_bytes) values -- Adds three materials:
  ('00000000-0000-0000-0000-00000000e611', 'Fractions booklet', 'booklet', 'General Maths', 'Year 4', 'Year 6', 'view/00000000-0000-0000-0000-00000000e611.pdf', 'application/pdf', 1000), -- a Year 4 to 6 fractions booklet,
  ('00000000-0000-0000-0000-00000000e612', 'Year 5 maths warm-ups', 'worksheet', 'General Maths', 'Year 5', 'Year 5', 'view/00000000-0000-0000-0000-00000000e612.pdf', 'application/pdf', 1000), -- a Year 5 warm-up worksheet,
  ('00000000-0000-0000-0000-00000000e613', 'Year 9 algebra', 'booklet', 'General Maths', 'Year 9', 'Year 9', 'view/00000000-0000-0000-0000-00000000e613.pdf', 'application/pdf', 1000); -- a Year 9 algebra booklet.
select tests.fails($$insert into public.materials (title, kind, subject, from_level, to_level, file_path, file_type, file_bytes) values ('Odd', 'poster', 'General Maths', 'Year 5', 'Year 5', 'view/00000000-0000-0000-0000-000000000001.pdf', 'application/pdf', 100)$$, 'unknown kind'); -- Checks this is refused: unknown kind.
insert into public.material_skills (material_id, skill_id) values -- Tags the fractions booklet with two skills:
  ('00000000-0000-0000-0000-00000000e611', '00000000-0000-0000-0000-00000000c611'), -- comparing fractions,
  ('00000000-0000-0000-0000-00000000e611', '00000000-0000-0000-0000-00000000c613'); -- and decimals.
update public.materials set status = 'published', no_skills_reason = case when id <> '00000000-0000-0000-0000-00000000e611' then 'test' end -- Publishes all three (the untagged ones with a reason):
  where id in ('00000000-0000-0000-0000-00000000e611', '00000000-0000-0000-0000-00000000e612', '00000000-0000-0000-0000-00000000e613'); -- (these three materials).

-- Skill picker: narrow by year level.
select tests.eq((select count(*) from public.skills_for_material('General Maths', 'Year 4', 'Year 6')), 3, 'all three years'); -- Checks: all three years.
select tests.eq((select count(*) from public.skills_for_material('General Maths', 'Year 4', 'Year 6', null, 'Year 5')), 1, 'Year 5 only'); -- Checks: Year 5 only.
select tests.eq((select count(*) from public.skills_for_material('General Maths', 'Year 4', 'Year 6', 'decimal', 'Year 6')), 1, 'year and words'); -- Checks: year and words.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- A goal for Cara with the fractions and place value skills.
insert into public.learning_goals (id, student_id, subject, title) -- Adds a goal for Cara:
  values ('00000000-0000-0000-0000-00000000a611', :'cara', 'General Maths', 'Fractions and place value'); -- in General Maths.
insert into public.goal_skills (goal_id, skill_id) values -- Adds two skills to the goal:
  ('00000000-0000-0000-0000-00000000a611', '00000000-0000-0000-0000-00000000c611'), -- comparing fractions,
  ('00000000-0000-0000-0000-00000000a611', '00000000-0000-0000-0000-00000000c612'); -- and place value.

-- Materials for Cara: the booklet (goal skill match) first, then the Year 5
-- warm-ups (her level), not Year 9 algebra.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.materials_for_student(:'cara')), 2, 'two materials fit Cara'); -- Checks: two materials fit Cara.
select tests.eq((select count(*) from public.materials_for_student(:'cara') where material_id = '00000000-0000-0000-0000-00000000e611' and goal_skill_ids = array['00000000-0000-0000-0000-00000000c611'::uuid]), 1, 'booklet lists only the goal skill it covers'); -- Checks: booklet lists only the goal skill it covers.
select tests.eq((select count(*) from (select material_id from public.materials_for_student(:'cara') limit 1) x where material_id = '00000000-0000-0000-0000-00000000e611'), 1, 'goal match listed first'); -- Checks: goal match listed first.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- Signs in as test account ...12 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select * from public.materials_for_student(%L)$$, :'cara'), 'another tutor'); -- Checks this is refused: another tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- Signs in as test account ...01 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select * from public.materials_for_student(%L)$$, :'cara'), 'parent'); -- Checks this is refused: parent.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Recording use from a session note.
insert into public.session_notes (id, student_id, tutor_id, session_date, minutes, attendance, went_well, next_step) -- Adds a session note from tutor T1:
  values ('00000000-0000-0000-0000-00000000d611', :'cara', '00000000-0000-0000-0000-000000000011', current_date, 60, 'attended', 'Good', 'Next'); -- (today, an hour, attended).
insert into public.session_notes (id, student_id, tutor_id, session_date, minutes, attendance, went_well, next_step) -- Adds a session note from tutor T2:
  values ('00000000-0000-0000-0000-00000000d612', :'cara', '00000000-0000-0000-0000-000000000012', current_date, 60, 'attended', 'Good', 'Next'); -- (today, an hour, attended).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(public.record_material_use('00000000-0000-0000-0000-00000000d611', array['00000000-0000-0000-0000-00000000e611'::uuid]), 1, 'tutor records the booklet'); -- Checks: tutor records the booklet.
select tests.eq(public.record_material_use('00000000-0000-0000-0000-00000000d611', array['00000000-0000-0000-0000-00000000e611'::uuid]), 0, 'recording twice adds nothing'); -- Checks: recording twice adds nothing.
select tests.fails($$select public.record_material_use('00000000-0000-0000-0000-00000000d611', array['00000000-0000-0000-0000-00000000e613'::uuid])$$, 'material the tutor cannot open'); -- Checks this is refused: material the tutor cannot open.
select tests.fails($$select public.record_material_use('00000000-0000-0000-0000-00000000d612', array['00000000-0000-0000-0000-00000000e611'::uuid])$$, 'another tutor''s note'); -- Checks this is refused: another tutor's note.
select tests.fails($$insert into public.material_uses (material_id, student_id, used_on) values ('00000000-0000-0000-0000-00000000e611', '00000000-0000-0000-0000-000000000000', current_date)$$, 'writing the table directly'); -- Checks this is refused: writing the table directly.
select tests.eq((select count(*) from public.material_uses), 1, 'tutor sees their student''s use'); -- Checks: tutor sees their student's use.
select tests.eq((select times_used from public.materials_for_student(:'cara') where material_id = '00000000-0000-0000-0000-00000000e611'), 1, 'use counted'); -- Checks: use counted.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- Signs in as test account ...01 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.material_uses), 0, 'family does not see material use'); -- Checks: family does not see material use.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.material_uses), 1, 'admin sees material use'); -- Checks: admin sees material use.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Clean up.
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.roadmap_steps where note_id in ('00000000-0000-0000-0000-00000000d611', '00000000-0000-0000-0000-00000000d612'); -- Removes roadmap steps made from those notes.
delete from public.session_notes where id in ('00000000-0000-0000-0000-00000000d611', '00000000-0000-0000-0000-00000000d612'); -- Removes the two notes.
delete from public.goal_skills where goal_id = '00000000-0000-0000-0000-00000000a611'; -- Removes the goal's skills.
delete from public.learning_goals where id = '00000000-0000-0000-0000-00000000a611'; -- Removes the goal.
delete from public.materials; -- Removes the test materials.
delete from public.curriculum_skills where framework_id = '00000000-0000-0000-0000-00000000f611'; -- Removes the test skills.
delete from public.curriculum_frameworks where id = '00000000-0000-0000-0000-00000000f611'; -- Removes the test curriculum.

-- Prints that every check in this file passed.
\echo '  materials in use: all checks passed'
