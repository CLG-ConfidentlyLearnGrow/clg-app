-- Carla's 2 Nov 2026 scheduling changes: offer follow-ups at 48 hours,
-- preferred parts of the day, requests (extra sessions, public holiday
-- one-offs, cover), public holidays, blocking, libraries with opening hours
-- and home or school sessions. Runs after scheduling_offer.test.sql and
-- reuses its people: owner admin (...a0), tutors T3 (...13) and T4
-- (...14), parents P3 (...03, Sam Three's parent) and P4 (...04).

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id, family id and state.
select id as sam, family_id as sam_family, state as sam_state from public.students where full_name = 'Sam Three' \gset
-- Keeps the Monday after next as first_day.
select (current_date + 7 + ((8 - extract(isodow from current_date)::int) % 7)) as first_day \gset

-- ---------------------------------------------------------------------------
-- Offers: open 72 hours, follow-up at 48
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select f.tutor_id as offer_tutor, f.weekday as offer_day, f.start_time as offer_start -- Keeps the first online time the app finds:
from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) f -- (searching General Maths, an hour, online, from first_day),
-- (the earliest one).
where f.delivery = 'online' order by f.weekday, f.start_time limit 1 \gset
select public.request_booking(:'sam', 'General Maths', :'offer_tutor', :'offer_day'::smallint, :'offer_start'::time, 60, -- An admin offers that time for three weeks:
  -- and keeps its id as offer.
  'online', null, :'first_day'::date, :'first_day'::date + 21) as offer \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select (tutor_reply_by = requested_at + interval '72 hours')::int from public.bookings where id = :'offer'), 1, 'CLG offers stay open 72 hours'); -- Checks: CLG offers stay open 72 hours.
select private.queue_offer_follow_ups(); -- Queues follow-ups for offers waiting on a reply.
select tests.eq((select count(*) from public.session_notices where booking_id = :'offer' and kind = 'offer_follow_up'), 0, 'no follow-up before 48 hours'); -- Checks: no follow-up before 48 hours.

-- The family approves; 48 hours pass with the tutor still to answer.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.approve_booking(:'offer', true); -- The family approves.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
update public.bookings set requested_at = now() - interval '49 hours', tutor_reply_by = now() + interval '23 hours' where id = :'offer'; -- Makes the offer 49 hours old, with 23 hours left for the tutor.
select tests.eq(private.queue_offer_follow_ups(), 1, 'one offer followed up'); -- Checks: one offer followed up.
select tests.eq((select count(*) from public.session_notices where booking_id = :'offer' and kind = 'offer_follow_up' -- Checks the tutor is reminded:
  and account_id = :'offer_tutor' and title like 'Reminder%'), 1, 'tutor reminded'); -- (one reminder).
select tests.eq((select count(*) from public.session_notices where booking_id = :'offer' and kind = 'offer_follow_up' -- Checks the family is told it's waiting on the tutor:
  and account_id = '00000000-0000-0000-0000-000000000003' and title = 'Waiting for the tutor'), 1, 'family told it is waiting on the tutor'); -- (one notice).
select tests.eq(private.queue_offer_follow_ups(), 0, 'followed up once'); -- Checks: followed up once.
-- Still open after 48 hours: the tutor can answer.
select tests.claims(:'offer_tutor', 'aal2'); -- Signs in as the account named here with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.respond_to_booking(:'offer', false, 'Not that day after all'); -- The tutor declines.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.bookings where id = :'offer'; -- Removes the offer.

-- ---------------------------------------------------------------------------
-- Preferred parts of the day
-- ---------------------------------------------------------------------------
select tests.eq((private.part_of_day('09:30') = 'morning' and private.part_of_day('12:00') = 'midday' -- Checks the parts of the day:
  and private.part_of_day('15:30') = 'afternoon' and private.part_of_day('17:00') = 'evening')::int, 1, 'parts of the day'); -- (morning, midday, afternoon and evening).
insert into public.student_places (student_id, online, preferred_parts) values (:'sam', true, array['evening']); -- Sam prefers evenings.
select tests.fails(format($$update public.student_places set preferred_parts = array['night'] where student_id = %L$$, :'sam'), 'not a part of the day'); -- Checks this is refused: not a part of the day.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.offer_options(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) -- Checks only evening times are marked preferred:
  where preferred and start_time < '17:00'), 0, 'only evening times marked preferred'); -- (none before 5pm).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.student_places where student_id = :'sam'; -- Removes Sam's places.

