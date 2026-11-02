-- CLG offers a time: the admin picks the tutor and time, then the tutor and
-- the family both approve, in either order. Runs after the earlier
-- scheduling tests and reuses their people: owner admin (...a0), tutors T3
-- (...13) and T4 (...14), parents P3 (...03, Sam Three's parent) and P4.

select tests.claims(null);
select id as sam from public.students where full_name = 'Sam Three' \gset
select (current_date + 7 + ((8 - extract(isodow from current_date)::int) % 7)) as first_day \gset

-- The admin finds a free time and offers it.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select f.tutor_id as offer_tutor, f.weekday as offer_day, f.start_time as offer_start
from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) f
where f.delivery = 'online'
order by f.weekday, f.start_time limit 1 \gset
select public.request_booking(:'sam', 'General Maths', :'offer_tutor', :'offer_day'::smallint, :'offer_start'::time, 60,
  'online', null, :'first_day'::date, :'first_day'::date + 21) as offer \gset
reset role;

select tests.claims(null);
select tests.eq((select needs_family_ok::int from public.bookings where id = :'offer'), 1, 'admin booking needs the family''s approval');
select tests.eq((select count(*) from public.session_notices where booking_id = :'offer' and kind = 'booking_requested'
  and account_id = '00000000-0000-0000-0000-000000000003'), 1, 'family asked to approve');
select tests.eq((select count(*) from public.session_notices where booking_id = :'offer' and kind = 'booking_requested'
  and account_id = :'offer_tutor'), 1, 'tutor asked to approve');

-- The tutor says yes first: still waiting for the family.
select tests.claims(:'offer_tutor', 'aal2');
set role authenticated;
select public.respond_to_booking(:'offer', true, 'Happy to');
select tests.fails(format($$select public.respond_to_booking(%L, true)$$, :'offer'), 'tutor answers twice');
reset role;
select tests.claims(null);
select tests.eq((select (status = 'requested' and tutor_ok_at is not null)::int from public.bookings where id = :'offer'), 1, 'waiting for the family');
select tests.eq((select count(*) from public.sessions where booking_id = :'offer'), 0, 'no sessions yet');

-- Other people can't approve.
select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.fails(format($$select public.approve_booking(%L, true)$$, :'offer'), 'other parent approves');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2');
set role authenticated;
select tests.fails(format($$select public.approve_booking(%L, true)$$, :'offer'), 'a tutor approves for the family');
reset role;

-- The family approves: confirmed, sessions made, everyone told.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.approve_booking(:'offer', true);
select tests.fails(format($$select public.approve_booking(%L, true)$$, :'offer'), 'family approves twice');
reset role;
select tests.claims(null);
select tests.eq((select (status = 'confirmed')::int from public.bookings where id = :'offer'), 1, 'confirmed once both said yes');
select tests.eq((select (count(*) > 0)::int from public.sessions where booking_id = :'offer'), 1, 'sessions made');
select tests.eq((select count(distinct account_id) from public.session_notices where booking_id = :'offer' and kind = 'booking_confirmed'
  and account_id in ('00000000-0000-0000-0000-000000000003', :'offer_tutor')), 2, 'tutor and family both get the details');

-- A second offer at the same time (after the first is stopped): the
-- family declines first, and the tutor is told.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.cancel_booking(:'offer', 'Testing', 'admin');
select :'offer_tutor' as offer2_tutor \gset
select public.request_booking(:'sam', 'General Maths', :'offer_tutor', :'offer_day'::smallint, :'offer_start'::time, 60,
  'online', null, :'first_day'::date, :'first_day'::date + 21) as offer2 \gset
reset role;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.approve_booking(:'offer2', false, 'Sport on that day');
reset role;
select tests.claims(null);
select tests.eq((select (status = 'declined' and declined_by_role = 'family')::int from public.bookings where id = :'offer2'), 1, 'family declined');
select tests.eq((select count(*) from public.session_notices where booking_id = :'offer2' and kind = 'booking_declined'
  and account_id = :'offer2_tutor'), 1, 'tutor told');
select tests.claims(:'offer2_tutor', 'aal2');
set role authenticated;
select tests.fails(format($$select public.respond_to_booking(%L, true)$$, :'offer2'), 'tutor can''t accept a declined offer');
reset role;

-- The admin picked something other than the suggestion: the reason is kept.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.record_offer_change(:'offer2', '00000000-0000-0000-0000-000000000014', 1::smallint, '15:00', 'online', null, 'family_request', 'Prefers a later time');
select tests.fails(format($$select public.record_offer_change(%L, null, null, null, null, null, 'because')$$, :'offer2'), 'a reason from the list is needed');
select tests.eq((select changes from public.offer_change_reasons() where reason = 'family_request'), 1::bigint, 'reasons counted');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.record_offer_change(%L, null, null, null, null, null, 'other')$$, :'offer2'), 'families can''t record changes');
select tests.eq((select count(*) from public.offer_changes), 0, 'families can''t see changes');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails($$select * from public.offer_change_reasons()$$, 'tutors can''t see change reasons');
reset role;

-- A family's own booking needs only the tutor.
select tests.claims(null);
select tests.eq((select count(*) from public.bookings where needs_family_ok and requested_by = '00000000-0000-0000-0000-000000000003'), 0,
  'family bookings don''t ask the family again');

-- Preferred days come first in the options.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select weekday as pref_day from public.offer_options(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date)
order by weekday desc limit 1 \gset
insert into public.student_places (student_id, online, preferred_days) values (:'sam', true, array[:'pref_day']::smallint[])
on conflict (student_id) do update set preferred_days = excluded.preferred_days;
select tests.eq((select (weekday = :'pref_day'::smallint and preferred)::int
  from public.offer_options(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date) limit 1), 1, 'preferred day suggested first');
select tests.fails(format($$update public.student_places set preferred_days = array[9]::smallint[] where student_id = %L$$, :'sam'), 'not a day of the week');
update public.student_places set preferred_days = null, preferred_school_hours = true where student_id = :'sam';
select tests.eq((select count(*) from public.offer_options(:'sam', 'General Maths', 60, true, '{}', :'first_day'::date)
  where preferred and not (weekday between 1 and 5 and start_time >= '09:00' and end_time <= '15:00')), 0, 'school hours preference');
reset role;
select tests.claims(null);
delete from public.student_places where student_id = :'sam';

-- Leave the extra bookings out of the later tests.
delete from public.sessions where booking_id in (:'offer', :'offer2');
delete from public.tutor_assignments where student_id = :'sam' and created_by = '00000000-0000-0000-0000-000000000003';
delete from public.bookings where id in (:'offer', :'offer2');

\echo '  scheduling offers approved by tutor and family: all checks passed'
