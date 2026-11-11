-- Scheduling and tutor matching. Runs after access_rules.test.sql and reuses
-- its helpers and the owner admin (...a0). Everything else is set up here:
--   tutors T3 (...13) and T4 (...14), parents P3 (...03) and P4 (...04).

-- ---------------------------------------------------------------------------
-- Set up
-- ---------------------------------------------------------------------------
-- Earlier tests gave other tutors Monday availability; start clean.
delete from public.tutor_availability; -- Clears all tutor availability.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.invitations (email, role, invited_by) values -- Invites two tutors:
  ('s3@clg.example', 'tutor', '00000000-0000-0000-0000-0000000000a0'), -- Tara,
  ('s4@clg.example', 'tutor', '00000000-0000-0000-0000-0000000000a0'); -- and Theo.
reset role; -- Goes back to the all-powerful test user (access rules off).
insert into auth.users (id, email, raw_user_meta_data) values -- They sign up from the invites:
  ('00000000-0000-0000-0000-000000000013', 's3@clg.example', '{"full_name":"Tara Three"}'), -- Tara (tutor T3),
  ('00000000-0000-0000-0000-000000000014', 's4@clg.example', '{"full_name":"Theo Four"}'); -- Theo (tutor T4).
update auth.users set invited_at = now(), email_confirmed_at = now() where email in ('s3@clg.example', 's4@clg.example'); -- Marks both as invited and confirmed.
insert into auth.users (id, email, raw_user_meta_data) values -- Adds two test parents:
  ('00000000-0000-0000-0000-000000000003', 'sp3@example.com', '{"signup_as":"parent","full_name":"Paula Three"}'), -- Paula (account ...03),
  ('00000000-0000-0000-0000-000000000004', 'sp4@example.com', '{"signup_as":"parent","full_name":"Pete Four"}'); -- Pete (account ...04).

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.add_my_child('Sam Three', (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Park PS', -- Paula adds her child, Sam, 10, Year 5:
  '[{"subject": "General Maths", "level": "Year 5"}]'); -- (General Maths at Year 5).
reset role; -- Goes back to the all-powerful test user (access rules off).
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset

-- Admin: libraries, tutor checks and weekly hours.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.libraries (name, suburb) values ('Alpha Library', 'Adelaide'), ('Beta Library', 'Norwood'); -- Adds two libraries: Alpha in Adelaide and Beta in Norwood.
insert into public.tutor_checks (tutor_id, kind, reference, expires_on) -- Gives both tutors current checks:
select t, k::public.tutor_check_kind, 'REF', current_date + 365 -- (each check, expiring in a year)
from unnest(array['00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000014']::uuid[]) t -- (for tutors T3 and T4)
cross join unnest(array['wwcc_sa', 'rrhan_ec_fundamentals', 'rrhan_ec_masterclass']) k; -- (SA WWCC and both RRHAN-EC courses).
update public.tutor_work_settings set max_weekly_hours = 3 where tutor_id = '00000000-0000-0000-0000-000000000013'; -- Sets tutor T3's weekly maximum to 3 hr.
reset role; -- Goes back to the all-powerful test user (access rules off).
-- Keeps Alpha Library's id as lib_a.
select id as lib_a from public.libraries where name = 'Alpha Library' \gset
-- Keeps Beta Library's id as lib_b.
select id as lib_b from public.libraries where name = 'Beta Library' \gset

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.libraries), 2, 'families see libraries'); -- Checks: families see libraries.
select tests.fails($$insert into public.libraries (name) values ('My house')$$, 'parent adds a library'); -- Checks this is refused: parent adds a library.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- T3: Mondays 3pm to 7pm, at Alpha Library or online.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at) -- Tutor T3 is free Mondays 3pm to 7pm:
  values ('00000000-0000-0000-0000-000000000013', 1, '15:00', '19:00'); -- (tutor, day, start, end).
insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) -- Tutor T3 teaches General Maths:
  values ('00000000-0000-0000-0000-000000000013', 'General Maths', 'Year 3', 'Year 10'); -- from Year 3 to Year 10.
insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000013', :'lib_a'); -- Tutor T3 works at Alpha Library.
insert into public.tutor_session_settings (tutor_id, learning_support) values ('00000000-0000-0000-0000-000000000013', true); -- Tutor T3 has learning support experience.
select tests.fails(format($$insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000014', %L)$$, :'lib_a'), 'tutor adds a place for another tutor'); -- Checks this is refused: tutor adds a place for another tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal1'); -- Signs in as test account ...13.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000013', %L)$$, :'lib_b'), 'tutor without two-step login'); -- Checks this is refused: tutor without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- T4: Mondays 3pm to 5pm, Beta Library only, no online.
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as test account ...14 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at) -- Tutor T4 is free Mondays 3pm to 5pm:
  values ('00000000-0000-0000-0000-000000000014', 1, '15:00', '17:00'); -- (tutor, day, start, end).
insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) -- Tutor T4 teaches General Maths:
  values ('00000000-0000-0000-0000-000000000014', 'General Maths', 'Year 1', 'Year 12'); -- from Year 1 to Year 12.
insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000014', :'lib_b'); -- Tutor T4 works at Beta Library.
insert into public.tutor_session_settings (tutor_id, online) values ('00000000-0000-0000-0000-000000000014', false); -- Tutor T4 doesn't teach online.
select tests.eq((select count(*) from public.tutor_places), 1, 'tutor sees only own places'); -- Checks: tutor sees only own places.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Finding times
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- T3: 7 one-hour starts (3pm to 6pm) online + 7 at Alpha. T4: 3 at Beta.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, array[:'lib_a', :'lib_b']::uuid[])), 17, 'all free times'); -- Checks: all free times.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib_b']::uuid[])), 3, 'only the chosen library'); -- Checks: only the chosen library.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}')), 7, 'online only (T4 is not online)'); -- Checks: online only (T4 is not online).
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', null, null, '16:00', '18:00')), 3, 'family time window'); -- Checks: family time window.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', null, array[2]::smallint[])), 0, 'nobody free on Tuesdays'); -- Checks: nobody free on Tuesdays.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'English', 60, true, '{}')), 0, 'nobody teaches English'); -- Checks: nobody teaches English.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 240, true, '{}')), 0, 'four hours is over T3''s 3-hour weekly limit'); -- Checks: four hours is over T3's 3-hour weekly limit.
select tests.fails(format($$select * from public.find_session_times(%L, 'General Maths', 45, true, '{}')$$, :'sam'), 'under one hour'); -- Checks this is refused: under one hour.
select tests.fails(format($$select * from public.find_session_times(%L, 'General Maths', 60, false, '{}')$$, :'sam'), 'no place chosen'); -- Checks this is refused: no place chosen.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as test account ...04.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select * from public.find_session_times(%L, 'General Maths', 60, true, '{}')$$, :'sam'), 'another parent searches'); -- Checks this is refused: another parent searches.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Requesting
-- ---------------------------------------------------------------------------
-- Keeps the Monday after next as first_day.
select (current_date + 7 + ((8 - extract(isodow from current_date)::int) % 7)) as first_day \gset
-- Parents' own links are confirmed straight away; undo that to test the rule.
select tests.claims(null); -- Signs out, so no one is signed in.
update public.parent_student_links set verified_at = null where student_id = :'sam'; -- Makes Sam's parent link unconfirmed.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'library', %L, %L::date, %L::date + 28)$$, :'sam', :'lib_a', :'first_day', :'first_day'), 'parent link not yet verified'); -- Checks this is refused: parent link not yet verified.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
update public.parent_student_links set verified_at = now() where student_id = :'sam'; -- Confirms it again.

-- A family paused for an overdue payment can't book (billing's function).
-- If billing's real function is installed, move it aside for this check.
do $$ -- Sets aside the real "is this family on hold?" check, if there is one:
begin -- (start)
  if to_regprocedure('private.billing_family_paused(uuid)') is not null then -- if it exists,
    alter function private.billing_family_paused(uuid) rename to billing_family_paused_set_aside; -- renames it out of the way.
  end if; -- End of the check.