-- ---------------------------------------------------------------------------
-- Requests: an extra session before a test
-- ---------------------------------------------------------------------------
select a.tutor_id as sam_tutor from public.tutor_assignments a -- Keeps Sam's current General Maths tutor as sam_tutor:
where a.student_id = :'sam' and lower(a.subject) = 'general maths' and private.assignment_is_current(a.starts_on, a.ends_on) -- (a current assignment),
-- (the latest one).
order by a.starts_on desc limit 1 \gset

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.make_session_request(%L, 'extra', 'General Maths')$$, :'sam'), 'extra needs the event date'); -- Checks this is refused: extra needs the event date.
select tests.fails(format($$select public.make_session_request(%L, 'extra', 'General Maths', current_date - 1)$$, :'sam'), 'event in the past'); -- Checks this is refused: event in the past.
-- The family asks for an extra session before an algebra test, and keeps its id as req.
select public.make_session_request(:'sam', 'extra', 'General Maths', current_date + 20, 'Algebra test', null, 'Any afternoon') as req \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as test account ...04.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.make_session_request(%L, 'extra', 'General Maths', current_date + 20)$$, :'sam'), 'another parent asks'); -- Checks this is refused: another parent asks.
select tests.eq((select count(*) from public.list_session_requests()), 0, 'another parent sees none'); -- Checks: another parent sees none.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.session_requests where id = :'req' and tutor_id = :'sam_tutor'), 1, 'request goes to the student''s tutor'); -- Checks: request goes to the student's tutor.
select tests.eq((select count(*) from public.session_notices where account_id = :'sam_tutor' and kind = 'request_update' and body like '%Algebra test%'), 1, 'tutor told'); -- Checks: tutor told.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and kind = 'staff_alert' and title = 'Extra session asked for'), 1, 'admins told'); -- Checks: admins told.

-- The tutor offers a time before the test; after the test is refused.
select tests.claims(:'sam_tutor', 'aal2'); -- Signs in as the account named here with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_session_requests() where id = :'req'), 1, 'tutor sees the request'); -- Checks: tutor sees the request.
select tests.fails(format($$select public.offer_one_off(%L, null, current_date + 21, '16:00', 60, 'online')$$, :'req'), 'offer after the test'); -- Checks this is refused: offer after the test.
select tests.fails(format($$select public.offer_one_off(%L, null, current_date + 5, '16:00', 60, 'home')$$, :'req'), 'tutor offers a home session'); -- Checks this is refused: tutor offers a home session.
-- An admin offers a one-off 6am online session, and keeps its id as one_off.
select public.offer_one_off(:'req', null, current_date + 5, '06:00', 60, 'online') as one_off \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select (first_date = last_date and needs_family_ok and tutor_ok_at is not null)::int from public.bookings where id = :'one_off'), 1, 'one-off booking, tutor already agreed'); -- Checks: one-off booking, tutor already agreed.
select tests.eq((select count(*) from public.session_requests where id = :'req' and status = 'offered'), 1, 'request marked offered'); -- Checks: request marked offered.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.approve_booking(:'one_off', true); -- The family approves it.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.sessions where booking_id = :'one_off'), 1, 'one session made'); -- Checks: one session made.
select tests.eq((select count(*) from public.session_requests where id = :'req' and status = 'done'), 1, 'request done once approved'); -- Checks: request done once approved.
delete from public.sessions where booking_id = :'one_off'; -- Removes its sessions.
delete from public.bookings where id = :'one_off'; -- Removes the one-off booking.

-- Withdrawn and declined.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- The family asks for cover while the tutor is away, and keeps its id as cover.
select public.make_session_request(:'sam', 'away_cover', 'General Maths', current_date + 3, null, 'tutor') as cover \gset
select tests.fails(format($$select public.close_session_request(%L, 'declined')$$, :'cover'), 'family declines its own request'); -- Checks this is refused: family declines its own request.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.close_session_request(:'cover', 'declined', 'No other tutor free that week.'); -- An admin declines it, with the reason.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003' -- Checks the family is told why:
  and kind = 'request_update' and body like '%No other tutor free%'), 1, 'family told why'); -- (one notice with the reason).
