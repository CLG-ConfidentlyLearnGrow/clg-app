-- Matching: working levels, where each child can have sessions, and the
-- admin pipeline. Runs after scheduling_away.test.sql and reuses its people:
-- owner admin (...a0), tutors T3 (...13, General Maths Years 3 to 10) and T4
-- (...14, General Maths Years 1 to 12), parents P3 (...03, Sam Three's
-- parent) and P4 (...04).

select tests.claims(null);
select id as sam from public.students where full_name = 'Sam Three' \gset

-- ---------------------------------------------------------------------------
-- Working level
-- ---------------------------------------------------------------------------
select tests.eq((private.matching_level(:'sam', 'General Maths') = 'Year 5')::int, 1, 'no working level: school year');
update public.student_subjects set working_level = 'Year 11' where student_id = :'sam' and subject = 'General Maths';
select tests.eq((private.matching_level(:'sam', 'general maths ') = 'Year 11')::int, 1, 'working level used');

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.eligible_tutors(:'sam') where tutor_id = '00000000-0000-0000-0000-000000000013'), 0, 'tutor who stops at Year 10 not offered');
select tests.eq((select count(*) from public.eligible_tutors(:'sam') where tutor_id = '00000000-0000-0000-0000-000000000014'), 1, 'tutor who teaches Year 11 offered');
select tests.fails(format($$insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000013', %L, 'General Maths')$$, :'sam'), 'assigning a tutor below the working level');
reset role;
select tests.claims(null);
update public.student_subjects set working_level = null where student_id = :'sam' and subject = 'General Maths';

-- ---------------------------------------------------------------------------
-- Where sessions can happen
-- ---------------------------------------------------------------------------
select id as lib from public.libraries order by name limit 1 \gset
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
insert into public.student_places (student_id, online, library_ids) values (:'sam', true, array[:'lib']::uuid[]);
select tests.eq((select count(*) from public.student_places where student_id = :'sam'), 1, 'family saves places');
update public.student_places set online = false where student_id = :'sam';
select tests.fails(format($$update public.student_places set library_ids = '{}' where student_id = %L$$, :'sam'), 'no places at all');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.eq((select count(*) from public.student_places), 0, 'other parent sees none');
select tests.fails(format($$insert into public.student_places (student_id) values (%L)$$, :'sam'), 'other parent sets places');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.student_places), 0, 'tutors don''t see family places');
reset role;
select tests.claims(null);
set role anon;
select tests.fails($$select * from public.student_places$$, 'anon');
reset role;

-- ---------------------------------------------------------------------------
-- Pipeline
-- ---------------------------------------------------------------------------
select tests.claims(null);
insert into public.student_subjects (student_id, subject) values (:'sam', 'English');

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.list_matching('needs_tutor') where student_id = :'sam' and subject = 'English'), 1, 'new subject needs a tutor');
select tests.eq((select count(*) from public.list_matching(null, 'sam three') where subject = 'English' and has_places), 1, 'search by name; places noted');
select tests.eq((select count(*) from public.list_matching(null, 'engl') where student_id = :'sam'), 1, 'search by subject');
select tests.eq((select (subjects >= 1)::int from public.matching_pipeline() where stage = 'needs_tutor'), 1, 'pipeline counts');
select tests.eq((select count(*) from public.list_matching(null, null, 1, 0)), 1, 'one page at a time');
select tests.eq((select count(*) from public.list_matching('active') where student_id = :'sam' and subject = 'General Maths' and tutor_name is not null), 1, 'running booking is active, with the tutor');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.join_waitlist(:'sam', 'English', 60, true, '{}', null, null, null, null, null);
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.list_matching('waitlist') where student_id = :'sam' and subject = 'English'), 1, 'waitlisted');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails($$select * from public.list_matching()$$, 'families can''t see the pipeline');
select tests.fails($$select * from public.matching_pipeline()$$, 'families can''t see the counts');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails($$select * from public.list_matching()$$, 'tutors can''t see the pipeline');
reset role;

-- Put things back for the later tests.
select tests.claims(null);
delete from public.waitlist where student_id = :'sam' and subject = 'English';
delete from public.student_subjects where student_id = :'sam' and subject = 'English';
delete from public.student_places where student_id = :'sam';

\echo '  scheduling matching: all checks passed'
