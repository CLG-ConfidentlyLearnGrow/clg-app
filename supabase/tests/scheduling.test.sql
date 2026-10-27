-- Scheduling and tutor matching. Runs after access_rules.test.sql and reuses
-- its helpers and the owner admin (...a0). Everything else is set up here:
--   tutors T3 (...13) and T4 (...14), parents P3 (...03) and P4 (...04).

-- ---------------------------------------------------------------------------
-- Set up
-- ---------------------------------------------------------------------------
-- Earlier tests gave other tutors Monday availability; start clean.
delete from public.tutor_availability;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
insert into public.invitations (email, role, invited_by) values
  ('s3@clg.example', 'tutor', '00000000-0000-0000-0000-0000000000a0'),
  ('s4@clg.example', 'tutor', '00000000-0000-0000-0000-0000000000a0');
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000013', 's3@clg.example', '{"full_name":"Tara Three"}'),
  ('00000000-0000-0000-0000-000000000014', 's4@clg.example', '{"full_name":"Theo Four"}');
update auth.users set invited_at = now(), email_confirmed_at = now() where email in ('s3@clg.example', 's4@clg.example');
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000003', 'sp3@example.com', '{"signup_as":"parent","full_name":"Paula Three"}'),
  ('00000000-0000-0000-0000-000000000004', 'sp4@example.com', '{"signup_as":"parent","full_name":"Pete Four"}');

select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.add_my_child('Sam Three', (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Park PS',
  '[{"subject": "General Maths", "level": "Year 5"}]');
reset role;
select id as sam from public.students where full_name = 'Sam Three' \gset

-- Admin: libraries, tutor checks and weekly hours.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
insert into public.libraries (name, suburb) values ('Alpha Library', 'Adelaide'), ('Beta Library', 'Norwood');
insert into public.tutor_checks (tutor_id, kind, reference, expires_on)
select t, k::public.tutor_check_kind, 'REF', current_date + 365
from unnest(array['00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000014']::uuid[]) t
cross join unnest(array['wwcc_sa', 'rrhan_ec_fundamentals', 'rrhan_ec_masterclass']) k;
update public.tutor_work_settings set max_weekly_hours = 3 where tutor_id = '00000000-0000-0000-0000-000000000013';
reset role;
select id as lib_a from public.libraries where name = 'Alpha Library' \gset
select id as lib_b from public.libraries where name = 'Beta Library' \gset

select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.libraries), 2, 'families see libraries');
select tests.fails($$insert into public.libraries (name) values ('My house')$$, 'parent adds a library');
reset role;

-- T3: Mondays 3pm to 7pm, at Alpha Library or online.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at)
  values ('00000000-0000-0000-0000-000000000013', 1, '15:00', '19:00');
insert into public.tutor_teaching (tutor_id, subject, from_level, to_level)
  values ('00000000-0000-0000-0000-000000000013', 'General Maths', 'Year 3', 'Year 10');
insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000013', :'lib_a');
insert into public.tutor_session_settings (tutor_id, learning_support) values ('00000000-0000-0000-0000-000000000013', true);
select tests.fails(format($$insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000014', %L)$$, :'lib_a'), 'tutor adds a place for another tutor');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal1');
set role authenticated;
select tests.fails(format($$insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000013', %L)$$, :'lib_b'), 'tutor without two-step login');
reset role;

-- T4: Mondays 3pm to 5pm, Beta Library only, no online.
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2');
set role authenticated;
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at)
  values ('00000000-0000-0000-0000-000000000014', 1, '15:00', '17:00');
insert into public.tutor_teaching (tutor_id, subject, from_level, to_level)
  values ('00000000-0000-0000-0000-000000000014', 'General Maths', 'Year 1', 'Year 12');
insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000014', :'lib_b');
insert into public.tutor_session_settings (tutor_id, online) values ('00000000-0000-0000-0000-000000000014', false);
select tests.eq((select count(*) from public.tutor_places), 1, 'tutor sees only own places');
reset role;

-- ---------------------------------------------------------------------------
-- Finding times
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
-- T3: 7 one-hour starts (3pm to 6pm) online + 7 at Alpha. T4: 3 at Beta.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, array[:'lib_a', :'lib_b']::uuid[])), 17, 'all free times');
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib_b']::uuid[])), 3, 'only the chosen library');
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}')), 7, 'online only (T4 is not online)');
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', null, null, '16:00', '18:00')), 3, 'family time window');
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', null, array[2]::smallint[])), 0, 'nobody free on Tuesdays');
select tests.eq((select count(*) from public.find_session_times(:'sam', 'English', 60, true, '{}')), 0, 'nobody teaches English');
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 240, true, '{}')), 0, 'four hours is over T3''s 3-hour weekly limit');
select tests.fails(format($$select * from public.find_session_times(%L, 'General Maths', 45, true, '{}')$$, :'sam'), 'under one hour');
select tests.fails(format($$select * from public.find_session_times(%L, 'General Maths', 60, false, '{}')$$, :'sam'), 'no place chosen');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.fails(format($$select * from public.find_session_times(%L, 'General Maths', 60, true, '{}')$$, :'sam'), 'another parent searches');
reset role;

-- ---------------------------------------------------------------------------
-- Requesting
-- ---------------------------------------------------------------------------
select (current_date + 7 + ((8 - extract(isodow from current_date)::int) % 7)) as first_day \gset
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'library', %L, %L::date, %L::date + 28)$$, :'sam', :'lib_a', :'first_day', :'first_day'), 'parent link not yet verified');
reset role;
select tests.claims(null);
update public.parent_student_links set verified_at = now() where student_id = :'sam';

-- A family paused for an overdue payment can't book (billing's function).
create function private.billing_family_paused(p_family uuid) returns boolean language sql stable as $$ select true $$;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'library', %L, %L::date, %L::date + 28)$$, :'sam', :'lib_a', :'first_day', :'first_day'), 'family paused');
reset role;
drop function private.billing_family_paused(uuid);

select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'home', null, %L::date, %L::date + 28)$$, :'sam', :'first_day', :'first_day'), 'parent books a home session');
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000014', 1::smallint, '16:00', 60, 'library', %L, %L::date, %L::date + 28)$$, :'sam', :'lib_a', :'first_day', :'first_day'), 'tutor does not go to that library');
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '18:30', 60, 'online', null, %L::date, %L::date + 28)$$, :'sam', :'first_day', :'first_day'), 'runs past the tutor''s availability');
select tests.fails(format($$select public.request_booking(%L, 'Science', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'online', null, %L::date, %L::date + 28)$$, :'sam', :'first_day', :'first_day'), 'subject not asked for');
select tests.fails($$insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date) select id, '00000000-0000-0000-0000-000000000013', 'General Maths', 1, '16:00', 60, 'online', current_date, current_date from public.students$$, 'parent writes a booking directly');
select public.request_booking(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'library', :'lib_a', :'first_day'::date, :'first_day'::date + 28, 'Prefers a quiet room') as booking_1 \gset
select tests.eq((select extract(isodow from first_date)::int from public.bookings where id = :'booking_1'), 1, 'first session moved to a Monday');
select tests.eq((select count(*) from public.list_bookings() where id = :'booking_1' and tutor_name = 'Tara Three'), 1, 'family sees the tutor''s name on the request');
-- The time is now held. T3 is busy 4pm to 5pm and Sam can't be in two places.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}')), 4, 'held time no longer offered');
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}') where joins_other_sessions), 2, 'times next to the booking are marked');
select tests.eq((select count(*) from (select joins_other_sessions from public.find_session_times(:'sam', 'General Maths', 60, true, '{}') limit 2) x where joins_other_sessions), 2, 'and listed first');
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:30', 60, 'online', null, %L::date, %L::date + 28)$$, :'sam', :'first_day', :'first_day'), 'clashing time');
reset role;

