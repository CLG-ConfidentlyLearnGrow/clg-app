-- What tutors teach. Runs after access_rules.test.sql and reuses its helpers,
-- staff admin (...b0), tutors T1 (...11) and T2 (...12), and parent P1 (...01).

-- access_rules.test.sql added some subjects for its assignments; start clean.
delete from public.tutor_teaching; -- Clears any earlier teaching ranges.

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- Signs in as test account ...11.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000011', 'General Maths', 'Year 3', 'Year 10')$$, 'tutor without two-step login'); -- Checks this is refused: tutor without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values -- Adds what tutor T1 teaches:
  ('00000000-0000-0000-0000-000000000011', 'General Maths', 'Year 3', 'Year 10'), -- General Maths from Year 3 to Year 10,
  ('00000000-0000-0000-0000-000000000011', 'English', 'Year 7', 'Year 12'); -- and English from Year 7 to Year 12.
select tests.eq((select count(*) from public.tutor_teaching), 2, 'tutor adds subjects with different year ranges'); -- Checks: tutor adds subjects with different year ranges.
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000011', 'general maths', 'Year 1', 'Year 2')$$, 'same subject twice'); -- Checks this is refused: same subject twice.
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000011', 'Science', 'Year 9', 'Year 4')$$, 'range backwards'); -- Checks this is refused: range backwards.
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000011', 'Science', 'Grade 4', 'Year 6')$$, 'unknown year level'); -- Checks this is refused: unknown year level.
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000012', 'Science', 'Year 4', 'Year 6')$$, 'tutor adds for another tutor'); -- Checks this is refused: tutor adds for another tutor.
update public.tutor_teaching set to_level = 'Year 11' where subject = 'General Maths'; -- Tries to change a range.
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000011', 'Maths', 'Year 1', 'Year 2')$$, 'plain Maths is refused'); -- Checks this is refused: plain Maths is refused.
select tests.fails($$insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values ('00000000-0000-0000-0000-000000000011', 'Mathematics', 'Year 9', 'Year 11')$$, 'Mathematics only goes to Year 10'); -- Checks this is refused: Mathematics only goes to Year 10.
select tests.eq((select count(*) from public.tutor_teaching where to_level = 'Year 11'), 1, 'tutor changes own range'); -- Checks: tutor changes own range.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.eq(private.tutor_teaches('00000000-0000-0000-0000-000000000011', 'general maths ', 'Year 5')::int, 1, 'teaches Maths in Year 5'); -- Checks: teaches Maths in Year 5.
select tests.eq(private.tutor_teaches('00000000-0000-0000-0000-000000000011', 'English', 'Year 5')::int, 0, 'not English in Year 5'); -- Checks: not English in Year 5.

-- Others can't see it; admins can.
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- Signs in as test account ...12 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.tutor_teaching), 0, 'other tutor sees none'); -- Checks: other tutor sees none.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- Signs in as test account ...01 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.tutor_teaching), 0, 'parent sees none'); -- Checks: parent sees none.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.tutor_teaching), 2, 'admin sees all'); -- Checks: admin sees all.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.tutor_teaching$$, 'anon'); -- Checks this is refused: anon.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Matching: only tutors who teach at the student's year level, and only
-- subjects they teach. T1 teaches Maths Years 3 to 11 and English 7 to 12.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.eligible_tutors(:'cara')), 1, 'T1 listed for Cara (Year 5)'); -- Checks: T1 listed for Cara (Year 5).
select tests.eq((select count(*) from public.eligible_tutors(:'cara') where subjects = array['General Maths']), 1, 'only matching subject listed'); -- Checks: only matching subject listed.
select tests.fails(format($$insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000011', %L, 'English')$$, :'cara'), 'subject not taught at this year level'); -- Checks this is refused: subject not taught at this year level.
select tests.fails(format($$insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000011', %L, 'Science')$$, :'cara'), 'subject not taught at all'); -- Checks this is refused: subject not taught at all.
insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000011', :'cara', 'general maths'); -- Assigns tutor T1 to Cara for General Maths.
delete from public.tutor_teaching where tutor_id = '00000000-0000-0000-0000-000000000011'; -- Clears tutor T1's teaching ranges.
select tests.eq((select count(*) from public.eligible_tutors(:'cara')), 0, 'tutor with no subjects is not listed'); -- Checks: tutor with no subjects is not listed.
select tests.fails(format($$insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000011', %L, 'General Maths')$$, :'cara'), 'tutor with no subjects cannot be assigned'); -- Checks this is refused: tutor with no subjects cannot be assigned.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- Prints that every check in this file passed.
\echo '  tutor teaching: all checks passed'
