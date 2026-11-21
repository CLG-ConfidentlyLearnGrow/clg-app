-- Summary: tests the plan for the next session, session files and materials
-- linked to the plan (Carla, 21 Nov 2026; migration
-- 20261123620100_session_plans_and_files.sql).
-- Runs after progress.test.sql and progress_follow_up.test.sql and reuses
-- their people: owner ...a0 (admin), tutor T1 ...11 (teaches Cara One,
-- General Maths Years 3 to 6), tutor T2 ...12 (teaches Vic Two), parent P1
-- ...01 (Cara's parent), parent P2 ...02 (Vic's parent).
-- It checks: only Cara's tutor (or an admin) can save a plan; families and
-- other tutors cannot see plans; the plan links to the next booked session;
-- materials can be linked only if the tutor can open them; session files
-- are seen by the family but not by other families or tutors; only the
-- summary's tutor can add files, at most 10; deleted files are queued for
-- removal; and the 7-day limit. Cleans up its material at the end.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- The migration is safe to run twice.
\ir ../migrations/20261123620100_session_plans_and_files.sql

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset
-- Keeps Vic's student id as vic.
select id as vic from public.students where full_name = 'Vic Two' \gset

-- A session with Cara and tutor T1 in 3 days, and one with another tutor
-- in 1 day (the plan must link to T1's, not the sooner one with T2).
insert into public.sessions (id, student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status) values -- Adds two coming sessions:
  ('00000000-0000-0000-0000-0000000e5a01', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', -- Cara with tutor T1,
   now() + interval '3 days', now() + interval '3 days 1 hour', 'scheduled'), -- in 3 days;
  ('00000000-0000-0000-0000-0000000e5a02', :'cara', '00000000-0000-0000-0000-000000000012', 'General Maths', 'school', 'online', -- Cara with tutor T2,
   now() + interval '1 day', now() + interval '1 day 1 hour', 'scheduled'); -- in 1 day.

-- A published material tutor T1 can open (General Maths, Year 5), and one
-- they cannot (General Maths, Year 10, outside the years they teach).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into storage.objects (bucket_id, name) values -- Adds two material files, as if uploaded:
  ('materials', 'view/00000000-0000-0000-0000-00000000e5b1.pdf'), -- the Year 5 one,
  ('materials', 'view/00000000-0000-0000-0000-00000000e5b2.pdf'); -- the Year 10 one.
insert into public.materials (id, title, kind, subject, from_level, to_level, file_path, file_type, file_bytes) values -- Adds two materials:
  ('00000000-0000-0000-0000-00000000e5b1', 'Plan test fractions', 'worksheet', 'General Maths', 'Year 5', 'Year 5', 'view/00000000-0000-0000-0000-00000000e5b1.pdf', 'application/pdf', 1000), -- Year 5 fractions,
  ('00000000-0000-0000-0000-00000000e5b2', 'Plan test algebra', 'worksheet', 'General Maths', 'Year 10', 'Year 10', 'view/00000000-0000-0000-0000-00000000e5b2.pdf', 'application/pdf', 1000); -- Year 10 algebra.
update public.materials set status = 'published', no_skills_reason = 'Test material' -- Publishes both (with a reason they have no skills),
  where id in ('00000000-0000-0000-0000-00000000e5b1', '00000000-0000-0000-0000-00000000e5b2'); -- (these two).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Tutor T1 writes a summary, then the plan for the next session
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Saves a summary for today (not linked to a booked session) and keeps its id as note.
select public.save_session_note(:'cara', (now() at time zone 'Australia/Adelaide')::date, 60, 'attended', 'You compared fractions well.', 'Practise ordering three fractions.') as note \gset
select tests.fails(format($$select public.save_session_plan(%L, '', 'Fraction wall then ordering game')$$, :'note'), 'plan with no focus'); -- Checks a plan with no focus is refused.
select tests.fails(format($$select public.save_session_plan(%L, 'Order fractions', '')$$, :'note'), 'plan with no activities'); -- Checks a plan with no activities is refused.
select tests.fails(format($$select public.save_session_plan(%L, 'Order fractions', 'Game', p_materials => array['00000000-0000-0000-0000-00000000e5b2']::uuid[])$$, :'note'), 'material the tutor cannot open'); -- Checks a material T1 cannot open is refused.
select public.save_session_plan( -- Saves the plan:
  p_note => :'note', -- for that summary,
  p_focus => 'Order three fractions with different denominators', -- the focus,
  p_activities => 'Fraction wall, then the ordering card game, then two exit questions', -- the activities,
  p_review_first => 'Equivalent fractions', -- what to review first,
  p_success_check => 'Orders three fractions without the wall', -- how T1 will know it worked,
  p_materials => array['00000000-0000-0000-0000-00000000e5b1']::uuid[] -- and the Year 5 worksheet,
) as plan \gset
select tests.eq((select count(*) from public.session_plans where id = :'plan'), 1, 'tutor sees own plan'); -- Checks T1 can read the plan.
select tests.eq((select count(*) from public.session_plans where id = :'plan' and next_session_id = '00000000-0000-0000-0000-0000000e5a01'), 1, 'plan linked to the next session with the same tutor'); -- Checks the plan is for T1's next session (not T2's sooner one).
select tests.eq((select count(*) from public.session_plan_materials where plan_id = :'plan'), 1, 'material linked'); -- Checks the worksheet is linked.
select tests.fails($$insert into public.session_plans (note_id, student_id, focus, activities) select id, student_id, 'x x x', 'y y y' from public.session_notes limit 1$$, 'tutor writes plans directly'); -- Checks plans cannot be written directly.
select tests.fails(format($$update public.session_plans set focus = 'Changed directly' where id = %L$$, :'plan'), 'tutor changes plans directly'); -- Checks plans cannot be changed directly.
select tests.fails(format($$insert into public.session_plan_materials (plan_id, material_id) values (%L, '00000000-0000-0000-0000-00000000e5b2')$$, :'plan'), 'tutor links materials directly'); -- Checks materials cannot be linked directly.
-- Corrects the plan: one plan per summary, so it is changed, not added.
select public.save_session_plan(:'note', 'Order and compare fractions', 'Ordering card game and exit questions') as plan2 \gset
select tests.eq((select count(*) from public.session_plans where note_id = :'note'), 1, 'still one plan per summary'); -- Checks there is still one plan.
select tests.eq((select count(*) from public.session_plans where id = :'plan' and focus = 'Order and compare fractions'), 1, 'plan corrected in place'); -- Checks the same plan was corrected.
select tests.eq((select count(*) from public.session_plan_materials where plan_id = :'plan'), 0, 'materials list replaced'); -- Checks the materials list was replaced (none chosen this time).
select public.save_session_plan(:'note', 'Order and compare fractions', 'Ordering card game and exit questions', p_materials => array['00000000-0000-0000-0000-00000000e5b1']::uuid[]); -- Links the worksheet again.

