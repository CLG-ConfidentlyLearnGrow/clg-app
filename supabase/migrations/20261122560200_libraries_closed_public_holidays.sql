-- Summary: libraries are closed on public holidays by default (Carla, 20 Nov 2026).
--
-- Carla asked: "Can it be default that libraries close on public holidays?"
-- Most South Australian public libraries close on public holidays, so CLG
-- now treats every library as closed on its state's public holidays unless
-- an admin ticks "Open on public holidays" for that library.
--
-- What changes:
--   * libraries gets open_public_holidays (false for every library, old and
--     new, until an admin changes it under Sessions > Libraries).
--   * private.library_closed_on(library, date) says whether a library is
--     closed that day because of a public holiday in the library's state.
--   * Times offered for a one-off date skip a library closed that day
--     (private.library_open now checks it).
--   * Weekly bookings at a library do not make a session on a public holiday
--     the library is closed (like a booking that skips public holidays). The
--     family can still ask for a one-off at another time that week. Any other
--     new library session on such a day is refused with a plain message.
--   * The public holiday list families see says "library closed" for those
--     weeks (list_public_holiday_weeks gains a library_closed column).
--   * The notices asking admins to check a library's holiday hours now say
--     it is set as closed on public holidays, and how to change that.
--   * The libraries to-do list says a library to confirm was "asked for by a
--     tutor, family or student" (it said "suggested by a tutor").
--
-- It does NOT cancel sessions already booked. The last step lists any booked
-- library sessions on an upcoming public holiday at a library now counted as
-- closed, so CLG can move or cancel them with the family.
--
-- Scheduling module (libraries, sessions it is asked to make, notices to
-- admins). Safe to run more than once.
-- Run after 20261122560100_tick_off_notices.sql.

-- ---------------------------------------------------------------------------
-- 1. Whether a library opens on public holidays (no, unless an admin says so).
-- ---------------------------------------------------------------------------
alter table public.libraries add column if not exists open_public_holidays boolean not null default false; -- false = closed on public holidays (the default for every library)

-- ---------------------------------------------------------------------------
-- 2. Is a library closed on a date because of a public holiday?
-- ---------------------------------------------------------------------------
create or replace function private.library_closed_on(p_library uuid, p_date date) -- the library and the date
returns boolean -- true if closed for a public holiday
language sql stable -- only reads, same answer within one query
security definer -- reads libraries and holidays whoever is asking
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the answer:
  select exists ( -- true if there is
    select 1 -- any row
    from public.libraries l -- among the libraries
    join public.public_holidays h on h.state = l.state and h.holiday_on = p_date -- with a public holiday in the library's state on that date (uses the state + date index)
    where l.id = p_library -- for this library
      and not l.open_public_holidays -- and the library does not open on public holidays
  ) -- end of the check
$$; -- end of the function
revoke all on function private.library_closed_on(uuid, date) from public; -- only used inside the database

-- ---------------------------------------------------------------------------
-- 3. One-off times: a library must be confirmed, shown, inside its weekly
--    hours, and not closed for a public holiday that day.
-- ---------------------------------------------------------------------------
create or replace function private.library_open(p_library uuid, p_date date, p_start time, p_minutes integer) -- the library, date, start time and length
returns boolean -- true if a session can be held there then
language sql stable -- only reads
security definer -- reads libraries whoever is asking
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the answer:
  select exists (select 1 from public.libraries l where l.id = p_library and l.active and l.confirmed_at is not null) -- the library is shown and confirmed,
     and private.library_open_weekly(p_library, extract(isodow from p_date)::smallint, p_start, p_minutes) -- open for the whole session that weekday,
     and not private.library_closed_on(p_library, p_date) -- and not closed for a public holiday that day
$$; -- end of the function
revoke all on function private.library_open(uuid, date, time, integer) from public; -- only used inside the database

-- ---------------------------------------------------------------------------
-- 4. New sessions: skip public holidays when the booking skips them (as
--    before), and never make a session at a library closed that day.
-- ---------------------------------------------------------------------------
create or replace function private.skip_public_holiday_session() -- runs before each new session is saved
returns trigger -- gives back the session to save, or nothing to skip it
language plpgsql -- written as a small program
security definer -- reads bookings, students and libraries whoever adds the session
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the program:
declare -- working values:
  v_state public.au_state; -- the student's state
  v_lib_state public.au_state; -- the library's state
