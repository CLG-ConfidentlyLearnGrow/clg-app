-- CLG offers a time: the admin picks the tutor and time, then the tutor and
-- the family both approve, in either order. Runs after the earlier
-- scheduling tests and reuses their people: owner admin (...a0), tutors T3
-- (...13) and T4 (...14), parents P3 (...03, Sam Three's parent) and P4.

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Keeps the Monday after next as first_day.
select (current_date + 7 + ((8 - extract(isodow from current_date)::int) % 7)) as first_day \gset

-- The admin finds a free time and offers it.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select f.tutor_id as offer_tutor, f.weekday as offer_day, f.start_time as offer_start -- Keeps the first online time the app finds:
from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) f -- (searching General Maths, an hour, online, from first_day),
where f.delivery = 'online' -- (online only),
-- (the earliest one).
order by f.weekday, f.start_time limit 1 \gset
select public.request_booking(:'sam', 'General Maths', :'offer_tutor', :'offer_day'::smallint, :'offer_start'::time, 60, -- An admin offers that time for three weeks:
  -- and keeps its id as offer.
  'online', null, :'first_day'::date, :'first_day'::date + 21) as offer \gset
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select needs_family_ok::int from public.bookings where id = :'offer'), 1, 'admin booking needs the family''s approval'); -- Checks: admin booking needs the family's approval.
select tests.eq((select count(*) from public.session_notices where booking_id = :'offer' and kind = 'booking_requested' -- Checks the family is asked to approve:
  and account_id = '00000000-0000-0000-0000-000000000003'), 1, 'family asked to approve'); -- (one notice for the parent).
select tests.eq((select count(*) from public.session_notices where booking_id = :'offer' and kind = 'booking_requested' -- Checks the tutor is asked to approve:
  and account_id = :'offer_tutor'), 1, 'tutor asked to approve'); -- (one notice for the tutor).

-- The tutor says yes first: still waiting for the family.
select tests.claims(:'offer_tutor', 'aal2'); -- Signs in as the offered tutor with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.respond_to_booking(:'offer', true, 'Happy to'); -- The tutor accepts.
select tests.fails(format($$select public.respond_to_booking(%L, true)$$, :'offer'), 'tutor answers twice'); -- Checks this is refused: tutor answers twice.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select (status = 'requested' and tutor_ok_at is not null)::int from public.bookings where id = :'offer'), 1, 'waiting for the family'); -- Checks: waiting for the family.
select tests.eq((select count(*) from public.sessions where booking_id = :'offer'), 0, 'no sessions yet'); -- Checks: no sessions yet.

-- Other people can't approve.
select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as test account ...04.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.approve_booking(%L, true)$$, :'offer'), 'other parent approves'); -- Checks this is refused: other parent approves.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as test account ...14 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.approve_booking(%L, true)$$, :'offer'), 'a tutor approves for the family'); -- Checks this is refused: a tutor approves for the family.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The family approves: confirmed, sessions made, everyone told.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.approve_booking(:'offer', true); -- The family approves.
select tests.fails(format($$select public.approve_booking(%L, true)$$, :'offer'), 'family approves twice'); -- Checks this is refused: family approves twice.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select (status = 'confirmed')::int from public.bookings where id = :'offer'), 1, 'confirmed once both said yes'); -- Checks: confirmed once both said yes.
select tests.eq((select (count(*) > 0)::int from public.sessions where booking_id = :'offer'), 1, 'sessions made'); -- Checks: sessions made.
select tests.eq((select count(distinct account_id) from public.session_notices where booking_id = :'offer' and kind = 'booking_confirmed' -- Checks the tutor and family both get the details:
  and account_id in ('00000000-0000-0000-0000-000000000003', :'offer_tutor')), 2, 'tutor and family both get the details'); -- (one confirmed notice each).

-- A second offer at the same time (after the first is stopped): the
-- family declines first, and the tutor is told.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.cancel_booking(:'offer', 'Testing', 'admin'); -- An admin cancels the booking.
-- Keeps the same tutor as offer2_tutor.
select :'offer_tutor' as offer2_tutor \gset
select public.request_booking(:'sam', 'General Maths', :'offer_tutor', :'offer_day'::smallint, :'offer_start'::time, 60, -- Offers the same time again:
  -- and keeps its id as offer2.
  'online', null, :'first_day'::date, :'first_day'::date + 21) as offer2 \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.approve_booking(:'offer2', false, 'Sport on that day'); -- The family declines (sport on that day).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select (status = 'declined' and declined_by_role = 'family')::int from public.bookings where id = :'offer2'), 1, 'family declined'); -- Checks: family declined.
select tests.eq((select count(*) from public.session_notices where booking_id = :'offer2' and kind = 'booking_declined' -- Checks the tutor is told:
  and account_id = :'offer2_tutor'), 1, 'tutor told'); -- (one declined notice).
