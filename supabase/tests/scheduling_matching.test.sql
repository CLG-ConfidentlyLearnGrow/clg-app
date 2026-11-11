-- Matching: working levels, where each child can have sessions, and the
-- admin pipeline. Runs after scheduling_away.test.sql and reuses its people:
-- owner admin (...a0), tutors T3 (...13, General Maths Years 3 to 10) and T4
-- (...14, General Maths Years 1 to 12), parents P3 (...03, Sam Three's
-- parent) and P4 (...04).

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset

-- ---------------------------------------------------------------------------
-- Working level
-- ---------------------------------------------------------------------------
select tests.eq((private.matching_level(:'sam', 'General Maths') = 'Year 5')::int, 1, 'no working level: school year'); -- Checks: no working level: school year.
update public.student_subjects set working_level = 'Year 11' where student_id = :'sam' and subject = 'General Maths'; -- Sets Sam's General Maths working level to Year 11.
select tests.eq((private.matching_level(:'sam', 'general maths ') = 'Year 11')::int, 1, 'working level used'); -- Checks: working level used.

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.eligible_tutors(:'sam') where tutor_id = '00000000-0000-0000-0000-000000000013'), 0, 'tutor who stops at Year 10 not offered'); -- Checks: tutor who stops at Year 10 not offered.
select tests.eq((select count(*) from public.eligible_tutors(:'sam') where tutor_id = '00000000-0000-0000-0000-000000000014'), 1, 'tutor who teaches Year 11 offered'); -- Checks: tutor who teaches Year 11 offered.
select tests.fails(format($$insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000013', %L, 'General Maths')$$, :'sam'), 'assigning a tutor below the working level'); -- Checks this is refused: assigning a tutor below the working level.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
update public.student_subjects set working_level = null where student_id = :'sam' and subject = 'General Maths'; -- Clears it again.

-- ---------------------------------------------------------------------------
-- Where sessions can happen
-- ---------------------------------------------------------------------------
-- Keeps the first library's id as lib.
select id as lib from public.libraries order by name limit 1 \gset
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.student_places (student_id, online, library_ids) values (:'sam', true, array[:'lib']::uuid[]); -- Sam can have sessions online or at that library.
select tests.eq((select count(*) from public.student_places where student_id = :'sam'), 1, 'family saves places'); -- Checks: family saves places.
update public.student_places set online = false where student_id = :'sam'; -- Turns online off for Sam.
select tests.fails(format($$update public.student_places set library_ids = '{}' where student_id = %L$$, :'sam'), 'no places at all'); -- Checks this is refused: no places at all.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as test account ...04.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.student_places), 0, 'other parent sees none'); -- Checks: other parent sees none.
select tests.fails(format($$insert into public.student_places (student_id) values (%L)$$, :'sam'), 'other parent sets places'); -- Checks this is refused: other parent sets places.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.student_places), 0, 'tutors don''t see family places'); -- Checks: tutors don't see family places.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.student_places$$, 'anon'); -- Checks this is refused: anon.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Pipeline
-- ---------------------------------------------------------------------------
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.student_subjects (student_id, subject) values (:'sam', 'English'); -- Adds English to Sam's subjects.

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_matching('needs_tutor') where student_id = :'sam' and subject = 'English'), 1, 'new subject needs a tutor'); -- Checks: new subject needs a tutor.
select tests.eq((select count(*) from public.list_matching(null, 'sam three') where subject = 'English' and has_places), 1, 'search by name; places noted'); -- Checks: search by name; places noted.
select tests.eq((select count(*) from public.list_matching(null, 'engl') where student_id = :'sam'), 1, 'search by subject'); -- Checks: search by subject.
select tests.eq((select (subjects >= 1)::int from public.matching_pipeline() where stage = 'needs_tutor'), 1, 'pipeline counts'); -- Checks: pipeline counts.
select tests.eq((select count(*) from public.list_matching(null, null, 1, 0)), 1, 'one page at a time'); -- Checks: one page at a time.
select tests.eq((select count(*) from public.list_matching('active') where student_id = :'sam' and subject = 'General Maths' and tutor_name is not null), 1, 'running booking is active, with the tutor'); -- Checks: running booking is active, with the tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.join_waitlist(:'sam', 'English', 60, true, '{}', null, null, null, null, null); -- Puts Sam on the English waitlist.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_matching('waitlist') where student_id = :'sam' and subject = 'English'), 1, 'waitlisted'); -- Checks: waitlisted.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select * from public.list_matching()$$, 'families can''t see the pipeline'); -- Checks this is refused: families can't see the pipeline.
select tests.fails($$select * from public.matching_pipeline()$$, 'families can''t see the counts'); -- Checks this is refused: families can't see the counts.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select * from public.list_matching()$$, 'tutors can''t see the pipeline'); -- Checks this is refused: tutors can't see the pipeline.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Put things back for the later tests.
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.waitlist where student_id = :'sam' and subject = 'English'; -- Removes Sam from the waitlist.
delete from public.student_subjects where student_id = :'sam' and subject = 'English'; -- Removes English from Sam's subjects.
delete from public.student_places where student_id = :'sam'; -- Removes Sam's places.

-- Prints that every check in this file passed.
\echo '  scheduling matching: all checks passed'
