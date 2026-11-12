-- Support requests (subjects, end goal, extra information), the automatic
-- curriculum on assignment, and family notes. Runs after
-- access_rules.test.sql and reuses its helpers: owner (...a0), admin (...b0),
-- tutor T1 (...11), parents P1 (...01, Cara's parent) and P2 (...02).

-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset

-- ---------------------------------------------------------------------------
-- Subjects a student wants help with
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.student_subjects where student_id = :'cara'), 1, 'subject saved when child added'); -- Checks: subject saved when child added.
select tests.fails($$select public.add_my_child('No Subject', (current_date - interval '12 years')::date, 'SA', 'Year 7', 'Hill PS')$$, 'child without a subject'); -- Checks this is refused: child without a subject.
select tests.fails($$select public.add_my_child('Empty Subject', (current_date - interval '12 years')::date, 'SA', 'Year 7', 'Hill PS', '[]'::jsonb)$$, 'child with empty subject list'); -- Checks this is refused: child with empty subject list.
insert into public.student_subjects (student_id, subject) values (:'cara', 'English'); -- Adds English to Cara's subjects.
select tests.fails(format($$insert into public.student_subjects (student_id, subject) values (%L, 'Maths')$$, :'cara'), 'plain Maths is refused'); -- Checks this is refused: plain Maths is refused.
select tests.fails(format($$insert into public.student_subjects (student_id, subject, working_level) values (%L, 'Mathematics', 'Year 11')$$, :'cara'), 'Mathematics is not a Year 11 subject'); -- Checks this is refused: Mathematics is not a Year 11 subject.
select tests.fails(format($$insert into public.student_subjects (student_id, subject) values (%L, ' english ')$$, :'cara'), 'same subject twice'); -- Checks this is refused: same subject twice.
select tests.fails(format($$update public.student_subjects set subject = 'Science' where student_id = %L$$, :'cara'), 'subjects are added or removed, not changed'); -- Checks this is refused: subjects are added or removed, not changed.
select tests.fails(format($$update public.student_subjects set working_level = 'Grade 4' where student_id = %L$$, :'cara'), 'unknown working level'); -- Checks this is refused: unknown working level.
update public.student_subjects set working_level = null where student_id = :'cara' and subject = 'English'; -- Clears her English working level.
select tests.eq((select count(*) from public.student_subjects where student_id = :'cara' and subject = 'General Maths' and working_level = 'Year 5'), 1, 'level saved per subject'); -- Checks: level saved per subject.
select tests.eq((select count(*) from public.student_subjects where student_id = :'cara'), 2, 'parent adds a subject'); -- Checks: parent adds a subject.
delete from public.student_subjects where student_id = :'cara' and subject = 'English'; -- Removes English again.
select tests.eq((select count(*) from public.student_subjects where student_id = :'cara'), 1, 'parent removes a subject'); -- Checks: parent removes a subject.
-- End goal and other information
update public.students set goals = 'Feel confident for Year 7 maths', extra_info = 'Loves drawing' where id = :'cara'; -- Writes Cara's end goal and other information.
select tests.eq((select count(*) from public.students where id = :'cara' and extra_info = 'Loves drawing'), 1, 'parent edits goal and extra information'); -- Checks: parent edits goal and extra information.
select tests.fails(format($$update public.students set extra_info = repeat('x', 2001) where id = %L$$, :'cara'), 'extra information too long'); -- Checks this is refused: extra information too long.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.student_subjects where student_id = :'cara'), 0, 'other parent sees none'); -- Checks: other parent sees none.
select tests.fails(format($$insert into public.student_subjects (student_id, subject) values (%L, 'Science')$$, :'cara'), 'other parent adds a subject'); -- Checks this is refused: other parent adds a subject.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$insert into public.student_subjects (student_id, subject) values (%L, 'Science')$$, :'cara'), 'tutor adds a subject'); -- Checks this is refused: tutor adds a subject.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.student_subjects$$, 'anon'); -- Checks this is refused: anon.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Subject and level matching
-- ---------------------------------------------------------------------------
select tests.eq(private.subject_fits('General Maths', 'General Mathematics')::int, 1, 'General Maths fits SACE General Mathematics'); -- Checks: General Maths fits SACE General Mathematics.
select tests.eq(private.subject_fits('Advanced Maths', 'Mathematics')::int, 1, 'Advanced Maths fits AC9 Mathematics'); -- Checks: Advanced Maths fits AC9 Mathematics.
select tests.eq(private.subject_fits('General Maths', 'Essential Mathematics')::int, 0, 'General is not Essential'); -- Checks: General is not Essential.
select tests.eq(private.subject_fits('Humanities and Social Sciences', 'HASS F-6')::int, 1, 'HASS'); -- Checks: HASS.
select tests.eq(private.subject_fits('History', 'History 7-10')::int, 1, 'History'); -- Checks: History.
select tests.eq(private.subject_fits('Numeracy', 'Mathematics')::int, 1, 'Numeracy'); -- Checks: Numeracy.
select tests.eq(private.subject_fits('English', 'Mathematics')::int, 0, 'English is not Maths'); -- Checks: English is not Maths.
select tests.eq(private.subject_fits('Mathematics', 'Mathematics')::int, 1, 'Mathematics fits AC9 Mathematics'); -- Checks: Mathematics fits AC9 Mathematics.
select tests.eq(private.subject_fits('Mathematics: General', 'General Mathematics')::int, 1, 'Mathematics: General fits SACE'); -- Checks: Mathematics: General fits SACE.
select tests.eq(private.subject_fits('Mathematics: Methods', 'Mathematical Methods')::int, 1, 'Mathematics: Methods fits SACE'); -- Checks: Mathematics: Methods fits SACE.
select tests.eq(private.subject_fits('Mathematics: Specialist', 'Specialist Mathematics')::int, 1, 'Mathematics: Specialist fits SACE'); -- Checks: Mathematics: Specialist fits SACE.
select tests.eq(private.subject_fits('Mathematics: Essential', 'General Mathematics')::int, 0, 'Essential is not General'); -- Checks: Essential is not General.
select tests.eq(private.level_fits('Year 11', 'Year 11 (Stage 1)')::int, 1, 'Year 11 fits Stage 1'); -- Checks: Year 11 fits Stage 1.
select tests.eq(private.level_fits('Year 1', 'Year 11 (Stage 1)')::int, 0, 'Year 1 is not Year 11'); -- Checks: Year 1 is not Year 11.
select tests.eq(private.level_fits('Year 6', 'Year 6')::int, 1, 'same year'); -- Checks: same year.

