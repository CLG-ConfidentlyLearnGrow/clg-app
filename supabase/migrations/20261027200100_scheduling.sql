-- Scheduling and tutor matching (module: scheduling).
--
-- A family (or an admin, during the pilot) picks a subject, how long, and
-- where: online or at libraries they tick. The app shows only tutors who
-- are cleared for the student's state, teach that subject at the student's
-- year level, and are free at that time. The family picks a time, which
-- sends the tutor a request. The tutor has 48 hours to accept. On accepting,
-- the tutor is assigned to the student and every weekly session up to the
-- booking's last date is created.
--
-- This module owns: libraries, tutor_places, tutor_session_settings,
-- bookings, sessions. Billing reads sessions but never writes them.
-- See docs/features/scheduling.md.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'session_delivery' and typnamespace = 'public'::regnamespace) then
    -- home: only an admin can book it, for special circumstances.
    create type public.session_delivery as enum ('online', 'library', 'home');
  end if;
  if not exists (select 1 from pg_type where typname = 'booking_status' and typnamespace = 'public'::regnamespace) then
    -- requested: the family has chosen a time and the tutor has 48 hours to
    -- accept. A request past its reply time counts as expired.
    create type public.booking_status as enum ('requested', 'confirmed', 'declined', 'cancelled', 'ended');
  end if;
  if not exists (select 1 from pg_type where typname = 'session_status' and typnamespace = 'public'::regnamespace) then
    create type public.session_status as enum ('scheduled', 'completed', 'cancelled', 'no_show');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Places: public libraries (CLG's office can be added as a place later)
-- ---------------------------------------------------------------------------
create table if not exists public.libraries (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 200),
  suburb text check (char_length(suburb) <= 100),
  address text check (char_length(address) <= 300),
  state public.au_state not null default 'SA',
  latitude numeric(9, 6) check (latitude between -90 and 90),
  longitude numeric(9, 6) check (longitude between -180 and 180),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists libraries_name_once on public.libraries (lower(name), state);

-- Libraries a tutor is happy to work at.
create table if not exists public.tutor_places (
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade,
  library_id uuid not null references public.libraries (id) on delete cascade,
  primary key (tutor_id, library_id)
);

-- How a tutor works: online, in person, and whether they have experience
-- with learning difficulties (ranked first for students who need it).
create table if not exists public.tutor_session_settings (
  tutor_id uuid primary key references public.tutor_profiles (account_id) on delete cascade,
  online boolean not null default true,
  in_person boolean not null default true,
  learning_support boolean not null default false,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Bookings: the weekly arrangement. Sessions: each single lesson.
-- ---------------------------------------------------------------------------
create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade,
  family_id uuid references public.families (id) on delete set null,
  subject text not null check (char_length(subject) between 1 and 100),
  weekday smallint not null check (weekday between 1 and 7), -- 1 = Monday
  start_time time not null,
  -- 1-hour minimum, in half-hour steps, up to 4 hours.
  minutes integer not null check (minutes between 60 and 240 and minutes % 30 = 0),
  delivery public.session_delivery not null,
  -- A library in use can't be deleted; mark it inactive instead.
  library_id uuid references public.libraries (id) on delete restrict,
  first_date date not null,
  last_date date not null,
  status public.booking_status not null default 'requested',
  family_note text check (char_length(family_note) <= 1000),
  tutor_note text check (char_length(tutor_note) <= 1000),
  requested_by uuid references public.accounts (id) on delete set null,
  requested_at timestamptz not null default now(),
  tutor_reply_by timestamptz not null default now() + interval '48 hours',
  confirmed_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  check (last_date >= first_date and last_date <= first_date + 400),
  -- a library session names its library; others name none
  check ((delivery = 'library') = (library_id is not null))
);
create index if not exists bookings_tutor on public.bookings (tutor_id, weekday);
create index if not exists bookings_student on public.bookings (student_id);
-- When CLG offers a time (an admin books for a family), the tutor and the
-- family both approve, in either order. The booking stays "requested"
-- (shown as waiting for confirmation) until both have said yes, within the
-- same 48 hours (tutor_reply_by).
alter table public.bookings add column if not exists needs_family_ok boolean not null default false;
alter table public.bookings add column if not exists tutor_ok_at timestamptz;
alter table public.bookings add column if not exists family_ok_at timestamptz;
alter table public.bookings add column if not exists family_ok_by uuid references public.accounts (id) on delete set null;
alter table public.bookings add column if not exists declined_by_role text check (declined_by_role in ('tutor', 'family', 'admin'));

create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references public.bookings (id) on delete set null,
  student_id uuid not null references public.students (id) on delete cascade,
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade,
  family_id uuid references public.families (id) on delete set null,
  subject text not null check (char_length(subject) between 1 and 100),
  -- school or tertiary: decides the price and the award (billing reads it).
  level_kind text not null check (level_kind in ('school', 'tertiary')),
  delivery public.session_delivery not null,
  library_id uuid references public.libraries (id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status public.session_status not null default 'scheduled',
  cancelled_at timestamptz,
  cancelled_by uuid references public.accounts (id) on delete set null,
  cancelled_by_role text check (cancelled_by_role in ('family', 'tutor', 'admin')),
  cancel_reason text check (char_length(cancel_reason) <= 500),
  completed_at timestamptz,
  -- Teams link, filled in by a later step.
  meeting_url text check (char_length(meeting_url) <= 2000),
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check ((status = 'cancelled') = (cancelled_at is not null))
);
create index if not exists sessions_tutor on public.sessions (tutor_id, starts_at);
create index if not exists sessions_student on public.sessions (student_id, starts_at);
create index if not exists sessions_family on public.sessions (family_id, starts_at);
create unique index if not exists sessions_once_per_booking on public.sessions (booking_id, starts_at);

alter table public.libraries enable row level security;
alter table public.tutor_places enable row level security;
alter table public.tutor_session_settings enable row level security;
alter table public.bookings enable row level security;
alter table public.sessions enable row level security;
revoke all on public.libraries, public.tutor_places, public.tutor_session_settings,
  public.bookings, public.sessions from anon;
-- Bookings and sessions change only through the functions below.
revoke insert, update, delete, truncate on public.bookings, public.sessions from authenticated;

drop trigger if exists audit on public.libraries;
create trigger audit after insert or update or delete on public.libraries
  for each row execute function private.audit_change();
drop trigger if exists audit on public.tutor_places;
create trigger audit after insert or update or delete on public.tutor_places
  for each row execute function private.audit_change();
drop trigger if exists audit on public.tutor_session_settings;
create trigger audit after insert or update or delete on public.tutor_session_settings
  for each row execute function private.audit_change();
drop trigger if exists audit on public.bookings;
create trigger audit after insert or update or delete on public.bookings
  for each row execute function private.audit_change();
drop trigger if exists audit on public.sessions;
create trigger audit after insert or update or delete on public.sessions
  for each row execute function private.audit_change();
drop trigger if exists touch on public.tutor_session_settings;
create trigger touch before update on public.tutor_session_settings
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Access rules
-- ---------------------------------------------------------------------------
drop policy if exists "signed in people see active libraries" on public.libraries;
create policy "signed in people see active libraries" on public.libraries
  for select to authenticated using (active or private.is_admin());
drop policy if exists "admins manage libraries" on public.libraries;
create policy "admins manage libraries" on public.libraries
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

drop policy if exists "tutors see own places, admins see all" on public.tutor_places;
create policy "tutors see own places, admins see all" on public.tutor_places
  for select to authenticated using (tutor_id = auth.uid() or private.is_admin());
drop policy if exists "tutors manage own places" on public.tutor_places;
create policy "tutors manage own places" on public.tutor_places
  for all to authenticated
  using ((tutor_id = auth.uid() and private.has_aal2()) or private.is_admin())
  with check ((tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2()) or private.is_admin());

drop policy if exists "tutors see own settings, admins see all" on public.tutor_session_settings;
create policy "tutors see own settings, admins see all" on public.tutor_session_settings
  for select to authenticated using (tutor_id = auth.uid() or private.is_admin());
drop policy if exists "tutors manage own settings" on public.tutor_session_settings;
create policy "tutors manage own settings" on public.tutor_session_settings
  for all to authenticated
  using ((tutor_id = auth.uid() and private.has_aal2()) or private.is_admin())
  with check ((tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2()) or private.is_admin());

drop policy if exists "see own bookings" on public.bookings;
create policy "see own bookings" on public.bookings
  for select to authenticated using (
    private.is_admin()
    or (tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
    or private.is_parent_of(student_id)
    or private.is_student_self(student_id)
  );

drop policy if exists "see own sessions" on public.sessions;
create policy "see own sessions" on public.sessions
  for select to authenticated using (
    private.is_admin()
    or (tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
    or private.is_parent_of(student_id)
    or private.is_student_self(student_id)
  );

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Local time zone for a state. Session times are entered in the student's
-- local time.
create or replace function private.state_timezone(p_state public.au_state)
returns text language sql immutable
set search_path = ''
as $$
  select case p_state
    when 'SA' then 'Australia/Adelaide'
    when 'NSW' then 'Australia/Sydney'
    when 'VIC' then 'Australia/Melbourne'
    when 'QLD' then 'Australia/Brisbane'
    when 'WA' then 'Australia/Perth'
    when 'TAS' then 'Australia/Hobart'
    when 'ACT' then 'Australia/Sydney'
    when 'NT' then 'Australia/Darwin'
  end
$$;

-- Is a booking still holding its time? Confirmed bookings do; requests do
-- until the tutor's 48 hours run out.
create or replace function private.booking_is_live(p_status public.booking_status, p_reply_by timestamptz)
returns boolean language sql stable
set search_path = ''
as $$ select p_status = 'confirmed' or (p_status = 'requested' and p_reply_by > now()) $$;

-- Is this family paused for an overdue payment? Billing provides
-- private.billing_family_paused; until it exists nobody is paused.
create or replace function private.family_paused(p_family uuid)
returns boolean language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_paused boolean := false;
begin
  if p_family is not null and to_regprocedure('private.billing_family_paused(uuid)') is not null then
    execute 'select private.billing_family_paused($1)' into v_paused using p_family;
  end if;
  return coalesce(v_paused, false);
end;
$$;

-- Who may book for this student: an admin, a parent who manages them, or
-- the student themselves (own login from 16).
create or replace function private.can_book_for(p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select private.is_admin()
    or private.can_manage_student(p_student)
    or private.is_student_self(p_student)
$$;

-- ---------------------------------------------------------------------------
-- Finding a time
-- ---------------------------------------------------------------------------

-- The level a tutor must teach for this student and subject: the level the
-- student is working at in that subject if the family gave one, otherwise
-- their school year level.
create or replace function private.matching_level(p_student uuid, p_subject text)
returns text language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select ss.working_level from public.student_subjects ss
     where ss.student_id = p_student and lower(trim(ss.subject)) = lower(trim(p_subject))
       and ss.working_level is not null
     limit 1),
    (select s.year_level from public.students s where s.id = p_student)
  )
$$;

-- Every free weekly time, with a tutor who can take it. A tutor is listed
-- only when they are:
--   * cleared for the student's state (checks verified and in date),
--   * teaching the subject at the student's working level (or year level),
--   * available then (their weekly availability), and not already booked,
--   * under their maximum weekly hours,
--   * willing to work that way (online, or at one of the chosen libraries),
--   * not at a different library that day (a tutor stays at one library a
--     day; online sessions on a library day are fine).
-- Tutors with learning-support experience come first for students with
-- learning needs on record, then times that join onto a tutor's other
-- sessions (so tutors get blocks of 2 hours or more, as the awards expect).
create or replace function public.find_session_times(
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
  tutor_id uuid,
  tutor_name text,
  weekday smallint,
  start_time time,
  end_time time,
  delivery public.session_delivery,
  library_id uuid,
  library_name text,
  joins_other_sessions boolean,
  learning_support boolean
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_level text;
  v_first date := greatest(coalesce(p_first_date, current_date), current_date);
  v_needs boolean;
begin
  if not private.can_book_for(p_student) then
    raise exception 'You can only look for times for your own children' using errcode = '42501';
  end if;
  if p_minutes is null or p_minutes < 60 or p_minutes > 240 or p_minutes % 30 <> 0 then
    raise exception 'Sessions are 1 to 4 hours, in half-hour steps' using errcode = '22023';
  end if;
  if not coalesce(p_online, false) and coalesce(cardinality(p_libraries), 0) = 0 then
    raise exception 'Choose online, at least one library, or both' using errcode = '22023';
  end if;

  -- Match on the level the student is working at in this subject.
  v_level := private.matching_level(p_student, p_subject);
  if v_level is null then
    raise exception 'Add the student''s year level first' using errcode = '22023';
  end if;
  select exists (
    select 1 from public.student_sensitive x
    where x.student_id = p_student and nullif(trim(x.learning_needs), '') is not null
  ) into v_needs;

  return query
  with tutors as (
    select t.account_id as tid, a.full_name, w.max_weekly_hours,
           coalesce(ss.online, true) as can_online,
           coalesce(ss.in_person, true) as can_in_person,
           coalesce(ss.learning_support, false) as ls
    from public.tutor_profiles t
    join public.accounts a on a.id = t.account_id
    left join public.tutor_work_settings w on w.tutor_id = t.account_id
    left join public.tutor_session_settings ss on ss.tutor_id = t.account_id
    where t.active
      and private.tutor_cleared_for_student(t.account_id, p_student)
      and private.tutor_teaches(t.account_id, p_subject, v_level)
  ),
  -- What each tutor already has booked (from the first date on).
  busy as (
    select b.tutor_id as tid, b.student_id, b.weekday, b.start_time,
           b.start_time + make_interval(mins => b.minutes) as end_time,
           b.minutes, b.delivery, b.library_id
    from public.bookings b
    where private.booking_is_live(b.status, b.tutor_reply_by)
      and b.last_date >= v_first
  ),
  hours as (
    select tid, sum(minutes) as booked from busy group by tid
  ),
  -- Candidate start times every half hour inside each availability slot.
  slots as (
    select tu.tid, av.weekday,
           g::time as st
    from tutors tu
    join public.tutor_availability av on av.tutor_id = tu.tid
    cross join lateral generate_series(
      date '2000-01-01' + av.starts_at,
      date '2000-01-01' + av.ends_at - make_interval(mins => p_minutes),
      interval '30 minutes') g
    where (p_weekdays is null or av.weekday = any (p_weekdays))
  ),
  options as (
    -- Online
    select s.tid, s.weekday, s.st, 'online'::public.session_delivery as dl, null::uuid as lib
    from slots s join tutors tu on tu.tid = s.tid
    where p_online and tu.can_online
    union all
    -- At a library both the family and the tutor chose
    select s.tid, s.weekday, s.st, 'library'::public.session_delivery, tp.library_id
    from slots s
    join tutors tu on tu.tid = s.tid
    join public.tutor_places tp on tp.tutor_id = s.tid
    join public.libraries l on l.id = tp.library_id and l.active
    where tu.can_in_person and tp.library_id = any (coalesce(p_libraries, '{}'))
  )
  select o.tid, tu.full_name, o.weekday, o.st,
         o.st + make_interval(mins => p_minutes),
         o.dl, o.lib, l.name,
         exists (
           select 1 from busy b
           where b.tid = o.tid and b.weekday = o.weekday
             and (b.end_time = o.st or b.start_time = o.st + make_interval(mins => p_minutes))
         ),
         tu.ls
  from options o
  join tutors tu on tu.tid = o.tid
  left join public.libraries l on l.id = o.lib
  left join hours h on h.tid = o.tid
  where (p_earliest is null or o.st >= p_earliest)
    and (p_latest is null or o.st + make_interval(mins => p_minutes) <= p_latest)
    -- the start time can't pass midnight
    and o.st + make_interval(mins => p_minutes) > o.st
    -- under the weekly hour limit
    and (tu.max_weekly_hours is null
         or coalesce(h.booked, 0) + p_minutes <= tu.max_weekly_hours * 60)
    -- the tutor is free then
    and not exists (
      select 1 from busy b
      where b.tid = o.tid and b.weekday = o.weekday
        and b.start_time < o.st + make_interval(mins => p_minutes)
        and b.end_time > o.st
    )
    -- the student is free then
    and not exists (
      select 1 from busy b
      where b.student_id = p_student and b.weekday = o.weekday
        and b.start_time < o.st + make_interval(mins => p_minutes)
        and b.end_time > o.st
    )
    -- one library per day
    and (o.dl <> 'library' or not exists (
      select 1 from busy b
      where b.tid = o.tid and b.weekday = o.weekday
        and b.delivery = 'library' and b.library_id is distinct from o.lib
    ))
  order by (v_needs and tu.ls) desc, 9 desc, o.weekday, o.st, tu.full_name, o.dl;
end;
$$;
revoke all on function public.find_session_times(uuid, text, integer, boolean, uuid[], date, smallint[], time, time) from public, anon;
grant execute on function public.find_session_times(uuid, text, integer, boolean, uuid[], date, smallint[], time, time) to authenticated;

-- ---------------------------------------------------------------------------
-- Asking for a booking (the family confirms first)
-- ---------------------------------------------------------------------------
create or replace function public.request_booking(
  p_student uuid,
  p_subject text,
  p_tutor uuid,
  p_weekday smallint,
  p_start time,
  p_minutes integer,
  p_delivery public.session_delivery,
  p_library uuid,
  p_first_date date,
  p_last_date date,
  p_note text default null
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_student public.students;
  v_first date;
  v_id uuid;
begin
  if not private.can_book_for(p_student) then
    raise exception 'You can only book for your own children' using errcode = '42501';
  end if;
  select * into v_student from public.students where id = p_student;

  if private.family_paused(v_student.family_id) then
    raise exception 'Bookings are paused while a payment is overdue. Please contact CLG.' using errcode = '42501';
  end if;
  if v_student.date_of_birth > (current_date - interval '18 years')::date and not exists (
    select 1 from public.parent_student_links
    where student_id = p_student and verified_at is not null
  ) then
    raise exception 'CLG needs to confirm the parent link first. We''ll be in touch soon.' using errcode = '23514';
  end if;
  if not private.is_admin() and not exists (
    select 1 from public.student_subjects ss
    where ss.student_id = p_student and lower(ss.subject) = lower(trim(p_subject))
  ) then
    raise exception 'Add % to the student''s subjects first', trim(p_subject) using errcode = '22023';
  end if;
  if p_delivery = 'home' and not private.is_admin() then
    raise exception 'Sessions are online or at a library. Please contact CLG about home sessions.' using errcode = '42501';
  end if;
  if p_first_date is null or p_last_date is null then
    raise exception 'Choose a first and last date' using errcode = '22023';
  end if;
  if p_first_date < current_date then
    raise exception 'The first date can''t be in the past' using errcode = '22023';
  end if;

  -- The first session falls on the chosen weekday, on or after the first date.
  v_first := p_first_date + ((p_weekday - extract(isodow from p_first_date)::int + 7) % 7);
  if p_last_date < v_first then
    raise exception 'The last date is before the first session' using errcode = '22023';
  end if;
  if p_last_date > v_first + 400 then
    raise exception 'Bookings can run for up to about a year' using errcode = '22023';
  end if;

  -- The time must still be free with this tutor (an admin booking at home
  -- skips the place check but not the tutor's checks).
  if p_delivery = 'home' then
    if not (private.tutor_cleared_for_student(p_tutor, p_student)
            and private.tutor_teaches(p_tutor, p_subject, private.matching_level(p_student, p_subject))) then
      raise exception 'This tutor can''t take this student for %', p_subject using errcode = '23514';
    end if;
  elsif not exists (
    select 1 from public.find_session_times(
      p_student, p_subject, p_minutes, p_delivery = 'online',
      case when p_library is null then '{}'::uuid[] else array[p_library] end,
      v_first, array[p_weekday], p_start, null) f
    where f.tutor_id = p_tutor and f.weekday = p_weekday and f.start_time = p_start
      and f.delivery = p_delivery and f.library_id is not distinct from p_library
  ) then
    raise exception 'Sorry, that time is no longer available. Please pick another.' using errcode = '23514';
  end if;

  insert into public.bookings (
    student_id, tutor_id, family_id, subject, weekday, start_time, minutes,
    delivery, library_id, first_date, last_date, family_note, requested_by, needs_family_ok
  ) values (
    p_student, p_tutor, v_student.family_id, trim(p_subject), p_weekday, p_start, p_minutes,
    p_delivery, case when p_delivery = 'library' then p_library end, v_first, p_last_date,
    nullif(left(trim(p_note), 1000), ''), auth.uid(),
    -- An admin booking for someone else's child: the family approves too.
    private.is_admin() and not private.can_manage_student(p_student) and not private.is_student_self(p_student)
  )
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.request_booking(uuid, text, uuid, smallint, time, integer, public.session_delivery, uuid, date, date, text) from public, anon;
grant execute on function public.request_booking(uuid, text, uuid, smallint, time, integer, public.session_delivery, uuid, date, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Making the weekly sessions
-- ---------------------------------------------------------------------------
-- Makes a booking's weekly sessions.
-- Later migrations replace this function, so it's only created here when
-- missing. Running this file again won't undo their changes.
do $guard$
begin
  if to_regprocedure('private.make_sessions(uuid, date)') is null then
    execute $fn$
create function private.make_sessions(p_booking uuid, p_from date default null)
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
  on conflict (booking_id, starts_at) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
    $fn$;
  end if;
end;
$guard$;
revoke all on function private.make_sessions(uuid, date) from public;

-- ---------------------------------------------------------------------------
-- The tutor accepts or declines
-- ---------------------------------------------------------------------------
-- Confirms a booking once everyone needed has said yes: assigns the tutor
-- and makes the weekly sessions.
create or replace function private.confirm_booking(p_booking uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_b public.bookings;
  v_assignment uuid;
begin
  select * into v_b from public.bookings where id = p_booking for update;
  if private.family_paused(v_b.family_id) then
    raise exception 'This family''s bookings are paused for an overdue payment. CLG will be in touch.' using errcode = '23514';
  end if;

  -- Another booking may have taken the time since it was offered.
  if exists (
    select 1 from public.bookings o
    where o.id <> v_b.id and o.status = 'confirmed'
      and (o.tutor_id = v_b.tutor_id or o.student_id = v_b.student_id)
      and o.weekday = v_b.weekday
      and o.first_date <= v_b.last_date and o.last_date >= v_b.first_date
      and o.start_time < v_b.start_time + make_interval(mins => v_b.minutes)
      and o.start_time + make_interval(mins => o.minutes) > v_b.start_time
  ) then
    raise exception 'This time now clashes with another confirmed booking' using errcode = '23514';
  end if;

  -- Assign the tutor (or extend a current assignment for this subject). The
  -- core checks on assignments (cleared, teaches the subject, parent link
  -- verified) run here too.
  select a.id into v_assignment
  from public.tutor_assignments a
  where a.tutor_id = v_b.tutor_id and a.student_id = v_b.student_id
    and lower(a.subject) = lower(v_b.subject)
    and private.assignment_is_current(a.starts_on, a.ends_on)
  limit 1;
  if v_assignment is null then
    insert into public.tutor_assignments (tutor_id, student_id, subject, starts_on, ends_on, created_by)
    values (v_b.tutor_id, v_b.student_id, v_b.subject, current_date, v_b.last_date, auth.uid());
  else
    update public.tutor_assignments
    set ends_on = case when ends_on is null then null else greatest(ends_on, v_b.last_date) end
    where id = v_assignment;
  end if;

  update public.bookings set status = 'confirmed', confirmed_at = now() where id = p_booking;
  perform private.make_sessions(p_booking);
end;
$$;
revoke all on function private.confirm_booking(uuid) from public;

-- The tutor (or an admin for them) accepts or declines. When the family
-- must approve too and hasn't yet, accepting records the tutor's yes and
-- the booking waits for the family.
create or replace function public.respond_to_booking(p_booking uuid, p_accept boolean, p_note text default null)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_b public.bookings;
begin
  select * into v_b from public.bookings where id = p_booking for update;
  if v_b.id is null or not (
    private.is_admin()
    or (v_b.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
  ) then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  if v_b.status <> 'requested' or v_b.tutor_ok_at is not null then
    raise exception 'This request has already been answered' using errcode = '22023';
  end if;
  if v_b.tutor_reply_by < now() and not private.is_admin() then
    raise exception 'This request has expired. CLG will offer the family other times.' using errcode = '22023';
  end if;

  if not p_accept then
    update public.bookings
    set status = 'declined', declined_by_role = 'tutor', tutor_note = nullif(left(trim(p_note), 1000), '')
    where id = p_booking;
    return;
  end if;

  if private.family_paused(v_b.family_id) then
    raise exception 'This family''s bookings are paused for an overdue payment. CLG will be in touch.' using errcode = '23514';
  end if;
  update public.bookings
  set tutor_ok_at = now(), tutor_note = nullif(left(trim(p_note), 1000), '')
  where id = p_booking;
  if not v_b.needs_family_ok or v_b.family_ok_at is not null then
    perform private.confirm_booking(p_booking);
  end if;
end;
$$;
revoke all on function public.respond_to_booking(uuid, boolean, text) from public, anon;
grant execute on function public.respond_to_booking(uuid, boolean, text) to authenticated;

-- The family (or an admin for them) approves or declines a time CLG
-- offered. Once the tutor has also said yes, the booking is confirmed.
create or replace function public.approve_booking(p_booking uuid, p_ok boolean, p_note text default null)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_b public.bookings;
begin
  select * into v_b from public.bookings where id = p_booking for update;
  if v_b.id is null or not private.can_book_for(v_b.student_id) then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  if v_b.status <> 'requested' or not v_b.needs_family_ok or v_b.family_ok_at is not null then
    raise exception 'This has already been answered' using errcode = '22023';
  end if;
  if v_b.tutor_reply_by < now() and not private.is_admin() then
    raise exception 'This offer has expired. CLG will be in touch with other times.' using errcode = '22023';
  end if;

  if not p_ok then
    update public.bookings
    set status = 'declined', declined_by_role = 'family',
        family_note = coalesce(nullif(left(trim(p_note), 1000), ''), family_note)
    where id = p_booking;
    return;
  end if;

  if private.family_paused(v_b.family_id) then
    raise exception 'Bookings are paused while a payment is overdue. Please contact CLG.' using errcode = '23514';
  end if;
  update public.bookings
  set family_ok_at = now(), family_ok_by = auth.uid(),
      family_note = coalesce(nullif(left(trim(p_note), 1000), ''), family_note)
  where id = p_booking;
  if v_b.tutor_ok_at is not null then
    perform private.confirm_booking(p_booking);
  end if;
end;
$$;
revoke all on function public.approve_booking(uuid, boolean, text) from public, anon;
grant execute on function public.approve_booking(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Cancelling
-- ---------------------------------------------------------------------------

-- Who is cancelling, for credits and pay: the tutor, the family, or CLG.
-- An admin acting for a family or tutor passes p_for.
create or replace function private.cancel_role(p_student uuid, p_tutor uuid, p_for text)
returns text language plpgsql stable security definer
set search_path = ''
as $$
begin
  if private.is_admin() then
    if p_for is not null and p_for not in ('family', 'tutor', 'admin') then
      raise exception 'Cancelling for must be family, tutor or admin' using errcode = '22023';
    end if;
    return coalesce(p_for, 'admin');
  elsif p_for is not null then
    raise exception 'Only CLG staff can cancel on someone else''s behalf' using errcode = '42501';
  elsif p_tutor = auth.uid() and private.has_role('tutor') and private.has_aal2() then
    return 'tutor';
  elsif private.can_book_for(p_student) then
    return 'family';
  end if;
  return null;
end;
$$;

-- Cancel one session. It must not have started. Billing works out any
-- credit from cancelled_at and cancelled_by_role.
create or replace function public.cancel_session(p_session uuid, p_reason text default null, p_for text default null)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_s public.sessions;
  v_role text;
begin
  select * into v_s from public.sessions where id = p_session for update;
  v_role := case when v_s.id is null then null else private.cancel_role(v_s.student_id, v_s.tutor_id, p_for) end;
  if v_role is null then
    raise exception 'Session not found' using errcode = 'P0002';
  end if;
  if v_s.status <> 'scheduled' then
    raise exception 'This session is already %', replace(v_s.status::text, '_', ' ') using errcode = '22023';
  end if;
  if v_s.starts_at <= now() and not private.is_admin() then
    raise exception 'This session has started. Please contact CLG.' using errcode = '22023';
  end if;
  update public.sessions
  set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
      cancelled_by_role = v_role, cancel_reason = nullif(left(trim(p_reason), 500), '')
  where id = p_session;
end;
$$;
revoke all on function public.cancel_session(uuid, text, text) from public, anon;
grant execute on function public.cancel_session(uuid, text, text) to authenticated;

-- Withdraw a request, or stop a booking: every future session is cancelled.
create or replace function public.cancel_booking(p_booking uuid, p_reason text default null, p_for text default null)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_b public.bookings;
  v_role text;
begin
  select * into v_b from public.bookings where id = p_booking for update;
  v_role := case when v_b.id is null then null else private.cancel_role(v_b.student_id, v_b.tutor_id, p_for) end;
  if v_role is null then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  if v_b.status not in ('requested', 'confirmed') then
    raise exception 'This booking is already %', v_b.status using errcode = '22023';
  end if;
  update public.bookings
  set status = case when v_b.status = 'requested' then 'cancelled'::public.booking_status else 'ended'::public.booking_status end,
      ended_at = now()
  where id = p_booking;
  update public.sessions
  set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
      cancelled_by_role = v_role, cancel_reason = nullif(left(trim(p_reason), 500), '')
  where booking_id = p_booking and status = 'scheduled' and starts_at > now();
end;
$$;
revoke all on function public.cancel_booking(uuid, text, text) from public, anon;
grant execute on function public.cancel_booking(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- After a session: did it happen?
-- ---------------------------------------------------------------------------
-- Records whether a session happened.
-- Later migrations replace this function, so it's only created here when
-- missing. Running this file again won't undo their changes.
do $guard$
begin
  if to_regprocedure('public.record_session_outcome(uuid, public.session_status)') is null then
    execute $fn$
create function public.record_session_outcome(p_session uuid, p_status public.session_status)
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
  -- No need to touch the student's activity date: the tutor assignment made
  -- with the booking already keeps the record from automatic deletion.
end;
$$;
    $fn$;
  end if;
end;
$guard$;
revoke all on function public.record_session_outcome(uuid, public.session_status) from public, anon;
grant execute on function public.record_session_outcome(uuid, public.session_status) to authenticated;

-- ---------------------------------------------------------------------------
-- Lists for the screens, with names
-- ---------------------------------------------------------------------------

-- Bookings the signed-in person can see. A tutor sees only the student's
-- first name and year level until they accept.
create or replace function public.list_bookings()
returns table (
  id uuid, status public.booking_status, expired boolean,
  student_id uuid, student_name text, year_level text,
  tutor_id uuid, tutor_name text, subject text,
  weekday smallint, start_time time, minutes integer,
  delivery public.session_delivery, library_name text,
  first_date date, last_date date, family_note text, tutor_note text,
  tutor_reply_by timestamptz, sessions_left bigint
)
language sql stable security definer
set search_path = ''
as $$
  select b.id, b.status, b.status = 'requested' and b.tutor_reply_by <= now(),
         b.student_id,
         case when b.status = 'confirmed' or private.can_view_student(b.student_id)
              then s.full_name else split_part(s.full_name, ' ', 1) end,
         s.year_level,
         b.tutor_id, a.full_name, b.subject,
         b.weekday, b.start_time, b.minutes, b.delivery, l.name,
         b.first_date, b.last_date, b.family_note, b.tutor_note, b.tutor_reply_by,
         (select count(*) from public.sessions x
          where x.booking_id = b.id and x.status = 'scheduled' and x.starts_at > now())
  from public.bookings b
  join public.students s on s.id = b.student_id
  join public.accounts a on a.id = b.tutor_id
  left join public.libraries l on l.id = b.library_id
  where private.is_admin()
     or (b.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
     or private.is_parent_of(b.student_id)
     or private.is_student_self(b.student_id)
  order by b.status, b.weekday, b.start_time
$$;
revoke all on function public.list_bookings() from public, anon;
grant execute on function public.list_bookings() to authenticated;

-- Sessions the signed-in person can see in a date range.
create or replace function public.list_sessions(p_from date default null, p_to date default null)
returns table (
  id uuid, booking_id uuid, status public.session_status,
  student_id uuid, student_name text, tutor_id uuid, tutor_name text,
  subject text, delivery public.session_delivery, library_name text,
  starts_at timestamptz, ends_at timestamptz,
  cancelled_by_role text, meeting_url text
)
language sql stable security definer
set search_path = ''
as $$
  select x.id, x.booking_id, x.status, x.student_id, s.full_name, x.tutor_id, a.full_name,
         x.subject, x.delivery, l.name, x.starts_at, x.ends_at, x.cancelled_by_role, x.meeting_url
  from public.sessions x
  join public.students s on s.id = x.student_id
  join public.accounts a on a.id = x.tutor_id
  left join public.libraries l on l.id = x.library_id
  where x.starts_at >= coalesce(p_from, current_date - 7)
    and x.starts_at < coalesce(p_to, current_date + 60) + 1
    and (private.is_admin()
         or (x.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
         or private.is_parent_of(x.student_id)
         or private.is_student_self(x.student_id))
  order by x.starts_at
$$;
revoke all on function public.list_sessions(date, date) from public, anon;
grant execute on function public.list_sessions(date, date) to authenticated;