end; -- (end)
$$; -- (end of the block)
create function private.billing_family_paused(p_family uuid) returns boolean language sql stable as $$ select true $$; -- A stand-in that says every family is on hold.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'library', %L, %L::date, %L::date + 28)$$, :'sam', :'lib_a', :'first_day', :'first_day'), 'family paused'); -- Checks this is refused: family paused.
reset role; -- Goes back to the all-powerful test user (access rules off).
drop function private.billing_family_paused(uuid); -- Removes the stand-in.
do $$ -- Puts the real check back:
begin -- (start)
  if to_regprocedure('private.billing_family_paused_set_aside(uuid)') is not null then -- if it was set aside,
    alter function private.billing_family_paused_set_aside(uuid) rename to billing_family_paused; -- gives it its name back.
  end if; -- End of the check.
end; -- (end)
$$; -- (end of the block)

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'home', null, %L::date, %L::date + 28)$$, :'sam', :'first_day', :'first_day'), 'parent books a home session'); -- Checks this is refused: parent books a home session.
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000014', 1::smallint, '16:00', 60, 'library', %L, %L::date, %L::date + 28)$$, :'sam', :'lib_a', :'first_day', :'first_day'), 'tutor does not go to that library'); -- Checks this is refused: tutor does not go to that library.
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '18:30', 60, 'online', null, %L::date, %L::date + 28)$$, :'sam', :'first_day', :'first_day'), 'runs past the tutor''s availability'); -- Checks this is refused: runs past the tutor's availability.
select tests.fails(format($$select public.request_booking(%L, 'Science', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'online', null, %L::date, %L::date + 28)$$, :'sam', :'first_day', :'first_day'), 'subject not asked for'); -- Checks this is refused: subject not asked for.
select tests.fails($$insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date) select id, '00000000-0000-0000-0000-000000000013', 'General Maths', 1, '16:00', 60, 'online', current_date, current_date from public.students$$, 'parent writes a booking directly'); -- Checks this is refused: parent writes a booking directly.
-- Asks for a Monday 4pm booking at Alpha with tutor T3 for four weeks, with a note; keeps its id as booking_1.
select public.request_booking(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'library', :'lib_a', :'first_day'::date, :'first_day'::date + 28, 'Prefers a quiet room') as booking_1 \gset
select tests.eq((select extract(isodow from first_date)::int from public.bookings where id = :'booking_1'), 1, 'first session moved to a Monday'); -- Checks: first session moved to a Monday.
select tests.eq((select count(*) from public.list_bookings() where id = :'booking_1' and tutor_name = 'Tara Three'), 1, 'family sees the tutor''s name on the request'); -- Checks: family sees the tutor's name on the request.
-- The time is now held. T3 is busy 4pm to 5pm and Sam can't be in two places.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}')), 4, 'held time no longer offered'); -- Checks: held time no longer offered.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}') where joins_other_sessions), 2, 'times next to the booking are marked'); -- Checks: times next to the booking are marked.
select tests.eq((select count(*) from (select joins_other_sessions from public.find_session_times(:'sam', 'General Maths', 60, true, '{}') limit 2) x where joins_other_sessions), 2, 'and listed first'); -- Checks: and listed first.
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:30', 60, 'online', null, %L::date, %L::date + 28)$$, :'sam', :'first_day', :'first_day'), 'clashing time'); -- Checks this is refused: clashing time.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- One library a day: T3 is at Alpha on Mondays now, so not offered at Beta.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000013', :'lib_b'); -- Tutor T3 can also work at Beta Library.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib_b']::uuid[]) where tutor_id = '00000000-0000-0000-0000-000000000013'), 0, 'tutor stays at one library a day'); -- Checks: tutor stays at one library a day.
-- Weekly hours: T3 has 1 of 3 hours booked, so a 3-hour session won't fit.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 180, true, '{}') where tutor_id = '00000000-0000-0000-0000-000000000013'), 0, 'over the weekly hour limit'); -- Checks: over the weekly hour limit.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- The tutor answers
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_bookings() where id = :'booking_1' and student_name = 'Sam' and family_note = 'Prefers a quiet room'), 1, 'tutor sees first name only before accepting'); -- Checks: tutor sees first name only before accepting.
select tests.eq((select count(*) from public.students where id = :'sam'), 0, 'tutor cannot open the student record yet'); -- Checks: tutor cannot open the student record yet.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal1'); -- Signs in as test account ...13.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.respond_to_booking(%L, true)$$, :'booking_1'), 'tutor without two-step login'); -- Checks this is refused: tutor without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as test account ...14 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_bookings()), 0, 'other tutor sees no bookings'); -- Checks: other tutor sees no bookings.
select tests.fails(format($$select public.respond_to_booking(%L, true)$$, :'booking_1'), 'other tutor accepts'); -- Checks this is refused: other tutor accepts.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.respond_to_booking(%L, true)$$, :'booking_1'), 'parent accepts for the tutor'); -- Checks this is refused: parent accepts for the tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.respond_to_booking(:'booking_1', true, 'See you then'); -- Tutor T3 accepts, with a note.
select tests.eq((select count(*) from public.sessions where booking_id = :'booking_1'), 5, 'five weekly sessions made'); -- Checks: five weekly sessions made.
select tests.eq((select count(*) from public.sessions where booking_id = :'booking_1' and level_kind = 'school' and delivery = 'library' and library_id = :'lib_a'), 5, 'sessions carry level and place'); -- Checks: sessions carry level and place.
select tests.eq((select count(*) from public.sessions where booking_id = :'booking_1' and to_char(starts_at at time zone 'Australia/Adelaide', 'HH24:MI') = '16:00' and ends_at - starts_at = interval '1 hour'), 5, 'sessions at 4pm Adelaide time'); -- Checks: sessions at 4pm Adelaide time.
select tests.eq((select count(*) from public.students where id = :'sam'), 1, 'tutor can open the student record once assigned'); -- Checks: tutor can open the student record once assigned.
select tests.eq((select count(*) from public.list_bookings() where student_name = 'Sam Three'), 1, 'full name after accepting'); -- Checks: full name after accepting.
select tests.fails(format($$select public.respond_to_booking(%L, false)$$, :'booking_1'), 'answering twice'); -- Checks this is refused: answering twice.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.tutor_assignments where tutor_id = '00000000-0000-0000-0000-000000000013' and student_id = :'sam' and ends_on = :'first_day'::date + 28), 1, 'tutor assigned until the last date'); -- Checks: tutor assigned until the last date.

