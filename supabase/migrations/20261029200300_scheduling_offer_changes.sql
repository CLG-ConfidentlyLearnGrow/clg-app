-- Scheduling part 8 (module: scheduling): learning from changed suggestions.
--
-- When an admin offers a time, the app suggests the best tutor, time and
-- place first (from the family's saved places, tutors with learning-support
-- experience first, then times that join a tutor's other sessions). The
-- admin approves it or picks another. When they pick another, the app keeps
-- the suggestion, what was chosen instead and why, so CLG can see patterns
-- and improve the suggestions.
--
-- See docs/features/scheduling.md. Safe to run more than once.

create table if not exists public.offer_changes (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id) on delete cascade,
  suggested_tutor uuid references public.tutor_profiles (account_id) on delete set null,
  suggested_weekday smallint check (suggested_weekday between 1 and 7),
  suggested_start time,
  suggested_delivery public.session_delivery,
  suggested_library uuid references public.libraries (id) on delete set null,
  reason text not null check (reason in ('tutor_fit', 'family_request', 'tutor_request', 'time', 'place', 'other')),
  note text check (char_length(note) <= 500),
  changed_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists offer_changes_booking on public.offer_changes (booking_id);

alter table public.offer_changes enable row level security;
revoke all on public.offer_changes from anon;
revoke insert, update, delete, truncate on public.offer_changes from authenticated;
drop policy if exists "admins see offer changes" on public.offer_changes;
create policy "admins see offer changes" on public.offer_changes
  for select to authenticated using (private.is_admin());

-- Records why an admin chose something other than the suggestion.
create or replace function public.record_offer_change(
  p_booking uuid,
  p_suggested_tutor uuid,
  p_suggested_weekday smallint,
  p_suggested_start time,
  p_suggested_delivery public.session_delivery,
  p_suggested_library uuid,
  p_reason text,
  p_note text default null
)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only CLG admins can record this' using errcode = '42501';
  end if;
  if not exists (select 1 from public.bookings where id = p_booking) then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  if p_reason is null or p_reason not in ('tutor_fit', 'family_request', 'tutor_request', 'time', 'place', 'other') then
    raise exception 'Please choose why the suggestion was changed' using errcode = '22023';
  end if;
  insert into public.offer_changes (
    booking_id, suggested_tutor, suggested_weekday, suggested_start, suggested_delivery, suggested_library,
    reason, note, changed_by
  ) values (
    p_booking, p_suggested_tutor, p_suggested_weekday, p_suggested_start, p_suggested_delivery, p_suggested_library,
    p_reason, nullif(left(trim(p_note), 500), ''), auth.uid()
  );
end;
$$;
revoke all on function public.record_offer_change(uuid, uuid, smallint, time, public.session_delivery, uuid, text, text) from public, anon;
grant execute on function public.record_offer_change(uuid, uuid, smallint, time, public.session_delivery, uuid, text, text) to authenticated;

-- Why suggestions were changed, most common first, with recent notes.
create or replace function public.offer_change_reasons(p_days integer default 90)
returns table (reason text, changes bigint, recent_notes text[])
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return query
    select c.reason, count(*),
           (array_agg(c.note order by c.created_at desc) filter (where c.note is not null))[1:5]
    from public.offer_changes c
    where c.created_at >= now() - make_interval(days => greatest(coalesce(p_days, 90), 1))
    group by c.reason
    order by count(*) desc;
end;
$$;
revoke all on function public.offer_change_reasons(integer) from public, anon;
grant execute on function public.offer_change_reasons(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Preferred days and times (preferences, not guarantees)
-- ---------------------------------------------------------------------------
alter table public.student_places add column if not exists preferred_days smallint[];
alter table public.student_places add column if not exists preferred_from time;
alter table public.student_places add column if not exists preferred_to time;
-- Support during school hours (9am to 3pm, Monday to Friday), for example
-- for home-schooled students or flexible learning.
alter table public.student_places add column if not exists preferred_school_hours boolean not null default false;
alter table public.student_places drop constraint if exists student_places_preferred_days;
alter table public.student_places add constraint student_places_preferred_days
  check (preferred_days is null or preferred_days <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]);

-- Free times, as find_session_times, with the family's preferred days and
-- times first. The first row is the app's suggestion.
create or replace function public.offer_options(
  p_student uuid,
  p_subject text,
  p_minutes integer,
  p_online boolean,
  p_libraries uuid[] default '{}',
  p_first_date date default null,
  p_weekdays smallint[] default null,
  p_earliest time default null,
  p_latest time default null
)
returns table (
  tutor_id uuid, tutor_name text, weekday smallint, start_time time, end_time time,
  delivery public.session_delivery, library_id uuid, library_name text,
  joins_other_sessions boolean, learning_support boolean, preferred boolean
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_p public.student_places;
begin
  select * into v_p from public.student_places where student_id = p_student;
  return query
    select f.tutor_id, f.tutor_name, f.weekday, f.start_time, f.end_time, f.delivery, f.library_id,
           f.library_name, f.joins_other_sessions, f.learning_support,
           coalesce(
             ((v_p.preferred_days is not null or v_p.preferred_from is not null or v_p.preferred_to is not null)
              and (v_p.preferred_days is null or f.weekday = any (v_p.preferred_days))
              and (v_p.preferred_from is null or f.start_time >= v_p.preferred_from)
              and (v_p.preferred_to is null or f.end_time <= v_p.preferred_to))
             or (v_p.preferred_school_hours and f.weekday between 1 and 5
                 and f.start_time >= time '09:00' and f.end_time <= time '15:00'),
             false) as preferred
    from public.find_session_times(p_student, p_subject, p_minutes, p_online, p_libraries,
                                   p_first_date, p_weekdays, p_earliest, p_latest)
         with ordinality as f
    order by 11 desc, f.ordinality;
end;
$$;
revoke all on function public.offer_options(uuid, text, integer, boolean, uuid[], date, smallint[], time, time) from public, anon;
grant execute on function public.offer_options(uuid, text, integer, boolean, uuid[], date, smallint[], time, time) to authenticated;
