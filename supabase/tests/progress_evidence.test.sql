-- Evidence of learning and the family upload portal. Runs after
-- progress_drafts.test.sql (alphabetical) and reuses the people from
-- progress.test.sql: owner ...a0, tutor T1 ...11 (teaches Cara One), tutor
-- T2 ...12, parent P1 ...01 (Cara's parent), parent P2 ...02.

-- The migration is safe to run twice. It needs the roadmaps and term review
-- migrations, which the runner has already applied.
-- Runs the database change 20261029500300_progress_evidence.sql first, as this test needs it.
\ir ../migrations/20261029500300_progress_evidence.sql

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset
-- Keeps Vic's student id as vic.
select id as vic from public.students where full_name = 'Vic Two' \gset
-- Keeps a photo's file path in Cara's folder as file1.
select :'cara' || '/11111111-1111-1111-1111-111111111111.jpg' as file1 \gset
-- Keeps a PDF's file path in Cara's folder as file2.
select :'cara' || '/22222222-2222-2222-2222-222222222222.pdf' as file2 \gset

-- ===========================================================================
-- Uploading
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$insert into storage.objects (bucket_id, name) values ('learning-evidence', %L)$$, :'file1'), 'other parent uploads into Cara''s folder'); -- Checks this is refused: other parent uploads into Cara's folder.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$insert into storage.objects (bucket_id, name) values ('learning-evidence', 'not-a-student/x.jpg')$$, 'upload outside a student folder'); -- Checks this is refused: upload outside a student folder.
insert into storage.objects (bucket_id, name) values ('learning-evidence', :'file1'), ('learning-evidence', :'file2'); -- Adds both files to storage, as if uploaded.
insert into public.learning_evidence (id, student_id, kind, subject, title, dated_on, grade, file_path, file_type, uploaded_by_role) -- Adds a record for the photo:
  values ('00000000-0000-0000-0000-0000000e1001', :'cara', 'graded_work', 'General Maths', 'Fractions quiz', current_date - 3, '15/20', :'file1', 'image/jpeg', 'tutor'); -- a graded fractions quiz, three days old, 15/20.
select tests.eq((select count(*) from public.learning_evidence where uploaded_by_role = 'parent' -- Checks the parent's upload is labelled as from the parent:
  and uploaded_by = '00000000-0000-0000-0000-000000000001'), 1, 'parent uploads graded work (labelled parent)'); -- (one record by parent P1).
select tests.fails(format($$insert into public.learning_evidence (student_id, kind, title, file_path, file_type, uploaded_by_role) -- Checks a record for a file that didn't upload is refused:
  values (%L, 'school_report', 'Report', %L, 'application/pdf', 'parent')$$, :'cara', :'cara' || '/33333333-3333-3333-3333-333333333333.pdf'), 'record for a file that didn''t upload'); -- (a school report for a file that isn't in storage).
select tests.fails(format($$insert into public.learning_evidence (student_id, kind, title, file_path, file_type, uploaded_by_role) -- Checks a record for a file in another student's folder is refused:
  values (%L, 'school_report', 'Report', %L, 'application/pdf', 'parent')$$, :'vic', :'file2'), 'record for a file in another student''s folder'); -- (Vic's record pointing at Cara's file).
select tests.fails(format($$insert into public.learning_evidence (student_id, kind, title, dated_on, file_path, file_type, uploaded_by_role) -- Checks a date in the future is refused:
  values (%L, 'naplan', 'NAPLAN', current_date + 5, %L, 'application/pdf', 'parent')$$, :'cara', :'file2'), 'dated in the future'); -- (NAPLAN dated five days ahead).
select tests.fails(format($$update public.learning_evidence set grade = '20/20' where id = '00000000-0000-0000-0000-0000000e1001'$$), 'parent changes the grade after upload'); -- Checks this is refused: parent changes the grade after upload.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Who can see it
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.learning_evidence), 0, 'other parent sees no uploads'); -- Checks: other parent sees no uploads.
select tests.eq((select count(*) from storage.objects where bucket_id = 'learning-evidence'), 0, 'other parent can''t open the files'); -- Checks: other parent can't open the files.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- Signs in as test account ...12 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.learning_evidence), 0, 'other tutor sees no uploads'); -- Checks: other tutor sees no uploads.
select tests.eq((select count(*) from storage.objects where bucket_id = 'learning-evidence'), 0, 'other tutor can''t open the files'); -- Checks: other tutor can't open the files.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- Signs in as test account ...11.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from storage.objects where bucket_id = 'learning-evidence'), 0, 'tutor without two-step can''t open the files'); -- Checks: tutor without two-step can't open the files.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- The tutor reviews it
-- ===========================================================================
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.progress_notices where kind = 'evidence_added' -- Checks the tutor is told about the upload:
  and account_id = '00000000-0000-0000-0000-000000000011' and student_id = :'cara'), 1, 'tutor told about the upload'); -- (one notice for tutor T1).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.learning_evidence where student_id = :'cara'), 1, 'tutor sees the upload'); -- Checks: tutor sees the upload.