-- ---------------------------------------------------------------------------
-- Who sees sessions
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.sessions), 5, 'family sees their sessions'); -- Checks: family sees their sessions.
select tests.eq((select count(*) from public.list_sessions(null, (current_date + 60)::date)), 5, 'family session list'); -- Checks: family session list.
select tests.fails($$update public.sessions set status = 'completed'$$, 'family edits a session'); -- Checks this is refused: family edits a session.
select tests.fails($$delete from public.sessions$$, 'family deletes a session'); -- Checks this is refused: family deletes a session.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as test account ...04.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.sessions), 0, 'other family sees none'); -- Checks: other family sees none.
select tests.eq((select count(*) from public.list_sessions()), 0, 'other family list is empty'); -- Checks: other family list is empty.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as test account ...14 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.sessions), 0, 'other tutor sees none'); -- Checks: other tutor sees none.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.sessions$$, 'anon sessions'); -- Checks this is refused: anon sessions.
select tests.fails($$select * from public.bookings$$, 'anon bookings'); -- Checks this is refused: anon bookings.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Cancelling and recording
-- ---------------------------------------------------------------------------
-- Keeps the first session's id as s1.
select id as s1 from public.sessions where booking_id = :'booking_1' order by starts_at limit 1 \gset
-- Keeps the second session's id as s2.
select id as s2 from public.sessions where booking_id = :'booking_1' order by starts_at offset 1 limit 1 \gset
-- Keeps the third session's id as s3.
select id as s3 from public.sessions where booking_id = :'booking_1' order by starts_at offset 2 limit 1 \gset