delete from public.session_requests where student_id = :'sam'; -- Clears Sam's requests.

-- ---------------------------------------------------------------------------
-- Public holidays
-- ---------------------------------------------------------------------------
select tests.eq((select count(*) from public.public_holidays where state = 'SA' and extract(year from holiday_on) = 2027), 14, 'SA 2027 public holidays loaded'); -- Checks: SA 2027 public holidays loaded.
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery, -- Adds a confirmed booking for Sam:
                             first_date, last_date, status, confirmed_at) -- (with its dates and status)
select :'sam', :'sam_tutor', :'sam_family', 'General Maths', extract(isodow from current_date + 9)::smallint, '05:30', 60, 'online', -- on the weekday 9 days from now, 5:30am, online,
       current_date + 2, current_date + 16, 'confirmed', now() -- for two weeks, confirmed now,
-- and keeps its id as ph_booking.
returning id as ph_booking \gset
insert into public.public_holidays (state, holiday_on, name) values (:'sam_state', current_date + 9, 'Test Day') -- Makes that day a public holiday in Sam's state:
  on conflict (state, holiday_on) do update set name = 'Test Day'; -- (or renames it if one is there).
select private.make_sessions(:'ph_booking'); -- Makes the booking's sessions.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_public_holiday_weeks() where booking_id = :'ph_booking' and holiday_name = 'Test Day' and not skipping), 1, 'family sees the public holiday week'); -- Checks: family sees the public holiday week.
select tests.eq(public.set_skip_public_holidays(:'ph_booking', true), 1, 'skipping cancels the public holiday session'); -- Checks: skipping cancels the public holiday session.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.sessions where booking_id = :'ph_booking' and status = 'cancelled' and cancel_reason = 'Public holiday' -- Checks it's recorded as a family cancellation:
  and cancelled_by_role = 'family'), 1, 'recorded as a family cancellation'); -- (the label).
select tests.eq((select count(*) from public.sessions where booking_id = :'ph_booking' and status = 'scheduled'), 2, 'other weeks unchanged'); -- Checks: other weeks unchanged.
delete from public.sessions where booking_id = :'ph_booking'; -- Removes the sessions.
select private.make_sessions(:'ph_booking'); -- Makes them again.
select tests.eq((select count(*) from public.sessions where booking_id = :'ph_booking'), 2, 'no session made on a public holiday when skipping'); -- Checks: no session made on a public holiday when skipping.
delete from public.sessions where booking_id = :'ph_booking'; -- Removes the sessions.
delete from public.bookings where id = :'ph_booking'; -- Removes the booking.
delete from public.public_holidays where name = 'Test Day'; -- Removes the test holiday.

-- ---------------------------------------------------------------------------
-- Home or school sessions: CLG only
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.request_booking(%L, 'General Maths', %L, 1::smallint, '10:00', 60, 'school', null, %L::date, %L::date)$$, -- Checks a family can't book a session at school:
  :'sam', :'sam_tutor', :'first_day', :'first_day'), 'family books a session at school'); -- (the label).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Blocking
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select (count(*) > 0)::int from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) where tutor_id = :'sam_tutor'), 1, 'tutor offered before the block'); -- Checks: tutor offered before the block.
select tests.fails(format($$select public.block_match(%L, %L, 'short')$$, :'sam_tutor', :'sam'), 'reason too short'); -- Checks this is refused: reason too short.
-- An admin blocks Sam's tutor from Sam, with the reason, and keeps its id as blk.
select public.block_match(:'sam_tutor', :'sam', 'Sessions keep starting late and Sam is unsettled.') as blk \gset
select tests.fails(format($$select public.block_match(%L, %L, 'Sessions keep starting late and Sam is unsettled.')$$, :'sam_tutor', :'sam'), 'blocked twice'); -- Checks this is refused: blocked twice.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) where tutor_id = :'sam_tutor'), 0, 'blocked tutor no longer suggested'); -- Checks: blocked tutor no longer suggested.
select tests.eq((select count(*) from public.list_blocks()), 1, 'family sees their own block'); -- Checks: family sees their own block.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(:'sam_tutor', 'aal2'); -- Signs in as the account named here with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.match_blocks), 0, 'the tutor is not told'); -- Checks: the tutor is not told.
select tests.eq((select count(*) from public.list_blocks()), 0, 'the tutor sees no block'); -- Checks: the tutor sees no block.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' -- Checks admins are told, with the reason:
  and kind = 'staff_alert' and title = 'Block to follow up' and body like '%starting late%'), 1, 'admins told, with the reason'); -- (one "block to follow up" alert).
