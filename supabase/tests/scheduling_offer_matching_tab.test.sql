-- The Matching tab: queue, ranked shortlist, gaps, tutor preferences and
-- what a tutor sees before accepting. Runs after the earlier scheduling
-- tests and reuses their people: owner admin (...a0), tutors T3 (...13,
-- General Maths Years 3 to 10, Sam's current tutor) and T4 (...14, General
-- Maths Years 1 to 12, library only), parents P3 (...03, Sam Three's
-- parent) and P4 (...04).

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam and his family id as sam_family.
select id as sam, family_id as sam_family from public.students where full_name = 'Sam Three' \gset
select tests.eq((select (:'sam_family' <> '')::int), 1, 'Sam has a family'); -- Checks: Sam has a family.

-- ---------------------------------------------------------------------------
-- Queue and shortlist
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.matching_queue(null, 'sam three') where subject = 'General Maths'), 1, 'queue finds the student'); -- Checks: queue finds the student.
select tests.eq((select count(*) from public.matching_queue(null, null, 'Year 5', 'SA') where student_id = :'sam'), 1, 'filters by year level and state'); -- Checks: filters by year level and state.
select tests.eq((select count(*) from public.matching_queue(null, null, 'Year 9') where student_id = :'sam'), 0, 'year filter leaves others out'); -- Checks: year filter leaves others out.
select tests.eq((select (sum(subjects) >= 1)::int from public.matching_stage_counts()), 1, 'stage counts'); -- Checks: stage counts.
select tests.eq((select count(*) from public.matching_shortlist(:'sam', 'General Maths') -- Checks both tutors who teach the level are listed:
  where tutor_id in ('00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000014')), 2, 'both tutors who teach the level are listed'); -- (tutors T3 and T4).
select tests.eq((select count(*) from public.matching_shortlist(:'sam', 'General Maths') where tutor_id = '00000000-0000-0000-0000-000000000014' and times = 0), 1, -- Checks a tutor with no times that suit still shows, with none:
  'a tutor with no times that suit still shows, with none'); -- (the label).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- A sibling taught by T4: T4 comes first.
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.students (family_id, full_name, date_of_birth, state, year_level, school) -- Adds Sam's sister Kim to the same family:
-- (aged 12, Year 7) and keeps her id as kim.
values (:'sam_family', 'Kim Three', current_date - interval '12 years', 'SA', 'Year 7', 'Park PS') returning id as kim \gset
insert into public.parent_student_links (parent_id, student_id, verified_at) values ('00000000-0000-0000-0000-000000000003', :'kim', now()); -- Links Kim to Sam's parent.
insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000014', :'kim', 'General Maths'); -- Assigns tutor T4 to Kim for General Maths.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select (teaches_sibling and sibling_names = 'Kim' and rank = 1)::int from public.matching_shortlist(:'sam', 'General Maths') -- Checks the sibling's tutor comes first:
  where tutor_id = '00000000-0000-0000-0000-000000000014'), 1, 'the sibling''s tutor comes first'); -- (tutor T4 is ranked 1 and names Kim).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- At their weekly maximum: still listed, flagged, with no times offered.
select tests.claims(null); -- Signs out, so no one is signed in.
update public.tutor_work_settings set max_weekly_hours = 0.5 where tutor_id = '00000000-0000-0000-0000-000000000013'; -- Sets tutor T3's weekly maximum to half an hour.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select (at_max and times = 0)::int from public.matching_shortlist(:'sam', 'General Maths') -- Checks a tutor at their maximum is flagged and not offered times:
  where tutor_id = '00000000-0000-0000-0000-000000000013'), 1, 'tutor at their maximum is flagged and not offered times'); -- (tutor T3).
select tests.eq((select (rank = (select count(*) from public.matching_shortlist(:'sam', 'General Maths')))::int -- Checks a tutor with no spare hours comes last:
  from public.matching_shortlist(:'sam', 'General Maths') where tutor_id = '00000000-0000-0000-0000-000000000013'), 1, -- (tutor T3 is ranked last),
  'a tutor with no spare hours comes after tutors with room'); -- (the label).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
update public.tutor_work_settings set max_weekly_hours = 3 where tutor_id = '00000000-0000-0000-0000-000000000013'; -- Sets tutor T3's weekly maximum to 3 hr.