select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as test account ...04.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.cancel_session(%L)$$, :'s1'), 'other parent cancels'); -- Checks this is refused: other parent cancels.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.cancel_session(:'s1', 'Sick'); -- The family cancels the first session (sick).
select tests.eq((select count(*) from public.sessions where id = :'s1' and status = 'cancelled' and cancelled_by_role = 'family' and cancelled_at is not null), 1, 'family cancels a session'); -- Checks: family cancels a session.
select tests.fails(format($$select public.cancel_session(%L)$$, :'s1'), 'cancelling twice'); -- Checks this is refused: cancelling twice.
select tests.fails(format($$select public.cancel_session(%L, null, 'admin')$$, :'s2'), 'family claims to be CLG'); -- Checks this is refused: family claims to be CLG.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.cancel_session(:'s2', 'Tutor unwell', 'tutor'); -- The tutor cancels the second session (unwell).
select tests.eq((select count(*) from public.sessions where id = :'s2' and cancelled_by_role = 'tutor'), 1, 'admin cancels for the tutor'); -- Checks: admin cancels for the tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Recording what happened, once the session has started.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.record_session_outcome(%L, 'completed')$$, :'s3'), 'session not started yet'); -- Checks this is refused: session not started yet.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
update public.sessions set starts_at = now() - interval '2 hours', ends_at = now() - interval '1 hour' where id = :'s3'; -- Moves the third session into the past.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.record_session_outcome(%L, 'completed')$$, :'s3'), 'parent records an outcome'); -- Checks this is refused: parent records an outcome.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.record_session_outcome(%L, 'cancelled')$$, :'s3'), 'outcome must be completed or no-show'); -- Checks this is refused: outcome must be completed or no-show.
select public.record_session_outcome(:'s3', 'completed'); -- Records the third session as done.
select tests.fails(format($$select public.record_session_outcome(%L, 'no_show')$$, :'s3'), 'tutor changes a recorded outcome'); -- Checks this is refused: tutor changes a recorded outcome.
select tests.fails(format($$select public.cancel_session(%L)$$, :'s3'), 'cancel a completed session'); -- Checks this is refused: cancel a completed session.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.sessions where id = :'s3' and status = 'completed' and completed_at is not null), 1, 'session completed'); -- Checks: session completed.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.record_session_outcome(:'s3', 'no_show'); -- Tries to change it to a no-show.
select tests.eq((select count(*) from public.sessions where id = :'s3' and status = 'no_show' and completed_at is null), 1, 'admin corrects an outcome'); -- Checks: admin corrects an outcome.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Declined and expired requests
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Asks for a Monday 3pm booking at Beta with tutor T4 for a week; keeps its id as booking_2.
select public.request_booking(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000014', 1::smallint, '15:00', 60, 'library', :'lib_b', :'first_day'::date, :'first_day'::date + 7) as booking_2 \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as test account ...14 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.respond_to_booking(:'booking_2', false, 'Sorry, not this term'); -- Tutor T4 declines, with a reason.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.bookings where id = :'booking_2' and status = 'declined'), 1, 'tutor declines'); -- Checks: tutor declines.
select tests.eq((select count(*) from public.sessions where booking_id = :'booking_2'), 0, 'no sessions when declined'); -- Checks: no sessions when declined.

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Asks again; keeps its id as booking_3.
select public.request_booking(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000014', 1::smallint, '15:00', 60, 'library', :'lib_b', :'first_day'::date, :'first_day'::date + 7) as booking_3 \gset
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib_b']::uuid[])), 0, 'requested time is held'); -- Checks: requested time is held.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
update public.bookings set tutor_reply_by = now() - interval '1 minute' where id = :'booking_3'; -- Makes the tutor's time to reply run out.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib_b']::uuid[])), 1, 'expired request frees the time'); -- Checks: expired request frees the time.
select tests.eq((select count(*) from public.list_bookings() where id = :'booking_3' and expired), 1, 'shown as expired'); -- Checks: shown as expired.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as test account ...14 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.respond_to_booking(%L, true)$$, :'booking_3'), 'tutor accepts after 48 hours'); -- Checks this is refused: tutor accepts after 48 hours.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Stopping a booking cancels its future sessions
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.cancel_booking(:'booking_1', 'Moving interstate'); -- Cancels the first booking (moving interstate).
select tests.eq((select count(*) from public.bookings where id = :'booking_1' and status = 'ended'), 1, 'booking ended'); -- Checks: booking ended.
select tests.eq((select count(*) from public.sessions where booking_id = :'booking_1' and status = 'scheduled'), 0, 'no future sessions left'); -- Checks: no future sessions left.
select tests.eq((select count(*) from public.sessions where booking_id = :'booking_1' and status = 'no_show'), 1, 'past session kept'); -- Checks: past session kept.
select tests.fails(format($$select public.cancel_booking(%L)$$, :'booking_1'), 'stopping twice'); -- Checks this is refused: stopping twice.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- Prints that every check in this file passed.
\echo '  scheduling: all checks passed'
