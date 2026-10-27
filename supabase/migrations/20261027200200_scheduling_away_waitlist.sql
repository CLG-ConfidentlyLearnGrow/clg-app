-- Scheduling part 2 (module: scheduling): away dates and the waitlist.
--
-- Away dates: a tutor, or a family for their child, enters dates they
-- can't make (holidays, camps, exams). Sessions already booked on those
-- dates are cancelled, recorded as cancelled by the tutor or the family at
-- the time the away dates were entered, so billing gives the right credit.
-- New bookings skip away dates.
--
-- Waitlist: when no tutor is free, the family can join the waitlist for
-- any suitable tutor (or a named one). Admins see who is waiting, how many
-- times would now suit, and who has waited 4 weeks or more.
--
-- See docs/features/scheduling.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Away dates
-- ---------------------------------------------------------------------------
create table if not exists public.away_dates (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid references public.tutor_profiles (account_id) on delete cascade,
  student_id uuid references public.students (id) on delete cascade,
  from_date date not null,
  to_date date not null,
  reason text check (char_length(reason) <= 300),
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  -- Either a tutor's or a student's, never both.
  check ((tutor_id is null) <> (student_id is null)),
  check (to_date >= from_date and to_date <= from_date + 366)
);
create index if not exists away_dates_tutor on public.away_dates (tutor_id, to_date);
create index if not exists away_dates_student on public.away_dates (student_id, to_date);

alter table public.away_dates enable row level security;
revoke all on public.away_dates from anon;
-- Added and removed only through the functions below.
revoke insert, update, delete, truncate on public.away_dates from authenticated;

drop trigger if exists audit on public.away_dates;
create trigger audit after insert or update or delete on public.away_dates
  for each row execute function private.audit_change();

