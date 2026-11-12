-- Each availability time has its own place: online, one library, or both
-- (Carla, 11 Nov 2026). Reuses the earlier scheduling tests' people: owner
-- admin (...a0), tutor T3 (...13, General Maths Years 3 to 10, has Alpha
-- Library) and Sam Three (Year 5).

select tests.claims(null);
select id as sam from public.students where full_name = 'Sam Three' \gset
select id as lib_a from public.libraries where name = 'Alpha Library' \gset
insert into public.libraries (name, suburb, confirmed_at) values ('Gamma Test Library', 'Unley', now()) returning id as lib_g \gset
insert into public.libraries (name, suburb, suggested_by) values ('Unconfirmed Test Library', 'Unley', '00000000-0000-0000-0000-000000000014') returning id as lib_u \gset
delete from public.bookings where tutor_id = '00000000-0000-0000-0000-000000000013' and weekday = 6;

-- T3 adds Saturday 9 to 11am at Gamma only.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at, online, in_person, library_id)
values ('00000000-0000-0000-0000-000000000013', 6, '09:00', '11:00', false, true, :'lib_g') returning id as sat \gset
select tests.eq((select count(*) from public.tutor_places where tutor_id = '00000000-0000-0000-0000-000000000013' and library_id = :'lib_g'), 1,
  'choosing a library for a time adds it to the tutor''s libraries');
select tests.fails(format($$insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at, online, in_person, library_id)
  values ('00000000-0000-0000-0000-000000000013', 6, '12:00', '13:00', false, true, %L)$$, :'lib_u'),
  'a library CLG hasn''t confirmed (and the tutor didn''t suggest) can''t be chosen');
reset role;

-- Saturday is offered at Gamma only, not at Alpha (another of T3's libraries).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, false, array[:'lib_a', :'lib_g']::uuid[], null, array[6]::smallint[])
  where tutor_id = '00000000-0000-0000-0000-000000000013' and library_id = :'lib_g'), 3::bigint, 'Saturday times at the chosen library');
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, array[:'lib_a', :'lib_g']::uuid[], null, array[6]::smallint[])
  where tutor_id = '00000000-0000-0000-0000-000000000013' and (library_id = :'lib_a' or delivery = 'online')), 0::bigint,
  'not at the tutor''s other library, and not online when online isn''t ticked');
reset role;

-- Put things back.
select tests.claims(null);
delete from public.tutor_availability where id = :'sat';
delete from public.tutor_places where library_id = :'lib_g';
delete from public.libraries where id in (:'lib_g', :'lib_u');

\echo '  scheduling availability places: all checks passed'
