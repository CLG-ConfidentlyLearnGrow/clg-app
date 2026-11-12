-- Summary: checks what happens when a session time runs out with no answer
-- (Carla, 12 Nov 2026): the tutor, the family and CLG are each told once,
-- and the dashboard count shows only times still waiting for the viewer.
-- Reuses the earlier scheduling tests' people: owner admin (...a0), tutor
-- T3 (...13), parent Paula (...03) and her son Sam Three.

select tests.claims(null); -- acts as the database itself while setting up
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Clears any Sunday bookings from earlier tests, so times don't clash.
delete from public.bookings where tutor_id = '00000000-0000-0000-0000-000000000013' and weekday = 7;

-- How many times were already waiting before this test (left by earlier tests).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- signs in as tutor T3
set role authenticated; -- acts as a signed-in person, so access rules apply
select as_tutor as tutor_before from public.my_offers_to_answer() \gset
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000003'); -- signs in as Paula
set role authenticated; -- acts as a signed-in person
select as_family as family_before from public.my_offers_to_answer() \gset
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself again

-- Two times CLG found for Sam. Both start open; then one is moved past its
-- answer time (inserting sets the time to 72 hr from now).
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by, needs_family_ok) -- the columns being filled
values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 7, '10:00', 60, 'online', current_date + 14, current_date + 42, -- Sunday 10am online
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0', true) -- family must approve too
returning id as open_one \gset
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by, needs_family_ok) -- the columns being filled
values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 7, '13:00', 60, 'online', current_date + 14, current_date + 42, -- Sunday 1pm online
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0', true) -- family must approve too
returning id as late \gset
update public.bookings set tutor_reply_by = now() - interval '1 hour' where id = :'late'; -- its answer time ran out an hour ago

-- The dashboard counts: only the time still open is counted.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- signs in as tutor T3
set role authenticated; -- acts as a signed-in person
select tests.eq((select as_tutor from public.my_offers_to_answer()), :tutor_before + 1, 'the tutor sees 1 more time waiting for their answer');
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000003'); -- signs in as Paula
set role authenticated; -- acts as a signed-in person
select tests.eq((select as_family from public.my_offers_to_answer()), :family_before + 1, 'the parent sees 1 more time waiting for their approval');
reset role; -- back to the database itself

-- Signed-out visitors can't call the count.
select tests.claims(null); -- no one signed in
set role anon; -- acts as a signed-out visitor
select tests.fails($q$select * from public.my_offers_to_answer()$q$, 'signed-out visitors can''t see offer counts');
reset role; -- back to the database itself

-- Run the job once.
select private.notify_offers_not_answered(); -- sends what's due

-- The tutor, the parent and CLG are told about the time that ran out.
select tests.eq((select count(*) from public.session_notices where booking_id = :'late'
  and account_id = '00000000-0000-0000-0000-000000000013' and title = 'Session time not answered in time'), 1::bigint, 'the tutor is told the time lapsed');
select tests.eq((select count(*) from public.session_notices where booking_id = :'late'
  and account_id = '00000000-0000-0000-0000-000000000003' and title = 'Session time not answered in time'), 1::bigint, 'the parent is told the time lapsed');
select tests.eq((select count(*) from public.session_notices where booking_id = :'late'
  and account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Session time not answered'), 1::bigint, 'CLG''s owner is told, to find another time');
-- Nothing is sent about the time that is still open.
select tests.eq((select count(*) from public.session_notices where booking_id = :'open_one' and title like 'Session time not answered%'), 0::bigint, 'nothing about a time still open');

-- Running again sends nothing new.
select tests.eq(private.notify_offers_not_answered(), 0, 'a second run sends nothing new');

-- Families can't run the job themselves.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- signs in as Paula
set role authenticated; -- acts as a signed-in person
select tests.fails($q$select private.notify_offers_not_answered()$q$, 'families can''t run the job');
reset role; -- back to the database itself

-- Put things back.
select tests.claims(null); -- acts as the database itself
delete from public.session_notices where booking_id in (:'open_one', :'late'); -- removes the test notices
delete from public.bookings where id in (:'open_one', :'late'); -- removes the test bookings

\echo '  scheduling offer not answered: all checks passed'