-- One library a day: T3 is at Alpha on Mondays now, so not offered at Beta.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000013', :'lib_b');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib_b']::uuid[]) where tutor_id = '00000000-0000-0000-0000-000000000013'), 0, 'tutor stays at one library a day');
-- Weekly hours: T3 has 1 of 3 hours booked, so a 3-hour session won't fit.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 180, true, '{}') where tutor_id = '00000000-0000-0000-0000-000000000013'), 0, 'over the weekly hour limit');
reset role;

-- ---------------------------------------------------------------------------
-- The tutor answers
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.list_bookings() where id = :'booking_1' and student_name = 'Sam' and family_note = 'Prefers a quiet room'), 1, 'tutor sees first name only before accepting');
select tests.eq((select count(*) from public.students where id = :'sam'), 0, 'tutor cannot open the student record yet');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal1');
set role authenticated;
select tests.fails(format($$select public.respond_to_booking(%L, true)$$, :'booking_1'), 'tutor without two-step login');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.list_bookings()), 0, 'other tutor sees no bookings');
select tests.fails(format($$select public.respond_to_booking(%L, true)$$, :'booking_1'), 'other tutor accepts');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.respond_to_booking(%L, true)$$, :'booking_1'), 'parent accepts for the tutor');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select public.respond_to_booking(:'booking_1', true, 'See you then');
select tests.eq((select count(*) from public.sessions where booking_id = :'booking_1'), 5, 'five weekly sessions made');
select tests.eq((select count(*) from public.sessions where booking_id = :'booking_1' and level_kind = 'school' and delivery = 'library' and library_id = :'lib_a'), 5, 'sessions carry level and place');
select tests.eq((select count(*) from public.sessions where booking_id = :'booking_1' and to_char(starts_at at time zone 'Australia/Adelaide', 'HH24:MI') = '16:00' and ends_at - starts_at = interval '1 hour'), 5, 'sessions at 4pm Adelaide time');
select tests.eq((select count(*) from public.students where id = :'sam'), 1, 'tutor can open the student record once assigned');
select tests.eq((select count(*) from public.list_bookings() where student_name = 'Sam Three'), 1, 'full name after accepting');
select tests.fails(format($$select public.respond_to_booking(%L, false)$$, :'booking_1'), 'answering twice');
reset role;
select tests.eq((select count(*) from public.tutor_assignments where tutor_id = '00000000-0000-0000-0000-000000000013' and student_id = :'sam' and ends_on = :'first_day'::date + 28), 1, 'tutor assigned until the last date');

-- ---------------------------------------------------------------------------
-- Who sees sessions
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.sessions), 5, 'family sees their sessions');
select tests.eq((select count(*) from public.list_sessions(null, (current_date + 60)::date)), 5, 'family session list');
select tests.fails($$update public.sessions set status = 'completed'$$, 'family edits a session');
select tests.fails($$delete from public.sessions$$, 'family deletes a session');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.eq((select count(*) from public.sessions), 0, 'other family sees none');
select tests.eq((select count(*) from public.list_sessions()), 0, 'other family list is empty');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.sessions), 0, 'other tutor sees none');
reset role;
select tests.claims(null);
set role anon;
select tests.fails($$select * from public.sessions$$, 'anon sessions');
select tests.fails($$select * from public.bookings$$, 'anon bookings');
reset role;

-- ---------------------------------------------------------------------------
-- Cancelling and recording
-- ---------------------------------------------------------------------------
select id as s1 from public.sessions where booking_id = :'booking_1' order by starts_at limit 1 \gset
select id as s2 from public.sessions where booking_id = :'booking_1' order by starts_at offset 1 limit 1 \gset
select id as s3 from public.sessions where booking_id = :'booking_1' order by starts_at offset 2 limit 1 \gset

