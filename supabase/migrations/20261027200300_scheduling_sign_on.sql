-- Scheduling part 3 (module: scheduling): tutor sign on and sign off.
--
-- Carla's rules (2026-10-26):
--   * In person: one location check at the library when the tutor signs on,
--     with their consent. Only the result is kept (at the library or not),
--     never the location itself. No tracking.
--   * Online: the start counts from the later of signing on and the
--     scheduled start.
--   * Sign-off is automatic at the scheduled end, unless the tutor records a
--     different end time. A different end time waits for an admin to
--     confirm it.
--   * A tutor who starts late (and doesn't make it up) is paid for the time
--     worked. A student who is late doesn't change the tutor's time.
--
-- worked_from and worked_to are the times payroll uses. Billing still
-- charges the family the booked time.
--
-- See docs/features/scheduling.md. Safe to run more than once.

alter table public.libraries
  add column if not exists check_radius_m integer not null default 300
    check (check_radius_m between 50 and 2000);

alter table public.sessions add column if not exists signed_on_at timestamptz;
alter table public.sessions add column if not exists sign_on_check text;
alter table public.sessions drop constraint if exists sessions_sign_on_check;
alter table public.sessions add constraint sessions_sign_on_check
  check (sign_on_check is null or sign_on_check in ('online', 'at_library', 'not_at_library', 'no_location', 'admin'));
-- A different end time the tutor recorded, waiting for an admin.
alter table public.sessions add column if not exists tutor_end_at timestamptz;
alter table public.sessions add column if not exists tutor_time_note text check (char_length(tutor_time_note) <= 500);
alter table public.sessions add column if not exists worked_from timestamptz;
alter table public.sessions add column if not exists worked_to timestamptz;
alter table public.sessions add column if not exists times_confirmed_by uuid references public.accounts (id) on delete set null;
alter table public.sessions add column if not exists times_confirmed_at timestamptz;
alter table public.sessions drop constraint if exists sessions_worked_order;
alter table public.sessions add constraint sessions_worked_order
  check (worked_from is null or worked_to is null or worked_to > worked_from);

-- Distance in metres between two points (haversine).
create or replace function private.distance_m(lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric)
returns double precision language sql immutable
set search_path = ''
as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians((lat2 - lat1)::double precision) / 2), 2)
    + cos(radians(lat1::double precision)) * cos(radians(lat2::double precision))
      * power(sin(radians((lon2 - lon1)::double precision) / 2), 2)
  ))
$$;

-- Fill in the worked times for a session that has ended: from the later of
-- signing on and the start, to the scheduled end. Left blank while a
-- different end time waits for an admin.
create or replace function private.set_worked_times(p_session uuid)
returns void language sql security definer
set search_path = ''
as $$
  update public.sessions
  set worked_from = greatest(coalesce(signed_on_at, starts_at), starts_at),
      worked_to = ends_at
  where id = p_session
    and worked_to is null
    and tutor_end_at is null
    and ends_at <= now()
    and greatest(coalesce(signed_on_at, starts_at), starts_at) < ends_at
$$;
revoke all on function private.set_worked_times(uuid) from public;

-- ---------------------------------------------------------------------------
-- Signing on
-- ---------------------------------------------------------------------------
-- p_latitude and p_longitude are the tutor's position, read once by the
-- app with their permission, for library sessions only. They are compared
-- with the library and then thrown away.
create or replace function public.sign_on(
  p_session uuid,
  p_latitude numeric default null,
  p_longitude numeric default null
)
returns text language plpgsql security definer
set search_path = ''
as $$
declare
  v_s public.sessions;
  v_lib public.libraries;
  v_check text;
