-- Summary: checks the database parts of the cleaner Matching page (Carla,
-- 16 Nov 2026): back-dating when a student started waiting, the
-- missing-information check, "Ask the family" (app notice and email),
-- offers waiting for the tutor or the family, and response times. Only
-- front desk admins may use them. Reuses the earlier scheduling tests'
-- people: owner admin (...a0), tutor T3 (...13), Paula (...03) and her son
-- Sam Three.

select tests.claims(null); -- acts as the database itself while setting up
select id as sam from public.students where full_name = 'Sam Three' \gset
delete from public.student_places where student_id = :'sam'; -- Sam starts with no places or "How long to book"
delete from public.bookings where student_id = :'sam' and weekday = 6; -- clear Saturday bookings from earlier tests

-- ---------------------------------------------------------------------------
-- Back-dating when a student started waiting
-- ---------------------------------------------------------------------------
select stage as before_stage, since as before_since from private.matching_rows() where student_id = :'sam' and subject = 'General Maths' \gset
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- signs in as tutor T3
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.fails(format($$select public.set_waiting_since(%L, 'General Maths', date '2025-03-01')$$, :'sam'), 'tutors cannot back-date waiting');
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person
select tests.fails(format($$select public.set_waiting_since(%L, 'General Maths', current_date + 5)$$, :'sam'), 'a future date is refused');
select tests.fails(format($$select public.set_waiting_since(%L, 'Latin', date '2025-03-01')$$, :'sam'), 'a subject the student did not ask for is refused');
select public.set_waiting_since(:'sam', 'General Maths', date '2025-03-01'); -- Sam started waiting on 1 March 2025
select tests.eq((select count(*) from public.matching_waiting_since where student_id = :'sam'), 1::bigint, 'the admin can see the date they set');
reset role; -- back to the database itself
-- Waiting students now show the earlier date; others are unchanged.
select tests.eq((select count(*) from private.matching_rows() where student_id = :'sam' and subject = 'General Maths' -- Sam's General Maths row,
  and since = case when :'before_stage' in ('needs_tutor', 'waitlist') -- where the time is what is expected:
    then least(:'before_since'::timestamptz, (timestamp '2025-03-01' at time zone 'Australia/Adelaide')) else :'before_since'::timestamptz end), 1::bigint, -- the earlier date while waiting, otherwise unchanged
  'the queue uses the back-dated time while the student is waiting');
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person
select public.set_waiting_since(:'sam', 'General Maths', null); -- clears it again
select tests.eq((select count(*) from public.matching_waiting_since where student_id = :'sam'), 0::bigint, 'an empty date clears it');
reset role; -- back to the database itself

-- ---------------------------------------------------------------------------
-- Missing information and "Ask the family"
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.matching_missing(array[:'sam']::uuid[]) where item in ('session_places', 'booking_length')), 2::bigint,
  'no places and no "How long to book" are both listed as missing');
select tests.eq((select count(*) from (select public.ask_family(:'sam', 'booking_length') as n) x where x.n >= 1), 1::bigint, 'the admin can ask the family');
select tests.fails(format($$select public.ask_family(%L, 'booking_length')$$, :'sam'), 'asking again within 24 hours is refused');
select tests.fails(format($$select public.ask_family(%L, 'shoe_size')$$, :'sam'), 'an unknown item is refused');
select tests.eq((select count(*) from public.matching_missing(array[:'sam']::uuid[]) where item = 'booking_length' and last_asked is not null), 1::bigint, 'the check shows when the family was asked');
reset role; -- back to the database itself
-- Paula gets an app notice with what to do.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003'
  and title = 'Please add Sam''s how long to book' and body like '%help chat%'), 1::bigint, 'the parent gets an app notice that points to the help chat');
-- The email goes out once (asked at midday yesterday, so not in quiet hours).
update public.matching_family_asks set asked_at = ((date_trunc('day', now() at time zone 'Australia/Adelaide') - interval '12 hours') at time zone 'Australia/Adelaide')
where student_id = :'sam'; -- moves the ask to midday yesterday, Adelaide time
select tests.eq((select count(*) from public.family_ask_emails_claim(50) e where e.link = '/schedule?as=parent&section=booking-length' and e.body like '%help chat%'), 1::bigint,
  'the parent is emailed once, with a link to fill it in');
select tests.eq((select count(*) from public.family_ask_emails_claim(50)), 0::bigint, 'a second send has nothing new');

-- Tutors and families cannot use these.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- signs in as tutor T3
set role authenticated; -- acts as a signed-in person
select tests.fails(format($$select public.ask_family(%L, 'school')$$, :'sam'), 'tutors cannot ask families');
select tests.fails(format($$select * from public.matching_missing(array[%L]::uuid[])$$, :'sam'), 'tutors cannot see the missing list');
select tests.eq((select count(*) from public.matching_family_asks), 0::bigint, 'tutors cannot read the asks');
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000003'); -- signs in as Paula
set role authenticated; -- acts as a signed-in person
select tests.fails($q$select * from public.family_ask_emails_claim(50)$q$, 'families cannot take emails');
reset role; -- back to the database itself

-- ---------------------------------------------------------------------------
-- Offers waiting, and response times
-- ---------------------------------------------------------------------------
select tests.claims(null); -- acts as the database itself
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by, needs_family_ok) -- the columns being filled
values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 6, '09:00', 60, 'online', current_date + 7, current_date + 70, -- Saturday 9am online
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0', true) returning id as offer \gset
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.matching_offer_waits() where student_id = :'sam' and subject = 'General Maths' and waiting_on = 'both'), 1::bigint, 'a new offer waits for both');
reset role; -- back to the database itself
update public.bookings set tutor_ok_at = now() where id = :'offer'; -- the tutor says yes
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.matching_offer_waits() where student_id = :'sam' and subject = 'General Maths' and waiting_on = 'family'), 1::bigint, 'after the tutor says yes, it waits for the family');
select tests.eq((select count(*) from public.matching_response_times(180) where who = 'tutor' and tutor_id = '00000000-0000-0000-0000-000000000013' and answered >= 1), 1::bigint, 'the tutor''s answers are counted');
reset role; -- back to the database itself
-- Declining stamps the time, so declines count as answers.
update public.bookings set status = 'declined', declined_by_role = 'family' where id = :'offer'; -- the family said no
select tests.eq((select count(*) from public.bookings where id = :'offer' and declined_at is not null), 1::bigint, 'declining notes when');
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- signs in as tutor T3
set role authenticated; -- acts as a signed-in person
select tests.fails($q$select * from public.matching_response_times(180)$q$, 'tutors cannot see response times');
select tests.fails($q$select * from public.matching_offer_waits()$q$, 'tutors cannot see offers waiting');
reset role; -- back to the database itself

-- Put things back.
select tests.claims(null); -- acts as the database itself
delete from public.session_notices where account_id in (select account_id from public.matching_family_asks where student_id = :'sam') and title like 'Please add Sam%'; -- removes the ask notices
delete from public.matching_family_asks where student_id = :'sam'; -- removes the asks
delete from public.session_notices where booking_id = :'offer'; -- removes the offer's notices
delete from public.bookings where id = :'offer'; -- removes the test offer

\echo '  scheduling matching redesign: all checks passed'
