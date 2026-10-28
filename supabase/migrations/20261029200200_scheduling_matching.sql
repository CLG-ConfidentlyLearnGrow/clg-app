-- Scheduling part 7 (module: scheduling): matching students with tutors.
--
-- * Matching uses the level the student is working at in each subject (the
--   family's "working level"), falling back to their school year level.
--   That applies to finding times (see 20261027200100) and to assigning a
--   tutor (the core check below).
-- * Families save where sessions can happen for each child: online, and the
--   libraries that suit. Booking searches start from these.
-- * Admins get a matching pipeline: every subject a student asked for, the
--   stage it's at, and how many days it has been there. Built to page
--   through hundreds of students.
--
-- Stages, worked out from the records (nobody has to move cards):
--   needs_tutor        asked for, nothing booked or waiting
--   waitlist           on the waitlist
--   tutor_to_confirm   a booking request is waiting for the tutor
--   assigned           a tutor is assigned but no weekly time is booked
--   active             a confirmed booking is running
--
-- See docs/features/scheduling.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Core: assigning a tutor checks the working level too
-- ---------------------------------------------------------------------------
-- private.matching_level is defined in 20261027200100_scheduling.sql.
create or replace function private.check_assignment_teaching()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_level text;
begin
  if private.is_backend() then return new; end if;
  if new.ends_on is not null and new.ends_on < current_date then return new; end if;

  v_level := private.matching_level(new.student_id, new.subject);
  if v_level is null then
    raise exception 'Add this student''s year level before assigning a tutor'
      using errcode = '23514';
  end if;
  if not private.tutor_teaches(new.tutor_id, new.subject, v_level) then
    raise exception 'This tutor hasn''t listed % for %. They can add it under "What you teach" in their dashboard.',
      new.subject, v_level using errcode = '23514';
  end if;
  return new;
end;
$$;

-- The admin "assign a tutor" list: subjects each tutor teaches at the
-- level this student works at in that subject.
create or replace function public.eligible_tutors(p_student uuid)
returns table (tutor_id uuid, full_name text, subjects text[], max_weekly_hours numeric)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return query
    select t.account_id, a.full_name, m.subjects, w.max_weekly_hours
    from public.tutor_profiles t
    join public.accounts a on a.id = t.account_id
    left join public.tutor_work_settings w on w.tutor_id = t.account_id
    cross join lateral (
      select array_agg(tt.subject order by tt.subject) as subjects
      from public.tutor_teaching tt
      where tt.tutor_id = t.account_id
        and private.year_level_rank(private.matching_level(p_student, tt.subject))
            between private.year_level_rank(tt.from_level) and private.year_level_rank(tt.to_level)
    ) m
    where private.tutor_cleared_for_student(t.account_id, p_student)
      and m.subjects is not null
    order by a.full_name;
end;
$$;

-- ---------------------------------------------------------------------------
-- Where each child can have sessions
-- ---------------------------------------------------------------------------
create table if not exists public.student_places (
  student_id uuid primary key references public.students (id) on delete cascade,
  online boolean not null default true,
  library_ids uuid[] not null default '{}',
  updated_at timestamptz not null default now(),
  check (online or cardinality(library_ids) > 0)
);
alter table public.student_places enable row level security;
revoke all on public.student_places from anon;
drop trigger if exists touch on public.student_places;
create trigger touch before update on public.student_places
  for each row execute function private.touch_updated_at();

-- The family and admins. Tutors see places through the booking itself.
drop policy if exists "family and admins see places" on public.student_places;
create policy "family and admins see places" on public.student_places
  for select to authenticated using (private.can_book_for(student_id));
drop policy if exists "family and admins set places" on public.student_places;
create policy "family and admins set places" on public.student_places
  for insert to authenticated with check (private.can_book_for(student_id));
drop policy if exists "family and admins change places" on public.student_places;
create policy "family and admins change places" on public.student_places
  for update to authenticated using (private.can_book_for(student_id)) with check (private.can_book_for(student_id));

-- ---------------------------------------------------------------------------
-- The matching pipeline (admins)
-- ---------------------------------------------------------------------------
create index if not exists bookings_student_subject on public.bookings (student_id, lower(subject));

create or replace function private.matching_rows()
returns table (
  student_id uuid, student_name text, year_level text, working_level text, subject text,
  stage text, since timestamptz, tutor_name text, has_places boolean
)
language sql stable security definer
set search_path = ''
as $$
  select ss.student_id, s.full_name, s.year_level, ss.working_level, ss.subject,
         case
           when live.status = 'confirmed' then 'active'
           when live.status = 'requested' then 'tutor_to_confirm'
           when asg.id is not null then 'assigned'
           when w.id is not null then 'waitlist'
           else 'needs_tutor'
         end,
         case
           when live.status = 'confirmed' then coalesce(live.confirmed_at, live.requested_at)
           when live.status = 'requested' then live.requested_at
           when asg.id is not null then asg.created_at
           when w.id is not null then w.created_at
           else greatest(ss.added_at, past.finished)
         end,
         coalesce(tl.full_name, ta.full_name),
         sp.student_id is not null
  from public.student_subjects ss
  join public.students s on s.id = ss.student_id
  left join public.student_places sp on sp.student_id = ss.student_id
  -- The booking that's running or waiting for the tutor.
  left join lateral (
    select b.status, b.confirmed_at, b.requested_at, b.tutor_id
    from public.bookings b
    where b.student_id = ss.student_id and lower(b.subject) = lower(ss.subject)
      and private.booking_is_live(b.status, b.tutor_reply_by)
      and b.last_date >= current_date
    order by (b.status = 'confirmed') desc, b.requested_at desc
    limit 1
  ) live on true
  left join public.accounts tl on tl.id = live.tutor_id
  -- When the last booking finished (ended, declined, expired or ran out).
  left join lateral (
    select max(greatest(
             coalesce(b.ended_at, b.requested_at),
             case when b.status = 'requested' then b.tutor_reply_by else b.requested_at end,
             case when b.status = 'confirmed' then b.last_date::timestamptz else b.requested_at end)) as finished
    from public.bookings b
    where b.student_id = ss.student_id and lower(b.subject) = lower(ss.subject)
  ) past on true
  left join lateral (
    select a.id, a.tutor_id, a.created_at from public.tutor_assignments a
    where a.student_id = ss.student_id and lower(a.subject) = lower(ss.subject)
      and private.assignment_is_current(a.starts_on, a.ends_on)
    order by a.created_at desc limit 1
  ) asg on live.status is null
  left join public.accounts ta on ta.id = asg.tutor_id
  left join lateral (
    select wl.id, wl.created_at from public.waitlist wl
    where wl.student_id = ss.student_id and lower(wl.subject) = lower(ss.subject) and wl.closed_at is null
    order by wl.created_at limit 1
  ) w on true
$$;
revoke all on function private.matching_rows() from public;

-- How many student subjects are at each stage.
create or replace function public.matching_pipeline()
returns table (stage text, subjects bigint, oldest_days integer)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return query
    select r.stage, count(*), max(current_date - (r.since at time zone 'Australia/Adelaide')::date)
    from private.matching_rows() r
    group by r.stage;
end;
$$;
revoke all on function public.matching_pipeline() from public, anon;
grant execute on function public.matching_pipeline() to authenticated;

-- One page of the pipeline, longest waiting first. p_search matches the
-- student's name or the subject.
create or replace function public.list_matching(
  p_stage text default null, p_search text default null, p_limit integer default 50, p_offset integer default 0
)
returns table (
  student_id uuid, student_name text, year_level text, working_level text, subject text,
  stage text, since timestamptz, days integer, tutor_name text, has_places boolean, total bigint
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_search text := nullif(trim(p_search), '');
begin
  if not private.is_admin() then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return query
    select r.student_id, r.student_name, r.year_level, r.working_level, r.subject,
           r.stage, r.since, current_date - (r.since at time zone 'Australia/Adelaide')::date,
           r.tutor_name, r.has_places, count(*) over ()
    from private.matching_rows() r
    where (p_stage is null or r.stage = p_stage)
      and (v_search is null or r.student_name ilike '%' || v_search || '%' or r.subject ilike '%' || v_search || '%')
    order by r.since, r.student_name
    limit least(greatest(coalesce(p_limit, 50), 1), 200)
    offset greatest(coalesce(p_offset, 0), 0);
end;
$$;
revoke all on function public.list_matching(text, text, integer, integer) from public, anon;
grant execute on function public.list_matching(text, text, integer, integer) to authenticated;