select tests.claims(:'offer2_tutor', 'aal2'); -- Signs in as the offered tutor with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.respond_to_booking(%L, true)$$, :'offer2'), 'tutor can''t accept a declined offer'); -- Checks this is refused: tutor can't accept a declined offer.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The admin picked something other than the suggestion: the reason is kept.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.record_offer_change(:'offer2', '00000000-0000-0000-0000-000000000014', 1::smallint, '15:00', 'online', null, 'family_request', 'Prefers a later time'); -- Records why the admin chose a different tutor and time.
select tests.fails(format($$select public.record_offer_change(%L, null, null, null, null, null, 'because')$$, :'offer2'), 'a reason from the list is needed'); -- Checks this is refused: a reason from the list is needed.
select tests.eq((select changes from public.offer_change_reasons() where reason = 'family_request'), 1::bigint, 'reasons counted'); -- Checks: reasons counted.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.record_offer_change(%L, null, null, null, null, null, 'other')$$, :'offer2'), 'families can''t record changes'); -- Checks this is refused: families can't record changes.
select tests.eq((select count(*) from public.offer_changes), 0, 'families can''t see changes'); -- Checks: families can't see changes.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select * from public.offer_change_reasons()$$, 'tutors can''t see change reasons'); -- Checks this is refused: tutors can't see change reasons.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- A family's own booking needs only the tutor.
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.bookings where needs_family_ok and requested_by = '00000000-0000-0000-0000-000000000003'), 0, -- Checks bookings families make themselves don't ask them again:
  'family bookings don''t ask the family again'); -- (the label).

-- Preferred days come first in the options.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select weekday as pref_day from public.offer_options(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) -- Keeps the latest weekday on offer as pref_day:
-- (the last one).
order by weekday desc limit 1 \gset
insert into public.student_places (student_id, online, preferred_days) values (:'sam', true, array[:'pref_day']::smallint[]) -- Saves that day as Sam's preferred day:
on conflict (student_id) do update set preferred_days = excluded.preferred_days; -- (or updates it if already saved).
select tests.eq((select (weekday = :'pref_day'::smallint and preferred)::int -- Checks the preferred day is suggested first:
  from public.offer_options(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) limit 1), 1, 'preferred day suggested first'); -- (the first option is that day, marked preferred).
select tests.fails(format($$update public.student_places set preferred_days = array[9]::smallint[] where student_id = %L$$, :'sam'), 'not a day of the week'); -- Checks this is refused: not a day of the week.
update public.student_places set preferred_days = null, preferred_school_hours = true where student_id = :'sam'; -- Swaps to preferring school hours.
select tests.eq((select count(*) from public.offer_options(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) -- Checks only school-hours times are marked preferred:
  where preferred and not (weekday between 1 and 5 and start_time >= '09:00' and end_time <= '15:00')), 0, 'school hours preference'); -- (none outside 9am to 3pm weekdays).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.student_places where student_id = :'sam'; -- Removes Sam's places.

-- Leave the extra bookings out of the later tests.
delete from public.sessions where booking_id in (:'offer', :'offer2'); -- Removes the sessions from both offers.
delete from public.tutor_assignments where student_id = :'sam' and created_by = '00000000-0000-0000-0000-000000000003'; -- Removes assignments the parent made.
delete from public.bookings where id in (:'offer', :'offer2'); -- Removes both offers.

-- Each available time says how the tutor can teach: in person, online or both.
select tests.claims(:'offer_tutor', 'aal2'); -- Signs in as the offered tutor with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at, in_person, online) -- Checks a time with no way of teaching is refused:
  values (%L, 1, '09:00', '10:00', false, false)$$, :'offer_tutor'), 'a time with no way of teaching'); -- (neither in person nor online).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
create temp table saved_slots as -- Keeps the tutor's teaching options in a short-lived table:
  select id, in_person, online from public.tutor_availability where tutor_id = :'offer_tutor'; -- (in person or online, for each time).
select tests.eq((select (count(*) > 0)::int from saved_slots), 1, 'the tutor has available times to test with'); -- Checks: the tutor has available times to test with.
update public.tutor_availability set online = false where tutor_id = :'offer_tutor'; -- Turns online off for all the tutor's times.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) -- Checks in-person-only times aren't offered online:
  where tutor_id = :'offer_tutor'), 0, 'in-person-only times not offered online'); -- (none for this tutor).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
update public.tutor_availability t set online = s.online, in_person = s.in_person from saved_slots s where s.id = t.id; -- Puts the options back.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select (count(*) > 0)::int from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) -- Checks online times are offered again:
  where tutor_id = :'offer_tutor'), 1, 'online times offered again'); -- (at least one).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- Prints that every check in this file passed.
\echo '  scheduling offers approved by tutor and family: all checks passed'
