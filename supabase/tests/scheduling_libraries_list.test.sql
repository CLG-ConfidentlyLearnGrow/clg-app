-- Loading SA libraries in one go (Carla, 11 Nov 2026). Reuses the earlier
-- scheduling tests' people: owner admin (...a0), tutor T3 (...13), parent P3.

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq(public.import_libraries('[
  {"name": "Load Test Library", "address": "1 Main Road", "suburb": "Loadville", "latitude": "-34.9", "longitude": "138.6", "osm_ref": "node/1"},
  {"name": "Alpha Library", "address": "9 New Street", "suburb": "Adelaide", "latitude": "-34.92", "longitude": "138.6", "osm_ref": "way/2"},
  {"name": "x"}
]'::jsonb), 1, 'only the new library is counted; short names are skipped');
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.libraries where name = 'Load Test Library' and confirmed_at is not null and osm_ref = 'node/1'), 1::bigint,
  'a loaded library can be picked straight away');
select tests.eq((select count(*) from public.libraries where name = 'Alpha Library' and osm_ref = 'way/2'), 1::bigint,
  'a library already listed keeps its details and gets the map reference');

-- Loading again adds nothing new.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq(public.import_libraries('[{"name": "Load Test Library", "osm_ref": "node/1"}]'::jsonb), 0, 'loading twice adds nothing');
reset role;

-- Only CLG admins can load libraries.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails($q$select public.import_libraries('[]'::jsonb)$q$, 'tutors can''t load libraries');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails($q$select public.import_libraries('[]'::jsonb)$q$, 'families can''t load libraries');
reset role;

select tests.claims(null);
update public.libraries set osm_ref = null where name = 'Alpha Library';
delete from public.libraries where name = 'Load Test Library';

\echo '  scheduling libraries list: all checks passed'
