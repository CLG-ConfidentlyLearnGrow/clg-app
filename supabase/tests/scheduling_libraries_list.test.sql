-- Loading SA libraries in one go (Carla, 11 Nov 2026). Reuses the earlier
-- scheduling tests' people: owner admin (...a0), tutor T3 (...13), parent P3.

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Loads three libraries from a list: a new one, one already listed, and one with a name too short.
select tests.eq(public.import_libraries('[
  {"name": "Load Test Library", "address": "1 Main Road", "suburb": "Loadville", "latitude": "-34.9", "longitude": "138.6", "osm_ref": "node/1"},
  {"name": "Alpha Library", "address": "9 New Street", "suburb": "Adelaide", "latitude": "-34.92", "longitude": "138.6", "osm_ref": "way/2"},
  {"name": "x"}
]'::jsonb), 1, 'only the new library is counted; short names are skipped'); -- Checks only the new library is counted, and short names are skipped.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.libraries where name = 'Load Test Library' and confirmed_at is not null and osm_ref = 'node/1'), 1::bigint, -- Checks a loaded library can be picked straight away:
  'a loaded library can be picked straight away'); -- (confirmed, with its map reference).
select tests.eq((select count(*) from public.libraries where name = 'Alpha Library' and osm_ref = 'way/2'), 1::bigint, -- Checks a library already listed keeps its details and gets the map reference:
  'a library already listed keeps its details and gets the map reference'); -- (the label).

-- Loading again adds nothing new.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(public.import_libraries('[{"name": "Load Test Library", "osm_ref": "node/1"}]'::jsonb), 0, 'loading twice adds nothing'); -- Checks: loading twice adds nothing.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Only CLG admins can load libraries.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($q$select public.import_libraries('[]'::jsonb)$q$, 'tutors can''t load libraries'); -- Checks this is refused: tutors can't load libraries.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($q$select public.import_libraries('[]'::jsonb)$q$, 'families can''t load libraries'); -- Checks this is refused: families can't load libraries.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
update public.libraries set osm_ref = null where name = 'Alpha Library'; -- Clears Alpha Library's map reference.
delete from public.libraries where name = 'Load Test Library'; -- Removes the loaded library.

-- Prints that every check in this file passed.
\echo '  scheduling libraries list: all checks passed'
