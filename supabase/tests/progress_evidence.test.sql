-- Evidence of learning and the family upload portal. Runs after
-- progress_drafts.test.sql (alphabetical) and reuses the people from
-- progress.test.sql: owner ...a0, tutor T1 ...11 (teaches Cara One), tutor
-- T2 ...12, parent P1 ...01 (Cara's parent), parent P2 ...02.

-- The migration is safe to run twice. It needs the roadmaps and term review
-- migrations, which the runner has already applied.
\ir ../migrations/20261029500300_progress_evidence.sql

select tests.claims(null);
select id as cara from public.students where full_name = 'Cara One' \gset
select id as vic from public.students where full_name = 'Vic Two' \gset
select :'cara' || '/11111111-1111-1111-1111-111111111111.jpg' as file1 \gset
select :'cara' || '/22222222-2222-2222-2222-222222222222.pdf' as file2 \gset

-- ===========================================================================
-- Uploading
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.fails(format($$insert into storage.objects (bucket_id, name) values ('learning-evidence', %L)$$, :'file1'), 'other parent uploads into Cara''s folder');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails($$insert into storage.objects (bucket_id, name) values ('learning-evidence', 'not-a-student/x.jpg')$$, 'upload outside a student folder');
insert into storage.objects (bucket_id, name) values ('learning-evidence', :'file1'), ('learning-evidence', :'file2');
insert into public.learning_evidence (id, student_id, kind, subject, title, dated_on, grade, file_path, file_type, uploaded_by_role)
  values ('00000000-0000-0000-0000-0000000e1001', :'cara', 'graded_work', 'General Maths', 'Fractions quiz', current_date - 3, '15/20', :'file1', 'image/jpeg', 'tutor');
select tests.eq((select count(*) from public.learning_evidence where uploaded_by_role = 'parent'
  and uploaded_by = '00000000-0000-0000-0000-000000000001'), 1, 'parent uploads graded work (labelled parent)');
select tests.fails(format($$insert into public.learning_evidence (student_id, kind, title, file_path, file_type, uploaded_by_role)
  values (%L, 'school_report', 'Report', %L, 'application/pdf', 'parent')$$, :'cara', :'cara' || '/33333333-3333-3333-3333-333333333333.pdf'), 'record for a file that didn''t upload');
select tests.fails(format($$insert into public.learning_evidence (student_id, kind, title, file_path, file_type, uploaded_by_role)
  values (%L, 'school_report', 'Report', %L, 'application/pdf', 'parent')$$, :'vic', :'file2'), 'record for a file in another student''s folder');
select tests.fails(format($$insert into public.learning_evidence (student_id, kind, title, dated_on, file_path, file_type, uploaded_by_role)
  values (%L, 'naplan', 'NAPLAN', current_date + 5, %L, 'application/pdf', 'parent')$$, :'cara', :'file2'), 'dated in the future');
select tests.fails(format($$update public.learning_evidence set grade = '20/20' where id = '00000000-0000-0000-0000-0000000e1001'$$), 'parent changes the grade after upload');
reset role;

-- ===========================================================================
-- Who can see it
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.learning_evidence), 0, 'other parent sees no uploads');
select tests.eq((select count(*) from storage.objects where bucket_id = 'learning-evidence'), 0, 'other parent can''t open the files');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.learning_evidence), 0, 'other tutor sees no uploads');
select tests.eq((select count(*) from storage.objects where bucket_id = 'learning-evidence'), 0, 'other tutor can''t open the files');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1');
set role authenticated;
select tests.eq((select count(*) from storage.objects where bucket_id = 'learning-evidence'), 0, 'tutor without two-step can''t open the files');
reset role;

-- ===========================================================================
-- The tutor reviews it
-- ===========================================================================
select tests.claims(null);
select tests.eq((select count(*) from public.progress_notices where kind = 'evidence_added'
  and account_id = '00000000-0000-0000-0000-000000000011' and student_id = :'cara'), 1, 'tutor told about the upload');

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.learning_evidence where student_id = :'cara'), 1, 'tutor sees the upload');
select tests.eq((select count(*) from storage.objects where name = :'file1'), 1, 'tutor can open the file');
select tests.fails($$select public.review_evidence('00000000-0000-0000-0000-0000000e1001', 'ok', array['00000000-0000-0000-0000-00000000c003']::uuid[])$$, 'linking a skill outside the goals');
select public.review_evidence('00000000-0000-0000-0000-0000000e1001', 'Good working shown on Q3.', array['00000000-0000-0000-0000-00000000c001']::uuid[]);
select tests.eq((select count(*) from public.learning_evidence where reviewed_by = '00000000-0000-0000-0000-000000000011' and tutor_comment like 'Good working%'), 1, 'tutor reviews it');
select tests.fails($$insert into public.evidence_skills (evidence_id, skill_id) values ('00000000-0000-0000-0000-0000000e1001', '00000000-0000-0000-0000-00000000c002')$$, 'linking skills directly');
-- A tutor's own work sample doesn't notify anyone.
insert into storage.objects (bucket_id, name) values ('learning-evidence', :'cara' || '/44444444-4444-4444-4444-444444444444.png');
insert into public.learning_evidence (student_id, kind, title, file_path, file_type, uploaded_by_role)
  values (:'cara', 'work_sample', 'Fraction wall', :'cara' || '/44444444-4444-4444-4444-444444444444.png', 'image/png', 'parent');
select tests.eq((select count(*) from public.learning_evidence where title = 'Fraction wall' and uploaded_by_role = 'tutor'), 1, 'tutor''s upload labelled tutor');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.fails($$select public.review_evidence('00000000-0000-0000-0000-0000000e1001')$$, 'parent reviews');
reset role;

-- ===========================================================================
-- Removing
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.evidence_skills), 1, 'family sees the linked skill');
delete from storage.objects where name = :'file1';
select tests.eq((select count(*) from storage.objects where name = :'file1'), 1, 'a file in use can''t be removed directly');
select tests.fails($$select * from public.evidence_files_to_remove()$$, 'family reads the removal queue');
delete from public.learning_evidence where id = '00000000-0000-0000-0000-0000000e1001';
select tests.eq((select count(*) from public.learning_evidence where id = '00000000-0000-0000-0000-0000000e1001'), 0, 'parent removes the upload');
reset role;

select tests.claims(null);
select tests.eq((select count(*) from public.evidence_file_removals where file_path = :'file1'), 1, 'its file is queued for removal');
set role service_role;
select tests.eq((select count(*) from public.evidence_files_to_remove() f where f = :'file1'), 1, 'the daily job sees it');
select public.evidence_files_removed(array[:'file1']);
reset role;
select tests.eq((select count(*) from public.evidence_file_removals), 0, 'and clears it');

set role anon;
select tests.fails($$select * from public.learning_evidence$$, 'anon reads uploads');
reset role;

-- Tidy up.
delete from public.learning_evidence where student_id = :'cara';
delete from public.evidence_file_removals;
delete from storage.objects where bucket_id = 'learning-evidence';

\echo '  progress evidence: all checks passed'
