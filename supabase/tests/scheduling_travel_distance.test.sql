-- Summary: tests travel distances for tutors and families (Carla, 16 Nov 2026).
-- Reuses the earlier scheduling tests' people: owner admin (...a0), tutor
-- T3 Tara (...13, General Maths Years 3 to 10), tutor T4 Theo (...14),
-- parent Paula (...03) and her child Sam Three (Year 5).
-- Checks: who can see and use a tutor's starting address, who can see a
-- family's address, and that libraries and homes are offered only within
-- both people's distances.
--
-- Map points used (straight-line distances, rounded):
--   Adelaide city (tutor's start) to Unley library: about 2.4 km
--   Adelaide city to Glenelg library: about 9.6 km
--   Adelaide city to Norwood (family's address): about 2.8 km
--   Norwood to Unley library: about 3.6 km; Norwood to Glenelg: about 11.5 km

-- Keeps psql quiet so only problems are printed.
\set QUIET on
select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Adds a confirmed library in Unley (near), and keeps its id as near.
insert into public.libraries (name, suburb, latitude, longitude, confirmed_at) values ('Near Test Library', 'Unley', -34.9500, 138.6050, now()) returning id as near \gset
-- Adds a confirmed library in Glenelg (far), and keeps its id as far.
insert into public.libraries (name, suburb, latitude, longitude, confirmed_at) values ('Far Test Library', 'Glenelg', -34.9800, 138.5130, now()) returning id as far \gset
delete from public.bookings where tutor_id = '00000000-0000-0000-0000-000000000013' and weekday = 6; -- Clears tutor T3's Saturday bookings.
delete from public.tutor_availability where tutor_id = '00000000-0000-0000-0000-000000000013' and weekday = 6; -- Clears tutor T3's Saturday times.

-- ---------------------------------------------------------------------------
-- A tutor's starting address: only theirs to use, and private
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.tutor_travel_places (tutor_id, label, address, latitude, longitude) -- T3 adds a starting address:
values ('00000000-0000-0000-0000-000000000013', 'Home', '1 King William St, Adelaide SA 5000', -34.9285, 138.6007) -- in Adelaide city,
returning id as start \gset
select tests.fails($$insert into public.tutor_travel_places (tutor_id, label, address, latitude, longitude) values ('00000000-0000-0000-0000-000000000013', 'Away', '1 Queen St, London', 51.5, -0.1)$$, 'an address outside Australia is refused'); -- Checks this is refused: a map point outside Australia.
select tests.fails($$insert into public.tutor_travel_places (tutor_id, label, address, latitude, longitude) values ('00000000-0000-0000-0000-000000000014', 'Home', '2 King William St, Adelaide SA 5000', -34.9285, 138.6007)$$, 'a tutor cannot add an address for another tutor'); -- Checks this is refused: adding one for tutor T4.
-- T3 adds Saturday 9 to 11am: libraries and homes within 5 km of home, not online.
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at, online, in_person, travel_place_id, travel_km, home_visits) -- Adds the time:
values ('00000000-0000-0000-0000-000000000013', 6, '09:00', '11:00', false, true, :'start', 5, true) -- (Saturday, 5 km from home, home visits too)
returning id as sat \gset
select tests.fails($$insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at, online, in_person, home_visits) values ('00000000-0000-0000-0000-000000000013', 6, '12:00', '13:00', false, false, true)$$, 'home visits need a distance'); -- Checks this is refused: home visits with no distance.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as tutor T4 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.tutor_travel_places where id = :'start'), 0::bigint, 'another tutor cannot see the address'); -- Checks: T4 cannot see T3's address.
select tests.fails(format($$insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at, online, in_person, travel_place_id, travel_km) values ('00000000-0000-0000-0000-000000000014', 6, '09:00', '10:00', false, true, %L, 5)$$, :'start'), 'another tutor cannot start from it'); -- Checks this is refused: T4 using T3's address.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000003', 'aal2'); -- Signs in as parent Paula with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.tutor_travel_places where id = :'start'), 0::bigint, 'a parent cannot see a tutor''s address'); -- Checks: Paula cannot see T3's address.
-- Paula saves Sam's address in Norwood and a 5 km travel distance.
insert into public.student_places (student_id, online, travel_address, travel_latitude, travel_longitude, travel_km) -- Saves Sam's places:
values (:'sam', false, '10 The Parade, Norwood SA 5067', -34.9210, 138.6300, 5) -- (not online; Norwood; 5 km)
on conflict (student_id) do update set online = false, travel_address = excluded.travel_address, travel_latitude = excluded.travel_latitude, -- (or updates the row that is there)
  travel_longitude = excluded.travel_longitude, travel_km = excluded.travel_km, library_ids = '{}'; -- (with no ticked libraries)
