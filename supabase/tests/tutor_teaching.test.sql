-- What tutors teach. Runs after access_rules.test.sql and reuses its helpers,
-- staff admin (...b0), tutors T1 (...11) and T2 (...12), and parent P1 (...01).

-- access_rules.test.sql added some subjects for its assignments; start clean.
delete from public.tutor_teaching;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1');
set role authenticated;
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000011', 'General Maths', 'Year 3', 'Year 10')$$, 'tutor without two-step login');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values
  ('00000000-0000-0000-0000-000000000011', 'General Maths', 'Year 3', 'Year 10'),
  ('00000000-0000-0000-0000-000000000011', 'English', 'Year 7', 'Year 12');
select tests.eq((select count(*) from public.tutor_teaching), 2, 'tutor adds subjects with different year ranges');
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000011', 'general maths', 'Year 1', 'Year 2')$$, 'same subject twice');
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000011', 'Science', 'Year 9', 'Year 4')$$, 'range backwards');
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000011', 'Science', 'Grade 4', 'Year 6')$$, 'unknown year level');
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000012', 'Science', 'Year 4', 'Year 6')$$, 'tutor adds for another tutor');
update public.tutor_teaching set to_level = 'Year 11' where subject = 'General Maths';
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000011', 'Mathematics', 'Year 1', 'Year 2')$$, 'plain Maths must be General, Essential or Advanced');
select tests.eq((select count(*) from public.tutor_teaching where to_level = 'Year 11'), 1, 'tutor changes own range');
reset role;

select tests.eq(private.tutor_teaches('00000000-0000-0000-0000-000000000011', 'general maths ', 'Year 5')::int, 1, 'teaches Maths in Year 5');
select tests.eq(private.tutor_teaches('00000000-0000-0000-0000-000000000011', 'English', 'Year 5')::int, 0, 'not English in Year 5');

-- Others can't see it; admins can.
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.tutor_teaching), 0, 'other tutor sees none');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.tutor_teaching), 0, 'parent sees none');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.tutor_teaching), 2, 'admin sees all');
reset role;
select tests.claims(null);
set role anon;
select tests.fails($$select * from public.tutor_teaching$$, 'anon');
reset role;

-- Matching: only tutors who teach at the student's year level, and only
-- subjects they teach. T1 teaches Maths Years 3 to 11 and English 7 to 12.
select id as cara from public.students where full_name = 'Cara One' \gset
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.eligible_tutors(:'cara')), 1, 'T1 listed for Cara (Year 5)');
select tests.eq((select count(*) from public.eligible_tutors(:'cara') where subjects = array['General Maths']), 1, 'only matching subject listed');
select tests.fails(format($$insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000011', %L, 'English')$$, :'cara'), 'subject not taught at this year level');
select tests.fails(format($$insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000011', %L, 'Science')$$, :'cara'), 'subject not taught at all');
insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000011', :'cara', 'general maths');
delete from public.tutor_teaching where tutor_id = '00000000-0000-0000-0000-000000000011';
select tests.eq((select count(*) from public.eligible_tutors(:'cara')), 0, 'tutor with no subjects is not listed');
select tests.fails(format($$insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000011', %L, 'General Maths')$$, :'cara'), 'tutor with no subjects cannot be assigned');
reset role;
select tests.claims(null);

\echo '  tutor teaching: all checks passed'
