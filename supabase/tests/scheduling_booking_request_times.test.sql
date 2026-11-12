-- Summary: checks the booking request times used to put the most recent
-- bookings at the top of the Bookings list (Carla, 12 Nov 2026): each person
-- gets times only for bookings they can already see. Reuses the earlier
-- scheduling tests' people: owner admin (...a0), Paula (...03, Sam's
-- parent) and another parent (...04).

select tests.claims(null); -- acts as the database itself while setting up
select count(*) as all_bookings from public.bookings \gset

-- The owner admin sees a time for every booking.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq((select count(*) from public.booking_request_times()), :'all_bookings'::bigint, 'admins get a time for every booking');
reset role; -- back to the database itself

-- A parent gets exactly the bookings list_bookings shows them.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- signs in as Paula
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.booking_request_times()), (select count(*) from public.list_bookings()), 'a parent gets times only for bookings they can see');
reset role; -- back to the database itself

-- Another parent gets none of Sam's.
select tests.claims('00000000-0000-0000-0000-000000000004'); -- signs in as another parent
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.booking_request_times() t join public.bookings b on b.id = t.id
  join public.students s on s.id = b.student_id where s.full_name = 'Sam Three'), 0::bigint, 'another family gets no times for Sam''s bookings');
reset role; -- back to the database itself

-- Signed-out visitors can't call it.
select tests.claims(null); -- no one signed in
set role anon; -- acts as a signed-out visitor
select tests.fails($q$select * from public.booking_request_times()$q$, 'signed-out visitors can''t see booking times');
reset role; -- back to the database itself

\echo '  scheduling booking request times: all checks passed'