-- Session files: T1 uploads a photo into Cara's folder and attaches it.
insert into storage.objects (bucket_id, name) values ('session-files', :'cara' || '/whiteboard.jpg'); -- Uploads a file into Cara's folder.
select tests.fails(format($$insert into storage.objects (bucket_id, name) values ('session-files', %L)$$, :'vic' || '/x.jpg'), 'tutor uploads into another student''s folder'); -- Checks T1 cannot upload into Vic's folder.
select tests.fails($$insert into storage.objects (bucket_id, name) values ('session-files', 'not-a-student/x.jpg')$$, 'upload outside a student folder'); -- Checks uploads must be in a student's folder.
insert into public.session_note_files (note_id, student_id, title, file_path, file_type) -- Attaches the photo to the summary:
  values (:'note', :'cara', 'Whiteboard: fractions', :'cara' || '/whiteboard.jpg', 'image/jpeg'); -- (its name, path and type).
select tests.eq((select count(*) from public.session_note_files where note_id = :'note' and uploaded_by = '00000000-0000-0000-0000-000000000011'), 1, 'file attached and stamped with the tutor'); -- Checks the file record is there, stamped with T1.
select tests.fails(format($$insert into public.session_note_files (note_id, student_id, title, file_path, file_type) values (%L, %L, 'Missing', %L, 'image/jpeg')$$, :'note', :'cara', :'cara' || '/never-uploaded.jpg'), 'record for a file that did not upload'); -- Checks a record needs a real uploaded file.
select tests.fails(format($$insert into public.session_note_files (note_id, student_id, title, file_path, file_type) values (%L, %L, 'Wrong student', %L, 'image/jpeg')$$, :'note', :'vic', :'cara' || '/whiteboard.jpg'), 'file record for the wrong student'); -- Checks the student must match the summary.
delete from storage.objects where bucket_id = 'session-files' and name = :'cara' || '/whiteboard.jpg'; -- Tries to remove the attached file straight from the store (the rule skips it).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from storage.objects where bucket_id = 'session-files' and name = :'cara' || '/whiteboard.jpg'), 1, 'attached file still in the store'); -- Checks the attached file was not removed.