-- Why other tutors aren't listed.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.matching_not_offered(:'sam', 'General Maths') -- Checks listed tutors aren't in the "why not" list:
  where tutor_id in ('00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000014')), 0, 'listed tutors aren''t in the why-not list'); -- (neither T3 nor T4).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Gap report: a subject nobody teaches.
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.student_subjects (student_id, subject) values (:'sam', 'Japanese'); -- Adds Japanese to Sam's subjects.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select waiting from public.matching_gaps() where subject = 'Japanese' and state = 'SA'), 1::bigint, 'gap report shows what nobody teaches'); -- Checks: gap report shows what nobody teaches.
select tests.eq((select count(*) from public.matching_gaps() where subject = 'General Maths'), 0, 'taught subjects aren''t gaps'); -- Checks: taught subjects aren't gaps.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.student_subjects where student_id = :'sam' and subject = 'Japanese'; -- Removes Japanese again.

-- Only CLG admins see matching.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select * from public.matching_queue()$$, 'families can''t see the queue'); -- Checks this is refused: families can't see the queue.
select tests.fails(format($$select * from public.matching_shortlist(%L, 'General Maths')$$, :'sam'), 'families can''t see the shortlist'); -- Checks this is refused: families can't see the shortlist.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select * from public.matching_gaps()$$, 'tutors can''t see gaps'); -- Checks this is refused: tutors can't see gaps.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Tutor preferences note
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.student_places (student_id, online, tutor_preferences) values (:'sam', true, 'Someone patient with maths worries') -- Saves Sam's tutor preferences:
on conflict (student_id) do update set tutor_preferences = excluded.tutor_preferences; -- (or updates them if already saved).
select tests.fails(format($$update public.student_places set tutor_preferences = repeat('x', 1001) where student_id = %L$$, :'sam'), 'note too long'); -- Checks this is refused: note too long.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.student_places where student_id = :'sam'), 0, 'tutors don''t see the note'); -- Checks: tutors don't see the note.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Before accepting, a tutor sees only the offer card
-- ---------------------------------------------------------------------------
select tests.claims(null); -- Signs out, so no one is signed in.
update public.students set goals = 'Feel confident with fractions', learning_needs = 'Needs short breaks' where id = :'sam'; -- Writes Sam's goal and learning needs.
delete from public.tutor_assignments where student_id = :'kim'; -- Removes Kim's tutor.
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by) -- Adds an offer for Sam with tutor T4:
values (:'sam', '00000000-0000-0000-0000-000000000014', 'General Maths', 3, '17:00', 60, 'online', current_date + 14, current_date + 42, -- Wednesday 5pm online, starting in two weeks,
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0') -- the tutor has two days to reply, offered by the owner,
-- and keeps its id as pending.
returning id as pending \gset

select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as test account ...14 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select (first_name = 'Sam' and goal = 'Feel confident with fractions' and year_level = 'Year 5')::int -- Checks the offer card shows the first name, year level and goal:
  from public.offer_card(:'pending')), 1, 'offer card: first name, year level and goal'); -- (for the pending offer).
select tests.eq((select count(*) from public.students where id = :'sam'), 0, 'no student record before accepting'); -- Checks: no student record before accepting.
select tests.fails(format($$select * from public.read_student_sensitive(%L)$$, :'sam'), 'no learning needs before accepting'); -- Checks this is refused: no learning needs before accepting.
select tests.eq((select count(*) from public.parent_student_links where student_id = :'sam'), 0, 'no parent details before accepting'); -- Checks: no parent details before accepting.
select tests.eq((select count(*) from public.list_bookings() where id = :'pending' and student_name = 'Sam'), 1, 'bookings list shows the first name only'); -- Checks: bookings list shows the first name only.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.offer_card(:'pending')), 0, 'another tutor can''t see the offer card'); -- Checks: another tutor can't see the offer card.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Once accepted (an assignment exists), the record opens.
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000014', :'sam', 'General Maths') -- Assigns tutor T4 to Sam:
-- and keeps the id as t4_assignment.
returning id as t4_assignment \gset
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as test account ...14 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = :'sam' and learning_needs = 'Needs short breaks'), 1, 'record opens after accepting'); -- Checks: record opens after accepting.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Put things back for the later tests.
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.tutor_assignments where id = :'t4_assignment'; -- Removes that assignment.
delete from public.bookings where id = :'pending'; -- Removes the offer.
delete from public.students where id = :'kim'; -- Removes Kim.
delete from public.student_places where student_id = :'sam'; -- Removes Sam's places.
update public.students set goals = null, learning_needs = null where id = :'sam'; -- Clears Sam's goal and learning needs.

-- Prints that every check in this file passed.
\echo '  scheduling matching tab: all checks passed'
