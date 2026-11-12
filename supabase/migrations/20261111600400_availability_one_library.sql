-- Scheduling: each availability time has its own place (Carla, 11 Nov 2026).
--
-- A tutor's weekly time can be online, at ONE library, or online and one
-- library. Not several libraries. The library is stored on the time
-- (tutor_availability.library_id); in_person means "at that library".
--
-- * Choosing a library for a time also adds it to the tutor's libraries
--   (tutor_places), so lists of where each tutor works stay right.
-- * Older times with in person ticked but no library keep working with any
--   of the tutor's libraries until the tutor picks one. Where the tutor has
--   only one library, it is filled in now.
-- * Finding times and the term availability check use the time's library.
--
-- Changes find_session_times and list_availability_checks in place, so
-- other edits to them are kept. Needs 20261103600100_availability_places.sql.
-- Safe to run more than once.

alter table public.tutor_availability
  add column if not exists library_id uuid references public.libraries (id) on delete set null;

-- A time with a library is an in-person time.
create or replace function private.availability_library_place()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if new.library_id is not null then
    -- Only libraries CLG has confirmed, or one this tutor suggested and is
    -- waiting on, can be chosen.
    if not exists (
      select 1 from public.libraries l
      where l.id = new.library_id and l.active
        and (l.confirmed_at is not null or l.suggested_by = new.tutor_id or private.is_admin())
    ) then
      raise exception 'That library can''t be chosen. Pick one from the list, or suggest it first.' using errcode = '22023';
    end if;
    new.in_person := true;
    insert into public.tutor_places (tutor_id, library_id) values (new.tutor_id, new.library_id)
    on conflict do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.availability_library_place() from public;
drop trigger if exists library_place on public.tutor_availability;
create trigger library_place before insert or update of library_id on public.tutor_availability
  for each row execute function private.availability_library_place();

-- Fill in the library where the tutor has only one.
update public.tutor_availability av
set library_id = one.library_id
from (
  select tutor_id, min(library_id::text)::uuid as library_id
  from public.tutor_places group by tutor_id having count(*) = 1
) one
where av.tutor_id = one.tutor_id and av.in_person and av.library_id is null;

-- Finding times: a time with a library is offered only at that library.
do $$
declare
  v_def text;
begin
  v_def := pg_get_functiondef('public.find_session_times(uuid, text, integer, boolean, uuid[], date, smallint[], time, time)'::regprocedure);
  v_def := replace(v_def, chr(13), ''); -- line endings from pasting on Windows
  if strpos(v_def, 's.slot_library') > 0 then
    return; -- already done
  end if;
  if strpos(v_def, 'av.online as slot_online, av.in_person as slot_in_person') = 0
     or strpos(v_def, 'where tu.can_in_person and s.slot_in_person and tp.library_id') = 0 then
    raise exception 'find_session_times has changed since this update was written. Ask for an updated file.';
  end if;
  v_def := replace(v_def,
    'av.online as slot_online, av.in_person as slot_in_person',
    'av.online as slot_online, av.in_person as slot_in_person, av.library_id as slot_library');
  v_def := replace(v_def,
    'where tu.can_in_person and s.slot_in_person and tp.library_id',
    'where tu.can_in_person and s.slot_in_person and (s.slot_library is null or tp.library_id = s.slot_library) and tp.library_id');
  execute v_def;
end;
$$;

-- Term availability check: a library booking fits only that time's library.
do $$
declare
  v_def text;
  v_old text := 'case when b.delivery = ''online'' then av.online else av.in_person end';
  v_new text := 'case when b.delivery = ''online'' then av.online else av.in_person and (av.library_id is null or av.library_id is not distinct from b.library_id) end';
begin
  if to_regprocedure('public.list_availability_checks()') is null then
    return;
  end if;
  v_def := pg_get_functiondef('public.list_availability_checks()'::regprocedure);
  v_def := replace(v_def, chr(13), ''); -- line endings from pasting on Windows
  if strpos(v_def, 'av.library_id is null or') > 0 then
    return; -- already done
  end if;
  if strpos(v_def, v_old) = 0 then
    raise exception 'list_availability_checks has changed since this update was written. Ask for an updated file.';
  end if;
  execute replace(v_def, v_old, v_new);
end;
$$;