begin
  select * into v_s from public.sessions where id = p_session for update;
  if v_s.id is null or not (v_s.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2()) then
    raise exception 'Session not found' using errcode = 'P0002';
  end if;
  if v_s.status <> 'scheduled' then
    raise exception 'This session is %', replace(v_s.status::text, '_', ' ') using errcode = '22023';
  end if;
  if v_s.signed_on_at is not null then
    raise exception 'You''re already signed on' using errcode = '22023';
  end if;
  if now() < v_s.starts_at - interval '30 minutes' then
    raise exception 'You can sign on from 30 minutes before the start' using errcode = '22023';
  end if;
  if now() >= v_s.ends_at then
    raise exception 'This session has ended. Record a different time if needed.' using errcode = '22023';
  end if;

  if v_s.delivery = 'library' then
    select * into v_lib from public.libraries where id = v_s.library_id;
    if p_latitude is null or p_longitude is null or v_lib.latitude is null or v_lib.longitude is null then
      v_check := 'no_location';
    elsif private.distance_m(p_latitude, p_longitude, v_lib.latitude, v_lib.longitude) <= v_lib.check_radius_m then
      v_check := 'at_library';
    else
      v_check := 'not_at_library';
    end if;
  elsif v_s.delivery = 'online' then
    v_check := 'online';
  else
    v_check := 'no_location';
  end if;

  update public.sessions set signed_on_at = now(), sign_on_check = v_check where id = p_session;
  return v_check;
