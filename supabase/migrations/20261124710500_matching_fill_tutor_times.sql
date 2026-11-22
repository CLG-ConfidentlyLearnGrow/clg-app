-- Scheduling (Matching): fill a tutor's free times from the waiting
-- students (Carla, 22 Nov 2026, from her notes on Emma's Job Proposal: "let
-- admin open a tutor's weekly availability and fill it with suitable
-- students, listed in order of urgency, instead of matching only from the
-- student side").
--
-- Matching already works from the student side: choose a student, see the
-- tutors who suit. This adds the other way round: choose a tutor, see every
-- student still waiting for a tutor (Needs a tutor, or Waitlist) who fits
-- one of that tutor's free times, longest waiting first. Each row uses the
-- same rules as the student-side shortlist (the tutor teaches the subject
-- at the student's level, their checks are cleared, neither has blocked the
-- other, and a free time suits both), so an offer made from here is the
-- same as one made from the student's side.
--
-- For front desk admins (owner, Operations and Support), like the rest of
-- Matching. No pay rates are shown.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The tutors to choose from, with how full their week is.
-- ---------------------------------------------------------------------------
create or replace function public.matching_fill_tutors() -- no inputs
returns table (tutor_id uuid, tutor_name text, max_weekly_hours numeric, booked_minutes integer) -- one row per active tutor
language plpgsql stable security definer -- reads tutors and bookings for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_front_desk() then -- only the owner, Operations and Support admins
    raise exception 'Only CLG admins can see matching' using errcode = '42501'; -- plain message for anyone else
  end if; -- end of the check
  return query -- hands back:
    select t.account_id, a.full_name, w.max_weekly_hours, -- each tutor, their name and their weekly maximum (if set),
           coalesce((select sum(b.minutes)::integer from public.bookings b -- and the minutes a week already booked:
                     where b.tutor_id = t.account_id and private.booking_is_live(b.status, b.tutor_reply_by) and b.last_date >= current_date), 0) -- live bookings still running
    from public.tutor_profiles t -- from the tutors
    join public.accounts a on a.id = t.account_id -- with their names
    left join public.tutor_work_settings w on w.tutor_id = t.account_id -- and their weekly maximum
    where t.active -- active tutors only
    order by a.full_name; -- by name
end; -- end of the code
$$; -- end of the function
revoke all on function public.matching_fill_tutors() from public, anon; -- not for signed-out visitors
grant execute on function public.matching_fill_tutors() to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- The waiting students who fit one tutor's free times, longest waiting
-- first.
-- ---------------------------------------------------------------------------
create or replace function public.matching_tutor_fill(p_tutor uuid) -- the tutor
returns table ( -- one row per student and subject that fits:
  student_id uuid, student_name text, year_level text, subject text, stage text, days integer, -- the student, subject, stage and days waiting,
  times integer, preferred_times integer, -- how many times suit, and how many are in the family's preferred parts of the day,
  best_weekday smallint, best_start time, best_end time, best_delivery public.session_delivery, best_library_name text, -- the best time and place,
  teaches_sibling boolean, at_max boolean -- whether the tutor already teaches a sibling, and whether this would take them past their weekly maximum
)
language plpgsql stable security definer -- reads matching details for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  r record; -- one waiting student and subject
  v_level text; -- the level the student is matched at for that subject
begin -- start
  if not private.is_front_desk() then -- only the owner, Operations and Support admins
    raise exception 'Only CLG admins can see matching' using errcode = '42501'; -- plain message for anyone else
  end if; -- end of the check
  for r in -- for each student and subject still waiting for a tutor, longest waiting first:
    select m.student_id, m.student_name, m.year_level, m.subject, m.stage, -- the student, subject and stage,
           current_date - (m.since at time zone 'Australia/Adelaide')::date as days -- and days waiting
    from private.matching_rows() m -- from the Matching queue
    where m.stage in ('needs_tutor', 'waitlist') -- still waiting for a tutor
    order by m.since, m.student_name, m.subject -- longest waiting first
  loop -- (each one)
    v_level := private.matching_level(r.student_id, r.subject); -- the level to match at
    continue when v_level is null; -- no year level yet: skipped (Matching asks for it)
    continue when not private.tutor_teaches(p_tutor, r.subject, v_level); -- the tutor does not teach it at this level: skipped
    continue when not private.tutor_cleared_for_student(p_tutor, r.student_id); -- the tutor's checks do not clear them for this student: skipped
    continue when private.blocked_pair(p_tutor, r.student_id); -- one has blocked the other: skipped
    return query -- hands back this student, if a free time suits:
      select r.student_id, r.student_name, r.year_level, r.subject, r.stage, r.days, -- the student, subject, stage and days waiting,
             s.times, s.preferred_times, -- how many times suit,
             s.best_weekday, s.best_start, s.best_end, s.best_delivery, s.best_library_name, -- the best time and place,
             s.teaches_sibling, s.at_max -- sibling and weekly maximum
      from public.matching_shortlist(r.student_id, r.subject) s -- the student-side shortlist (the same rules)
      where s.tutor_id = p_tutor and s.times > 0; -- this tutor, with at least one time that suits
  end loop; -- next student
end; -- end of the code
$$; -- end of the function
revoke all on function public.matching_tutor_fill(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.matching_tutor_fill(uuid) to authenticated; -- signed-in people (the check is inside)
