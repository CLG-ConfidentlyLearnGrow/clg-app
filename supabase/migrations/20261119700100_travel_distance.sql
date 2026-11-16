-- Summary: travel distances for tutors and families (Carla, 16 Nov 2026).
--
-- Carla: "The travel distance from their home is determined by the tutor
-- (this is km by straight line from residence)", "It could also be km by
-- straight line from an address set by the tutor too", "This can change for
-- each set/day of availability the tutor provides", and "This can be the
-- same for clients too ... this would be the limit of where clients are
-- willing to travel for tutoring". Exact street addresses are used.
--
-- What this adds (scheduling module):
-- * tutor_travel_places: the addresses a tutor travels from (for example
--   "Home" or "Uni"), each with its map point. Only the tutor and CLG's
--   owner and operations admins can see them.
-- * On each weekly availability time: which of those addresses the tutor
--   starts from, how many km they will travel (in a straight line), and
--   whether they will go to learners' homes within that distance.
-- * On student_places: the family's address (or another place they choose),
--   its map point, and how many km they will travel. Only the family (and
--   the learner, if they have their own login) and CLG front desk admins can
--   see it, like the rest of student_places.
-- * Finding times: a library is offered when it is within the tutor's
--   distance for that time AND within the family's distance (or the family
--   or CLG ticked that library, as before). A learner's home is offered to
--   CLG admins when it is within the tutor's distance for that time. Times
--   set up the old way (one library, or the tutor's ticked libraries) keep
--   working.
--
-- The map point of an address is looked up by the app (server side) before
-- it is saved; the database only checks it is inside Australia.
--
-- Edits find_session_times in place (other files change it too). Safe to
-- run more than once.

-- ---------------------------------------------------------------------------
-- The addresses a tutor travels from
-- ---------------------------------------------------------------------------
create table if not exists public.tutor_travel_places ( -- one row per address a tutor travels from:
  id uuid primary key default gen_random_uuid(), -- its own id
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade, -- the tutor (removed with them)
  label text not null check (char_length(btrim(label)) between 1 and 60), -- a short name, such as Home or Uni
  address text not null check (char_length(btrim(address)) between 5 and 300), -- the street address as the tutor typed it
  latitude numeric(9, 6) not null check (latitude between -44 and -9), -- its map point: north to south, inside Australia
  longitude numeric(9, 6) not null check (longitude between 112 and 154), -- and west to east, inside Australia
  created_at timestamptz not null default now() -- when it was added
); -- (end of the table)
create index if not exists tutor_travel_places_tutor on public.tutor_travel_places (tutor_id); -- finds a tutor's addresses quickly

alter table public.tutor_travel_places enable row level security; -- turns on access rules: nobody sees a row unless a rule allows it
revoke all on public.tutor_travel_places from anon; -- signed-out visitors get nothing

drop policy if exists "tutor and admins see travel places" on public.tutor_travel_places; -- replaces the rule if re-run
create policy "tutor and admins see travel places" on public.tutor_travel_places -- who can read an address:
  for select to authenticated -- (signed-in people only)
  using (tutor_id = auth.uid() or private.is_admin()); -- the tutor themselves, or an owner or operations admin
drop policy if exists "tutor adds travel places" on public.tutor_travel_places; -- replaces the rule if re-run
create policy "tutor adds travel places" on public.tutor_travel_places -- who can add an address:
  for insert to authenticated -- (signed-in people only)
  with check (tutor_id = auth.uid() and private.has_role('tutor')); -- only a tutor, for themselves
drop policy if exists "tutor removes travel places" on public.tutor_travel_places; -- replaces the rule if re-run
create policy "tutor removes travel places" on public.tutor_travel_places -- who can remove an address:
  for delete to authenticated -- (signed-in people only)
  using (tutor_id = auth.uid() and private.has_role('tutor')); -- only the tutor, their own

drop trigger if exists audit on public.tutor_travel_places; -- replaces the audit trigger if re-run
create trigger audit after insert or update or delete on public.tutor_travel_places -- records every change in the audit log
  for each row execute function private.audit_change(); -- (using the app's shared audit step)

-- ---------------------------------------------------------------------------
-- Each weekly availability time: where the tutor starts from and how far
-- ---------------------------------------------------------------------------
alter table public.tutor_availability -- adds to each availability time:
  add column if not exists travel_place_id uuid references public.tutor_travel_places (id) on delete restrict; -- the address they start from (an address in use cannot be removed)
alter table public.tutor_availability -- and:
  add column if not exists travel_km smallint check (travel_km between 1 and 100); -- how many km they will travel, in a straight line
alter table public.tutor_availability -- and:
  add column if not exists home_visits boolean not null default false; -- whether they will go to learners' homes in that distance

alter table public.tutor_availability drop constraint if exists tutor_availability_travel_pair; -- replaces the rule if re-run
alter table public.tutor_availability add constraint tutor_availability_travel_pair -- a distance always comes with an address:
  check ((travel_km is null) = (travel_place_id is null)); -- both set, or neither
alter table public.tutor_availability drop constraint if exists tutor_availability_home_needs_km; -- replaces the rule if re-run
alter table public.tutor_availability add constraint tutor_availability_home_needs_km -- home visits need a distance:
  check (not home_visits or travel_km is not null); -- no home visits without one
alter table public.tutor_availability drop constraint if exists tutor_availability_some_place; -- replaces the older "somewhere" rule
alter table public.tutor_availability add constraint tutor_availability_some_place -- each time must allow somewhere:
  check (in_person or online or home_visits); -- libraries, online or learners' homes

-- The address on a time must be the tutor's own.
create or replace function private.availability_travel_place() -- checks a time's starting address
returns trigger language plpgsql security definer -- runs before saving; reads past the access rules to check
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  if new.travel_place_id is not null and not exists ( -- an address is given that is not
    select 1 from public.tutor_travel_places p -- one of the travel addresses
    where p.id = new.travel_place_id and p.tutor_id = new.tutor_id -- belonging to this tutor:
  ) then -- (then)
    raise exception 'Choose one of your own starting addresses.' using errcode = '22023'; -- plain refusal
  end if; -- (end of that check)
  return new; -- saves the time
end; -- finish
$$; -- (end of the function)
drop trigger if exists check_travel_place on public.tutor_availability; -- replaces the trigger if re-run
create trigger check_travel_place before insert or update on public.tutor_availability -- runs the check on every save
  for each row execute function private.availability_travel_place(); -- (using the function above)

-- ---------------------------------------------------------------------------
-- Each learner: the family's address and how far they will travel
-- ---------------------------------------------------------------------------
alter table public.student_places -- adds to each learner's places:
  add column if not exists travel_address text check (char_length(btrim(travel_address)) between 5 and 300); -- the address they travel from
alter table public.student_places -- and:
  add column if not exists travel_latitude numeric(9, 6) check (travel_latitude between -44 and -9); -- its map point: north to south, inside Australia
alter table public.student_places -- and:
  add column if not exists travel_longitude numeric(9, 6) check (travel_longitude between 112 and 154); -- and west to east, inside Australia
alter table public.student_places -- and:
  add column if not exists travel_km smallint check (travel_km between 1 and 100); -- how many km they will travel, in a straight line

alter table public.student_places drop constraint if exists student_places_travel_all; -- replaces the rule if re-run
alter table public.student_places add constraint student_places_travel_all -- the address, map point and distance go together:
  check ((travel_address is null) = (travel_km is null) -- address and distance both set or both empty,
     and (travel_address is null) = (travel_latitude is null) -- the same for the latitude,
     and (travel_address is null) = (travel_longitude is null)); -- and the longitude
alter table public.student_places drop constraint if exists student_places_check; -- replaces the older "somewhere" rule (its default name)
alter table public.student_places drop constraint if exists student_places_somewhere; -- replaces this rule if re-run
alter table public.student_places add constraint student_places_somewhere -- each learner must allow somewhere:
  check (online or cardinality(library_ids) > 0 or travel_km is not null); -- online, a ticked library, or a travel distance

-- ---------------------------------------------------------------------------
-- Finding times: libraries and homes within both people's distances
-- ---------------------------------------------------------------------------
do $$ -- (a block of steps)
declare -- working values:
  v_def text; -- the function's current code
  v_old_check text := E'if not coalesce(p_online, false) and coalesce(cardinality(p_libraries), 0) = 0 then'; -- the "choose somewhere" check
  v_new_check text := E'if not coalesce(p_online, false) and coalesce(cardinality(p_libraries), 0) = 0\n'
                   || E'     and not exists (select 1 from public.student_places x where x.student_id = p_student and x.travel_km is not null) then -- (a family travel distance also counts)'; -- the check, allowing a travel distance
  v_old_decl text := E'  v_needs boolean;\nbegin'; -- the end of the working values
  v_new_decl text := E'  v_needs boolean;\n  v_home public.student_places; -- the family''s address and travel distance (if any)\nbegin'; -- adds the family's places
  v_old_load text := E'  ) into v_needs;\n'; -- the end of the learning needs read
  v_new_load text := E'  ) into v_needs;\n  select * into v_home from public.student_places x where x.student_id = p_student; -- reads the family''s address and travel distance\n'; -- adds reading them
  v_old_slots text := E'av.online as slot_online, av.in_person as slot_in_person, av.library_id as slot_library\n    from tutors tu\n    join public.tutor_availability av on av.tutor_id = tu.tid\n'; -- what each time carries today
  v_new_slots text := E'av.online as slot_online, av.in_person as slot_in_person, av.library_id as slot_library,\n'
                   || E'           av.travel_km as slot_km, av.home_visits as slot_home, ttp.latitude as slot_lat, ttp.longitude as slot_lon -- the tutor''s distance and starting point for this time\n'
                   || E'    from tutors tu\n    join public.tutor_availability av on av.tutor_id = tu.tid\n'
                   || E'    left join public.tutor_travel_places ttp on ttp.id = av.travel_place_id -- (the starting address, if set)\n'; -- adds the distance and starting point
  v_old_libs text := E'    -- At a library both the family and the tutor chose\n'
                  || E'    select s.tid, s.weekday, s.st, ''library''::public.session_delivery, tp.library_id\n'
                  || E'    from slots s\n'
                  || E'    join tutors tu on tu.tid = s.tid\n'
                  || E'    join public.tutor_places tp on tp.tutor_id = s.tid\n'
                  || E'    join public.libraries l on l.id = tp.library_id and l.active and l.confirmed_at is not null\n'
                  || E'    where tu.can_in_person and s.slot_in_person and (s.slot_library is null or tp.library_id = s.slot_library) and tp.library_id = any (coalesce(p_libraries, ''{}''))\n'
                  || E'      and private.library_open_weekly(tp.library_id, s.weekday, s.st, p_minutes)\n'; -- the library part today
  v_new_libs text := E'    -- At a library both the family and the tutor can get to\n'
                  || E'    select s.tid, s.weekday, s.st, ''library''::public.session_delivery, l.id\n'
                  || E'    from slots s\n'
                  || E'    join tutors tu on tu.tid = s.tid\n'
                  || E'    join public.libraries l on l.active and l.confirmed_at is not null -- (confirmed libraries in use)\n'
                  || E'    where tu.can_in_person and s.slot_in_person\n'
                  || E'      and ( -- the tutor can get there: within their distance for this time,\n'
                  || E'        (s.slot_km is not null and private.distance_m(s.slot_lat, s.slot_lon, l.latitude, l.longitude) <= s.slot_km * 1000)\n'
                  || E'        or (s.slot_km is null and (s.slot_library is null or l.id = s.slot_library) -- or (times set up the old way) the time''s library,\n'
                  || E'            and exists (select 1 from public.tutor_places tp where tp.tutor_id = s.tid and tp.library_id = l.id))) -- among the libraries they ticked\n'
                  || E'      and ( -- and the family can get there: they (or CLG) ticked it,\n'
                  || E'        l.id = any (coalesce(p_libraries, ''{}''))\n'
                  || E'        or (v_home.travel_km is not null -- or it is within the family''s travel distance\n'
                  || E'            and private.distance_m(v_home.travel_latitude, v_home.travel_longitude, l.latitude, l.longitude) <= v_home.travel_km * 1000))\n'
                  || E'      and private.library_open_weekly(l.id, s.weekday, s.st, p_minutes)\n'
                  || E'    union all\n'
                  || E'    -- At the learner''s home (CLG front desk admins arrange these)\n'
                  || E'    select s.tid, s.weekday, s.st, ''home''::public.session_delivery, null::uuid\n'
                  || E'    from slots s\n'
                  || E'    join tutors tu on tu.tid = s.tid\n'
                  || E'    where private.is_front_desk() and s.slot_home and v_home.travel_km is not null -- (an admin, a time with home visits, and a family address)\n'
                  || E'      and private.distance_m(s.slot_lat, s.slot_lon, v_home.travel_latitude, v_home.travel_longitude) <= s.slot_km * 1000 -- within the tutor''s distance\n'; -- the new library and home parts
begin -- start
  v_def := replace(pg_get_functiondef( -- reads the function's code
    'public.find_session_times(uuid, text, integer, boolean, uuid[], date, smallint[], time, time)'::regprocedure), chr(13), ''); -- (without Windows line endings from pasting)
  if strpos(v_def, 'slot_km') > 0 then -- already done:
    return; -- nothing to change
  end if; -- (end of that check)
  if strpos(v_def, v_old_check) = 0 or strpos(v_def, v_old_decl) = 0 or strpos(v_def, v_old_load) = 0 -- any part not found as expected:
     or strpos(v_def, v_old_slots) = 0 or strpos(v_def, v_old_libs) = 0 then -- (any of the five)
    raise exception 'public.find_session_times has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- (end of that check)
  v_def := replace(v_def, v_old_check, v_new_check); -- allows a travel distance in place of ticked libraries
  v_def := replace(v_def, v_old_decl, v_new_decl); -- adds the family's places to the working values
  v_def := replace(v_def, v_old_load, v_new_load); -- reads them
  v_def := replace(v_def, v_old_slots, v_new_slots); -- gives each time its distance and starting point
  v_def := replace(v_def, v_old_libs, v_new_libs); -- matches libraries and homes by distance
  execute v_def; -- saves the new code
end; -- finish
$$; -- (end of the block)