select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.fails(format($$select public.cancel_session(%L)$$, :'s1'), 'other parent cancels');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.cancel_session(:'s1', 'Sick');
select tests.eq((select count(*) from public.sessions where id = :'s1' and status = 'cancelled' and cancelled_by_role = 'family' and cancelled_at is not null), 1, 'family cancels a session');
select tests.fails(format($$select public.cancel_session(%L)$$, :'s1'), 'cancelling twice');
select tests.fails(format($$select public.cancel_session(%L, null, 'admin')$$, :'s2'), 'family claims to be CLG');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.cancel_session(:'s2', 'Tutor unwell', 'tutor');
select tests.eq((select count(*) from public.sessions where id = :'s2' and cancelled_by_role = 'tutor'), 1, 'admin cancels for the tutor');
reset role;

-- Recording what happened, once the session has started.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails(format($$select public.record_session_outcome(%L, 'completed')$$, :'s3'), 'session not started yet');
reset role;
select tests.claims(null);
update public.sessions set starts_at = now() - interval '2 hours', ends_at = now() - interval '1 hour' where id = :'s3';
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.record_session_outcome(%L, 'completed')$$, :'s3'), 'parent records an outcome');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails(format($$select public.record_session_outcome(%L, 'cancelled')$$, :'s3'), 'outcome must be completed or no-show');
select public.record_session_outcome(:'s3', 'completed');
select tests.fails(format($$select public.record_session_outcome(%L, 'no_show')$$, :'s3'), 'tutor changes a recorded outcome');
select tests.fails(format($$select public.cancel_session(%L)$$, :'s3'), 'cancel a completed session');
reset role;
select tests.eq((select count(*) from public.sessions where id = :'s3' and status = 'completed' and completed_at is not null), 1, 'session completed');
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.record_session_outcome(:'s3', 'no_show');
select tests.eq((select count(*) from public.sessions where id = :'s3' and status = 'no_show' and completed_at is null), 1, 'admin corrects an outcome');
reset role;

-- ---------------------------------------------------------------------------
-- Declined and expired requests
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.request_booking(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000014', 1::smallint, '15:00', 60, 'library', :'lib_b', :'first_day'::date, :'first_day'::date + 7) as booking_2 \gset
reset role;
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2');
set role authenticated;
select public.respond_to_booking(:'booking_2', false, 'Sorry, not this term');
reset role;
select tests.eq((select count(*) from public.bookings where id = :'booking_2' and status = 'declined'), 1, 'tutor declines');
select tests.eq((select count(*) from public.sessions where booking_id = :'booking_2'), 0, 'no sessions when declined');

select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.request_booking(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000014', 1::smallint, '15:00', 60, 'library', :'lib_b', :'first_day'::date, :'first_day'::date + 7) as booking_3 \gset
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib_b']::uuid[])), 0, 'requested time is held');
reset role;
select tests.claims(null);
update public.bookings set tutor_reply_by = now() - interval '1 minute' where id = :'booking_3';
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib_b']::uuid[])), 1, 'expired request frees the time');
select tests.eq((select count(*) from public.list_bookings() where id = :'booking_3' and expired), 1, 'shown as expired');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2');
set role authenticated;
select tests.fails(format($$select public.respond_to_booking(%L, true)$$, :'booking_3'), 'tutor accepts after 48 hours');
reset role;

-- ---------------------------------------------------------------------------
-- Stopping a booking cancels its future sessions
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.cancel_booking(:'booking_1', 'Moving interstate');
select tests.eq((select count(*) from public.bookings where id = :'booking_1' and status = 'ended'), 1, 'booking ended');
select tests.eq((select count(*) from public.sessions where booking_id = :'booking_1' and status = 'scheduled'), 0, 'no future sessions left');
select tests.eq((select count(*) from public.sessions where booking_id = :'booking_1' and status = 'no_show'), 1, 'past session kept');
select tests.fails(format($$select public.cancel_booking(%L)$$, :'booking_1'), 'stopping twice');
reset role;
select tests.claims(null);

\echo '  scheduling: all checks passed'