-- ===========================================================================
-- Who sees what
-- ===========================================================================
-- Cara's parent: sees the file, never the plan.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as parent P1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.session_note_files where note_id = :'note'), 1, 'family sees the session file'); -- Checks the family sees the file record.
select tests.eq((select count(*) from storage.objects where bucket_id = 'session-files' and name = :'cara' || '/whiteboard.jpg'), 1, 'family can open the stored file'); -- Checks the family can open the file.
select tests.eq((select count(*) from public.session_plans), 0, 'family cannot see plans'); -- Checks the family sees no plans.
select tests.eq((select count(*) from public.session_plan_materials), 0, 'family cannot see linked materials'); -- Checks the family sees no linked materials.
select tests.fails(format($$insert into public.session_note_files (note_id, student_id, title, file_path, file_type) values (%L, %L, 'From parent', %L, 'image/jpeg')$$, :'note', :'cara', :'cara' || '/whiteboard.jpg'), 'family attaches a session file'); -- Checks the family cannot add session files.
select tests.fails(format($$select public.save_session_plan(%L, 'Parent plan', 'Parent activities')$$, :'note'), 'family saves a plan'); -- Checks the family cannot save a plan.
delete from public.session_note_files where note_id = :'note'; -- Tries to delete the file record.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.session_note_files where note_id = :'note'), 1, 'family cannot remove session files'); -- Checks the file record is still there.

-- Another family: sees nothing.
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as parent P2.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.session_note_files where student_id = :'cara'), 0, 'other family cannot see the file'); -- Checks P2 cannot see Cara's file.
select tests.eq((select count(*) from storage.objects where bucket_id = 'session-files'), 0, 'other family cannot open the stored file'); -- Checks P2 cannot open it.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Another tutor (T2 teaches Vic, not Cara as a matched tutor).
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- Signs in as tutor T2 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.session_plans where student_id = :'cara'), 0, 'other tutor cannot see the plan'); -- Checks T2 cannot see Cara's plan.
select tests.eq((select count(*) from public.session_note_files where student_id = :'cara'), 0, 'other tutor cannot see the file'); -- Checks T2 cannot see Cara's file.
select tests.fails(format($$select public.save_session_plan(%L, 'Other tutor plan', 'Other tutor activities')$$, :'note'), 'other tutor saves a plan'); -- Checks T2 cannot save Cara's plan.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Tutor T1 without two-step sign-in sees no plans.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- Signs in as T1 without two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.session_plans), 0, 'tutor without two-step sees no plans'); -- Checks plans need two-step sign-in.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- An admin sees the plan and its materials.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.session_plans where id = :'plan'), 1, 'admin sees the plan'); -- Checks the admin sees the plan.
select tests.eq((select count(*) from public.session_plan_materials where plan_id = :'plan'), 1, 'admin sees linked materials'); -- Checks the admin sees the linked material.
select tests.fails($$select count(*) from public.session_file_removals$$, 'people read the removal queue'); -- Checks nobody reads the removal queue directly.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Limits: 10 files per summary, and the 7-day window
-- ===========================================================================
-- Adds 10 more stored files; the tutor attaches 9 of them to reach 10.
insert into storage.objects (bucket_id, name) select 'session-files', :'cara' || '/extra' || g || '.jpg' from generate_series(1, 10) g; -- Adds 10 more stored files.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.session_note_files (note_id, student_id, title, file_path, file_type) -- Attaches 9 of them:
  select :'note', :'cara', 'Extra ' || g, :'cara' || '/extra' || g || '.jpg', 'image/jpeg' from generate_series(1, 9) g; -- (files 1 to 9).
