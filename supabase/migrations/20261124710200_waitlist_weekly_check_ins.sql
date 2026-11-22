-- Scheduling: check in with each waiting family every week (Carla, 22 Nov
-- 2026, from her notes on Emma's Job Proposal: "Waitlist check-in flag:
-- weekly instead of every 4 weeks").
--
-- Before: a waitlist place showed "Waiting 4+ weeks" once it was 28 days
-- old, and nothing showed whether anyone had been in touch since.
-- Now:
--   * Each place remembers when CLG last checked in with the family
--     (checked_in_at) and who did it (checked_in_by).
--   * A place is due for a check-in once 7 days have passed since the last
--     check-in (or since the family joined the waitlist, if no one has
--     checked in yet). The waitlist shows "Check in due" on those places.
--   * Front desk admins (owner, Operations and Support) press "Checked in"
--     after they contact the family, which starts the next 7 days.
--   * The Waitlist sub-tab on Sessions shows how many check-ins are due.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- When CLG last checked in with the family about each place.
-- ---------------------------------------------------------------------------
alter table public.waitlist add column if not exists checked_in_at timestamptz; -- when CLG last checked in (empty: not yet)
alter table public.waitlist add column if not exists checked_in_by uuid references public.accounts (id) on delete set null; -- who checked in last

-- ---------------------------------------------------------------------------
-- Whether a place is due for a check-in (7 days since the last one, or
-- since the family joined, if there has not been one).
-- ---------------------------------------------------------------------------
create or replace function private.waitlist_check_in_due(p_created timestamptz, p_checked timestamptz) -- when they joined, and the last check-in
returns boolean language sql stable -- reads the clock, so the answer can change over time
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the rule
  select coalesce(p_checked, p_created) <= now() - interval '7 days' -- due once 7 days have passed since the last contact
$$; -- end of the function
revoke all on function private.waitlist_check_in_due(timestamptz, timestamptz) from public; -- not for everyone by default
grant execute on function private.waitlist_check_in_due(timestamptz, timestamptz) to authenticated, service_role; -- signed-in people need it for their to-do numbers (it only compares two dates)

-- ---------------------------------------------------------------------------
-- The waitlist as listed on Sessions, Waitlist. The 4-week tag is replaced
-- by "check in due" and the last check-in date. (The list's columns change,
-- so the old version is removed first.)
-- ---------------------------------------------------------------------------
drop function if exists public.list_waitlist(); -- removes the old list (its columns change)
create function public.list_waitlist() -- no inputs
returns table ( -- one row per open place:
  id uuid, student_id uuid, student_name text, year_level text, subject text, minutes integer, -- the place, student, subject and length,
  online boolean, library_names text[], weekdays smallint[], earliest time, latest time, -- where and when suits,
  tutor_name text, note text, created_at timestamptz, -- the tutor they wait for, the note, and when they joined,
  checked_in_at timestamptz, check_in_due boolean, times_now_free bigint -- the last check-in, whether one is due, and how many times suit now
)
language sql stable security definer -- reads the waitlist for them; who can see is checked below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the list
  select w.id, w.student_id, s.full_name, s.year_level, w.subject, w.minutes, -- the place, student, subject and length,
         w.online, -- online or not,
         array(select l.name from public.libraries l where l.id = any (w.library_ids) order by l.name), -- the libraries' names,
         w.weekdays, w.earliest, w.latest, a.full_name, w.note, w.created_at, -- days, times, tutor, note and when they joined,
         w.checked_in_at, -- the last check-in,
         private.waitlist_check_in_due(w.created_at, w.checked_in_at), -- whether a check-in is due (7 days),
         (select count(*) from public.find_session_times( -- how many times suit now:
            w.student_id, w.subject, w.minutes, w.online, w.library_ids, null, -- for this student, subject, length and places,
            w.weekdays, w.earliest, w.latest) f -- on the days and times that suit,
          where w.tutor_id is null or f.tutor_id = w.tutor_id) -- with the named tutor, if they wait for one
  from public.waitlist w -- from the waitlist
  join public.students s on s.id = w.student_id -- with the student
  left join public.accounts a on a.id = w.tutor_id -- and the tutor they wait for (if any)
  where w.closed_at is null -- open places only
    and (private.is_front_desk() or private.can_book_for(w.student_id)) -- front desk admins, or the student's own family
  order by w.created_at -- longest waiting first
$$; -- end of the function
revoke all on function public.list_waitlist() from public, anon; -- not for signed-out visitors
grant execute on function public.list_waitlist() to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- A front desk admin records that they checked in with the family.
-- ---------------------------------------------------------------------------
create or replace function public.waitlist_checked_in(p_id uuid) -- the waitlist place
returns void language plpgsql security definer -- saves for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_front_desk() then -- only the owner, Operations and Support admins
    raise exception 'Only CLG admins can record a waitlist check-in' using errcode = '42501'; -- plain message for anyone else
  end if; -- end of the check
  update public.waitlist set checked_in_at = now(), checked_in_by = auth.uid() -- records the check-in now, and who did it
  where id = p_id and closed_at is null; -- on this open place
  if not found then -- no open place with that id:
    raise exception 'That waitlist place is no longer open' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
end; -- end of the code
$$; -- end of the function
revoke all on function public.waitlist_checked_in(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.waitlist_checked_in(uuid) to authenticated; -- signed-in people can try (the check is inside)

-- ---------------------------------------------------------------------------
-- The Waitlist sub-tab counts the check-ins due (front desk admins only).
-- The to-do function is edited in place, so anything else in it is kept.
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_def text; -- the to-do function's code
  v_old text := E'  if v_admin then\n    area := ''sessions''; section := ''libraries'';\n'; -- the line the new count goes before
begin -- start
  if to_regprocedure('public.to_do_counts()') is null then return; end if; -- not there: nothing to do
  v_def := replace(pg_get_functiondef('public.to_do_counts()'::regprocedure), chr(13), ''); -- reads its current code (without Windows line endings)
  if strpos(v_def, 'waitlist_check_in_due') > 0 then return; end if; -- already added: nothing to do
  if strpos(v_def, v_old) = 0 then -- the place to add it has changed:
    raise exception 'to_do_counts has changed since this update was written. Ask for an updated file.'; -- stops, so nothing half-changes
  end if; -- end of the check
  v_def := replace(v_def, v_old, -- adds the waitlist count before the libraries count:
    E'  if v_desk then\n' -- for front desk admins:
    || E'    area := ''sessions''; section := ''waitlist'';\n' -- the Waitlist sub-tab,
    || E'    n := (select count(*) from public.waitlist w where w.closed_at is null and private.waitlist_check_in_due(w.created_at, w.checked_in_at)); -- open places due for a weekly check-in\n'
    || E'    return next;\n' -- hands back the count,
    || E'  end if;\n' -- end of the front desk part,
    || v_old); -- then the libraries count as before
  execute v_def; -- saves the changed function
end; -- finish
$$; -- end of the block
