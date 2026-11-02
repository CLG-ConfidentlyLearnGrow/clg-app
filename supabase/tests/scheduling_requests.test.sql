-- Carla's 2 Nov 2026 scheduling changes: offer follow-ups at 48 hours,
-- preferred parts of the day, requests (extra sessions, public holiday
-- one-offs, cover), public holidays, blocking, libraries with opening hours
-- and home or school sessions. Runs after scheduling_offer.test.sql and
-- reuses its people: owner admin (...a0), tutors T3 (...13) and T4
-- (...14), parents P3 (...03, Sam Three's parent) and P4 (...04).

select tests.claims(null);
select id as sam, family_id as sam_family, state as sam_state from public.students where full_name = 'Sam Three' \gset
select (current_date + 7 + ((8 - extract(isodow from current_date)::int) % 7)) as first_day \gset

-- ---------------------------------------------------------------------------
-- Offers: open 72 hours, follow-up at 48
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select f.tutor_id as offer_tutor, f.weekday as offer_day, f.start_time as offer_start
from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) f
where f.delivery = 'online' order by f.weekday, f.start_time limit 1 \gset
select public.request_booking(:'sam', 'General Maths', :'offer_tutor', :'offer_day'::smallint, :'offer_start'::time, 60,
  'online', null, :'first_day'::date, :'first_day'::date + 21) as offer \gset
reset role;
select tests.claims(null);
select tests.eq((select (tutor_reply_by = requested_at + interval '72 hours')::int from public.bookings where id = :'offer'), 1, 'CLG offers stay open 72 hours');
select private.queue_offer_follow_ups();
select tests.eq((select count(*) from public.session_notices where booking_id = :'offer' and kind = 'offer_follow_up'), 0, 'no follow-up before 48 hours');

-- The family approves; 48 hours pass with the tutor still to answer.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.approve_booking(:'offer', true);
reset role;
select tests.claims(null);
update public.bookings set requested_at = now() - interval '49 hours', tutor_reply_by = now() + interval '23 hours' where id = :'offer';
select tests.eq(private.queue_offer_follow_ups(), 1, 'one offer followed up');
select tests.eq((select count(*) from public.session_notices where booking_id = :'offer' and kind = 'offer_follow_up'
  and account_id = :'offer_tutor' and title like 'Reminder%'), 1, 'tutor reminded');
select tests.eq((select count(*) from public.session_notices where booking_id = :'offer' and kind = 'offer_follow_up'
  and account_id = '00000000-0000-0000-0000-000000000003' and title = 'Waiting for the tutor'), 1, 'family told it is waiting on the tutor');
select tests.eq(private.queue_offer_follow_ups(), 0, 'followed up once');
-- Still open after 48 hours: the tutor can answer.
select tests.claims(:'offer_tutor', 'aal2');
set role authenticated;
select public.respond_to_booking(:'offer', false, 'Not that day after all');
reset role;
select tests.claims(null);
delete from public.bookings where id = :'offer';

-- ---------------------------------------------------------------------------
-- Preferred parts of the day
-- ---------------------------------------------------------------------------
select tests.eq((private.part_of_day('09:30') = 'morning' and private.part_of_day('12:00') = 'midday'
  and private.part_of_day('15:30') = 'afternoon' and private.part_of_day('17:00') = 'evening')::int, 1, 'parts of the day');
insert into public.student_places (student_id, online, preferred_parts) values (:'sam', true, array['evening']);
select tests.fails(format($$update public.student_places set preferred_parts = array['night'] where student_id = %L$$, :'sam'), 'not a part of the day');
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.offer_options(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date)
  where preferred and start_time < '17:00'), 0, 'only evening times marked preferred');
reset role;
select tests.claims(null);
delete from public.student_places where student_id = :'sam';

-- ---------------------------------------------------------------------------
-- Requests: an extra session before a test
-- ---------------------------------------------------------------------------
select a.tutor_id as sam_tutor from public.tutor_assignments a
where a.student_id = :'sam' and lower(a.subject) = 'general maths' and private.assignment_is_current(a.starts_on, a.ends_on)
order by a.starts_on desc limit 1 \gset

