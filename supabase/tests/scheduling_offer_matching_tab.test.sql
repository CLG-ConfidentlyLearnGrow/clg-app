-- The Matching tab: queue, ranked shortlist, gaps, tutor preferences and
-- what a tutor sees before accepting. Runs after the earlier scheduling
-- tests and reuses their people: owner admin (...a0), tutors T3 (...13,
-- General Maths Years 3 to 10, Sam's current tutor) and T4 (...14, General
-- Maths Years 1 to 12, library only), parents P3 (...03, Sam Three's
-- parent) and P4 (...04).

select tests.claims(null);
select id as sam, family_id as sam_family from public.students where full_name = 'Sam Three' \gset
select tests.eq((select (:'sam_family' <> '')::int), 1, 'Sam has a family');

-- ---------------------------------------------------------------------------
-- Queue and shortlist
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.matching_queue(null, 'sam three') where subject = 'General Maths'), 1, 'queue finds the student');
select tests.eq((select count(*) from public.matching_queue(null, null, 'Year 5', 'SA') where student_id = :'sam'), 1, 'filters by year level and state');
select tests.eq((select count(*) from public.matching_queue(null, null, 'Year 9') where student_id = :'sam'), 0, 'year filter leaves others out');
select tests.eq((select (sum(subjects) >= 1)::int from public.matching_stage_counts()), 1, 'stage counts');
select tests.eq((select count(*) from public.matching_shortlist(:'sam', 'General Maths')
  where tutor_id in ('00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000014')), 2, 'both tutors who teach the level are listed');
select tests.eq((select count(*) from public.matching_shortlist(:'sam', 'General Maths') where tutor_id = '00000000-0000-0000-0000-000000000014' and times = 0), 1,
  'a tutor with no times that suit still shows, with none');
reset role;

-- A sibling taught by T4: T4 comes first.
select tests.claims(null);
insert into public.students (family_id, full_name, date_of_birth, state, year_level, school)
values (:'sam_family', 'Kim Three', current_date - interval '12 years', 'SA', 'Year 7', 'Park PS') returning id as kim \gset
insert into public.parent_student_links (parent_id, student_id, verified_at) values ('00000000-0000-0000-0000-000000000003', :'kim', now());
insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000014', :'kim', 'General Maths');
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select (teaches_sibling and sibling_names = 'Kim' and rank = 1)::int from public.matching_shortlist(:'sam', 'General Maths')
  where tutor_id = '00000000-0000-0000-0000-000000000014'), 1, 'the sibling''s tutor comes first');
reset role;

-- At their weekly maximum: still listed, flagged, with no times offered.
select tests.claims(null);
update public.tutor_work_settings set max_weekly_hours = 0.5 where tutor_id = '00000000-0000-0000-0000-000000000013';
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select (at_max and times = 0)::int from public.matching_shortlist(:'sam', 'General Maths')
  where tutor_id = '00000000-0000-0000-0000-000000000013'), 1, 'tutor at their maximum is flagged and not offered times');
reset role;
select tests.claims(null);
update public.tutor_work_settings set max_weekly_hours = 3 where tutor_id = '00000000-0000-0000-0000-000000000013';

-- Why other tutors aren't listed.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.matching_not_offered(:'sam', 'General Maths')
  where tutor_id in ('00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000014')), 0, 'listed tutors aren''t in the why-not list');
reset role;

-- Gap report: a subject nobody teaches.
select tests.claims(null);
insert into public.student_subjects (student_id, subject) values (:'sam', 'Japanese');
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select waiting from public.matching_gaps() where subject = 'Japanese' and state = 'SA'), 1::bigint, 'gap report shows what nobody teaches');
select tests.eq((select count(*) from public.matching_gaps() where subject = 'General Maths'), 0, 'taught subjects aren''t gaps');
reset role;
select tests.claims(null);
delete from public.student_subjects where student_id = :'sam' and subject = 'Japanese';

-- Only CLG admins see matching.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails($$select * from public.matching_queue()$$, 'families can''t see the queue');
select tests.fails(format($$select * from public.matching_shortlist(%L, 'General Maths')$$, :'sam'), 'families can''t see the shortlist');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails($$select * from public.matching_gaps()$$, 'tutors can''t see gaps');
reset role;

-- ---------------------------------------------------------------------------
-- Tutor preferences note
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
insert into public.student_places (student_id, online, tutor_preferences) values (:'sam', true, 'Someone patient with maths worries')
on conflict (student_id) do update set tutor_preferences = excluded.tutor_preferences;
select tests.fails(format($$update public.student_places set tutor_preferences = repeat('x', 1001) where student_id = %L$$, :'sam'), 'note too long');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.student_places where student_id = :'sam'), 0, 'tutors don''t see the note');
reset role;

-- ---------------------------------------------------------------------------
-- Before accepting, a tutor sees only the offer card
-- ---------------------------------------------------------------------------
select tests.claims(null);
update public.students set goals = 'Feel confident with fractions', learning_needs = 'Needs short breaks' where id = :'sam';
delete from public.tutor_assignments where student_id = :'kim';
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by)
values (:'sam', '00000000-0000-0000-0000-000000000014', 'General Maths', 3, '17:00', 60, 'online', current_date + 14, current_date + 42,
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0')
returning id as pending \gset

select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2');
set role authenticated;
select tests.eq((select (first_name = 'Sam' and goal = 'Feel confident with fractions' and year_level = 'Year 5')::int
  from public.offer_card(:'pending')), 1, 'offer card: first name, year level and goal');
select tests.eq((select count(*) from public.students where id = :'sam'), 0, 'no student record before accepting');
select tests.fails(format($$select * from public.read_student_sensitive(%L)$$, :'sam'), 'no learning needs before accepting');
select tests.eq((select count(*) from public.parent_student_links where student_id = :'sam'), 0, 'no parent details before accepting');
select tests.eq((select count(*) from public.list_bookings() where id = :'pending' and student_name = 'Sam'), 1, 'bookings list shows the first name only');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.offer_card(:'pending')), 0, 'another tutor can''t see the offer card');
reset role;

-- Once accepted (an assignment exists), the record opens.
select tests.claims(null);
insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000014', :'sam', 'General Maths')
returning id as t4_assignment \gset
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.students where id = :'sam' and learning_needs = 'Needs short breaks'), 1, 'record opens after accepting');
reset role;

-- Put things back for the later tests.
select tests.claims(null);
delete from public.tutor_assignments where id = :'t4_assignment';
delete from public.bookings where id = :'pending';
delete from public.students where id = :'kim';
delete from public.student_places where student_id = :'sam';
update public.students set goals = null, learning_needs = null where id = :'sam';

\echo '  scheduling matching tab: all checks passed'