select tests.fails(format($$insert into public.session_note_files (note_id, student_id, title, file_path, file_type) values (%L, %L, 'Eleventh', %L, 'image/jpeg')$$, :'note', :'cara', :'cara' || '/extra10.jpg'), 'eleventh file on one session'); -- Checks the 11th file is refused.
-- T1 removes one file: its stored file is queued for the daily job.
delete from public.session_note_files where note_id = :'note' and title = 'Extra 9'; -- Removes one file record.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.session_file_removals where file_path = :'cara' || '/extra9.jpg'), 1, 'removed file queued for the daily job'); -- Checks the file is queued for removal.
select public.session_files_removed(array[:'cara' || '/extra9.jpg']); -- The daily job says it removed the file.
select tests.eq((select count(*) from public.session_file_removals), 0, 'queue cleared after removal'); -- Checks the queue is clear.

-- Moves the summary 8 days back: T1 can no longer change its plan or files.
set session_replication_role = replica; -- Turns triggers off for a moment (the summary's guard stops its date being changed).
update public.session_notes set created_at = now() - interval '8 days' where id = :'note'; -- Makes the summary 8 days old.
set session_replication_role = default; -- Turns triggers back on.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.save_session_plan(%L, 'Too late plan', 'Too late activities')$$, :'note'), 'plan changed after 7 days'); -- Checks the plan cannot be changed after 7 days.
select tests.fails(format($$insert into public.session_note_files (note_id, student_id, title, file_path, file_type) values (%L, %L, 'Late', %L, 'image/jpeg')$$, :'note', :'cara', :'cara' || '/extra10.jpg'), 'file added after 7 days'); -- Checks files cannot be added after 7 days.
select tests.eq((select count(*) from public.session_plans where id = :'plan'), 1, 'tutor still sees the older plan'); -- Checks T1 can still read the plan.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.save_session_plan(:'note', 'Admin corrected focus', 'Admin corrected activities'); -- The admin can still correct it.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.session_plans where id = :'plan' and focus = 'Admin corrected focus'), 1, 'admin corrects an older plan'); -- Checks the admin's correction saved.

-- ===========================================================================
-- Deleting the summary removes its plan and files (and queues the files).
-- ===========================================================================
select tests.claims(null); -- Signs out, so no one is signed in.
set session_replication_role = replica; -- Turns triggers off for a moment (a roadmap step ticked off by this summary guards its link).
delete from public.roadmap_steps where note_id = :'note'; -- Removes any roadmap step this summary ticked off (so the summary can go).
set session_replication_role = default; -- Turns triggers back on.
delete from public.session_notes where id = :'note'; -- Deletes the summary (as automatic deletion would, with the student).
select tests.eq((select count(*) from public.session_plans where id = :'plan'), 0, 'plan goes with the summary'); -- Checks the plan went too.
select tests.eq((select count(*) from public.session_note_files where note_id = :'note'), 0, 'files go with the summary'); -- Checks the file records went too.
select tests.eq((select count(*) from public.session_file_removals where file_path like :'cara' || '/%'), 9, 'their stored files are queued for removal'); -- Checks the 9 remaining files are queued.

-- Tidy up: the test material, the test sessions, the stray stored files and the queue.
delete from public.session_file_removals; -- Clears the queue.
delete from storage.objects where bucket_id = 'session-files'; -- Removes the test files.
delete from public.sessions where id in ('00000000-0000-0000-0000-0000000e5a01', '00000000-0000-0000-0000-0000000e5a02'); -- Removes the test sessions.
delete from public.materials where id in ('00000000-0000-0000-0000-00000000e5b1', '00000000-0000-0000-0000-00000000e5b2'); -- Removes the test materials.
delete from storage.objects where bucket_id = 'materials' and name like 'view/00000000-0000-0000-0000-00000000e5b%'; -- Removes their files.

\echo '  progress session plans and files: all checks passed'