select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.make_session_request(%L, 'extra', 'General Maths')$$, :'sam'), 'extra needs the event date');
select tests.fails(format($$select public.make_session_request(%L, 'extra', 'General Maths', current_date - 1)$$, :'sam'), 'event in the past');
select public.make_session_request(:'sam', 'extra', 'General Maths', current_date + 20, 'Algebra test', null, 'Any afternoon') as req \gset
reset role;
select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.fails(format($$select public.make_session_request(%L, 'extra', 'General Maths', current_date + 20)$$, :'sam'), 'another parent asks');
select tests.eq((select count(*) from public.list_session_requests()), 0, 'another parent sees none');
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.session_requests where id = :'req' and tutor_id = :'sam_tutor'), 1, 'request goes to the student''s tutor');
select tests.eq((select count(*) from public.session_notices where account_id = :'sam_tutor' and kind = 'request_update' and body like '%Algebra test%'), 1, 'tutor told');
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and kind = 'staff_alert' and title = 'Extra session asked for'), 1, 'admins told');

-- The tutor offers a time before the test; after the test is refused.
select tests.claims(:'sam_tutor', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.list_session_requests() where id = :'req'), 1, 'tutor sees the request');
select tests.fails(format($$select public.offer_one_off(%L, null, current_date + 21, '16:00', 60, 'online')$$, :'req'), 'offer after the test');
select tests.fails(format($$select public.offer_one_off(%L, null, current_date + 5, '16:00', 60, 'home')$$, :'req'), 'tutor offers a home session');
select public.offer_one_off(:'req', null, current_date + 5, '06:00', 60, 'online') as one_off \gset
reset role;
select tests.claims(null);
select tests.eq((select (first_date = last_date and needs_family_ok and tutor_ok_at is not null)::int from public.bookings where id = :'one_off'), 1, 'one-off booking, tutor already agreed');
select tests.eq((select count(*) from public.session_requests where id = :'req' and status = 'offered'), 1, 'request marked offered');
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.approve_booking(:'one_off', true);
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.sessions where booking_id = :'one_off'), 1, 'one session made');
select tests.eq((select count(*) from public.session_requests where id = :'req' and status = 'done'), 1, 'request done once approved');
delete from public.sessions where booking_id = :'one_off';
delete from public.bookings where id = :'one_off';

-- Withdrawn and declined.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.make_session_request(:'sam', 'away_cover', 'General Maths', current_date + 3, null, 'tutor') as cover \gset
select tests.fails(format($$select public.close_session_request(%L, 'declined')$$, :'cover'), 'family declines its own request');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.close_session_request(:'cover', 'declined', 'No other tutor free that week.');
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003'
  and kind = 'request_update' and body like '%No other tutor free%'), 1, 'family told why');
delete from public.session_requests where student_id = :'sam';

-- ---------------------------------------------------------------------------
-- Public holidays
-- ---------------------------------------------------------------------------
select tests.eq((select count(*) from public.public_holidays where state = 'SA' and extract(year from holiday_on) = 2027), 14, 'SA 2027 public holidays loaded');
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery,
                             first_date, last_date, status, confirmed_at)
select :'sam', :'sam_tutor', :'sam_family', 'General Maths', extract(isodow from current_date + 9)::smallint, '05:30', 60, 'online',
       current_date + 2, current_date + 16, 'confirmed', now()
returning id as ph_booking \gset
insert into public.public_holidays (state, holiday_on, name) values (:'sam_state', current_date + 9, 'Test Day')
  on conflict (state, holiday_on) do update set name = 'Test Day';
select private.make_sessions(:'ph_booking');
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.list_public_holiday_weeks() where booking_id = :'ph_booking' and holiday_name = 'Test Day' and not skipping), 1, 'family sees the public holiday week');
select tests.eq(public.set_skip_public_holidays(:'ph_booking', true), 1, 'skipping cancels the public holiday session');
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.sessions where booking_id = :'ph_booking' and status = 'cancelled' and cancel_reason = 'Public holiday'
  and cancelled_by_role = 'family'), 1, 'recorded as a family cancellation');
select tests.eq((select count(*) from public.sessions where booking_id = :'ph_booking' and status = 'scheduled'), 2, 'other weeks unchanged');
delete from public.sessions where booking_id = :'ph_booking';
select private.make_sessions(:'ph_booking');
select tests.eq((select count(*) from public.sessions where booking_id = :'ph_booking'), 2, 'no session made on a public holiday when skipping');
delete from public.sessions where booking_id = :'ph_booking';
delete from public.bookings where id = :'ph_booking';
delete from public.public_holidays where name = 'Test Day';