-- ---------------------------------------------------------------------------
-- Curriculum attached automatically when a tutor is assigned. Cara is in
-- Year 6 at school (access_rules.test.sql moved her up) but working at Year 5
-- in maths, so the Year 5 maths skills decide.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.curriculum_frameworks (id, code, name, version, source) values -- Adds four test curricula:
  ('00000000-0000-0000-0000-00000000a501', 'AUTO-M', 'Auto maths', '1', 'Test'), -- a maths one,
  ('00000000-0000-0000-0000-00000000a502', 'AUTO-E', 'Auto English', '1', 'Test'), -- an English one,
  ('00000000-0000-0000-0000-00000000a503', 'AUTO-D', 'Auto draft maths', '1', 'Test'), -- a draft maths one,
  ('00000000-0000-0000-0000-00000000a504', 'AUTO-S', 'Auto senior maths', '1', 'Test'); -- and a senior maths one.
insert into public.curriculum_skills (framework_id, subject, level_band, description) values -- Adds one skill to each:
  ('00000000-0000-0000-0000-00000000a501', 'Mathematics', 'Year 5', 'Maths skill'), -- Year 5 maths,
  ('00000000-0000-0000-0000-00000000a502', 'English', 'Year 6', 'English skill'), -- Year 6 English,
  ('00000000-0000-0000-0000-00000000a503', 'Mathematics', 'Year 6', 'Draft skill'), -- Year 6 draft maths,
  ('00000000-0000-0000-0000-00000000a504', 'General Mathematics', 'Year 11 (Stage 1)', 'Senior skill'); -- Year 11 General Mathematics.
