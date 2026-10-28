-- Senior certificates by state. Reuses the people from progress.test.sql:
-- owner ...a0, tutor T1 ...11 (teaches Cara One, SA), tutor T2 ...12,
-- parent P1 ...01 (Cara's parent), parent P2 ...02 (Vic Two's parent).

-- Safe to run twice.
\ir ../migrations/20261029500400_progress_senior_certificates.sql

select tests.claims(null);
select id as cara from public.students where full_name = 'Cara One' \gset
select id as vic from public.students where full_name = 'Vic Two' \gset
select state as vic_state from public.students where full_name = 'Vic Two' \gset

-- ===========================================================================
-- The rules
-- ===========================================================================
select tests.eq((select count(*) from public.certificate_requirements where certificate = 'SACE'), 6, 'SACE has six requirements');
select tests.eq((select count(*) from public.senior_certificates), 8, 'a certificate for every state and territory');
select tests.eq((select count(*) from unnest(enum_range(null::public.au_state)) st
  where not exists (select 1 from public.senior_certificates c where st = any(c.states))), 0, 'every state is covered');

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) where public.student_certificate(:'cara') = 'SACE'), 1, 'SA student follows SACE');
select tests.eq((select count(*) where public.student_certificate(:'vic') is null), 1, 'other family''s student not shown');
update public.certificate_requirements set min_credits = 1 where code = 'total';
select tests.eq((select min_credits from public.certificate_requirements where certificate = 'SACE' and code = 'total'), 200, 'rules unchanged');
reset role;

-- ===========================================================================
-- Subjects
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
insert into public.senior_subjects (student_id, certificate, subject, stage, credits, area, status, grade) values
  (:'cara', 'SACE', 'Exploring Identities and Futures', 1, 10, 'eif', 'finished', 'b'),
  (:'cara', 'SACE', 'English', 1, 20, 'literacy', 'finished', 'C'),
  (:'cara', 'SACE', 'General Mathematics', 1, 10, 'numeracy', 'finished', 'D'),
  (:'cara', 'SACE', 'Activating Identities and Futures', 2, 10, 'aif', 'studying', null),
  (:'cara', 'SACE', 'Biology', 2, 20, null, 'finished', 'C-'),
  (:'cara', 'SACE', 'Chemistry', 2, 20, null, 'studying', null);
select tests.eq((select count(*) from public.senior_subjects where subject = 'Exploring Identities and Futures' and grade = 'B'), 1, 'grade tidied to capitals');
select tests.fails(format($$insert into public.senior_subjects (student_id, certificate, subject, stage, credits, status, grade)
  values (%L, 'SACE', 'Physics', 1, 10, 'finished', 'A+')$$, :'cara'), 'Stage 2 grade at Stage 1');
select tests.fails(format($$insert into public.senior_subjects (student_id, certificate, subject, stage, credits, status, grade)
  values (%L, 'SACE', 'Physics', 2, 10, 'studying', 'A')$$, :'cara'), 'grade before it is finished');
select tests.fails(format($$insert into public.senior_subjects (student_id, certificate, subject, stage, credits)
  values (%L, 'SACE', 'Physics', 2, 15)$$, :'cara'), 'credits other than 10 or 20');
select tests.fails(format($$update public.senior_subjects set student_id = %L where subject = 'Biology'$$, :'vic'), 'moving a subject to another student');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.senior_subjects), 0, 'other parent sees none');
select tests.fails(format($$insert into public.senior_subjects (student_id, certificate, subject, stage, credits) values (%L, 'SACE', 'Art', 1, 10)$$, :'cara'), 'other parent adds a subject');
select tests.eq((select count(*) from public.certificate_progress(:'cara')), 0, 'other parent sees no progress');
reset role;

-- ===========================================================================
-- Progress
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.certificate_progress(:'cara') where code = 'eif' and met), 1, 'EIF met with a B');
select tests.eq((select count(*) from public.certificate_progress(:'cara') where code = 'literacy' and met), 1, 'literacy met with a C');
select tests.eq((select count(*) from public.certificate_progress(:'cara') where code = 'numeracy' and met), 0, 'numeracy not met with a D');
select tests.eq((select credits_under_way from public.certificate_progress(:'cara') where code = 'aif'), 10, 'AIF under way');
select tests.eq((select credits_done from public.certificate_progress(:'cara') where code = 'stage2'), 20, 'Biology counts at Stage 2, AIF doesn''t');
select tests.eq((select credits_under_way from public.certificate_progress(:'cara') where code = 'stage2'), 20, 'Chemistry under way');
select tests.eq((select credits_done from public.certificate_progress(:'cara') where code = 'total'), 60, 'total counts every finished subject');
-- The tutor can update a result.
update public.senior_subjects set status = 'finished', grade = 'B+' where subject = 'Chemistry';
select tests.eq((select credits_done from public.certificate_progress(:'cara') where code = 'stage2'), 40, 'tutor records a result');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.senior_subjects), 0, 'other tutor sees none');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
delete from public.senior_subjects where subject = 'Chemistry';
select tests.eq((select count(*) from public.senior_subjects where student_id = :'cara'), 5, 'parent removes a subject');
reset role;

set role anon;
select tests.fails($$select * from public.senior_subjects$$, 'anon reads subjects');
reset role;

-- Tidy up.
select tests.claims(null);
delete from public.senior_subjects;

\echo '  senior certificates: all checks passed'
