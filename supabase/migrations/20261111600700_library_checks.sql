-- Scheduling: library opening hours when needed, and holiday checks
-- (Carla, 11 Nov 2026).
--
-- * Opening hours are asked for only once a library is actually wanted: the
--   first time a tutor adds it (to their libraries or to a weekly time) or
--   CLG sets it as a place for a student. Admins get one notice per library.
-- * Libraries in use are re-checked: if their hours were last checked more
--   than 6 months ago, they show on the Libraries to-do list until an admin
--   says the hours are still right (or changes them).
-- * The first time sessions are booked at a library, admins are told to
--   check whether it closes on public holidays or changes its hours in the
--   school holidays (they may need to call the library).
--
-- Safe to run more than once.

alter table public.libraries add column if not exists hours_requested_at timestamptz;
alter table public.libraries add column if not exists hours_checked_at timestamptz;
alter table public.libraries add column if not exists first_booked_at timestamptz;

-- Hours already entered count as checked when they were first entered.
update public.libraries l set hours_checked_at = coalesce(l.confirmed_at, l.created_at)
where l.hours_checked_at is null and exists (select 1 from public.library_hours h where h.library_id = l.id);

-- Ask admins for a library's opening hours once, when it is first wanted.
create or replace function private.ask_for_library_hours(p_library uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  update public.libraries l set hours_requested_at = now()
  where l.id = p_library and l.hours_requested_at is null
    and not exists (select 1 from public.library_hours h where h.library_id = l.id)
  returning l.name into v_name;
  if v_name is not null then
    perform private.notify_admins('Library opening hours needed',
      v_name || ' has been chosen for sessions. Please add its opening hours under Schedule > Libraries, '
      || 'and check whether it closes on public holidays or changes hours in the school holidays.');
  end if;
end;
$$;
revoke all on function private.ask_for_library_hours(uuid) from public;

create or replace function private.library_wanted_tutor()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if new.library_id is not null then
    perform private.ask_for_library_hours(new.library_id);
  end if;
  return new;
end;
$$;
revoke all on function private.library_wanted_tutor() from public;
drop trigger if exists ask_for_hours on public.tutor_places;
create trigger ask_for_hours after insert on public.tutor_places
  for each row execute function private.library_wanted_tutor();

create or replace function private.library_wanted_student()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_lib uuid;
begin
  foreach v_lib in array coalesce(new.library_ids, '{}') loop
    perform private.ask_for_library_hours(v_lib);
  end loop;
  return new;
end;
$$;
revoke all on function private.library_wanted_student() from public;
drop trigger if exists ask_for_hours on public.student_places;
create trigger ask_for_hours after insert or update of library_ids on public.student_places
  for each row execute function private.library_wanted_student();

-- Entering or changing hours counts as checking them.
create or replace function private.library_hours_checked()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  update public.libraries set hours_checked_at = now()
  where id = coalesce(new.library_id, old.library_id);
  return null;
end;
$$;
revoke all on function private.library_hours_checked() from public;
drop trigger if exists checked on public.library_hours;
create trigger checked after insert or update or delete on public.library_hours
  for each row execute function private.library_hours_checked();

-- An admin says a library's hours are still right.
create or replace function public.mark_library_hours_checked(p_library uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only CLG admins can do this' using errcode = '42501';
  end if;
  if not exists (select 1 from public.library_hours h where h.library_id = p_library) then
    raise exception 'Add the library''s opening hours first' using errcode = '22023';
  end if;
  update public.libraries set hours_checked_at = now() where id = p_library;
end;
$$;
revoke all on function public.mark_library_hours_checked(uuid) from public, anon;
grant execute on function public.mark_library_hours_checked(uuid) to authenticated;

-- Libraries that need something from an admin: in use (a tutor's library,
-- a student's place or a live booking) and either no hours yet, or hours
-- last checked more than 6 months ago, or not yet confirmed.
create or replace function public.library_checks()
returns table (library_id uuid, name text, suburb text, problem text)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG admins can see library checks' using errcode = '42501';
  end if;
  return query
  with in_use as (
    select tp.library_id as id from public.tutor_places tp
    union select unnest(sp.library_ids) from public.student_places sp
    union select b.library_id from public.bookings b
      where b.library_id is not null and private.booking_is_live(b.status, b.tutor_reply_by)
  )
  select l.id, l.name, l.suburb,
         case
           when l.confirmed_at is null then 'Suggested by a tutor: confirm it'
           when not exists (select 1 from public.library_hours h where h.library_id = l.id) then 'Opening hours needed'
           else 'Check the opening hours are still right'
         end
  from public.libraries l
  join in_use u on u.id = l.id
  where l.active
    and (l.confirmed_at is null
         or not exists (select 1 from public.library_hours h where h.library_id = l.id)
         or l.hours_checked_at is null
         or l.hours_checked_at < now() - interval '6 months')
  order by l.name;
end;
$$;
revoke all on function public.library_checks() from public, anon;
grant execute on function public.library_checks() to authenticated;

-- First sessions at a library: remind admins to check holiday hours.
create or replace function private.first_booking_at_library()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  if new.delivery <> 'library' or new.library_id is null then
    return new;
  end if;
  update public.libraries set first_booked_at = now()
  where id = new.library_id and first_booked_at is null
  returning name into v_name;
  if v_name is not null then
    perform private.notify_admins('First sessions at a library',
      'Sessions are being booked at ' || v_name || ' for the first time. Please check whether it closes on '
      || 'public holidays or changes its hours in the school holidays. If its website doesn''t say, call the library.',
      new.id);
  end if;
  return new;
end;
$$;
revoke all on function private.first_booking_at_library() from public;
drop trigger if exists first_at_library on public.bookings;
create trigger first_at_library after insert on public.bookings
  for each row execute function private.first_booking_at_library();

-- Libraries already booked before this update don't need the reminder.
update public.libraries l set first_booked_at = coalesce(l.confirmed_at, l.created_at)
where l.first_booked_at is null and exists (select 1 from public.bookings b where b.library_id = l.id);