begin -- start
  if new.delivery = 'library' and new.library_id is not null then -- if the session is at a library:
    select l.state into v_lib_state from public.libraries l where l.id = new.library_id; -- finds the library's state
    if private.library_closed_on(new.library_id, (new.starts_at at time zone private.state_timezone(coalesce(v_lib_state, 'SA')))::date) then -- if the library is closed for a public holiday that day (in the library's local time):
      if new.booking_id is not null then -- part of a weekly booking:
        return null; -- skips that week's session (the family can ask for a one-off at another time that week)
      end if; -- end of the booking case
      raise exception 'That library is closed on this public holiday. Please choose another day, online, or another library.' using errcode = '23514'; -- any other session: stops with a plain message
    end if; -- end of the closed check
  end if; -- end of the library check
  if new.booking_id is null -- if the session is not part of a booking,
     or not exists (select 1 from public.bookings b where b.id = new.booking_id and b.skip_public_holidays) then -- or the booking does not skip public holidays:
    return new; -- saves the session as normal
  end if; -- end of that check
  select s.state into v_state from public.students s where s.id = new.student_id; -- finds the student's state
  if exists ( -- if there is
    select 1 from public.public_holidays h -- a public holiday
    where h.state = v_state and h.holiday_on = (new.starts_at at time zone private.state_timezone(v_state))::date -- in the student's state on the session's local date:
  ) then -- then
    return null; -- skips the session (the booking skips public holidays)
  end if; -- end of the holiday check
  return new; -- otherwise saves the session
end; -- end of the program
$$; -- end of the function
drop trigger if exists skip_public_holidays on public.sessions; -- removes the old trigger (if any)
create trigger skip_public_holidays before insert on public.sessions -- runs before each new session is saved
  for each row execute function private.skip_public_holiday_session(); -- using the program above

-- ---------------------------------------------------------------------------
-- 5. The public holiday list: also say when the booking's library is closed.
--    The answer gains a column, so the old version is removed first.
-- ---------------------------------------------------------------------------
drop function if exists public.list_public_holiday_weeks(); -- removes the old version (its answer had one column fewer)
create function public.list_public_holiday_weeks() -- upcoming public holidays (next 120 days) that fall on a booking's weekday
returns table ( -- one row per booking and holiday:
  booking_id uuid, student_id uuid, student_name text, subject text, holiday_on date, holiday_name text, -- the booking, student, subject and holiday,
  skipping boolean, session_id uuid, library_closed boolean -- whether the booking skips holidays, the session that day (if any), and whether its library is closed that day
)
language sql stable -- only reads
security definer -- reads across tables; the where line below limits who sees what
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the list:
  select b.id, b.student_id, s.full_name, b.subject, h.holiday_on, h.name, b.skip_public_holidays, -- the booking, student, subject, holiday and skip setting,
         (select x.id from public.sessions x -- the session booked that day (if any):
          where x.booking_id = b.id and x.status = 'scheduled' -- for this booking, still booked,
            and (x.starts_at at time zone private.state_timezone(s.state))::date = h.holiday_on -- on the holiday (student's local date)
          limit 1), -- just one
         (b.delivery = 'library' and b.library_id is not null and private.library_closed_on(b.library_id, h.holiday_on)) -- whether the booking's library is closed that day
  from public.bookings b -- from bookings
  join public.students s on s.id = b.student_id -- with their student
  join public.public_holidays h -- and the public holidays
    on h.state = s.state -- in the student's state
   and h.holiday_on between greatest(b.first_date, current_date) and least(b.last_date, current_date + 120) -- within the booking's dates and the next 120 days
   and extract(isodow from h.holiday_on)::int = b.weekday -- on the booking's weekday
  where b.status = 'confirmed' -- confirmed bookings only
    and ((select private.is_admin()) or private.can_book_for(b.student_id)) -- admins see all; families see their own
  order by h.holiday_on, s.full_name -- soonest first, then by name
$$; -- end of the function
revoke all on function public.list_public_holiday_weeks() from public, anon; -- nobody signed out can use it
grant execute on function public.list_public_holiday_weeks() to authenticated; -- signed-in people can (their own only)

-- ---------------------------------------------------------------------------
-- 6. The notices to admins about library hours: say it is set as closed on
--    public holidays, and how to change that.
-- ---------------------------------------------------------------------------
create or replace function private.ask_for_library_hours(p_library uuid) -- the library chosen for sessions
returns void -- gives nothing back
language plpgsql -- written as a small program
security definer -- updates libraries and notifies admins whoever triggered it
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the program:
declare -- working values:
  v_name text; -- the library's name
begin -- start
  update public.libraries l set hours_requested_at = now() -- notes that hours were asked for,
  where l.id = p_library and l.hours_requested_at is null -- only the first time,
    and not exists (select 1 from public.library_hours h where h.library_id = l.id) -- and only if it has no hours yet,
  returning l.name into v_name; -- keeping its name
  if v_name is not null then -- if this is the first time:
    perform private.notify_admins('Library opening hours needed', -- tells admins, with this title
      v_name || ' has been chosen for sessions. Please add its opening hours under Sessions > Libraries. ' -- what to do,
      || 'It is set as closed on public holidays: if it opens on public holidays, choose "Set as open on public holidays" there. ' -- the public holiday default and how to change it,
      || 'Also check whether it changes its hours in the school holidays.'); -- and the school holiday check
  end if; -- end of the first-time check
end; -- end of the program
$$; -- end of the function
revoke all on function private.ask_for_library_hours(uuid) from public; -- only used inside the database

create or replace function private.first_booking_at_library() -- runs after each new booking
returns trigger -- gives back the booking
language plpgsql -- written as a small program
security definer -- updates libraries and notifies admins whoever made the booking
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the program:
declare -- working values:
  v_name text; -- the library's name
begin -- start
  if new.delivery <> 'library' or new.library_id is null then -- if the booking is not at a library:
    return new; -- nothing to do
  end if; -- end of that check
  update public.libraries set first_booked_at = now() -- notes the first booking there,
  where id = new.library_id and first_booked_at is null -- only the first time,
  returning name into v_name; -- keeping its name
  if v_name is not null then -- if this is the first booking there:
    perform private.notify_admins('First sessions at a library', -- tells admins, with this title
      'Sessions are being booked at ' || v_name || ' for the first time. It is set as closed on public holidays, ' -- what is happening and the default,
      || 'so no session is held there on one. If it opens on public holidays, choose "Set as open on public holidays" under Sessions > Libraries. ' -- how to change it,
      || 'Also check whether it changes its hours in the school holidays. If its website does not say, call the library.', -- and the school holiday check
      new.id); -- linked to this booking
  end if; -- end of the first-time check
  return new; -- keeps the booking
end; -- end of the program
$$; -- end of the function
revoke all on function private.first_booking_at_library() from public; -- only used inside the database

-- ---------------------------------------------------------------------------
-- 7. The libraries to-do list (Carla, 20 Nov 2026): a library not yet
--    confirmed may have been asked for by a tutor, a family or a student, so
--    the wording no longer says "Suggested by a tutor". Same list otherwise.
-- ---------------------------------------------------------------------------
create or replace function public.library_checks() -- libraries in use that need a look
returns table (library_id uuid, name text, suburb text, problem text) -- the library and what needs doing
language plpgsql stable -- written as a small program that only reads
security definer -- reads tutor and family places, which admins may not read directly
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the program:
begin -- start
  if not (select private.is_front_desk()) then -- if the person is not a front-desk admin:
    raise exception 'Only CLG admins can see library checks' using errcode = '42501'; -- stops with a plain message
  end if; -- end of the check
  return query -- gives back:
  with in_use as ( -- the libraries someone has asked for or uses:
    select tp.library_id as id from public.tutor_places tp -- chosen by a tutor,
    union select unnest(sp.library_ids) from public.student_places sp -- chosen for a student (by a family, a student or CLG),
    union select b.library_id from public.bookings b -- or used by a live booking
      where b.library_id is not null and private.booking_is_live(b.status, b.tutor_reply_by) -- (only bookings still going)
  ) -- end of the list
  select l.id, l.name, l.suburb, -- each library's id, name and suburb,
         case -- and what needs doing:
           when l.confirmed_at is null then 'Asked for by a tutor, family or student: confirm it' -- not confirmed yet,
           when not exists (select 1 from public.library_hours h where h.library_id = l.id) then 'Opening hours needed' -- no opening hours yet,
           else 'Check the opening hours are still right' -- or hours due for a re-check
         end -- end of what needs doing
  from public.libraries l -- from the libraries
  join in_use u on u.id = l.id -- that are in use
  where l.active -- and shown
    and (l.confirmed_at is null -- and not confirmed,
         or not exists (select 1 from public.library_hours h where h.library_id = l.id) -- or without hours,
         or l.hours_checked_at is null -- or hours never checked,
         or l.hours_checked_at < now() - interval '6 months') -- or last checked over 6 months ago
  order by l.name; -- by name
end; -- end of the program
$$; -- end of the function
revoke all on function public.library_checks() from public, anon; -- nobody signed out can use it
grant execute on function public.library_checks() to authenticated; -- signed-in people can ask (only front-desk admins get an answer)

-- ---------------------------------------------------------------------------
-- 8. Check: booked library sessions on an upcoming public holiday at a
--    library now counted as closed. If any are listed, move or cancel them
--    with the family (nothing here changes them). No rows means none.
-- ---------------------------------------------------------------------------
select x.starts_at at time zone 'Australia/Adelaide' as session_starts_adelaide_time, -- when the session starts (Adelaide time)
       l.name as library, -- which library
       h.name as public_holiday, -- which public holiday
       s.full_name as student -- which student
from public.sessions x -- from sessions
join public.libraries l on l.id = x.library_id -- with their library
join public.students s on s.id = x.student_id -- and student
join public.public_holidays h on h.state = l.state -- and public holidays in the library's state
  and h.holiday_on = (x.starts_at at time zone private.state_timezone(l.state))::date -- on the session's local date
where x.status = 'scheduled' -- still booked
  and x.starts_at >= now() -- in the future
  and x.delivery = 'library' -- at a library
  and not l.open_public_holidays -- that is counted as closed on public holidays
order by x.starts_at; -- soonest first
