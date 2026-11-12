-- Each availability time has its own place: online, one library, or both
-- (Carla, 11 Nov 2026). Reuses the earlier scheduling tests' people: owner
-- admin (...a0), tutor T3 (...13, General Maths Years 3 to 10, has Alpha
-- Library) and Sam Three (Year 5).

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Keeps Alpha Library's id as lib_a.
select id as lib_a from public.libraries where name = 'Alpha Library' \gset
-- Adds a confirmed library, Gamma, and keeps its id as lib_g.
insert into public.libraries (name, suburb, confirmed_at) values ('Gamma Test Library', 'Unley', now()) returning id as lib_g \gset
-- Adds a library CLG hasn't confirmed (suggested by tutor T4), and keeps its id as lib_u.
insert into public.libraries (name, suburb, suggested_by) values ('Unconfirmed Test Library', 'Unley', '00000000-0000-0000-0000-000000000014') returning id as lib_u \gset
delete from public.bookings where tutor_id = '00000000-0000-0000-0000-000000000013' and weekday = 6; -- Clears tutor T3's Saturday bookings.

-- T3 adds Saturday 9 to 11am at Gamma only.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at, online, in_person, library_id) -- Adds a Saturday 9am to 11am time for tutor T3, in person at Gamma:
-- and keeps its id as sat.
values ('00000000-0000-0000-0000-000000000013', 6, '09:00', '11:00', false, true, :'lib_g') returning id as sat \gset
select tests.eq((select count(*) from public.tutor_places where tutor_id = '00000000-0000-0000-0000-000000000013' and library_id = :'lib_g'), 1, -- Checks choosing a library for a time adds it to the tutor's libraries:
  'choosing a library for a time adds it to the tutor''s libraries'); -- (the label).
select tests.fails(format($$insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at, online, in_person, library_id) -- Checks a library CLG hasn't confirmed (and the tutor didn't suggest) can't be chosen:
  values ('00000000-0000-0000-0000-000000000013', 6, '12:00', '13:00', false, true, %L)$$, :'lib_u'), -- (a Saturday noon time at the unconfirmed library),
  'a library CLG hasn''t confirmed (and the tutor didn''t suggest) can''t be chosen'); -- (the label).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Saturday is offered at Gamma only, not at Alpha (another of T3's libraries).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib_a', :'lib_g']::uuid[], null, array[6]::smallint[]) -- Checks Saturday times are offered at the chosen library:
  where tutor_id = '00000000-0000-0000-0000-000000000013' and library_id = :'lib_g'), 5::bigint, 'Saturday times at the chosen library'); -- (five start times at Gamma: 9am to 10am, every 15 min).
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, array[:'lib_a', :'lib_g']::uuid[], null, array[6]::smallint[]) -- Checks no times at the tutor's other library, and none online when online isn't ticked:
  where tutor_id = '00000000-0000-0000-0000-000000000013' and (library_id = :'lib_a' or delivery = 'online')), 0::bigint, -- (searching in person only, at Alpha or Gamma),
  'not at the tutor''s other library, and not online when online isn''t ticked'); -- (the label).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Put things back.
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.tutor_availability where id = :'sat'; -- Removes the Saturday time.
delete from public.tutor_places where library_id = :'lib_g'; -- Removes Gamma from tutors' libraries.
delete from public.libraries where id in (:'lib_g', :'lib_u'); -- Removes both test libraries.

-- Prints that every check in this file passed.
\echo '  scheduling availability places: all checks passed'
