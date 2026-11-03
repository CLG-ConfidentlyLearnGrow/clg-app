-- Scheduling part 9 (module: scheduling): the Matching tab. Carla, 3 Nov 2026.
--
-- One place for matching, for owner, operations and support admins:
--   * a queue of student subjects by stage, longest waiting first, with
--     filters (stage, year level, state, search)
--   * for one student: a ranked tutor shortlist with the reasons each fits
--   * tutors who don't fit, and why
--   * a gap report: what students are waiting for that no tutor offers
--
-- Ranking (Carla's answers, 3 Nov 2026): a tutor who already teaches a
-- sibling first, then matching times (preferred times first), then place,
-- then spare weekly hours. A tutor is never booked past their own weekly
-- maximum. A tutor at their maximum still shows, with a note, so an admin
-- can ask them if they're the only option. No pay rates are shown.
--
-- Families can add a written "tutor preferences" note for each child.
-- There are no filters on things like gender or religion (Equal Opportunity
-- Act 1984 (SA)); admins read the note.
--
-- Before accepting an offer a tutor sees only the student's first name,
-- year level, subject, goal, place and time (offer_card). Everything else
-- (learning needs, documents, progress, contact details) opens only once
-- there is a current assignment, which is made when the tutor and family
-- have both accepted (see private.is_tutor_of and confirm_booking).
--
-- See docs/features/scheduling.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Tutor preferences note (families write it; admins read it)
-- ---------------------------------------------------------------------------
alter table public.student_places add column if not exists tutor_preferences text;
alter table public.student_places drop constraint if exists student_places_tutor_preferences_length;
alter table public.student_places add constraint student_places_tutor_preferences_length
  check (char_length(tutor_preferences) <= 1000);

-- ---------------------------------------------------------------------------
-- The queue
-- ---------------------------------------------------------------------------
-- How many student subjects are at each stage (front desk admins).
create or replace function public.matching_stage_counts()
returns table (stage text, subjects bigint, oldest_days integer)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG admins can see matching' using errcode = '42501';
  end if;
  return query
    select r.stage, count(*), max(current_date - (r.since at time zone 'Australia/Adelaide')::date)
    from private.matching_rows() r
    group by r.stage;
end;
$$;
revoke all on function public.matching_stage_counts() from public, anon;
grant execute on function public.matching_stage_counts() to authenticated;

-- One page of the queue, longest waiting first.
create or replace function public.matching_queue(
  p_stage text default null,
  p_search text default null,
  p_year text default null,
  p_state text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  student_id uuid, student_name text, year_level text, working_level text, subject text,
  state text, stage text, since timestamptz, days integer, tutor_name text, has_places boolean,
  total bigint
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_search text := nullif(trim(p_search), '');
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG admins can see matching' using errcode = '42501';
  end if;
  return query
    select r.student_id, r.student_name, r.year_level, r.working_level, r.subject,
           s.state::text, r.stage, r.since,
           current_date - (r.since at time zone 'Australia/Adelaide')::date,
           r.tutor_name, r.has_places, count(*) over ()
    from private.matching_rows() r
    join public.students s on s.id = r.student_id
    where (p_stage is null or r.stage = p_stage)
      and (nullif(p_year, '') is null or r.year_level = p_year)
      and (nullif(p_state, '') is null or s.state::text = p_state)
      and (v_search is null or r.student_name ilike '%' || v_search || '%' or r.subject ilike '%' || v_search || '%')
    order by r.since, r.student_name, r.subject
    limit least(greatest(coalesce(p_limit, 50), 1), 200)
    offset greatest(coalesce(p_offset, 0), 0);
end;
$$;
revoke all on function public.matching_queue(text, text, text, text, integer, integer) from public, anon;
grant execute on function public.matching_queue(text, text, text, text, integer, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- The shortlist for one student and subject
-- ---------------------------------------------------------------------------
create or replace function public.matching_shortlist(p_student uuid, p_subject text, p_minutes integer default 60)
returns table (
  tutor_id uuid, tutor_name text,
  teaches_sibling boolean, sibling_names text,
  times integer, preferred_times integer, in_person_times integer,
  best_weekday smallint, best_start time, best_end time,
  best_delivery public.session_delivery, best_library uuid, best_library_name text,
  booked_minutes integer, max_weekly_hours numeric, at_max boolean,
  learning_support boolean, check_kind text, check_expires date, rank integer
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_level text;
  v_online boolean;
  v_libs uuid[];
  v_family uuid;
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG admins can see matching' using errcode = '42501';
  end if;
  v_level := private.matching_level(p_student, p_subject);
  if v_level is null then
    raise exception 'Add the student''s year level first' using errcode = '22023';
  end if;
  select coalesce(sp.online, true), coalesce(sp.library_ids, '{}')
    into v_online, v_libs
  from (select 1) x left join public.student_places sp on sp.student_id = p_student;
  select s.family_id into v_family from public.students s where s.id = p_student;

  return query
  with opts as (
    select o.*, o.ordinality as n
    from public.offer_options(p_student, p_subject, coalesce(p_minutes, 60), v_online, v_libs) with ordinality o
  ),
  per_tutor as (
    select o.tutor_id as tid,
           count(*)::integer as times,
           count(*) filter (where o.preferred)::integer as preferred_times,
           count(*) filter (where o.delivery = 'library')::integer as in_person_times,
           min(o.n) as first_n
    from opts o group by o.tutor_id
  ),
  candidates as (
    select t.account_id as tid, a.full_name, w.max_weekly_hours,
           coalesce(ss.learning_support, false) as ls
    from public.tutor_profiles t
    join public.accounts a on a.id = t.account_id
    left join public.tutor_work_settings w on w.tutor_id = t.account_id
    left join public.tutor_session_settings ss on ss.tutor_id = t.account_id
    where t.active
      and private.tutor_cleared_for_student(t.account_id, p_student)
      and private.tutor_teaches(t.account_id, p_subject, v_level)
      and not private.blocked_pair(t.account_id, p_student)
  ),
  booked as (
    select b.tutor_id as tid, sum(b.minutes)::integer as mins
    from public.bookings b
    where private.booking_is_live(b.status, b.tutor_reply_by) and b.last_date >= current_date
    group by b.tutor_id
  ),
  siblings as (
    select ta.tutor_id as tid, string_agg(distinct split_part(s2.full_name, ' ', 1), ', ') as names
    from public.tutor_assignments ta
    join public.students s2 on s2.id = ta.student_id
    where v_family is not null and s2.family_id = v_family and s2.id <> p_student
      and private.assignment_is_current(ta.starts_on, ta.ends_on)
    group by ta.tutor_id
  ),
  warnings as (
    select distinct on (c.tutor_id) c.tutor_id as tid, c.kind::text as kind, c.expires_on as expires
    from public.tutor_checks c
    where c.expires_on between current_date and current_date + 30
    order by c.tutor_id, c.expires_on
  ),
  scored as (
    select c.tid, c.full_name,
           sib.tid is not null as teaches_sibling, sib.names,
           coalesce(pt.times, 0) as times, coalesce(pt.preferred_times, 0) as preferred_times,
           coalesce(pt.in_person_times, 0) as in_person_times,
           best.weekday, best.start_time, best.end_time, best.delivery, best.library_id, best.library_name,
           coalesce(bk.mins, 0) as booked_minutes, c.max_weekly_hours,
           c.max_weekly_hours is not null
             and coalesce(bk.mins, 0) + coalesce(p_minutes, 60) > c.max_weekly_hours * 60 as at_max,
           c.ls, wn.kind, wn.expires
    from candidates c
    left join per_tutor pt on pt.tid = c.tid
    left join opts best on best.n = pt.first_n
    left join booked bk on bk.tid = c.tid
    left join siblings sib on sib.tid = c.tid
    left join warnings wn on wn.tid = c.tid
  )
  select s.tid, s.full_name, s.teaches_sibling, s.names, s.times, s.preferred_times, s.in_person_times,
         s.weekday, s.start_time, s.end_time, s.delivery, s.library_id, s.library_name,
         s.booked_minutes, s.max_weekly_hours, s.at_max, s.ls, s.kind, s.expires,
         (row_number() over (
            order by s.teaches_sibling desc,
                     (s.times > 0) desc,
                     (s.preferred_times > 0) desc,
                     (s.in_person_times > 0 and cardinality(v_libs) > 0) desc,
                     coalesce(s.max_weekly_hours * 60 - s.booked_minutes, 100000) desc,
                     s.full_name))::integer
  from scored s
  order by 20;
end;
$$;
revoke all on function public.matching_shortlist(uuid, text, integer) from public, anon;
grant execute on function public.matching_shortlist(uuid, text, integer) to authenticated;

-- Active tutors who aren't on the shortlist, and why.
create or replace function public.matching_not_offered(p_student uuid, p_subject text)
returns table (tutor_id uuid, tutor_name text, reason text)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_level text;
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG admins can see matching' using errcode = '42501';
  end if;
  v_level := private.matching_level(p_student, p_subject);
  return query
    select t.account_id, a.full_name,
           case
             when private.blocked_pair(t.account_id, p_student) then 'Can''t be matched with this student'
             when not private.tutor_cleared_for_student(t.account_id, p_student)
               then 'Checks not current for this student''s state'
             else 'Doesn''t teach ' || p_subject || ' at ' || coalesce(v_level, 'this level')
           end
    from public.tutor_profiles t
    join public.accounts a on a.id = t.account_id
    where t.active
      and not (private.tutor_cleared_for_student(t.account_id, p_student)
               and v_level is not null
               and private.tutor_teaches(t.account_id, p_subject, v_level)
               and not private.blocked_pair(t.account_id, p_student))
    order by a.full_name;
end;
$$;
revoke all on function public.matching_not_offered(uuid, text) from public, anon;
grant execute on function public.matching_not_offered(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Gap report: what waiting students need that no tutor offers
-- ---------------------------------------------------------------------------
create or replace function public.matching_gaps()
returns table (subject text, level text, state text, waiting bigint, longest_days integer)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG admins can see matching' using errcode = '42501';
  end if;
  return query
    select r.subject, coalesce(r.working_level, r.year_level, 'Year level not set'), s.state::text,
           count(*), max(current_date - (r.since at time zone 'Australia/Adelaide')::date)
    from private.matching_rows() r
    join public.students s on s.id = r.student_id
    where r.stage in ('needs_tutor', 'waitlist')
      and not exists (
        select 1 from public.tutor_profiles t
        where t.active
          and private.tutor_cleared_for_student(t.account_id, r.student_id)
          and private.tutor_teaches(t.account_id, r.subject, private.matching_level(r.student_id, r.subject))
      )
    group by r.subject, coalesce(r.working_level, r.year_level, 'Year level not set'), s.state
    order by count(*) desc, 5 desc;
end;
$$;
revoke all on function public.matching_gaps() from public, anon;
grant execute on function public.matching_gaps() to authenticated;

-- ---------------------------------------------------------------------------
-- What a tutor sees before accepting an offer
-- ---------------------------------------------------------------------------
-- First name, year level, subject, goal, place and time only. Learning
-- needs and other details open once the tutor has a current assignment.
create or replace function public.offer_card(p_booking uuid)
returns table (
  first_name text, year_level text, subject text, goal text,
  delivery public.session_delivery, library_name text,
  weekday smallint, start_time time, minutes integer, first_date date
)
language sql stable security definer
set search_path = ''
as $$
  select split_part(s.full_name, ' ', 1), s.year_level, b.subject, s.goals,
         b.delivery, l.name, b.weekday, b.start_time, b.minutes, b.first_date
  from public.bookings b
  join public.students s on s.id = b.student_id
  left join public.libraries l on l.id = b.library_id
  where b.id = p_booking
    and (private.is_front_desk()
         or (b.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2()))
$$;
revoke all on function public.offer_card(uuid) from public, anon;
grant execute on function public.offer_card(uuid) to authenticated;