select tests.eq((select count(*) from storage.objects where name = :'file1'), 1, 'tutor can open the file'); -- Checks: tutor can open the file.
select tests.fails($$select public.review_evidence('00000000-0000-0000-0000-0000000e1001', 'ok', array['00000000-0000-0000-0000-00000000c003']::uuid[])$$, 'linking a skill outside the goals'); -- Checks this is refused: linking a skill outside the goals.
select public.review_evidence('00000000-0000-0000-0000-0000000e1001', 'Good working shown on Q3.', array['00000000-0000-0000-0000-00000000c001']::uuid[]); -- The tutor reviews the quiz with a comment and one linked skill.
select tests.eq((select count(*) from public.learning_evidence where reviewed_by = '00000000-0000-0000-0000-000000000011' and tutor_comment like 'Good working%'), 1, 'tutor reviews it'); -- Checks: tutor reviews it.
select tests.fails($$insert into public.evidence_skills (evidence_id, skill_id) values ('00000000-0000-0000-0000-0000000e1001', '00000000-0000-0000-0000-00000000c002')$$, 'linking skills directly'); -- Checks this is refused: linking skills directly.
-- A tutor's own work sample doesn't notify anyone.
insert into storage.objects (bucket_id, name) values ('learning-evidence', :'cara' || '/44444444-4444-4444-4444-444444444444.png'); -- Adds a picture to storage, as if uploaded.
insert into public.learning_evidence (student_id, kind, title, file_path, file_type, uploaded_by_role) -- Adds a record for it:
  values (:'cara', 'work_sample', 'Fraction wall', :'cara' || '/44444444-4444-4444-4444-444444444444.png', 'image/png', 'parent'); -- a work sample from the parent.
select tests.eq((select count(*) from public.learning_evidence where title = 'Fraction wall' and uploaded_by_role = 'tutor'), 1, 'tutor''s upload labelled tutor'); -- Checks: tutor's upload labelled tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.review_evidence('00000000-0000-0000-0000-0000000e1001')$$, 'parent reviews'); -- Checks this is refused: parent reviews.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Removing
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.evidence_skills), 1, 'family sees the linked skill'); -- Checks: family sees the linked skill.
delete from storage.objects where name = :'file1'; -- Tries to delete the photo from storage.
select tests.eq((select count(*) from storage.objects where name = :'file1'), 1, 'a file in use can''t be removed directly'); -- Checks: a file in use can't be removed directly.
select tests.fails($$select * from public.evidence_files_to_remove()$$, 'family reads the removal queue'); -- Checks this is refused: family reads the removal queue.
delete from public.learning_evidence where id = '00000000-0000-0000-0000-0000000e1001'; -- Deletes the quiz record.
select tests.eq((select count(*) from public.learning_evidence where id = '00000000-0000-0000-0000-0000000e1001'), 0, 'parent removes the upload'); -- Checks: parent removes the upload.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.evidence_file_removals where file_path = :'file1'), 1, 'its file is queued for removal'); -- Checks: its file is queued for removal.
set role service_role; -- Acts as the server's own key.
select tests.eq((select count(*) from public.evidence_files_to_remove() f where f = :'file1'), 1, 'the daily job sees it'); -- Checks: the daily job sees it.
select public.evidence_files_removed(array[:'file1']); -- Marks the photo as removed from storage.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.evidence_file_removals), 0, 'and clears it'); -- Checks: and clears it.

set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.learning_evidence$$, 'anon reads uploads'); -- Checks this is refused: anon reads uploads.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Tidy up.
delete from public.learning_evidence where student_id = :'cara'; -- Clears Cara's uploads.
delete from public.evidence_file_removals; -- Clears the removal list.
delete from storage.objects where bucket_id = 'learning-evidence'; -- Clears the test files from storage.

-- Prints that every check in this file passed.
\echo '  progress evidence: all checks passed'