-- A tutor sees their own; families see their child's; a student's tutors
-- see the student's (so they can plan); admins see all.
drop policy if exists "see relevant away dates" on public.away_dates;
create policy "see relevant away dates" on public.away_dates
  for select to authenticated using (
    private.is_admin()
    or (tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
    or (student_id is not null and private.can_view_student(student_id))
  );

-- Add away dates for a tutor (p_student null) or a student (p_tutor null).
-- Returns how many booked sessions were cancelled.
create or replace function public.add_away_dates(
  p_tutor uuid,
  p_student uuid,
  p_from date,
  p_to date,
  p_reason text default null
)
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if (p_tutor is null) = (p_student is null) then
    raise exception 'Choose a tutor or a student' using errcode = '22023';
  end if;
  if p_tutor is not null and not (
    private.is_admin() or (p_tutor = auth.uid() and private.has_role('tutor') and private.has_aal2())
  ) then
    raise exception 'You can only add your own away dates' using errcode = '42501';
  end if;
  if p_student is not null and not private.can_book_for(p_student) then
    raise exception 'You can only add away dates for your own children' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Choose a first and last date, in order' using errcode = '22023';
  end if;
  if p_to < current_date then
    raise exception 'Those dates have passed' using errcode = '22023';
  end if;
  if p_to > p_from + 366 then
    raise exception 'Away dates can cover up to a year' using errcode = '22023';
  end if;

  insert into public.away_dates (tutor_id, student_id, from_date, to_date, reason, created_by)
  values (p_tutor, p_student, greatest(p_from, current_date), p_to, nullif(left(trim(p_reason), 300), ''), auth.uid());

  -- Cancel booked sessions on those dates (local date of the session).
  update public.sessions x
  set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
      cancelled_by_role = case when p_tutor is not null then 'tutor' else 'family' end,
      cancel_reason = left(coalesce('Away: ' || nullif(trim(p_reason), ''), 'Away'), 500)
  from public.students s
  where s.id = x.student_id
    and x.status = 'scheduled'
    and x.starts_at > now()
    and (x.tutor_id = p_tutor or x.student_id = p_student)
    and (x.starts_at at time zone private.state_timezone(s.state))::date between p_from and p_to;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.add_away_dates(uuid, uuid, date, date, text) from public, anon;
grant execute on function public.add_away_dates(uuid, uuid, date, date, text) to authenticated;

-- Remove away dates. Sessions already cancelled stay cancelled (CLG can
-- rebook them); later bookings will no longer skip these dates.
create or replace function public.remove_away_dates(p_id uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_a public.away_dates;
begin
  select * into v_a from public.away_dates where id = p_id;
  if v_a.id is null or not (
    private.is_admin()
    or (v_a.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
    or (v_a.student_id is not null and private.can_book_for(v_a.student_id))
  ) then
    raise exception 'Away dates not found' using errcode = 'P0002';
  end if;
  delete from public.away_dates where id = p_id;
end;
$$;
revoke all on function public.remove_away_dates(uuid) from public, anon;
grant execute on function public.remove_away_dates(uuid) to authenticated;

-- Making the weekly sessions now skips the tutor's and student's away dates.
create or replace function private.make_sessions(p_booking uuid, p_from date default null)
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_b public.bookings;
  v_tz text;
  v_kind text;
  v_level text;
  v_count integer;
begin
  select * into v_b from public.bookings where id = p_booking;
  select private.state_timezone(s.state), s.year_level into v_tz, v_level
  from public.students s where s.id = v_b.student_id;
  v_kind := case when v_level in ('University or TAFE', 'Adult learner') then 'tertiary' else 'school' end;

  insert into public.sessions (
    booking_id, student_id, tutor_id, family_id, subject, level_kind,
    delivery, library_id, starts_at, ends_at
  )
  select v_b.id, v_b.student_id, v_b.tutor_id, v_b.family_id, v_b.subject, v_kind,
         v_b.delivery, v_b.library_id,
         (d::date + v_b.start_time) at time zone v_tz,
         (d::date + v_b.start_time + make_interval(mins => v_b.minutes)) at time zone v_tz
  from generate_series(v_b.first_date, v_b.last_date, interval '7 days') d
  where d::date >= greatest(coalesce(p_from, v_b.first_date), current_date)
    and not exists (
      select 1 from public.away_dates a
      where (a.tutor_id = v_b.tutor_id or a.student_id = v_b.student_id)
        and d::date between a.from_date and a.to_date
    )
  on conflict (booking_id, starts_at) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function private.make_sessions(uuid, date) from public;

-- How many weekly sessions a booking would have, after away dates. Shown
-- to the family before they send a request.
create or replace function public.count_booking_sessions(
  p_student uuid, p_tutor uuid, p_weekday smallint, p_first_date date, p_last_date date
)
returns table (sessions bigint, skipped bigint)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_first date;
begin
  if not private.can_book_for(p_student) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  v_first := p_first_date + ((p_weekday - extract(isodow from p_first_date)::int + 7) % 7);
  return query
    select count(*) filter (where not away), count(*) filter (where away)
    from (
      select exists (
        select 1 from public.away_dates a
        where (a.tutor_id = p_tutor or a.student_id = p_student)
          and d::date between a.from_date and a.to_date
      ) as away
      from generate_series(v_first, p_last_date, interval '7 days') d
    ) x;
end;
$$;
revoke all on function public.count_booking_sessions(uuid, uuid, smallint, date, date) from public, anon;
grant execute on function public.count_booking_sessions(uuid, uuid, smallint, date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- Waitlist
-- ---------------------------------------------------------------------------
create table if not exists public.waitlist (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  subject text not null check (char_length(subject) between 1 and 100),
  minutes integer not null check (minutes between 60 and 240 and minutes % 30 = 0),
  online boolean not null default true,
  library_ids uuid[] not null default '{}',
  weekdays smallint[],
  earliest time,
  latest time,
  -- A named tutor, if the family wants to wait for one person.
  tutor_id uuid references public.tutor_profiles (account_id) on delete set null,
  note text check (char_length(note) <= 1000),
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  closed_reason text check (closed_reason in ('booked', 'withdrawn', 'other')),
  check (online or cardinality(library_ids) > 0)
);
create index if not exists waitlist_open on public.waitlist (created_at) where closed_at is null;
-- One open place per student and subject.
create unique index if not exists waitlist_once
  on public.waitlist (student_id, lower(subject)) where closed_at is null;

alter table public.waitlist enable row level security;
revoke all on public.waitlist from anon;
revoke insert, update, delete, truncate on public.waitlist from authenticated;

drop trigger if exists audit on public.waitlist;
create trigger audit after insert or update or delete on public.waitlist
  for each row execute function private.audit_change();

drop policy if exists "see own waitlist places" on public.waitlist;
create policy "see own waitlist places" on public.waitlist
  for select to authenticated using (
    private.is_admin()
    or private.is_parent_of(student_id)
    or private.is_student_self(student_id)
  );

create or replace function public.join_waitlist(
  p_student uuid,
  p_subject text,
  p_minutes integer,
  p_online boolean,
  p_libraries uuid[] default '{}',
  p_weekdays smallint[] default null,
  p_earliest time default null,
  p_latest time default null,
  p_tutor uuid default null,
  p_note text default null
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not private.can_book_for(p_student) then
    raise exception 'You can only add your own children to the waitlist' using errcode = '42501';
  end if;
  if not coalesce(p_online, false) and coalesce(cardinality(p_libraries), 0) = 0 then
    raise exception 'Choose online, at least one library, or both' using errcode = '22023';
  end if;
  if p_minutes is null or p_minutes < 60 or p_minutes > 240 or p_minutes % 30 <> 0 then
    raise exception 'Sessions are 1 to 4 hours, in half-hour steps' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.waitlist
    where student_id = p_student and lower(subject) = lower(trim(p_subject)) and closed_at is null
  ) then
    raise exception 'Already on the waitlist for %', trim(p_subject) using errcode = '23505';
  end if;
  insert into public.waitlist (
    student_id, subject, minutes, online, library_ids, weekdays, earliest, latest, tutor_id, note, created_by
  ) values (
    p_student, trim(p_subject), p_minutes, coalesce(p_online, false), coalesce(p_libraries, '{}'),
    nullif(p_weekdays, '{}'), p_earliest, p_latest, p_tutor, nullif(left(trim(p_note), 1000), ''), auth.uid()
  )
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.join_waitlist(uuid, text, integer, boolean, uuid[], smallint[], time, time, uuid, text) from public, anon;
grant execute on function public.join_waitlist(uuid, text, integer, boolean, uuid[], smallint[], time, time, uuid, text) to authenticated;

create or replace function public.leave_waitlist(p_id uuid, p_reason text default 'withdrawn')
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_w public.waitlist;
begin
  select * into v_w from public.waitlist where id = p_id for update;
  if v_w.id is null or not private.can_book_for(v_w.student_id) then
    raise exception 'Waitlist place not found' using errcode = 'P0002';
  end if;
  if v_w.closed_at is not null then
    return;
  end if;
  if p_reason not in ('booked', 'withdrawn', 'other') then
    raise exception 'Reason must be booked, withdrawn or other' using errcode = '22023';
  end if;
  update public.waitlist set closed_at = now(), closed_reason = p_reason where id = p_id;
end;
$$;
revoke all on function public.leave_waitlist(uuid, text) from public, anon;
grant execute on function public.leave_waitlist(uuid, text) to authenticated;

-- A family's place closes by itself when they book that subject.
create or replace function private.close_waitlist_on_booking()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  update public.waitlist
  set closed_at = now(), closed_reason = 'booked'
  where student_id = new.student_id and lower(subject) = lower(new.subject) and closed_at is null;
  return new;
end;
$$;
drop trigger if exists close_waitlist on public.bookings;
create trigger close_waitlist after insert on public.bookings
  for each row execute function private.close_waitlist_on_booking();

-- Open waitlist places with names, how many times now suit, and whether
-- the place is 4 weeks old (time to check in with the family).
create or replace function public.list_waitlist()
returns table (
  id uuid, student_id uuid, student_name text, year_level text, subject text, minutes integer,
  online boolean, library_names text[], weekdays smallint[], earliest time, latest time,
  tutor_name text, note text, created_at timestamptz, waited_4_weeks boolean, times_now_free bigint
)
language sql stable security definer
set search_path = ''
as $$
  select w.id, w.student_id, s.full_name, s.year_level, w.subject, w.minutes,
         w.online,
         array(select l.name from public.libraries l where l.id = any (w.library_ids) order by l.name),
         w.weekdays, w.earliest, w.latest, a.full_name, w.note, w.created_at,
         w.created_at <= now() - interval '28 days',
         (select count(*) from public.find_session_times(
            w.student_id, w.subject, w.minutes, w.online, w.library_ids, null,
            w.weekdays, w.earliest, w.latest) f
          where w.tutor_id is null or f.tutor_id = w.tutor_id)
  from public.waitlist w
  join public.students s on s.id = w.student_id
  left join public.accounts a on a.id = w.tutor_id
  where w.closed_at is null
    and (private.is_admin() or private.can_book_for(w.student_id))
  order by w.created_at
$$;
revoke all on function public.list_waitlist() from public, anon;
grant execute on function public.list_waitlist() to authenticated;