-- ---------------------------------------------------------------------------
-- Home or school sessions: CLG only
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.request_booking(%L, 'General Maths', %L, 1::smallint, '10:00', 60, 'school', null, %L::date, %L::date)$$,
  :'sam', :'sam_tutor', :'first_day', :'first_day'), 'family books a session at school');
reset role;

-- ---------------------------------------------------------------------------
-- Blocking
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select (count(*) > 0)::int from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) where tutor_id = :'sam_tutor'), 1, 'tutor offered before the block');
select tests.fails(format($$select public.block_match(%L, %L, 'short')$$, :'sam_tutor', :'sam'), 'reason too short');
select public.block_match(:'sam_tutor', :'sam', 'Sessions keep starting late and Sam is unsettled.') as blk \gset
select tests.fails(format($$select public.block_match(%L, %L, 'Sessions keep starting late and Sam is unsettled.')$$, :'sam_tutor', :'sam'), 'blocked twice');
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) where tutor_id = :'sam_tutor'), 0, 'blocked tutor no longer suggested');
select tests.eq((select count(*) from public.list_blocks()), 1, 'family sees their own block');
reset role;
select tests.claims(:'sam_tutor', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.match_blocks), 0, 'the tutor is not told');
select tests.eq((select count(*) from public.list_blocks()), 0, 'the tutor sees no block');
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0'
  and kind = 'staff_alert' and title = 'Block to follow up' and body like '%starting late%'), 1, 'admins told, with the reason');
select tests.eq((select count(*) from public.session_notices where account_id = :'sam_tutor' and kind = 'staff_alert'), 0, 'no notice to the tutor');
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.lift_block(%L)$$, :'blk'), 'family lifts a block');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails(format($$select public.record_block_follow_up(%L, '')$$, :'blk'), 'follow-up needs a note');
select public.record_block_follow_up(:'blk', 'Called the family; agreed to try another tutor and spoke with the tutor about punctuality.');
select tests.eq((select count(*) from public.list_blocks() where followed_up_at is not null), 1, 'follow-up recorded');
select public.lift_block(:'blk');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select (count(*) > 0)::int from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) where tutor_id = :'sam_tutor'), 1, 'suggested again once lifted');
reset role;

-- A tutor blocks a student they teach.
select tests.claims(:'sam_tutor', 'aal2');
set role authenticated;
select public.block_match(:'sam_tutor', :'sam', 'Repeated rude messages in sessions despite reminders.') as blk2 \gset
select tests.eq((select count(*) from public.list_blocks() where blocked_by_role = 'tutor'), 1, 'tutor sees their own block');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.list_blocks() where blocked_by_role = 'tutor'), 0, 'the family is not told');
reset role;
select tests.claims(null);
delete from public.match_blocks;

-- ---------------------------------------------------------------------------
-- Libraries: confirmed, with opening hours
-- ---------------------------------------------------------------------------
select tests.claims(:'sam_tutor', 'aal2');
set role authenticated;
select public.suggest_library('Stirling Library', 'Stirling') as lib \gset
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.libraries where id = :'lib' and confirmed_at is null), 1, 'suggested library waits for CLG');
select tests.eq((select count(*) from public.tutor_places where library_id = :'lib' and tutor_id = :'sam_tutor'), 1, 'added to the tutor''s places');
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Library to confirm'), 1, 'admins asked to confirm it');
update public.tutor_session_settings set in_person = true where tutor_id = :'sam_tutor';
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib']::uuid[], :'first_day'::date)), 0, 'no sessions at an unconfirmed library');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails(format($$select public.confirm_library(%L)$$, :'lib'), 'confirming needs opening hours');
-- Open 10am to 4pm every day.
insert into public.library_hours (library_id, weekday, opens, closes) select :'lib', d, '10:00', '16:00' from generate_series(1, 7) d;
select public.confirm_library(:'lib');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib']::uuid[], :'first_day'::date)
  where start_time < '10:00' or end_time > '16:00'), 0, 'only times inside opening hours');
reset role;
select tests.claims(null);
delete from public.tutor_places where library_id = :'lib';
delete from public.libraries where id = :'lib';

\echo '  scheduling requests, holidays, blocks and libraries: all checks passed'