select tests.eq((select travel_km from public.student_places where student_id = :'sam'), 5::smallint, 'a parent can save their child''s travel distance'); -- Checks: it saved.
-- Paula searches: Near library is offered, Far is not, and homes are not offered to families.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, '{}'::uuid[], null, array[6]::smallint[]) -- Counts Saturday times:
  where tutor_id = '00000000-0000-0000-0000-000000000013' and library_id = :'near'), 5::bigint, 'a library within both distances is offered'); -- (five start times at Near: 9am to 10am, every 15 min).
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, '{}'::uuid[], null, array[6]::smallint[]) -- Counts Saturday times:
  where tutor_id = '00000000-0000-0000-0000-000000000013' and library_id = :'far'), 0::bigint, 'a library outside the distances is not offered'); -- (none at Far).
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, '{}'::uuid[], null, array[6]::smallint[]) -- Counts Saturday times:
  where delivery = 'home'), 0::bigint, 'families are not offered home sessions'); -- (CLG arranges home sessions).
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3 again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.student_places where student_id = :'sam'), 0::bigint, 'a tutor cannot see a family''s address'); -- Checks: T3 cannot see Sam's places or address.
select tests.fails(format($$delete from public.tutor_travel_places where id = %L$$, :'start'), 'an address in use cannot be removed'); -- Checks this is refused: removing the address a time uses.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- CLG admins: homes within the tutor's distance, and both distances apply
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.tutor_travel_places where id = :'start'), 1::bigint, 'admins can see a tutor''s address'); -- Checks: the owner can see it.
reset role; -- Goes back to the all-powerful test user (access rules off).
update public.tutor_availability set ends_at = '12:00' where id = :'sat'; -- For a moment, T3's Saturday runs to 12pm, so a 2 hr home session fits,
update public.tutor_work_settings set max_weekly_hours = 10 where tutor_id = '00000000-0000-0000-0000-000000000013'; -- and T3 may work up to 10 hr a week (it was 3).
set role authenticated; -- Back to acting as the signed-in owner.
select tests.eq((select case when count(*) > 0 then 1 else 0 end from public.find_session_times(:'sam', 'General Maths', 120, false, '{}'::uuid[], null, array[6]::smallint[]) -- Counts Saturday 2 hr times:
  where tutor_id = '00000000-0000-0000-0000-000000000013' and delivery = 'home')::bigint, 1::bigint, 'admins are offered the home within the tutor''s distance'); -- (Norwood is about 2.8 km from the tutor's home; home sessions are 2 hr or more since 20 Nov 2026).
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, '{}'::uuid[], null, array[6]::smallint[]) -- Counts Saturday 1 hr times:
  where tutor_id = '00000000-0000-0000-0000-000000000013' and delivery = 'home'), 0::bigint, 'a 1 hr home session is not offered'); -- (home sessions are booked for at least 2 hours, Carla 20 Nov 2026).
reset role; -- Goes back to the all-powerful test user (access rules off).
update public.tutor_availability set ends_at = '11:00' where id = :'sat'; -- Puts T3's Saturday back to 9 to 11am,
update public.tutor_work_settings set max_weekly_hours = 3 where tutor_id = '00000000-0000-0000-0000-000000000013'; -- and their weekly maximum back to 3 hr.
set role authenticated; -- Back to acting as the signed-in owner.
reset role; -- Goes back to the all-powerful test user (access rules off).
update public.student_places set travel_km = 2 where student_id = :'sam'; -- The family now travels only 2 km.
set role authenticated; -- Back to acting as the signed-in owner.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, '{}'::uuid[], null, array[6]::smallint[]) -- Counts Saturday times:
  where tutor_id = '00000000-0000-0000-0000-000000000013' and delivery = 'library'), 0::bigint, 'a library beyond the family''s distance is not offered'); -- (Near is about 3.6 km from Norwood).
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'near']::uuid[], null, array[6]::smallint[]) -- Counts Saturday times with Near ticked:
  where tutor_id = '00000000-0000-0000-0000-000000000013' and library_id = :'near'), 5::bigint, 'a library the family ticked is still offered'); -- (ticking a library still counts).
reset role; -- Goes back to the all-powerful test user (access rules off).
update public.tutor_availability set travel_km = 2 where id = :'sat'; -- The tutor now travels only 2 km on Saturday.
set role authenticated; -- Back to acting as the signed-in owner.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, '{}'::uuid[], null, array[6]::smallint[]) -- Counts Saturday times:
  where tutor_id = '00000000-0000-0000-0000-000000000013' and delivery = 'home'), 0::bigint, 'a home beyond the tutor''s distance is not offered'); -- (Norwood is about 2.8 km away).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Tidies up so later tests start clean.
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.tutor_availability where id = :'sat'; -- removes the Saturday time,
delete from public.tutor_travel_places where id = :'start'; -- the tutor's address,
update public.student_places set online = true, travel_address = null, travel_latitude = null, travel_longitude = null, travel_km = null where student_id = :'sam'; -- Sam's address (back to online),
delete from public.libraries where id in (:'near', :'far'); -- and both test libraries.

-- Prints that every check in this file passed.
\echo '  scheduling travel distance: all checks passed'
