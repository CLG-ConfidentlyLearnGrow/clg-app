-- Summary: checks "Fill a tutor's times" in Matching (Carla, 22 Nov 2026):
-- choosing a tutor lists the waiting students who fit their free times,
-- using the same rules as the student-side shortlist. Only front desk
-- admins may use it. Reuses the shared test people: owner admin (...a0),
-- Operations admin (...b0), tutor T1 (...11) and parent P1 (...01).

-- ---------------------------------------------------------------------------
-- Who may use it
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.fails_with($$select * from public.matching_fill_tutors()$$, 'Only CLG admins', 'tutors cannot see the tutor list'); -- refused
select tests.fails_with($$select * from public.matching_tutor_fill('00000000-0000-0000-0000-000000000011')$$, 'Only CLG admins', 'tutors cannot see who fits their times'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.fails($$select * from public.matching_tutor_fill('00000000-0000-0000-0000-000000000011')$$, 'parents cannot use it'); -- refused
reset role; -- back to the database itself
set role anon; -- acts as a signed-out visitor
select tests.fails($$select * from public.matching_fill_tutors()$$, 'signed-out visitors cannot use it'); -- refused
reset role; -- back to the database itself

-- ---------------------------------------------------------------------------
-- The tutor list
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- signs in as the Operations admin
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.matching_fill_tutors() where tutor_id = '00000000-0000-0000-0000-000000000011'), 1::bigint, 'an active tutor is in the list'); -- T1 is listed
select tests.eq((select count(*) from public.matching_fill_tutors() where booked_minutes < 0), 0::bigint, 'booked minutes are never negative'); -- a sense check
reset role; -- back to the database itself

-- ---------------------------------------------------------------------------
-- The students who fit: the same as the student-side shortlist
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person
-- Every student listed for T1 is still waiting for a tutor.
select tests.eq((select count(*) from public.matching_tutor_fill('00000000-0000-0000-0000-000000000011') where stage not in ('needs_tutor', 'waitlist')), 0::bigint,
  'only students still waiting for a tutor are listed');
-- Every student listed has at least one time that suits.
select tests.eq((select count(*) from public.matching_tutor_fill('00000000-0000-0000-0000-000000000011') where times < 1), 0::bigint,
  'only students with a time that suits are listed');
reset role; -- back to the database itself
-- The list matches the student-side shortlist exactly, for every tutor.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person
select tests.eq( -- counts the differences between the two ways round:
  (select count(*) from ( -- rows the tutor side has that the student side does not, and the other way:
    (select t.tutor_id, f.student_id, f.subject from public.matching_fill_tutors() t, lateral public.matching_tutor_fill(t.tutor_id) f -- the tutor side
     except -- minus
     select t.tutor_id, m.student_id, m.subject from public.matching_fill_tutors() t, -- the student side:
       (select distinct q.student_id, q.subject from public.matching_queue(p_limit => 100000) q where q.stage in ('needs_tutor', 'waitlist')) m, -- each waiting student and subject,
       lateral public.matching_shortlist(m.student_id, m.subject) s where s.tutor_id = t.tutor_id and s.times > 0) -- where the tutor suits with a time
    union all -- and
    (select t.tutor_id, m.student_id, m.subject from public.matching_fill_tutors() t, -- the student side
       (select distinct q.student_id, q.subject from public.matching_queue(p_limit => 100000) q where q.stage in ('needs_tutor', 'waitlist')) m,
       lateral public.matching_shortlist(m.student_id, m.subject) s where s.tutor_id = t.tutor_id and s.times > 0
     except -- minus
     select t.tutor_id, f.student_id, f.subject from public.matching_fill_tutors() t, lateral public.matching_tutor_fill(t.tutor_id) f) -- the tutor side
  ) d), 0::bigint, 'the tutor side lists exactly the students whose shortlist has that tutor with a time');
reset role; -- back to the database itself
