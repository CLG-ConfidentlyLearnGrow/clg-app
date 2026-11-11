-- Senior certificates by state. Reuses the people from progress.test.sql:
-- owner ...a0, tutor T1 ...11 (teaches Cara One, SA), tutor T2 ...12,
-- parent P1 ...01 (Cara's parent), parent P2 ...02 (Vic Two's parent).

-- Safe to run twice.
-- Runs the database change 20261029500400_progress_senior_certificates.sql first, as this test needs it.
\ir ../migrations/20261029500400_progress_senior_certificates.sql

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset
-- Keeps Vic's student id as vic.
select id as vic from public.students where full_name = 'Vic Two' \gset
-- Keeps Vic's state as vic_state.
select state as vic_state from public.students where full_name = 'Vic Two' \gset

-- ===========================================================================
-- The rules
-- ===========================================================================
select tests.eq((select count(*) from public.certificate_requirements where certificate = 'SACE'), 6, 'SACE has six requirements'); -- Checks: SACE has six requirements.
select tests.eq((select count(*) from public.senior_certificates), 8, 'a certificate for every state and territory'); -- Checks: a certificate for every state and territory.
select tests.eq((select count(*) from unnest(enum_range(null::public.au_state)) st -- Checks every state has a senior certificate:
  where not exists (select 1 from public.senior_certificates c where st = any(c.states))), 0, 'every state is covered'); -- (no state is left without one).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) where public.student_certificate(:'cara') = 'SACE'), 1, 'SA student follows SACE'); -- Checks: SA student follows SACE.
select tests.eq((select count(*) where public.student_certificate(:'vic') is null), 1, 'other family''s student not shown'); -- Checks: other family's student not shown.
update public.certificate_requirements set min_credits = 1 where code = 'total'; -- Lowers the total credits needed to 1, for this test.
select tests.eq((select min_credits from public.certificate_requirements where certificate = 'SACE' and code = 'total'), 200, 'rules unchanged'); -- Checks: rules unchanged.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Subjects
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.senior_subjects (student_id, certificate, subject, stage, credits, area, status, grade) values -- Adds Cara's senior subjects:
  (:'cara', 'SACE', 'Exploring Identities and Futures', 1, 10, 'eif', 'finished', 'b'), -- Exploring Identities and Futures, Stage 1, finished with a B,
  (:'cara', 'SACE', 'English', 1, 20, 'literacy', 'finished', 'C'), -- English, Stage 1, finished with a C,
  (:'cara', 'SACE', 'General Mathematics', 1, 10, 'numeracy', 'finished', 'D'), -- General Mathematics, Stage 1, finished with a D,
  (:'cara', 'SACE', 'Activating Identities and Futures', 2, 10, 'aif', 'studying', null), -- Activating Identities and Futures, Stage 2, studying,
  (:'cara', 'SACE', 'Biology', 2, 20, null, 'finished', 'C-'), -- Biology, Stage 2, finished with a C-,
  (:'cara', 'SACE', 'Chemistry', 2, 20, null, 'studying', null); -- Chemistry, Stage 2, studying.
select tests.eq((select count(*) from public.senior_subjects where subject = 'Exploring Identities and Futures' and grade = 'B'), 1, 'grade tidied to capitals'); -- Checks: grade tidied to capitals.
select tests.fails(format($$insert into public.senior_subjects (student_id, certificate, subject, stage, credits, status, grade) -- Checks a Stage 2 grade is refused at Stage 1:
  values (%L, 'SACE', 'Physics', 1, 10, 'finished', 'A+')$$, :'cara'), 'Stage 2 grade at Stage 1'); -- (an A+ at Stage 1).
select tests.fails(format($$insert into public.senior_subjects (student_id, certificate, subject, stage, credits, status, grade) -- Checks a grade before the subject is finished is refused:
  values (%L, 'SACE', 'Physics', 2, 10, 'studying', 'A')$$, :'cara'), 'grade before it is finished'); -- (an A while still studying).
select tests.fails(format($$insert into public.senior_subjects (student_id, certificate, subject, stage, credits) -- Checks credits other than 10 or 20 are refused:
  values (%L, 'SACE', 'Physics', 2, 15)$$, :'cara'), 'credits other than 10 or 20'); -- (15 credits).
select tests.fails(format($$update public.senior_subjects set student_id = %L where subject = 'Biology'$$, :'vic'), 'moving a subject to another student'); -- Checks this is refused: moving a subject to another student.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.senior_subjects), 0, 'other parent sees none'); -- Checks: other parent sees none.
select tests.fails(format($$insert into public.senior_subjects (student_id, certificate, subject, stage, credits) values (%L, 'SACE', 'Art', 1, 10)$$, :'cara'), 'other parent adds a subject'); -- Checks this is refused: other parent adds a subject.
select tests.eq((select count(*) from public.certificate_progress(:'cara')), 0, 'other parent sees no progress'); -- Checks: other parent sees no progress.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Progress
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.certificate_progress(:'cara') where code = 'eif' and met), 1, 'EIF met with a B'); -- Checks: EIF met with a B.
select tests.eq((select count(*) from public.certificate_progress(:'cara') where code = 'literacy' and met), 1, 'literacy met with a C'); -- Checks: literacy met with a C.
select tests.eq((select count(*) from public.certificate_progress(:'cara') where code = 'numeracy' and met), 0, 'numeracy not met with a D'); -- Checks: numeracy not met with a D.
select tests.eq((select credits_under_way from public.certificate_progress(:'cara') where code = 'aif'), 10, 'AIF under way'); -- Checks: AIF under way.
select tests.eq((select credits_done from public.certificate_progress(:'cara') where code = 'stage2'), 20, 'Biology counts at Stage 2, AIF doesn''t'); -- Checks: Biology counts at Stage 2, AIF doesn't.
select tests.eq((select credits_under_way from public.certificate_progress(:'cara') where code = 'stage2'), 20, 'Chemistry under way'); -- Checks: Chemistry under way.
select tests.eq((select credits_done from public.certificate_progress(:'cara') where code = 'total'), 60, 'total counts every finished subject'); -- Checks: total counts every finished subject.
-- The tutor can update a result.
update public.senior_subjects set status = 'finished', grade = 'B+' where subject = 'Chemistry'; -- Chemistry is now finished with a B+.
select tests.eq((select credits_done from public.certificate_progress(:'cara') where code = 'stage2'), 40, 'tutor records a result'); -- Checks: tutor records a result.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- Signs in as test account ...12 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.senior_subjects), 0, 'other tutor sees none'); -- Checks: other tutor sees none.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
delete from public.senior_subjects where subject = 'Chemistry'; -- Removes Chemistry.
select tests.eq((select count(*) from public.senior_subjects where student_id = :'cara'), 5, 'parent removes a subject'); -- Checks: parent removes a subject.
reset role; -- Goes back to the all-powerful test user (access rules off).

set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.senior_subjects$$, 'anon reads subjects'); -- Checks this is refused: anon reads subjects.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Tidy up.
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.senior_subjects; -- Removes all the test subjects.

-- Prints that every check in this file passed.
\echo '  senior certificates: all checks passed'