select public.confirm_curriculum('00000000-0000-0000-0000-00000000a501'); -- Confirms the maths curriculum.
select public.confirm_curriculum('00000000-0000-0000-0000-00000000a502'); -- Confirms the English curriculum.
select public.confirm_curriculum('00000000-0000-0000-0000-00000000a504'); -- Confirms the senior maths curriculum (the draft one stays a draft).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Assigned by the backend so tutor checks don't get in the way here; the
-- attach step is the same for an admin.
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.tutor_assignments (tutor_id, student_id, subject) -- Assigns tutor T1 to Cara for General Maths:
  values ('00000000-0000-0000-0000-000000000011', :'cara', 'General Maths'); -- (tutor, student, subject).
select tests.eq((select count(*) from public.student_frameworks where student_id = :'cara' and framework_id = '00000000-0000-0000-0000-00000000a501'), 1, 'matching curriculum attached'); -- Checks: matching curriculum attached.
select tests.eq((select count(*) from public.student_frameworks where student_id = :'cara' and framework_id = '00000000-0000-0000-0000-00000000a502'), 0, 'other subject not attached'); -- Checks: other subject not attached.
select tests.eq((select count(*) from public.student_frameworks where student_id = :'cara' and framework_id = '00000000-0000-0000-0000-00000000a503'), 0, 'draft curriculum not attached'); -- Checks: draft curriculum not attached.
select tests.eq((select count(*) from public.student_frameworks where student_id = :'cara' and framework_id = '00000000-0000-0000-0000-00000000a504'), 0, 'other year level not attached'); -- Checks: other year level not attached.
-- A second assignment for the same subject doesn't fail or duplicate.
insert into public.tutor_assignments (tutor_id, student_id, subject) -- Assigns the same again:
  values ('00000000-0000-0000-0000-000000000011', :'cara', 'General Maths'); -- (tutor, student, subject).
select tests.eq((select count(*) from public.student_frameworks where student_id = :'cara' and framework_id = '00000000-0000-0000-0000-00000000a501'), 1, 'attached once'); -- Checks: attached once.
delete from public.tutor_assignments where student_id = :'cara' and created_by is null and subject = 'General Maths' -- Removes the assignment just added:
  and created_at >= now() - interval '1 minute'; -- (the one made in the last minute with no creator).

-- ---------------------------------------------------------------------------
-- Family notes: feedback and progress at home
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.family_notes (student_id, kind, body) values (:'cara', 'home_progress', 'Practised times tables every night'); -- Adds a "progress at home" note for Cara.
insert into public.family_notes (student_id, kind, body) values (:'cara', 'feedback', 'Sessions are going well'); -- Adds a feedback note for Cara.
select tests.eq((select count(*) from public.family_notes where student_id = :'cara' and written_by = '00000000-0000-0000-0000-000000000001'), 2, 'parent writes notes'); -- Checks: parent writes notes.
select tests.fails(format($$insert into public.family_notes (student_id, kind, body) values (%L, 'session', 'x')$$, :'cara'), 'unknown kind'); -- Checks this is refused: unknown kind.
select tests.fails(format($$insert into public.family_notes (student_id, kind, body) values (%L, 'feedback', '')$$, :'cara'), 'empty note'); -- Checks this is refused: empty note.
select tests.fails($$update public.family_notes set body = 'changed'$$, 'notes are not edited'); -- Checks this is refused: notes are not edited.
delete from public.family_notes; -- Clears the family notes.
select tests.eq((select count(*) from public.family_notes where student_id = :'cara'), 2, 'parent cannot delete notes'); -- Checks: parent cannot delete notes.
select tests.fails(format($$select public.save_session_note(%L, current_date, 60, 'present', 'Good', 'Practise')$$, :'cara'), 'parent cannot write a session note'); -- Checks this is refused: parent cannot write a session note.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.family_notes), 0, 'other parent sees none'); -- Checks: other parent sees none.
select tests.fails(format($$insert into public.family_notes (student_id, kind, body) values (%L, 'feedback', 'x')$$, :'cara'), 'other parent writes a note'); -- Checks this is refused: other parent writes a note.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$insert into public.family_notes (student_id, kind, body) values (%L, 'feedback', 'x')$$, :'cara'), 'tutor writes a family note'); -- Checks this is refused: tutor writes a family note.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.family_notes where student_id = :'cara'), 2, 'admin sees notes'); -- Checks: admin sees notes.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.family_notes$$, 'anon'); -- Checks this is refused: anon.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Prints that every check in this file passed.
\echo '  support requests: all checks passed'
