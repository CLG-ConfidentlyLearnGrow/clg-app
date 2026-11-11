-- Scheduling: loading SA libraries, and addresses on suggestions
-- (Carla, 11 Nov 2026).
--
-- * Admins can load South Australia's libraries in one go (from
--   OpenStreetMap, under Schedule > Libraries). Loaded libraries can be
--   picked straight away; opening hours are asked for only once a tutor or
--   family chooses one (see the next update). Libraries already listed keep
--   their details, and only missing address or map details are filled in.
-- * A tutor suggesting a library must now give its address as well as its
--   name. CLG still confirms it.
--
-- Safe to run more than once.

alter table public.libraries add column if not exists osm_ref text check (char_length(osm_ref) <= 40);
create unique index if not exists libraries_osm_ref_once on public.libraries (osm_ref) where osm_ref is not null;

-- Load a list of libraries (owner and operations admins). Each row has
-- name, address, suburb, latitude, longitude and osm_ref. Returns how many
-- were new.
create or replace function public.import_libraries(p_rows jsonb, p_state public.au_state default 'SA')
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  r jsonb;
  v_new integer := 0;
  v_inserted boolean;
begin
  if not private.is_admin() then
    raise exception 'Only CLG admins can load libraries' using errcode = '42501';
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 2000 then
    raise exception 'The list of libraries couldn''t be read' using errcode = '22023';
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    continue when char_length(btrim(coalesce(r->>'name', ''))) < 3;
    insert into public.libraries (name, address, suburb, state, latitude, longitude, osm_ref)
    values (
      left(btrim(r->>'name'), 200),
      nullif(left(btrim(coalesce(r->>'address', '')), 300), ''),
      nullif(left(btrim(coalesce(r->>'suburb', '')), 100), ''),
      p_state,
      case when (r->>'latitude') ~ '^-?[0-9]+(\.[0-9]+)?$' and abs((r->>'latitude')::numeric) <= 90
           then round((r->>'latitude')::numeric, 6) end,
      case when (r->>'longitude') ~ '^-?[0-9]+(\.[0-9]+)?$' and abs((r->>'longitude')::numeric) <= 180
           then round((r->>'longitude')::numeric, 6) end,
      nullif(left(btrim(coalesce(r->>'osm_ref', '')), 40), '')
    )
    on conflict ((lower(name)), state) do update
      set address = coalesce(public.libraries.address, excluded.address),
          suburb = coalesce(public.libraries.suburb, excluded.suburb),
          latitude = coalesce(public.libraries.latitude, excluded.latitude),
          longitude = coalesce(public.libraries.longitude, excluded.longitude),
          osm_ref = coalesce(public.libraries.osm_ref, excluded.osm_ref)
    returning (xmax = 0) into v_inserted;
    if v_inserted then
      v_new := v_new + 1;
    end if;
  end loop;
  return v_new;
end;
$$;
revoke all on function public.import_libraries(jsonb, public.au_state) from public, anon;
grant execute on function public.import_libraries(jsonb, public.au_state) to authenticated;

-- Suggesting a library now needs its address. The old version (name and
-- suburb only) is replaced.
drop function if exists public.suggest_library(text, text);
create or replace function public.suggest_library(p_name text, p_suburb text, p_address text)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_state public.au_state;
begin
  if not (private.has_role('tutor') and private.has_aal2()) and not private.is_admin() then
    raise exception 'Only tutors can suggest a library' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_name, ''))) < 3 then
    raise exception 'Enter the library''s name' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_address, ''))) < 5 then
    raise exception 'Enter the library''s street address' using errcode = '22023';
  end if;
  select coalesce(w.work_state, 'SA') into v_state from public.tutor_work_settings w where w.tutor_id = auth.uid();
  v_state := coalesce(v_state, 'SA');
  select l.id into v_id from public.libraries l where lower(l.name) = lower(btrim(p_name)) and l.state = v_state;
  if v_id is null then
    insert into public.libraries (name, suburb, address, state, suggested_by)
    values (left(btrim(p_name), 200), nullif(left(btrim(p_suburb), 100), ''), left(btrim(p_address), 300), v_state, auth.uid())
    returning id into v_id;
    perform private.notify_admins('Library to confirm',
      btrim(p_name) || ', ' || btrim(p_address) || coalesce(' ' || nullif(btrim(p_suburb), ''), '')
      || ' was suggested by a tutor. Please confirm it and add its opening hours under Schedule > Libraries.');
  end if;
  if exists (select 1 from public.tutor_profiles tp where tp.account_id = auth.uid()) then
    insert into public.tutor_places (tutor_id, library_id) values (auth.uid(), v_id) on conflict do nothing;
  end if;
  return v_id;
end;
$$;
revoke all on function public.suggest_library(text, text, text) from public, anon;
grant execute on function public.suggest_library(text, text, text) to authenticated;
