-- Support requests (subjects, end goal, extra information), the automatic
-- curriculum on assignment, and family notes. Runs after
-- access_rules.test.sql and reuses its helpers: owner (...a0), admin (...b0),
-- tutor T1 (...11), parents P1 (...01, Cara's parent) and P2 (...02).

select id as cara from public.students where full_name = 'Cara One' \gset

-- ---------------------------------------------------------------------------
-- Subjects a student wants help with
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.student_subjects where student_id = :'cara'), 1, 'subject saved when child added');
select tests.fails($$select public.add_my_child('No Subject', (current_date - interval '12 years')::date, 'SA', 'Year 7', 'Hill PS')$$, 'child without a subject');
select tests.fails($$select public.add_my_child('Empty Subject', (current_date - interval '12 years')::date, 'SA', 'Year 7', 'Hill PS', '[]'::jsonb)$$, 'child with empty subject list');
insert into public.student_subjects (student_id, subject) values (:'cara', 'English');
select tests.fails(format($$insert into public.student_subjects (student_id, subject) values (%L, 'Maths')$$, :'cara'), 'plain Maths must be General, Essential or Advanced');
select tests.fails(format($$insert into public.student_subjects (student_id, subject) values (%L, ' english ')$$, :'cara'), 'same subject twice');
select tests.fails(format($$update public.student_subjects set subject = 'Science' where student_id = %L$$, :'cara'), 'subjects are added or removed, not changed');
select tests.fails(format($$update public.student_subjects set working_level = 'Grade 4' where student_id = %L$$, :'cara'), 'unknown working level');
update public.student_subjects set working_level = null where student_id = :'cara' and subject = 'English';
select tests.eq((select count(*) from public.student_subjects where student_id = :'cara' and subject = 'General Maths' and working_level = 'Year 5'), 1, 'level saved per subject');
select tests.eq((select count(*) from public.student_subjects where student_id = :'cara'), 2, 'parent adds a subject');
delete from public.student_subjects where student_id = :'cara' and subject = 'English';
select tests.eq((select count(*) from public.student_subjects where student_id = :'cara'), 1, 'parent removes a subject');
-- End goal and other information
update public.students set goals = 'Feel confident for Year 7 maths', extra_info = 'Loves drawing' where id = :'cara';
select tests.eq((select count(*) from public.students where id = :'cara' and extra_info = 'Loves drawing'), 1, 'parent edits goal and extra information');
select tests.fails(format($$update public.students set extra_info = repeat('x', 2001) where id = %L$$, :'cara'), 'extra information too long');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.student_subjects where student_id = :'cara'), 0, 'other parent sees none');
select tests.fails(format($$insert into public.student_subjects (student_id, subject) values (%L, 'Science')$$, :'cara'), 'other parent adds a subject');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.fails(format($$insert into public.student_subjects (student_id, subject) values (%L, 'Science')$$, :'cara'), 'tutor adds a subject');
reset role;

select tests.claims(null);
set role anon;
select tests.fails($$select * from public.student_subjects$$, 'anon');
reset role;

-- ---------------------------------------------------------------------------
-- Subject and level matching
-- ---------------------------------------------------------------------------
select tests.eq(private.subject_fits('General Maths', 'General Mathematics')::int, 1, 'General Maths fits SACE General Mathematics');
select tests.eq(private.subject_fits('Advanced Maths', 'Mathematics')::int, 1, 'Advanced Maths fits AC9 Mathematics');
select tests.eq(private.subject_fits('General Maths', 'Essential Mathematics')::int, 0, 'General is not Essential');
select tests.eq(private.subject_fits('Humanities and Social Sciences', 'HASS F-6')::int, 1, 'HASS');
select tests.eq(private.subject_fits('History', 'History 7-10')::int, 1, 'History');
select tests.eq(private.subject_fits('Numeracy', 'Mathematics')::int, 1, 'Numeracy');
select tests.eq(private.subject_fits('English', 'Mathematics')::int, 0, 'English is not Maths');
select tests.eq(private.level_fits('Year 11', 'Year 11 (Stage 1)')::int, 1, 'Year 11 fits Stage 1');
select tests.eq(private.level_fits('Year 1', 'Year 11 (Stage 1)')::int, 0, 'Year 1 is not Year 11');
select tests.eq(private.level_fits('Year 6', 'Year 6')::int, 1, 'same year');

