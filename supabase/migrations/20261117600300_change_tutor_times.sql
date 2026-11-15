-- Summary: changing the day and time while changing tutor (scheduling
-- module, Carla 15 Nov 2026).
--
-- Carla: "When changing the tutor for pre-booked sessions, the day and time
-- of the sessions can be altered in this step (will be set to the current
-- booked day and time initially though)." So the "Change tutor" step
-- (20261117600100_change_tutor.sql) now also takes an optional new weekday
-- and start time:
--   * the page fills in the current booked day and time to start with;
--   * each moved session keeps its length and moves to the new weekday in
--     the same Monday-to-Sunday week, at the new start time (in the
--     student's own time zone);
--   * it only works when every moved session is on the same day and time
--     (one weekly pattern). If they differ, the times stay as booked;
--   * the new times must start every 15 minutes, be on or after the change
--     date and still to come, and not clash with the new tutor's sessions
--     or the student's other sessions;
--   * the weekly booking that carries on takes the new day and time, so
--     sessions made later follow it;
--   * notices say the new day and time.
-- Carla, also 15 Nov: "A session which has been altered needs to be
-- confirmed by the other or all parties before being confirmed." So the
-- admin's change is now sent for confirmation first:
--   * the admin's "Send for confirmation" saves a waiting change (after the
--     same checks) and asks the new tutor and the family to confirm it;
--   * nothing moves until both have said yes. Then the change is made, the
--     checks run again (in case something changed meanwhile), and everyone
--     is told. If it can no longer be made, admins are told why;
--   * if either says no, the change doesn't happen, admins are told (with
--     the reason given) and the other side is told it isn't going ahead;
--   * the admin can withdraw a waiting change;
--   * the old tutor isn't asked (their sessions are being moved). They're
--     told once it's confirmed, unless the admin unticked that box (for
--     example, while a concern is looked into).
-- The same sessions are still kept, so paid sessions stay paid. Invoices
-- already made keep the old day and time in their wording (billing's own
-- records, which scheduling doesn't change). Teams links stay the same and
-- still work at the new time.
--
-- Needs 20261117600100_change_tutor.sql. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The record keeps any new day and time
-- ---------------------------------------------------------------------------
alter table public.tutor_changes add column if not exists new_weekday smallint check (new_weekday between 1 and 7); -- the new weekday (1 = Monday), if changed
alter table public.tutor_changes add column if not exists new_start time; -- the new start time, if changed

-- ---------------------------------------------------------------------------
-- Working out the new times
-- ---------------------------------------------------------------------------

-- Each moving session's new start and end: the chosen weekday in the same
-- Monday-to-Sunday week, at the chosen time, with the same length. With no
-- weekday or time chosen, the times stay as they are.
create or replace function private.moved_times(p_ids uuid[], p_weekday smallint, p_start time, p_tz text) -- takes the sessions, the new weekday and time, and the time zone
returns table (id uuid, starts_at timestamptz, ends_at timestamptz, local_date date) -- each session's new start, end and local date
language sql stable security definer -- reads the sessions past the access rules
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select s.id, n.new_start, n.new_start + (s.ends_at - s.starts_at), (n.new_start at time zone p_tz)::date -- the new start, the same length, and the new local date
  from public.sessions s -- from the sessions
  cross join lateral (select (s.starts_at at time zone p_tz) as old_local) o -- each one's local date and time now
  cross join lateral (select ( -- its new start:
      (o.old_local::date + (coalesce(p_weekday, extract(isodow from o.old_local)::smallint) - extract(isodow from o.old_local)::int)) -- the chosen weekday in the same week,
      + coalesce(p_start, o.old_local::time) -- at the chosen time (or the same time),
    ) at time zone p_tz as new_start) n -- turned back into a moment in the student's time zone
  where s.id = any(p_ids) -- only the moving sessions
$$; -- end of the function
revoke all on function private.moved_times(uuid[], smallint, time, text) from public; -- for the database's own use only

-- The current day and time of the sessions that would move, for filling in
-- the form. "same_pattern" is false when they're on different days or times
-- (then the day and time can't be changed in this step).
create or replace function public.tutor_change_pattern(p_student uuid, p_from_tutor uuid, p_subject text, p_from date) -- takes the student, tutor, subject and change date
returns table (weekday smallint, start_time time, minutes integer, same_pattern boolean) -- the current day, time, length, and whether they all match
language plpgsql stable security definer -- reads past the access rules, for matching admins only
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_ids uuid[]; -- the sessions that would move
  v_tz text; -- the student's time zone
begin -- starts the code
  if not (private.is_front_desk() and private.has_aal2()) then -- not a matching admin with two-step sign-in
    raise exception 'Only CLG admins who do matching can change a tutor.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  v_ids := private.sessions_to_move(p_student, p_from_tutor, p_subject, coalesce(p_from, current_date)); -- the sessions that would move
  select coalesce(private.state_timezone(state), 'Australia/Adelaide') into v_tz from public.students where id = p_student; -- the student's time zone
  return query -- gives back one row:
  select min(extract(isodow from s.starts_at at time zone v_tz))::smallint, -- the (first) weekday,
    min((s.starts_at at time zone v_tz)::time), -- the (earliest) start time,
    min(round(extract(epoch from s.ends_at - s.starts_at) / 60))::integer, -- the (shortest) length in minutes,
    count(distinct (extract(isodow from s.starts_at at time zone v_tz), (s.starts_at at time zone v_tz)::time)) = 1 -- whether they're all on one day and time
  from public.sessions s where s.id = any(v_ids) -- (from the moving sessions)
  having count(*) > 0; -- (nothing when there's nothing to move)
end; -- ends the code
$$; -- end of the function
revoke all on function public.tutor_change_pattern(uuid, uuid, text, date) from public, anon; -- not for signed-out visitors
grant execute on function public.tutor_change_pattern(uuid, uuid, text, date) to authenticated; -- signed-in people can try (the check is inside)

-- ---------------------------------------------------------------------------
-- The candidates, checked at the new times
-- ---------------------------------------------------------------------------
drop function if exists public.tutor_change_candidates(uuid, uuid, text, date); -- the old version (without a day and time) is replaced below

-- The tutors who could take over, with anything that would stop the move,
-- with clashes checked at the new day and time (if one is chosen).
create or replace function public.tutor_change_candidates(p_student uuid, p_from_tutor uuid, p_subject text, p_from date, p_weekday smallint default null, p_start time default null) -- takes the student, current tutor, subject, change date, and optional new day and time
returns table (tutor_id uuid, full_name text, clashes integer, first_clash timestamptz, missing_library text, booked_minutes integer, added_minutes integer, max_weekly_hours numeric, at_max boolean, teaches_sibling boolean) -- each tutor and what stands in the way
language plpgsql stable security definer -- reads past the access rules, for matching admins only
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_ids uuid[]; -- the sessions that would move
  v_level text; -- the level the student works at in this subject
  v_family uuid; -- the student's family (for siblings)
  v_tz text; -- the student's time zone
  v_added integer; -- the weekly minutes of the bookings that would move
begin -- starts the code
  if not (private.is_front_desk() and private.has_aal2()) then -- not a matching admin with two-step sign-in
    raise exception 'Only CLG admins who do matching can change a tutor.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  v_ids := private.sessions_to_move(p_student, p_from_tutor, p_subject, coalesce(p_from, current_date)); -- the sessions that would move
  v_level := private.matching_level(p_student, p_subject); -- the student's level in the subject
  select family_id, coalesce(private.state_timezone(state), 'Australia/Adelaide') into v_family, v_tz from public.students where id = p_student; -- the student's family and time zone
  select coalesce(sum(b.minutes), 0)::integer into v_added from public.bookings b -- adds up the weekly minutes
  where b.id in (select x.booking_id from public.sessions x where x.id = any(v_ids)) -- of the bookings those sessions belong to
     or (b.student_id = p_student and b.tutor_id = p_from_tutor and lower(b.subject) = lower(btrim(p_subject)) -- plus requests still waiting for the old tutor
         and b.status = 'requested' and private.booking_is_live(b.status, b.tutor_reply_by) and b.last_date >= coalesce(p_from, current_date)); -- (live, and running past the date)
  return query -- gives back:
  with moving as ( -- the moving sessions at their new times:
    select * from private.moved_times(v_ids, p_weekday, p_start, v_tz) -- (the same times when none is chosen)
  ), -- end of moving
  candidates as ( -- the tutors who could teach this student this subject:
    select t.account_id as tid, a.full_name as tname, w.max_weekly_hours as maxh -- each tutor, their name and most hours
    from public.tutor_profiles t -- from the tutors
    join public.accounts a on a.id = t.account_id -- with their names
    left join public.tutor_work_settings w on w.tutor_id = t.account_id -- and their work settings
    where t.active and t.account_id <> p_from_tutor -- active, and not the current tutor
      and private.tutor_cleared_for_student(t.account_id, p_student) -- holding the checks for the student's state
      and private.tutor_teaches(t.account_id, p_subject, v_level) -- teaching the subject at the student's level
      and not private.blocked_pair(t.account_id, p_student) -- and not blocked from this student
  ), -- end of candidates
  booked as ( -- each tutor's weekly minutes already booked:
    select b.tutor_id as tid, sum(b.minutes)::integer as mins -- the tutor and their minutes
    from public.bookings b -- from the bookings
    where private.booking_is_live(b.status, b.tutor_reply_by) and b.last_date >= current_date -- live and still running
    group by b.tutor_id -- one total per tutor
  ) -- end of booked
  select c.tid, c.tname, -- the tutor and their name,
    (select count(*)::integer from moving m join public.sessions o -- how many moving sessions clash with
       on o.tutor_id = c.tid and o.status = 'scheduled' and o.starts_at < m.ends_at and o.ends_at > m.starts_at), -- one of the tutor's booked sessions (at the new times)
    (select min(m.starts_at) from moving m join public.sessions o -- the first clash
       on o.tutor_id = c.tid and o.status = 'scheduled' and o.starts_at < m.ends_at and o.ends_at > m.starts_at), -- (same test)
    (select min(l.name) from public.sessions m join public.libraries l on l.id = m.library_id -- a library the moving sessions use
     where m.id = any(v_ids) and m.delivery = 'library' -- (library sessions only)
       and not exists (select 1 from public.tutor_places tp where tp.tutor_id = c.tid and tp.library_id = m.library_id)), -- that the tutor doesn't teach at
    coalesce(bk.mins, 0), v_added, c.maxh, -- minutes booked, minutes added, and their most hours,
    c.maxh is not null and coalesce(bk.mins, 0) + v_added > c.maxh * 60, -- whether this would take them past it,
    exists (select 1 from public.tutor_assignments ta join public.students s2 on s2.id = ta.student_id -- whether they teach a brother or sister:
            where ta.tutor_id = c.tid and v_family is not null and s2.family_id = v_family and s2.id <> p_student -- another child in the family
              and private.assignment_is_current(ta.starts_on, ta.ends_on)) -- with a current match
  from candidates c -- for each candidate
  left join booked bk on bk.tid = c.tid -- with their booked minutes
  order by 3, 9, 10 desc, 2; -- fewest clashes first, then within their hours, then siblings' tutor, then by name
end; -- ends the code
$$; -- end of the function
revoke all on function public.tutor_change_candidates(uuid, uuid, text, date, smallint, time) from public, anon; -- not for signed-out visitors
grant execute on function public.tutor_change_candidates(uuid, uuid, text, date, smallint, time) to authenticated; -- signed-in people can try (the check is inside)

-- ---------------------------------------------------------------------------
-- Making the change (with an optional new day and time), once confirmed
-- ---------------------------------------------------------------------------
drop function if exists public.change_session_tutor(uuid, uuid, text, uuid, date, text, boolean); -- the old version (made the change straight away) is replaced by the confirmation steps below

-- Checks, and then makes, a change: moves a student's upcoming sessions in
-- one subject from one tutor to another, from a date, and optionally to a
-- new weekday and start time. With p_dry it only runs the checks and gives
-- back how many sessions would move (used when the admin sends the change
-- for confirmation). Gives back how many sessions moved. Only the
-- confirmation steps below call it.
create or replace function private.apply_tutor_change( -- the change itself
  p_student uuid, -- the student
  p_from_tutor uuid, -- the tutor the sessions are with now
  p_subject text, -- the subject
  p_to_tutor uuid, -- the new tutor
  p_from date, -- the first date to move (today or later)
  p_reason text, -- a short reason, kept for admins
  p_tell_old_tutor boolean default true, -- whether to send the old tutor a plain notice
  p_weekday smallint default null, -- the new weekday (1 = Monday), or empty to keep it
  p_start time default null, -- the new start time, or empty to keep it
  p_by uuid default null, -- the admin who arranged it (for the record)
  p_dry boolean default false -- true: only check, change nothing
) -- end of the inputs
returns integer -- gives back how many sessions moved
language plpgsql security definer -- changes sessions, bookings and matches past the access rules
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_student public.students; -- the student
  v_tz text; -- the student's time zone
  v_level text; -- the student's level in the subject
  v_reason text := btrim(coalesce(p_reason, '')); -- the reason, trimmed
  v_ids uuid[]; -- the sessions that move
  v_requests uuid[]; -- the booking requests that move
  v_subject text; -- the subject, as written on the sessions
  v_library text; -- a library the new tutor doesn't teach at
  v_clash timestamptz; -- the first clashing session
  v_booked integer; -- the new tutor's weekly minutes already booked
  v_added integer; -- the weekly minutes that would move to them
  v_max numeric; -- the new tutor's most hours per week
  v_b public.bookings; -- one booking being moved
  v_new public.bookings; -- the new booking made when one is split
  v_first date; -- the first moved date in a booking (as booked now)
  v_new_first date; -- the first moved date in a booking (at the new day)
  v_new_last date; -- the last moved date in a booking (at the new day)
  v_until date; -- the last date the new tutor teaches this student (for the match)
  v_first_at timestamptz; -- when the first moved session starts (at the new time)
  v_retime boolean; -- whether the day or time changes
  v_old_day smallint; -- the weekday now (when the time changes)
  v_old_time time; -- the start time now (when the time changes)
  v_patterns integer; -- how many different days and times the sessions are on
  v_when text := ''; -- the new day and time in words, for notices
  v_moved integer := 0; -- how many sessions moved
  v_bookings integer := 0; -- how many bookings moved or were split
  v_to_name text; -- the new tutor's name
  v_change uuid; -- the change record's id
  p record; -- one person to tell
begin -- starts the code
  -- The basic answers (who may ask is checked by the steps that call this).
  if char_length(v_reason) < 2 or char_length(v_reason) > 500 then -- no reason, or too long
    raise exception 'Please give a short reason (up to 500 characters), e.g. "Tutor leaving CLG".' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_from is null or p_from < current_date then -- no date, or a past date
    raise exception 'Please choose a change date of today or later.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_to_tutor is null or p_to_tutor = p_from_tutor then -- no new tutor, or the same one
    raise exception 'Please choose a different tutor.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_weekday is not null and p_weekday not between 1 and 7 then -- not a real weekday
    raise exception 'Please choose a day of the week.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_start is not null and (extract(minute from p_start)::int % 15 <> 0 or extract(second from p_start) <> 0) then -- not on a quarter hour
    raise exception 'Sessions start on the hour or at 15, 30 or 45 minutes past. Please choose another start time.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select * into v_student from public.students where id = p_student; -- the student
  if v_student.id is null then -- not found
    raise exception 'Student not found.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_tz := coalesce(private.state_timezone(v_student.state), 'Australia/Adelaide'); -- the student's time zone
  v_level := private.matching_level(p_student, p_subject); -- the student's level in this subject

  -- The new tutor must be allowed to teach this student this subject.
  if not exists (select 1 from public.tutor_profiles where account_id = p_to_tutor and active) then -- not an active tutor
    raise exception 'Please choose an active tutor.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if private.blocked_pair(p_to_tutor, p_student) then -- blocked from this student
    raise exception 'That tutor can''t be matched with this student. Please choose another tutor.' using errcode = '22023'; -- plain message (no reason given)
  end if; -- end of the check
  if not private.tutor_cleared_for_student(p_to_tutor, p_student) then -- missing checks for the student's state
    raise exception 'That tutor doesn''t hold every in-date check needed for this student''s state.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if not private.tutor_teaches(p_to_tutor, p_subject, v_level) then -- doesn't teach the subject at this level
    raise exception 'That tutor doesn''t teach % at this student''s level.', btrim(p_subject) using errcode = '22023'; -- plain message
  end if; -- end of the check

  -- What moves: upcoming sessions from the date, and requests still waiting.
  v_ids := private.sessions_to_move(p_student, p_from_tutor, p_subject, p_from); -- the sessions
  perform 1 from public.sessions where id = any(v_ids) for update; -- holds them so nothing else changes them meanwhile
  select coalesce(array_agg(b.id), '{}') into v_requests from public.bookings b -- the requests:
  where b.student_id = p_student and b.tutor_id = p_from_tutor and lower(b.subject) = lower(btrim(p_subject)) -- for this student, tutor and subject
    and b.status = 'requested' and private.booking_is_live(b.status, b.tutor_reply_by) and b.last_date >= p_from; -- still waiting, and running past the date
  if cardinality(v_ids) = 0 and cardinality(v_requests) = 0 then -- nothing to move
    raise exception 'There are no upcoming sessions with this tutor in that subject from that date.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select coalesce((select subject from public.sessions where id = v_ids[1]), (select subject from public.bookings where id = v_requests[1])) into v_subject; -- the subject as written

  -- A new day or time: only for one weekly pattern, still to come, and on or after the change date.
  select count(distinct (extract(isodow from s.starts_at at time zone v_tz), (s.starts_at at time zone v_tz)::time))::integer, -- how many different days and times,
    min(extract(isodow from s.starts_at at time zone v_tz))::smallint, min((s.starts_at at time zone v_tz)::time) -- and the day and time now
  into v_patterns, v_old_day, v_old_time -- kept for below
  from public.sessions s where s.id = any(v_ids); -- (from the moving sessions)
  v_retime := cardinality(v_ids) > 0 -- there are sessions,
    and ((p_weekday is not null and p_weekday <> v_old_day) or (p_start is not null and p_start <> v_old_time)); -- and the day or time is different
  if v_retime and v_patterns > 1 then -- the sessions are on different days or times
    raise exception 'These sessions are on different days or times, so the day and time can''t be changed in this step. Leave them as booked, or change them one booking at a time first.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if v_retime then -- the day or time changes:
    if exists (select 1 from private.moved_times(v_ids, p_weekday, p_start, v_tz) m where m.starts_at <= now() or m.local_date < p_from) then -- one would land before the change date (or in the past)
      raise exception 'At that day and time, the first session would fall before the change date. Choose a later change date, or a later day in the week.' using errcode = '22023'; -- plain message
    end if; -- end of the check
    select min(m.starts_at) into v_clash from private.moved_times(v_ids, p_weekday, p_start, v_tz) m -- the first new time that clashes
    join public.sessions o on o.student_id = p_student and o.status = 'scheduled' and not (o.id = any(v_ids)) -- with one of the student's other sessions
      and o.starts_at < m.ends_at and o.ends_at > m.starts_at; -- (overlapping)
    if v_clash is not null then -- a clash
      raise exception 'The student already has another session at that time on %. Please choose another day or time.', private.when_text(v_clash) using errcode = '22023'; -- plain message
    end if; -- end of the check
  end if; -- end of the new time checks

  -- The new tutor must teach at the libraries used, be free, and stay within their hours.
  select min(l.name) into v_library from public.sessions s join public.libraries l on l.id = s.library_id -- a library used
  where s.id = any(v_ids) and s.delivery = 'library' -- by a moving library session
    and not exists (select 1 from public.tutor_places tp where tp.tutor_id = p_to_tutor and tp.library_id = s.library_id); -- that the new tutor doesn't teach at
  if v_library is not null then -- one found
    raise exception 'That tutor doesn''t teach at %. Choose another tutor, or change where the sessions are first.', v_library using errcode = '22023'; -- plain message
  end if; -- end of the check
  select min(m.starts_at) into v_clash from private.moved_times(v_ids, p_weekday, p_start, v_tz) m join public.sessions o -- the first moving session (at its new time) that clashes
    on o.tutor_id = p_to_tutor and o.status = 'scheduled' and o.starts_at < m.ends_at and o.ends_at > m.starts_at; -- with one of the new tutor's sessions
  if v_clash is not null then -- a clash
    raise exception 'That tutor already has a session at the same time on %. Choose another tutor or time, or move that session first.', private.when_text(v_clash) using errcode = '22023'; -- plain message
  end if; -- end of the check
  select w.max_weekly_hours into v_max from public.tutor_work_settings w where w.tutor_id = p_to_tutor; -- their most hours (if set)
  if v_max is not null then -- a limit is set
    select coalesce(sum(b.minutes), 0)::integer into v_booked from public.bookings b -- their weekly minutes already booked
    where b.tutor_id = p_to_tutor and private.booking_is_live(b.status, b.tutor_reply_by) and b.last_date >= current_date; -- (live and still running)
    select coalesce(sum(b.minutes), 0)::integer into v_added from public.bookings b -- the weekly minutes that would move to them
    where b.id in (select x.booking_id from public.sessions x where x.id = any(v_ids)) or b.id = any(v_requests); -- (bookings of the moving sessions, and requests)
    if v_booked + v_added > v_max * 60 then -- past their limit
      raise exception 'That would take this tutor past their most hours per week (% hr). Choose another tutor, or change their hours first.', v_max using errcode = '22023'; -- plain message
    end if; -- end of the check
  end if; -- end of the hours check
  if p_dry then -- only checking:
    return cardinality(v_ids); -- says how many sessions would move, changing nothing
  end if; -- end of the check-only case

  -- Weekly bookings: move the whole booking if it hasn't started, otherwise split it.
  for v_b in select b.* from public.bookings b -- each booking
    where b.id in (select x.booking_id from public.sessions x where x.id = any(v_ids)) -- that a moving session belongs to
    for update -- held while it changes
  loop -- for each one:
    select min((s.starts_at at time zone v_tz)::date) into v_first from public.sessions s -- the first moving date in this booking (as booked now)
    where s.booking_id = v_b.id and s.id = any(v_ids); -- (moving sessions only)
    select min(m.local_date), max(m.local_date) into v_new_first, v_new_last -- the first and last moving dates at the new day
    from private.moved_times(v_ids, case when v_retime then p_weekday end, case when v_retime then p_start end, v_tz) m -- (the same dates when nothing changes)
    join public.sessions s on s.id = m.id where s.booking_id = v_b.id; -- (this booking's sessions)
    if v_first <= v_b.first_date then -- the booking hasn't started yet
      update public.bookings set tutor_id = p_to_tutor, -- the whole booking moves to the new tutor,
        weekday = case when v_retime then coalesce(p_weekday, weekday) else weekday end, -- on the new day (if changed),
        start_time = case when v_retime then coalesce(p_start, start_time) else start_time end, -- at the new time (if changed),
        first_date = least(first_date, v_new_first), -- starting on its first session,
        last_date = greatest(last_date, v_new_last) -- and running at least to its last one
      where id = v_b.id; -- (this booking)
    else -- the booking has already started
      v_new := v_b; -- copies the booking (days, times, place, holidays, end date)
      v_new.id := gen_random_uuid(); -- a new id
      v_new.tutor_id := p_to_tutor; -- with the new tutor
      if v_retime then -- the day or time changes:
        v_new.weekday := coalesce(p_weekday, v_b.weekday); -- the new day,
        v_new.start_time := coalesce(p_start, v_b.start_time); -- and the new time
      end if; -- end of the new day and time
      v_new.first_date := v_new_first; -- starting at the first moving date
      v_new.last_date := greatest(v_b.last_date, v_new_last); -- running at least to the last one
      v_new.status := 'confirmed'; -- already confirmed (the admin arranged it)
      v_new.renews_booking := v_b.id; -- marked as carrying on the old booking
      v_new.requested_by := p_by; -- arranged by this admin
      v_new.requested_at := now(); -- now
      v_new.tutor_reply_by := now(); -- (nothing to reply to)
      v_new.tutor_ok_at := now(); -- the new tutor has already confirmed the change
      v_new.needs_family_ok := false; -- the family has already confirmed the change
      v_new.confirmed_at := now(); -- confirmed now
      v_new.ended_at := null; -- not ended
      v_new.follow_up_sent_at := null; -- no follow-ups sent yet
      v_new.not_answered_notice_at := null; -- no "not answered" notice yet
      v_new.created_at := now(); -- made now
      insert into public.bookings select (v_new).*; -- saves the new booking
      update public.bookings set last_date = v_first - 1 where id = v_b.id; -- the old booking ends the day before the first moved session
      update public.sessions set booking_id = v_new.id where booking_id = v_b.id and id = any(v_ids); -- the moving sessions now belong to the new booking
    end if; -- end of move or split
    v_until := greatest(v_until, v_b.last_date, v_new_last); -- the new tutor teaches at least until this booking ends
    v_bookings := v_bookings + 1; -- counts it
  end loop; -- end of the bookings

  -- Requests still waiting: the new tutor accepts or declines instead (at the time asked for).
  update public.bookings set tutor_id = p_to_tutor, tutor_ok_at = null, tutor_reply_by = now() + interval '48 hours' -- the new tutor, with a fresh 48 hours to answer
  where id = any(v_requests); -- (the waiting requests)
  v_bookings := v_bookings + cardinality(v_requests); -- counts them

  -- The sessions themselves: the tutor changes, and the day and time if chosen (places, links and invoices stay).
  update public.sessions s set tutor_id = p_to_tutor, -- the new tutor,
    starts_at = case when v_retime then m.starts_at else s.starts_at end, -- the new start (if changed),
    ends_at = case when v_retime then m.ends_at else s.ends_at end -- and the new end (if changed)
  from private.moved_times(v_ids, p_weekday, p_start, v_tz) m -- (each session's new times)
  where s.id = m.id; -- (matched to its session)
  get diagnostics v_moved = row_count; -- how many moved
  delete from public.session_notices -- reminders not yet sent for them (they named the old tutor or time):
  where session_id = any(v_ids) and kind in ('reminder_first', 'reminder_final') and deliver_at > now(); -- are made again with the new details on the next run
  select min(starts_at), greatest(v_until, max((starts_at at time zone v_tz)::date)) into v_first_at, v_until -- the first moved session, and the last date taught
  from public.sessions where id = any(v_ids); -- (from the moved sessions, now at their new times)
  v_until := greatest(v_until, (select max(last_date) from public.bookings where id = any(v_requests)), current_date); -- (or the requests' end dates, and at least today)
  if v_retime then -- the day or time changed:
    select ' New time: ' || to_char(v_first_at at time zone v_tz, 'FMDay') || 's at ' -- "New time: Mondays at
      || trim(to_char(v_first_at at time zone v_tz, 'FMHH12:MI')) || lower(to_char(v_first_at at time zone v_tz, 'am')) || '.' -- 4:00pm."
    into v_when; -- kept for the notices
  end if; -- end of the words

  -- The matches: the new tutor is matched (so they can read the notes), the old one's match ends.
  if exists (select 1 from public.tutor_assignments a -- the new tutor already has a current match
             where a.tutor_id = p_to_tutor and a.student_id = p_student and lower(a.subject) = lower(v_subject) -- for this student and subject
               and private.assignment_is_current(a.starts_on, a.ends_on)) then -- (current)
    update public.tutor_assignments a set ends_on = greatest(a.ends_on, v_until) -- stretches it to the last date, if it has an end
    where a.tutor_id = p_to_tutor and a.student_id = p_student and lower(a.subject) = lower(v_subject) -- (that match)
      and private.assignment_is_current(a.starts_on, a.ends_on) and a.ends_on is not null and a.ends_on < v_until; -- (only when it ends too soon)
  else -- no match yet
    insert into public.tutor_assignments (tutor_id, student_id, subject, starts_on, ends_on, created_by) -- adds one
    values (p_to_tutor, p_student, v_subject, current_date, v_until, p_by); -- from today until the last date (the usual checks run here)
  end if; -- end of the new tutor's match
  update public.tutor_assignments a set ends_on = greatest(a.starts_on, current_date, p_from - 1) -- the old tutor's match ends the day before the change (or today)
  where a.tutor_id = p_from_tutor and a.student_id = p_student and lower(a.subject) = lower(v_subject) -- for this student and subject
    and private.assignment_is_current(a.starts_on, a.ends_on) -- (current)
    and (a.ends_on is null or a.ends_on > greatest(a.starts_on, current_date, p_from - 1)) -- (only if it would end later)
    and not exists (select 1 from public.sessions s -- and they have no other sessions left after that
                    where s.tutor_id = p_from_tutor and s.student_id = p_student and lower(s.subject) = lower(v_subject) -- (same pair and subject)
                      and s.status = 'scheduled' and (s.starts_at at time zone v_tz)::date > greatest(current_date, p_from - 1)); -- (still to come, after the end)

  -- Tells the people involved (the notices go out as emails too, outside quiet hours).
  select full_name into v_to_name from public.accounts where id = p_to_tutor; -- the new tutor's name
  perform private.add_notice(p_to_tutor, null, null, 'booking_confirmed', 'Change confirmed', -- the new tutor:
    split_part(v_student.full_name, ' ', 1) || ' (' || v_subject || '): ' -- the student's first name and subject,
    || case when v_moved > 0 then v_moved || ' upcoming session(s) from ' || private.when_text(v_first_at) || ' are now with you.' || v_when || ' Please read their notes before the first one.' -- the sessions now theirs (and the new time),
            else 'a booking request is now with you. Please accept or decline under Sessions within 48 hours.' end, now()); -- or a request to answer
  for p in select * from private.session_people(p_student, p_to_tutor) where not is_tutor loop -- each parent (and the student, with their own login):
    perform private.add_notice(p.account_id, null, null, 'booking_confirmed', 'Change confirmed', -- a notice:
      v_student.full_name || '''s ' || v_subject || ' sessions' -- the student's sessions in the subject,
      || case when v_first_at is not null then ' from ' || private.when_text(v_first_at) else '' end -- from the first date,
      || ' will be with ' || coalesce(v_to_name, 'a new tutor') || '.' -- are with the new tutor,
      || case when v_retime then v_when || ' Places stay the same.' else ' Times and places stay the same.' end -- with the new time (or the same times),
      || ' Please contact CLG if you have any questions.', now()); -- and who to ask
  end loop; -- end of the family
  if p_tell_old_tutor then -- the admin chose to tell the old tutor
    perform private.add_notice(p_from_tutor, null, null, 'session_cancelled', 'Sessions moved', -- a plain notice, with no reason:
      split_part(v_student.full_name, ' ', 1) || '''s ' || v_subject || ' sessions from ' || trim(to_char(p_from, 'FMDD Mon')) -- the student's first name, subject and change date,
      || ' have moved to another CLG tutor. You don''t need to do anything.', now()); -- moved, nothing to do
  end if; -- end of the old tutor's notice

  -- Keeps a record for admins, and notes it in the activity log (ids only).
  insert into public.tutor_changes (student_id, from_tutor, to_tutor, subject, from_date, sessions_moved, bookings_moved, reason, told_old_tutor, changed_by, new_weekday, new_start) -- the record:
  values (p_student, p_from_tutor, p_to_tutor, v_subject, p_from, v_moved, v_bookings, v_reason, coalesce(p_tell_old_tutor, true), p_by, -- what moved, why and who arranged it,
    case when v_retime then coalesce(p_weekday, v_old_day) end, case when v_retime then coalesce(p_start, v_old_time) end) -- and the new day and time (if changed)
  returning id into v_change; -- keeps its id
  perform private.log_event('tutor_changed', 'tutor_changes', v_change::text, '{}'); -- the activity log entry
  return v_moved; -- how many sessions moved
end; -- ends the code
$$; -- end of the function
revoke all on function private.apply_tutor_change(uuid, uuid, text, uuid, date, text, boolean, smallint, time, uuid, boolean) from public; -- for the database's own use only (the confirmation steps below)

-- ---------------------------------------------------------------------------
-- Waiting changes: sent by an admin, confirmed by the new tutor and family
-- ---------------------------------------------------------------------------

-- One row per change an admin sends for confirmation.
create table if not exists public.tutor_change_offers ( -- the waiting (and answered) changes
  id uuid primary key default gen_random_uuid(), -- the change's id
  student_id uuid not null references public.students (id) on delete cascade, -- the student
  from_tutor uuid not null references public.accounts (id) on delete cascade, -- the tutor the sessions are with now
  to_tutor uuid not null references public.accounts (id) on delete cascade, -- the new tutor
  subject text not null check (char_length(subject) between 1 and 100), -- the subject
  from_date date not null, -- the first date to move
  new_weekday smallint check (new_weekday between 1 and 7), -- the new weekday (1 = Monday), if changing
  new_start time, -- the new start time, if changing
  old_weekday smallint check (old_weekday between 1 and 7), -- the weekday now (for showing the change)
  old_start time, -- the start time now (for showing the change)
  sessions integer not null default 0 check (sessions >= 0), -- how many sessions would move (when sent)
  reason text not null check (char_length(reason) between 2 and 500), -- the admin's reason (only matching admins see it)
  tell_old_tutor boolean not null default true, -- whether to tell the old tutor once confirmed
  status text not null default 'waiting' check (status in ('waiting', 'confirmed', 'declined', 'withdrawn', 'failed')), -- where it's up to
  tutor_ok_at timestamptz, -- when the new tutor confirmed
  family_ok_at timestamptz, -- when the family confirmed
  family_ok_by uuid references public.accounts (id) on delete set null, -- who in the family confirmed
  declined_by_role text check (declined_by_role in ('tutor', 'family')), -- who said no, if anyone
  answer_note text check (char_length(answer_note) <= 500), -- the reason given for saying no
  closed_note text check (char_length(closed_note) <= 1000), -- why it was withdrawn, or couldn't be made
  change_id uuid references public.tutor_changes (id) on delete set null, -- the record of the change, once made
  created_by uuid references public.accounts (id) on delete set null, -- the admin who sent it
  created_at timestamptz not null default now(), -- when it was sent
  closed_at timestamptz -- when it was confirmed, declined, withdrawn or failed
); -- end of the table
create unique index if not exists tutor_change_offers_one_waiting on public.tutor_change_offers (student_id, from_tutor, lower(subject)) where status = 'waiting'; -- only one waiting change per student, tutor and subject
alter table public.tutor_change_offers enable row level security; -- turns on access rules (no rule: read only through the functions below)
revoke all on public.tutor_change_offers from anon, authenticated; -- nobody reads or changes it directly
drop trigger if exists audit on public.tutor_change_offers; -- removes the old audit trigger if the file is run again
create trigger audit after insert or update or delete on public.tutor_change_offers -- records every change in the audit log
  for each row execute function private.audit_change(); -- using the shared audit step

-- A day and time in words, e.g. "Mondays at 4:00pm" (or "" when not set).
create or replace function private.weekly_time_text(p_weekday smallint, p_start time) -- takes the weekday and time
returns text language sql immutable -- the same inputs always give the same words
set search_path = '' -- only fully named tables, for safety
as $$ -- the words
  select case when p_weekday is null or p_start is null then '' -- nothing when not set
    else (array['Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays', 'Sundays'])[p_weekday] -- the day,
      || ' at ' || trim(to_char(p_start, 'FMHH12:MI')) || lower(to_char(p_start, 'am')) end -- and the time, e.g. 4:00pm
$$; -- end of the function

-- Whether the signed-in person speaks for the student's family (a parent,
-- or the student with their own login). Admins don't, unless they're family.
create or replace function private.is_family_of(p_student uuid) -- takes the student
returns boolean language sql stable security definer -- reads past the access rules
set search_path = '' -- only fully named tables, for safety
as $$ -- the test
  select exists (select 1 from private.session_people(p_student, null) p where not p.is_tutor and p.account_id = auth.uid()) -- one of the people told about the student's sessions
$$; -- end of the function
revoke all on function private.is_family_of(uuid) from public; -- for the database's own use only

-- The admin sends a change for confirmation (after every check). Gives back
-- the waiting change's id.
create or replace function public.propose_tutor_change( -- sending a change
  p_student uuid, -- the student
  p_from_tutor uuid, -- the tutor the sessions are with now
  p_subject text, -- the subject
  p_to_tutor uuid, -- the new tutor
  p_from date, -- the first date to move
  p_reason text, -- a short reason (only matching admins see it)
  p_tell_old_tutor boolean default true, -- whether to tell the old tutor once confirmed
  p_weekday smallint default null, -- the new weekday, or empty to keep it
  p_start time default null -- the new start time, or empty to keep it
) -- end of the inputs
returns uuid -- gives back the waiting change's id
language plpgsql security definer -- saves the change and the notices past the access rules
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_count integer; -- how many sessions would move
  v_pattern record; -- the day and time now
  v_id uuid; -- the new waiting change
  v_student text; -- the student's name
  v_to_name text; -- the new tutor's name
  v_new_text text; -- the new day and time in words
  v_family boolean := false; -- whether there's anyone in the family to ask
  p record; -- one person to ask
begin -- starts the code
  if not (private.is_front_desk() and private.has_aal2()) then -- not a matching admin with two-step sign-in
    raise exception 'Only CLG admins who do matching can change a tutor.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if exists (select 1 from public.tutor_change_offers o -- a change already waiting
             where o.student_id = p_student and o.from_tutor = p_from_tutor and lower(o.subject) = lower(btrim(p_subject)) and o.status = 'waiting') then -- (same student, tutor and subject)
    raise exception 'A change for these sessions is already waiting for confirmation. Withdraw it first to send a different one.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select * into v_pattern from public.tutor_change_pattern(p_student, p_from_tutor, p_subject, p_from); -- the day and time now
  v_count := private.apply_tutor_change(p_student, p_from_tutor, p_subject, p_to_tutor, p_from, p_reason, p_tell_old_tutor, p_weekday, p_start, auth.uid(), true); -- runs every check (changes nothing)
  insert into public.tutor_change_offers (student_id, from_tutor, to_tutor, subject, from_date, new_weekday, new_start, old_weekday, old_start, sessions, reason, tell_old_tutor, created_by) -- saves the waiting change:
  values (p_student, p_from_tutor, p_to_tutor, btrim(p_subject), p_from, -- who, what and from when,
    case when p_weekday is not null or p_start is not null then coalesce(p_weekday, v_pattern.weekday) end, -- the new day (when a day or time was given),
    case when p_weekday is not null or p_start is not null then coalesce(p_start, v_pattern.start_time) end, -- the new time (likewise),
    case when v_pattern.same_pattern then v_pattern.weekday end, case when v_pattern.same_pattern then v_pattern.start_time end, -- the day and time now (when there's one pattern),
    v_count, btrim(p_reason), coalesce(p_tell_old_tutor, true), auth.uid()) -- the count, reason, tick and who sent it
  returning id into v_id; -- keeps its id
  update public.tutor_change_offers set new_weekday = null, new_start = null -- no real change of day or time:
  where id = v_id and new_weekday is not distinct from old_weekday and new_start is not distinct from old_start; -- (same as now)
  select s.full_name into v_student from public.students s where s.id = p_student; -- the student's name
  select full_name into v_to_name from public.accounts where id = p_to_tutor; -- the new tutor's name
  select private.weekly_time_text(new_weekday, new_start) into v_new_text from public.tutor_change_offers where id = v_id; -- the new day and time in words (if changing)
  perform private.add_notice(p_to_tutor, null, null, 'booking_requested', 'Please confirm new sessions', -- asks the new tutor:
    'CLG would like you to take over ' || split_part(v_student, ' ', 1) || '''s ' || btrim(p_subject) || ' sessions from ' || trim(to_char(p_from, 'FMDD Mon')) -- the student, subject and date,
    || ' (' || v_count || ' booked' || case when v_new_text <> '' then ', ' || v_new_text else '' end || '). Please confirm or decline under Sessions.', now()); -- how many, the time, and where to answer
  for p in select * from private.session_people(p_student, p_to_tutor) where not is_tutor loop -- each parent (and the student, with their own login):
    v_family := true; -- there's someone to ask
    perform private.add_notice(p.account_id, null, null, 'booking_requested', 'Please confirm a change', -- asks them:
      'CLG would like to move ' || v_student || '''s ' || btrim(p_subject) || ' sessions from ' || trim(to_char(p_from, 'FMDD Mon')) || ' to ' || coalesce(v_to_name, 'a new tutor') -- the student, subject, date and new tutor,
      || case when v_new_text <> '' then ', on ' || v_new_text else '' end || '. Please confirm or decline under Sessions.', now()); -- the new time, and where to answer
  end loop; -- end of the family
  if not v_family then -- nobody in the family has a login to ask:
    update public.tutor_change_offers set family_ok_at = now() where id = v_id; -- only the new tutor needs to confirm
  end if; -- end of the check
  perform private.log_event('tutor_change_sent', 'tutor_change_offers', v_id::text, '{}'); -- the activity log entry (id only)
  return v_id; -- the waiting change
end; -- ends the code
$$; -- end of the function
revoke all on function public.propose_tutor_change(uuid, uuid, text, uuid, date, text, boolean, smallint, time) from public, anon; -- not for signed-out visitors
grant execute on function public.propose_tutor_change(uuid, uuid, text, uuid, date, text, boolean, smallint, time) to authenticated; -- signed-in people can try (the check is inside)

-- Makes a waiting change once everyone has confirmed. If it can't be made
-- any more (something changed meanwhile), marks it failed and tells admins
-- why, instead of showing the person who answered a confusing message.
create or replace function private.finish_tutor_change(p_offer uuid) -- takes the waiting change
returns void language plpgsql security definer -- makes the change past the access rules
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  o public.tutor_change_offers; -- the waiting change
  v_change uuid; -- the record of the change
  v_problem text; -- why it couldn't be made
begin -- starts the code
  select * into o from public.tutor_change_offers where id = p_offer for update; -- the waiting change, held
  if o.status <> 'waiting' or o.tutor_ok_at is null or o.family_ok_at is null then -- not ready
    return; -- nothing to do yet
  end if; -- end of the check
  begin -- tries to make the change:
    perform private.apply_tutor_change(o.student_id, o.from_tutor, o.subject, o.to_tutor, greatest(o.from_date, current_date), o.reason, o.tell_old_tutor, -- the same student, tutors, subject, date (not in the past), reason and tick,
      coalesce(o.new_weekday, o.old_weekday), coalesce(o.new_start, o.old_start), o.created_by, false); -- the agreed day and time, made for the admin who sent it
    select id into v_change from public.tutor_changes where student_id = o.student_id and to_tutor = o.to_tutor order by changed_at desc limit 1; -- the record just made
    update public.tutor_change_offers set status = 'confirmed', closed_at = now(), change_id = v_change where id = o.id; -- marks it done
  exception when others then -- it couldn't be made (the change is undone):
    v_problem := sqlerrm; -- the reason, in the database's words
    update public.tutor_change_offers set status = 'failed', closed_at = now(), closed_note = left(v_problem, 1000) where id = o.id; -- marks it failed, with why
    perform private.notify_admins('Tutor change couldn''t be made', -- tells the full admins:
      'Everyone confirmed a tutor change, but it couldn''t be made: ' || left(v_problem, 400) || ' Please look at Sessions > Change tutor.', null); -- why, and where to look
  end; -- end of the try
end; -- ends the code
$$; -- end of the function
revoke all on function private.finish_tutor_change(uuid) from public; -- for the database's own use only

-- The new tutor or the family confirms or declines a waiting change.
create or replace function public.answer_tutor_change(p_offer uuid, p_accept boolean, p_note text default null) -- takes the change, yes or no, and a reason for no
returns text -- gives back where it's up to: 'waiting', 'confirmed', 'declined' or 'failed'
language plpgsql security definer -- saves the answer past the access rules
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  o public.tutor_change_offers; -- the waiting change
  v_role text; -- who is answering: 'tutor' or 'family'
  v_student text; -- the student's name
  v_note text := nullif(left(btrim(coalesce(p_note, '')), 500), ''); -- the reason given, trimmed
  p record; -- one person to tell
begin -- starts the code
  select * into o from public.tutor_change_offers where id = p_offer for update; -- the waiting change, held
  if o.id is not null and o.to_tutor = auth.uid() and private.has_aal2() then -- the new tutor, with two-step sign-in
    v_role := 'tutor'; -- answers as the tutor
  elsif o.id is not null and private.is_family_of(o.student_id) then -- someone in the family
    v_role := 'family'; -- answers for the family
  else -- anyone else
    raise exception 'Change not found.' using errcode = '22023'; -- plain message (doesn't say whether it exists)
  end if; -- end of the check
  if o.status <> 'waiting' then -- already answered or withdrawn
    raise exception 'This change has already been %.', o.status using errcode = '22023'; -- plain message
  end if; -- end of the check
  if (v_role = 'tutor' and o.tutor_ok_at is not null) or (v_role = 'family' and o.family_ok_at is not null) then -- already confirmed by them
    raise exception 'You''ve already confirmed this change. It''s waiting for the others.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select full_name into v_student from public.students where id = o.student_id; -- the student's name
  if coalesce(p_accept, false) then -- a yes:
    if v_role = 'tutor' then -- from the tutor
      update public.tutor_change_offers set tutor_ok_at = now() where id = o.id; -- records it
    else -- from the family
      update public.tutor_change_offers set family_ok_at = now(), family_ok_by = auth.uid() where id = o.id; -- records it, and who
    end if; -- end of the yes
    perform private.finish_tutor_change(o.id); -- makes the change if everyone has now confirmed
  else -- a no:
    if v_note is null then -- no reason given
      raise exception 'Please say briefly why, so CLG can find something that suits.' using errcode = '22023'; -- plain message
    end if; -- end of the check
    update public.tutor_change_offers set status = 'declined', declined_by_role = v_role, answer_note = v_note, closed_at = now() where id = o.id; -- records the no
    perform private.notify_admins('Tutor change declined', -- tells the full admins:
      'The ' || v_role || ' declined the change for ' || v_student || ' (' || o.subject || '): ' || v_note, null); -- who, which student, and why
    if v_role = 'family' and o.tutor_ok_at is not null then -- the tutor had already said yes:
      perform private.add_notice(o.to_tutor, null, null, 'booking_declined', 'Change not going ahead', -- tells them
        split_part(v_student, ' ', 1) || '''s ' || o.subject || ' sessions won''t be moved to you after all. CLG will be in touch if anything else comes up.', now()); -- plainly
    elsif v_role = 'tutor' then -- the tutor said no:
      for p in select * from private.session_people(o.student_id, o.to_tutor) where not is_tutor loop -- each parent (and the student, with their own login):
        perform private.add_notice(p.account_id, null, null, 'booking_declined', 'Change not going ahead', -- tells them
          v_student || '''s ' || o.subject || ' sessions are staying as they are for now. CLG will be in touch soon.', now()); -- plainly
      end loop; -- end of the family
    end if; -- end of telling the other side
  end if; -- end of yes or no
  perform private.log_event('tutor_change_answered', 'tutor_change_offers', o.id::text, jsonb_build_object('role', v_role, 'accept', coalesce(p_accept, false))); -- the activity log entry (id, who and yes or no)
  return (select status from public.tutor_change_offers where id = o.id); -- where it's up to now
end; -- ends the code
$$; -- end of the function
revoke all on function public.answer_tutor_change(uuid, boolean, text) from public, anon; -- not for signed-out visitors
grant execute on function public.answer_tutor_change(uuid, boolean, text) to authenticated; -- signed-in people can try (the check is inside)

-- The admin withdraws a waiting change.
create or replace function public.withdraw_tutor_change(p_offer uuid, p_note text default null) -- takes the change and an optional note
returns void language plpgsql security definer -- changes the waiting change past the access rules
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  o public.tutor_change_offers; -- the waiting change
  v_student text; -- the student's name
  p record; -- one person to tell
begin -- starts the code
  if not (private.is_front_desk() and private.has_aal2()) then -- not a matching admin with two-step sign-in
    raise exception 'Only CLG admins who do matching can withdraw a change.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  update public.tutor_change_offers set status = 'withdrawn', closed_at = now(), closed_note = nullif(left(btrim(coalesce(p_note, '')), 1000), '') -- marks it withdrawn, with any note
  where id = p_offer and status = 'waiting' returning * into o; -- (only a waiting change)
  if o.id is null then -- nothing changed
    raise exception 'That change isn''t waiting any more.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select full_name into v_student from public.students where id = o.student_id; -- the student's name
  for p in select * from private.session_people(o.student_id, o.to_tutor) loop -- the new tutor and the family:
    perform private.add_notice(p.account_id, null, null, 'booking_declined', 'Change withdrawn', -- tells them
      case when p.is_tutor then split_part(v_student, ' ', 1) else v_student end || '''s ' || o.subject || ' sessions are staying as they are. You don''t need to do anything.', now()); -- plainly
  end loop; -- end of telling them
  perform private.log_event('tutor_change_withdrawn', 'tutor_change_offers', o.id::text, '{}'); -- the activity log entry (id only)
end; -- ends the code
$$; -- end of the function
revoke all on function public.withdraw_tutor_change(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.withdraw_tutor_change(uuid, text) to authenticated; -- signed-in people can try (the check is inside)

-- The waiting changes the signed-in person needs to answer (as the new
-- tutor, or for the family). The admin's reason is never shown.
create or replace function public.my_tutor_changes_to_answer() -- no inputs
returns table (id uuid, answer_as text, student_name text, subject text, from_tutor_name text, to_tutor_name text, from_date date, sessions integer, old_time text, new_time text, created_at timestamptz) -- what the card shows
language sql stable security definer -- reads past the access rules, only the person's own
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select o.id, x.role, s.full_name, o.subject, -- the change, who they answer as, the student and subject,
    case when x.role = 'family' then f.full_name end, t.full_name, -- the current tutor's name (families only) and the new tutor's,
    o.from_date, o.sessions, private.weekly_time_text(o.old_weekday, o.old_start), private.weekly_time_text(o.new_weekday, o.new_start), o.created_at -- the date, count, old and new times, and when sent
  from public.tutor_change_offers o -- each waiting change
  join public.students s on s.id = o.student_id -- with the student's name
  left join public.accounts f on f.id = o.from_tutor -- the current tutor's name
  left join public.accounts t on t.id = o.to_tutor -- the new tutor's name
  cross join lateral (select case -- who they answer as:
      when o.to_tutor = auth.uid() and o.tutor_ok_at is null and private.has_aal2() then 'tutor' -- the new tutor, not yet answered,
      when o.family_ok_at is null and private.is_family_of(o.student_id) then 'family' -- the family, not yet answered,
    end as role) x -- (or nobody)
  where o.status = 'waiting' and x.role is not null -- waiting, and theirs to answer
  order by o.created_at -- oldest first
$$; -- end of the function
revoke all on function public.my_tutor_changes_to_answer() from public, anon; -- not for signed-out visitors
grant execute on function public.my_tutor_changes_to_answer() to authenticated; -- signed-in people (only their own)

-- The waiting and recent changes, for matching admins.
create or replace function public.tutor_change_offers_list(p_student uuid default null) -- takes an optional student
returns table (id uuid, status text, student_name text, subject text, from_tutor_name text, to_tutor_name text, from_date date, sessions integer, old_time text, new_time text, tutor_ok boolean, family_ok boolean, declined_by_role text, answer_note text, closed_note text, reason text, created_at timestamptz) -- what the page shows
language plpgsql stable security definer -- reads past the access rules, for matching admins only
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if not (private.is_front_desk() and private.has_aal2()) then -- not a matching admin with two-step sign-in
    raise exception 'Only CLG admins who do matching can see tutor changes.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  return query -- gives back:
  select o.id, o.status, s.full_name, o.subject, f.full_name, t.full_name, o.from_date, o.sessions, -- the change, student, subject, tutors, date and count,
    private.weekly_time_text(o.old_weekday, o.old_start), private.weekly_time_text(o.new_weekday, o.new_start), -- the old and new times,
    o.tutor_ok_at is not null, o.family_ok_at is not null, o.declined_by_role, o.answer_note, o.closed_note, o.reason, o.created_at -- who has confirmed, any no and why, notes, reason and when sent
  from public.tutor_change_offers o -- each change
  join public.students s on s.id = o.student_id -- with the student's name
  left join public.accounts f on f.id = o.from_tutor -- the current tutor's name
  left join public.accounts t on t.id = o.to_tutor -- the new tutor's name
  where (p_student is null or o.student_id = p_student) -- just this student, if one was chosen
    and (o.status = 'waiting' or o.closed_at > now() - interval '30 days') -- waiting, or closed in the last 30 days
  order by (o.status = 'waiting') desc, o.created_at desc -- waiting first, then newest
  limit 50; -- at most 50
end; -- ends the code
$$; -- end of the function
revoke all on function public.tutor_change_offers_list(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.tutor_change_offers_list(uuid) to authenticated; -- signed-in people can try (the check is inside)