select tests.eq((select count(*) from public.session_notices where account_id = :'sam_tutor' and kind = 'staff_alert'), 0, 'no notice to the tutor'); -- Checks: no notice to the tutor.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.lift_block(%L)$$, :'blk'), 'family lifts a block'); -- Checks this is refused: family lifts a block.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.record_block_follow_up(%L, '')$$, :'blk'), 'follow-up needs a note'); -- Checks this is refused: follow-up needs a note.
select public.record_block_follow_up(:'blk', 'Called the family; agreed to try another tutor and spoke with the tutor about punctuality.'); -- Records the follow-up.
select tests.eq((select count(*) from public.list_blocks() where followed_up_at is not null), 1, 'follow-up recorded'); -- Checks: follow-up recorded.
select public.lift_block(:'blk'); -- Lifts the block.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select (count(*) > 0)::int from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) where tutor_id = :'sam_tutor'), 1, 'suggested again once lifted'); -- Checks: suggested again once lifted.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- A tutor blocks a student they teach.
select tests.claims(:'sam_tutor', 'aal2'); -- Signs in as the account named here with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Blocks the match again, with a new reason, and keeps its id as blk2.
select public.block_match(:'sam_tutor', :'sam', 'Repeated rude messages in sessions despite reminders.') as blk2 \gset
select tests.eq((select count(*) from public.list_blocks() where blocked_by_role = 'tutor'), 1, 'tutor sees their own block'); -- Checks: tutor sees their own block.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_blocks() where blocked_by_role = 'tutor'), 0, 'the family is not told'); -- Checks: the family is not told.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.match_blocks; -- Clears the blocks.

-- ---------------------------------------------------------------------------
-- Libraries: confirmed, with opening hours
-- ---------------------------------------------------------------------------
select tests.claims(:'sam_tutor', 'aal2'); -- Signs in as the account named here with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.suggest_library('Stirling Library', 'Stirling', '')$$, 'a suggestion needs the address'); -- Checks this is refused: a suggestion needs the address.
-- The tutor suggests a new library, and keeps its id as lib.
select public.suggest_library('Stirling Library', 'Stirling', '5 Mount Barker Road') as lib \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.libraries where id = :'lib' and confirmed_at is null), 1, 'suggested library waits for CLG'); -- Checks: suggested library waits for CLG.
select tests.eq((select count(*) from public.tutor_places where library_id = :'lib' and tutor_id = :'sam_tutor'), 1, 'added to the tutor''s places'); -- Checks: added to the tutor's places.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Library to confirm'), 1, 'admins asked to confirm it'); -- Checks: admins asked to confirm it.
update public.tutor_session_settings set in_person = true where tutor_id = :'sam_tutor'; -- Sam's tutor teaches in person.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib']::uuid[], :'first_day'::date)), 0, 'no sessions at an unconfirmed library'); -- Checks: no sessions at an unconfirmed library.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.confirm_library(%L)$$, :'lib'), 'confirming needs opening hours'); -- Checks this is refused: confirming needs opening hours.
-- Open 10am to 4pm every day.
insert into public.library_hours (library_id, weekday, opens, closes) select :'lib', d, '10:00', '16:00' from generate_series(1, 7) d; -- Adds opening hours: 10am to 4pm every day.
select public.confirm_library(:'lib'); -- An admin confirms the library.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib']::uuid[], :'first_day'::date) -- Checks only times inside the opening hours are offered:
  where start_time < '10:00' or end_time > '16:00'), 0, 'only times inside opening hours'); -- (none before 10am or after 4pm).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.tutor_places where library_id = :'lib'; -- Removes the library from tutors' libraries.
delete from public.libraries where id = :'lib'; -- Removes the library.

-- Prints that every check in this file passed.
\echo '  scheduling requests, holidays, blocks and libraries: all checks passed'