-- ---------------------------------------------------------------------------
-- Curriculum attached automatically when a tutor is assigned. Cara is in
-- Year 6 at school (access_rules.test.sql moved her up) but working at Year 5
-- in maths, so the Year 5 maths skills decide.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
insert into public.curriculum_frameworks (id, code, name, version, source) values
  ('00000000-0000-0000-0000-00000000a501', 'AUTO-M', 'Auto maths', '1', 'Test'),
  ('00000000-0000-0000-0000-00000000a502', 'AUTO-E', 'Auto English', '1', 'Test'),
  ('00000000-0000-0000-0000-00000000a503', 'AUTO-D', 'Auto draft maths', '1', 'Test'),
  ('00000000-0000-0000-0000-00000000a504', 'AUTO-S', 'Auto senior maths', '1', 'Test');
insert into public.curriculum_skills (framework_id, subject, level_band, description) values
  ('00000000-0000-0000-0000-00000000a501', 'Mathematics', 'Year 5', 'Maths skill'),
  ('00000000-0000-0000-0000-00000000a502', 'English', 'Year 6', 'English skill'),
  ('00000000-0000-0000-0000-00000000a503', 'Mathematics', 'Year 6', 'Draft skill'),
  ('00000000-0000-0000-0000-00000000a504', 'General Mathematics', 'Year 11 (Stage 1)', 'Senior skill');
select public.confirm_curriculum('00000000-0000-0000-0000-00000000a501');
select public.confirm_curriculum('00000000-0000-0000-0000-00000000a502');
select public.confirm_curriculum('00000000-0000-0000-0000-00000000a504');
reset role;

-- Assigned by the backend so tutor checks don't get in the way here; the
-- attach step is the same for an admin.
select tests.claims(null);
insert into public.tutor_assignments (tutor_id, student_id, subject)
  values ('00000000-0000-0000-0000-000000000011', :'cara', 'General Maths');
select tests.eq((select count(*) from public.student_frameworks where student_id = :'cara' and framework_id = '00000000-0000-0000-0000-00000000a501'), 1, 'matching curriculum attached');
select tests.eq((select count(*) from public.student_frameworks where student_id = :'cara' and framework_id = '00000000-0000-0000-0000-00000000a502'), 0, 'other subject not attached');
select tests.eq((select count(*) from public.student_frameworks where student_id = :'cara' and framework_id = '00000000-0000-0000-0000-00000000a503'), 0, 'draft curriculum not attached');
select tests.eq((select count(*) from public.student_frameworks where student_id = :'cara' and framework_id = '00000000-0000-0000-0000-00000000a504'), 0, 'other year level not attached');
-- A second assignment for the same subject doesn't fail or duplicate.
insert into public.tutor_assignments (tutor_id, student_id, subject)
  values ('00000000-0000-0000-0000-000000000011', :'cara', 'General Maths');
select tests.eq((select count(*) from public.student_frameworks where student_id = :'cara' and framework_id = '00000000-0000-0000-0000-00000000a501'), 1, 'attached once');
delete from public.tutor_assignments where student_id = :'cara' and created_by is null and subject = 'General Maths'
  and created_at >= now() - interval '1 minute';

-- ---------------------------------------------------------------------------
-- Family notes: feedback and progress at home
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
insert into public.family_notes (student_id, kind, body) values (:'cara', 'home_progress', 'Practised times tables every night');
insert into public.family_notes (student_id, kind, body) values (:'cara', 'feedback', 'Sessions are going well');
select tests.eq((select count(*) from public.family_notes where student_id = :'cara' and written_by = '00000000-0000-0000-0000-000000000001'), 2, 'parent writes notes');
select tests.fails(format($$insert into public.family_notes (student_id, kind, body) values (%L, 'session', 'x')$$, :'cara'), 'unknown kind');
select tests.fails(format($$insert into public.family_notes (student_id, kind, body) values (%L, 'feedback', '')$$, :'cara'), 'empty note');
select tests.fails($$update public.family_notes set body = 'changed'$$, 'notes are not edited');
delete from public.family_notes;
select tests.eq((select count(*) from public.family_notes where student_id = :'cara'), 2, 'parent cannot delete notes');
select tests.fails(format($$select public.save_session_note(%L, current_date, 60, 'present', 'Good', 'Practise')$$, :'cara'), 'parent cannot write a session note');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.family_notes), 0, 'other parent sees none');
select tests.fails(format($$insert into public.family_notes (student_id, kind, body) values (%L, 'feedback', 'x')$$, :'cara'), 'other parent writes a note');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.fails(format($$insert into public.family_notes (student_id, kind, body) values (%L, 'feedback', 'x')$$, :'cara'), 'tutor writes a family note');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.family_notes where student_id = :'cara'), 2, 'admin sees notes');
reset role;

select tests.claims(null);
set role anon;
select tests.fails($$select * from public.family_notes$$, 'anon');
reset role;

\echo '  support requests: all checks passed'