end;
$$;
revoke all on function public.sign_on(uuid, numeric, numeric) from public, anon;
grant execute on function public.sign_on(uuid, numeric, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- A different end time (the session ran over or finished early)
-- ---------------------------------------------------------------------------
create or replace function public.record_end_time(p_session uuid, p_end timestamptz, p_note text default null)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_s public.sessions;
begin
  select * into v_s from public.sessions where id = p_session for update;
  if v_s.id is null or not (v_s.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2()) then
    raise exception 'Session not found' using errcode = 'P0002';
  end if;
  if v_s.status in ('cancelled', 'no_show') then
    raise exception 'This session is %', replace(v_s.status::text, '_', ' ') using errcode = '22023';
  end if;
  if v_s.times_confirmed_at is not null then
    raise exception 'CLG has already confirmed the times for this session' using errcode = '22023';
  end if;
  if p_end is null or p_end <= greatest(coalesce(v_s.signed_on_at, v_s.starts_at), v_s.starts_at)
     or p_end > v_s.ends_at + interval '2 hours' then
    raise exception 'Choose an end time after the start and no more than 2 hours after the booked end' using errcode = '22023';
  end if;
  if now() > v_s.ends_at + interval '7 days' then
    raise exception 'It''s more than a week since this session. Please contact CLG.' using errcode = '22023';
  end if;
  if nullif(trim(p_note), '') is null then
    raise exception 'Please say why the time was different' using errcode = '22023';
  end if;
  update public.sessions
  set tutor_end_at = p_end, tutor_time_note = left(trim(p_note), 500), worked_from = null, worked_to = null
  where id = p_session;
end;
$$;
revoke all on function public.record_end_time(uuid, timestamptz, text) from public, anon;
grant execute on function public.record_end_time(uuid, timestamptz, text) to authenticated;

-- An admin confirms (or sets) the times worked for pay.
create or replace function public.confirm_session_times(p_session uuid, p_from timestamptz, p_to timestamptz)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only CLG admins can confirm times' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '6 hours' then
    raise exception 'Choose a start and end time, in order, up to 6 hours apart' using errcode = '22023';
  end if;
  update public.sessions
  set worked_from = p_from, worked_to = p_to, times_confirmed_by = auth.uid(), times_confirmed_at = now(),
      status = case when status = 'scheduled' then 'completed'::public.session_status else status end,
      completed_at = case when status = 'scheduled' then now() else completed_at end,
      sign_on_check = coalesce(sign_on_check, 'admin')
  where id = p_session and status in ('scheduled', 'completed');
  if not found then
    raise exception 'Session not found, or it was cancelled or a no-show' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.confirm_session_times(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.confirm_session_times(uuid, timestamptz, timestamptz) to authenticated;

-- ---------------------------------------------------------------------------
-- Recording the outcome now also fills in the worked times
-- ---------------------------------------------------------------------------
create or replace function public.record_session_outcome(p_session uuid, p_status public.session_status)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_s public.sessions;
begin
  select * into v_s from public.sessions where id = p_session for update;
  if v_s.id is null or not (
    private.is_admin()
    or (v_s.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
  ) then
    raise exception 'Session not found' using errcode = 'P0002';
  end if;
  if p_status not in ('completed', 'no_show') then
    raise exception 'Choose completed or no-show' using errcode = '22023';
  end if;
  if v_s.starts_at > now() then
    raise exception 'This session hasn''t started yet' using errcode = '22023';
  end if;
  -- Tutors record it once; admins can correct it.
  if v_s.status <> 'scheduled' and not (private.is_admin() and v_s.status in ('completed', 'no_show')) then
    raise exception 'This session is already %', replace(v_s.status::text, '_', ' ') using errcode = '22023';
  end if;
  update public.sessions
  set status = p_status, completed_at = case when p_status = 'completed' then now() end
  where id = p_session;
  if p_status = 'completed' then
    perform private.set_worked_times(p_session);
  end if;
  -- No need to touch the student's activity date: the tutor assignment made
  -- with the booking already keeps the record from automatic deletion.
end;
$$;

-- ---------------------------------------------------------------------------
-- Automatic sign-off: every 15 minutes, sessions the tutor signed on to are
-- marked done at their scheduled end (unless a different end time waits).
-- ---------------------------------------------------------------------------
create or replace function private.auto_sign_off()
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_id uuid;
begin
  update public.sessions
  set status = 'completed', completed_at = now()
  where status = 'scheduled' and signed_on_at is not null and ends_at <= now();
  get diagnostics v_count = row_count;
  for v_id in
    select id from public.sessions
    where status = 'completed' and worked_to is null and tutor_end_at is null and ends_at <= now()
  loop
    perform private.set_worked_times(v_id);
  end loop;
  return v_count;
end;
$$;
revoke all on function private.auto_sign_off() from public;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    execute $job$
      select cron.schedule('clg-auto-sign-off', '*/15 * * * *', 'select private.auto_sign_off()')
    $job$;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- For admins: session times that need a look
-- ---------------------------------------------------------------------------
-- A different end time to confirm, a tutor not at the library, no location
-- check, or a past session nobody signed on to.
create or replace function public.list_times_to_check()
returns table (
  id uuid, starts_at timestamptz, ends_at timestamptz, student_name text, tutor_name text,
  subject text, delivery public.session_delivery, library_name text, status public.session_status,
  signed_on_at timestamptz, sign_on_check text, tutor_end_at timestamptz, tutor_time_note text, reason text
)
language sql stable security definer
set search_path = ''
as $$
  select x.id, x.starts_at, x.ends_at, s.full_name, a.full_name, x.subject, x.delivery, l.name, x.status,
         x.signed_on_at, x.sign_on_check, x.tutor_end_at, x.tutor_time_note,
         case
           when x.tutor_end_at is not null then 'different_end'
           when x.signed_on_at is null then 'not_signed_on'
           when x.sign_on_check = 'not_at_library' then 'not_at_library'
           else 'no_location'
         end
  from public.sessions x
  join public.students s on s.id = x.student_id
  join public.accounts a on a.id = x.tutor_id
  left join public.libraries l on l.id = x.library_id
  where private.is_admin()
    and x.times_confirmed_at is null
    and x.status in ('scheduled', 'completed')
    and x.starts_at > now() - interval '60 days'
    and (
      x.tutor_end_at is not null
      or (x.signed_on_at is null and x.ends_at <= now())
      or x.sign_on_check in ('not_at_library', 'no_location')
    )
  order by x.starts_at
$$;
revoke all on function public.list_times_to_check() from public, anon;
grant execute on function public.list_times_to_check() to authenticated;
