-- Task sheets and rubrics for upcoming assessments, and who uploads school
-- reports and NAPLAN. Reuses the people from progress.test.sql: tutor T1
-- ...11 (teaches Cara One), parent P1 ...01 (manages Cara), parent P2 ...02
-- (manages Cal Two), login ...31 (Cal's own login, given here for a while).

-- Safe to run twice.
\ir ../migrations/20261029500500_progress_assessment_files.sql

select tests.claims(null);
select id as cara from public.students where full_name = 'Cara One' \gset
select id as cal from public.students where full_name = 'Cal Two' \gset
select :'cara' || '/a1111111-1111-1111-1111-111111111111.pdf' as sheet \gset
select :'cara' || '/a2222222-2222-2222-2222-222222222222.pdf' as rubric \gset
select :'cara' || '/a3333333-3333-3333-3333-333333333333.pdf' as report \gset

-- ===========================================================================
-- A parent adds an assessment with its task sheet and rubric
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
insert into public.roadmap_targets (id, student_id, kind, subject, title, due_on, target_grade)
  values ('00000000-0000-0000-0000-0000000d0101', :'cara', 'assessment', 'English', 'Persuasive essay', current_date + 14, 'B');
insert into storage.objects (bucket_id, name) values ('learning-evidence', :'sheet'), ('learning-evidence', :'rubric'), ('learning-evidence', :'report');
insert into public.learning_evidence (student_id, target_id, kind, subject, title, file_path, file_type, uploaded_by_role) values
  (:'cara', '00000000-0000-0000-0000-0000000d0101', 'task_sheet', 'English', 'Persuasive essay: task sheet', :'sheet', 'application/pdf', 'parent'),
  (:'cara', '00000000-0000-0000-0000-0000000d0101', 'rubric', 'English', 'Persuasive essay: rubric', :'rubric', 'application/pdf', 'parent');
select tests.eq((select count(*) from public.learning_evidence where target_id = '00000000-0000-0000-0000-0000000d0101'), 2, 'task sheet and rubric linked to the assessment');
insert into public.learning_evidence (student_id, kind, title, file_path, file_type, uploaded_by_role)
  values (:'cara', 'school_report', 'Term 3 report', :'report', 'application/pdf', 'parent');
select tests.eq((select count(*) from public.learning_evidence where kind = 'school_report'), 1, 'parent uploads a school report');
reset role;

select tests.claims(null);
select tests.eq((select count(*) from public.progress_notices where kind = 'evidence_added'
  and account_id = '00000000-0000-0000-0000-000000000011' and body like 'The family added the rubric for "Persuasive essay"%'), 1, 'tutor told about the rubric');

-- ===========================================================================
-- Tutors don't upload reports or NAPLAN
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
insert into storage.objects (bucket_id, name) values ('learning-evidence', :'cara' || '/a4444444-4444-4444-4444-444444444444.pdf');
select tests.fails(format($$insert into public.learning_evidence (student_id, kind, title, file_path, file_type, uploaded_by_role)
  values (%L, 'naplan', 'NAPLAN 2026', %L, 'application/pdf', 'parent')$$, :'cara', :'cara' || '/a4444444-4444-4444-4444-444444444444.pdf'), 'tutor uploads NAPLAN');
insert into public.learning_evidence (student_id, kind, title, file_path, file_type, uploaded_by_role)
  values (:'cara', 'work_sample', 'Essay plan', :'cara' || '/a4444444-4444-4444-4444-444444444444.pdf', 'application/pdf', 'tutor');
select tests.eq((select count(*) from public.learning_evidence where title = 'Essay plan'), 1, 'tutor still adds work samples');
reset role;

-- An assessment from another student's roadmap can't be used.
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
insert into storage.objects (bucket_id, name) values ('learning-evidence', :'cal' || '/a5555555-5555-5555-5555-555555555555.pdf');
select tests.fails(format($$insert into public.learning_evidence (student_id, target_id, kind, title, file_path, file_type, uploaded_by_role)
  values (%L, '00000000-0000-0000-0000-0000000d0101', 'task_sheet', 'Sheet', %L, 'application/pdf', 'parent')$$, :'cal', :'cal' || '/a5555555-5555-5555-5555-555555555555.pdf'), 'linking to another student''s assessment');
reset role;

-- ===========================================================================
-- A student with their own login, whose parent manages the account
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
update public.students set account_id = '00000000-0000-0000-0000-000000000031', date_of_birth = current_date - interval '17 years' where id = :'cal';
select tests.claims('00000000-0000-0000-0000-000000000031');
set role authenticated;
select tests.fails(format($$insert into public.learning_evidence (student_id, kind, title, file_path, file_type, uploaded_by_role)
  values (%L, 'school_report', 'My report', %L, 'application/pdf', 'student')$$, :'cal', :'cal' || '/a5555555-5555-5555-5555-555555555555.pdf'), 'student with a parent uploads a report');
insert into public.learning_evidence (student_id, kind, title, file_path, file_type, uploaded_by_role)
  values (:'cal', 'graded_work', 'My test', :'cal' || '/a5555555-5555-5555-5555-555555555555.pdf', 'application/pdf', 'student');
select tests.eq((select count(*) from public.learning_evidence where title = 'My test'), 1, 'student still uploads marked work');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
update public.students set account_id = null, date_of_birth = current_date - interval '12 years' where id = :'cal';

-- ===========================================================================
-- Removing the assessment removes its files
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.fails($$delete from public.roadmap_targets where id = '00000000-0000-0000-0000-0000000d0101'$$, 'tutor deletes an assessment (they close it instead)');
reset role;
select tests.claims(null);
-- As happens when a student's records are deleted.
delete from public.roadmap_targets where id = '00000000-0000-0000-0000-0000000d0101';
select tests.eq((select count(*) from public.learning_evidence where kind in ('task_sheet', 'rubric')), 0, 'task sheet and rubric go with the assessment');
select tests.eq((select count(*) from public.evidence_file_removals where file_path in (:'sheet', :'rubric')), 2, 'their files are queued for removal');

-- Tidy up.
delete from public.learning_evidence;
delete from public.evidence_file_removals;
delete from public.progress_notices where evidence_id is not null or kind = 'evidence_added';
delete from storage.objects where bucket_id = 'learning-evidence';

\echo '  assessment files: all checks passed'
