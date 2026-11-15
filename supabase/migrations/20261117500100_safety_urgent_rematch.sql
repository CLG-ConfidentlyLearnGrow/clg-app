-- Summary: urgent re-matching after a match is ended from a concern (Carla, 15 Nov 2026).
--
-- When the person handling a concern ends a tutor's match with a child
-- ("End match", 20261117400100), the child may already have sessions booked
-- and paid for with that tutor. Carla: those pre-purchased sessions are now
-- high priority and need a new tutor. So ending a match now also:
--   * counts the child's upcoming sessions with that tutor, and how many of
--     them are already on an invoice (paid, or invoiced and waiting);
--   * if there are any, adds an "Urgent: needs a new tutor" flag that shows
--     at the top of the Matching page for every admin who does matching
--     (owner, operations and support), with the child, subject, how many
--     sessions are paid for, and the first date. It gives NO reason, so the
--     concern stays confidential;
--   * the flag stays until an admin marks it sorted.
--
-- This module only writes its own table. It reads sessions, bookings and
-- invoice lines to count; it never changes them (moving sessions to a new
-- tutor is done in Sessions, as usual).
--
-- Needs 20261117400100_safety_quiet_steps.sql. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The urgent flags
-- ---------------------------------------------------------------------------

create table if not exists public.safety_rematch_flags ( -- one row per child needing a new tutor urgently
  id uuid primary key default gen_random_uuid(), -- the flag's id
  hold_id uuid not null unique references public.safety_holds (id) on delete cascade, -- the "end match" step that caused it (one flag per step)
  student_id uuid not null references public.students (id) on delete cascade, -- the child
  tutor_id uuid references public.accounts (id) on delete set null, -- the tutor the sessions are still booked with
  subjects text not null default '' check (char_length(subjects) <= 300), -- the subjects of those sessions, e.g. "English, Maths"
  upcoming_sessions integer not null default 0 check (upcoming_sessions >= 0), -- how many sessions are booked from now on
  paid_sessions integer not null default 0 check (paid_sessions >= 0), -- how many of them are on an invoice already (paid or waiting)
  first_session date, -- the date of the first of them
  upcoming_bookings integer not null default 0 check (upcoming_bookings >= 0), -- how many weekly bookings are still running
  created_at timestamptz not null default now(), -- when the flag was raised
  sorted_at timestamptz, -- when an admin marked it sorted (empty while urgent)
  sorted_by uuid references public.accounts (id) on delete set null, -- who did
  sorted_note text check (char_length(sorted_note) <= 1000) -- what they did, e.g. "Moved to Jack from 20 Nov"
); -- end of the table
create index if not exists safety_rematch_open on public.safety_rematch_flags (created_at) where sorted_at is null; -- finds open flags quickly
alter table public.safety_rematch_flags enable row level security; -- turns on access rules (no rule: read only through the functions below)
revoke all on public.safety_rematch_flags from anon, authenticated; -- nobody reads or changes it directly

-- ---------------------------------------------------------------------------
-- Counting a child's upcoming sessions with a tutor
-- ---------------------------------------------------------------------------

-- Raises (or refreshes) the urgent flag for an "end match" step, if the
-- child has any upcoming sessions or bookings with that tutor.
create or replace function private.raise_rematch_flag(p_hold uuid) -- takes the "end match" step
returns void -- gives nothing back
language plpgsql security definer -- reads sessions and invoices, writes this module's table
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_hold public.safety_holds; -- the step
  v_upcoming integer; -- upcoming sessions
  v_paid integer; -- of those, on an invoice
  v_first date; -- the first one's date
  v_subjects text; -- their subjects
  v_bookings integer; -- running bookings
begin -- starts the code
  select * into v_hold from public.safety_holds where id = p_hold and kind = 'end_match'; -- the step
  if v_hold.id is null then -- not an "end match" step
    return; -- nothing to do
  end if; -- end of the check
  select count(*)::integer, -- how many sessions,
    count(*) filter (where exists ( -- how many are on a live invoice
      select 1 from public.billing_invoice_lines l -- an invoice line
      join public.billing_invoices i on i.id = l.invoice_id -- on an invoice
      where l.session_id = s.id and l.active and i.status <> 'void' -- for this session, not voided
    ))::integer, -- (paid, or sent and waiting)
    min((s.starts_at at time zone 'Australia/Adelaide')::date), -- the first date (Adelaide time),
    coalesce(string_agg(distinct s.subject, ', '), '') -- and the subjects
  into v_upcoming, v_paid, v_first, v_subjects -- kept for below
  from public.sessions s -- from the sessions
  where s.tutor_id = v_hold.tutor_id and s.student_id = v_hold.student_id -- for this tutor and child
    and s.status = 'scheduled' and s.starts_at >= now(); -- still to come
  select count(*)::integer into v_bookings from public.bookings b -- counts the running bookings
  where b.tutor_id = v_hold.tutor_id and b.student_id = v_hold.student_id -- for this pair
    and b.status in ('requested', 'confirmed') and b.last_date >= current_date; -- still running or waiting
  if v_upcoming = 0 and v_bookings = 0 then -- nothing booked
    return; -- no flag needed
  end if; -- end of the check
  insert into public.safety_rematch_flags (hold_id, student_id, tutor_id, subjects, upcoming_sessions, paid_sessions, first_session, upcoming_bookings) -- the flag:
  values (v_hold.id, v_hold.student_id, v_hold.tutor_id, left(v_subjects, 300), v_upcoming, v_paid, v_first, v_bookings) -- with the counts
  on conflict (hold_id) do update set -- or, if already there, refreshes the counts:
    subjects = excluded.subjects, upcoming_sessions = excluded.upcoming_sessions, paid_sessions = excluded.paid_sessions, -- subjects and counts,
    first_session = excluded.first_session, upcoming_bookings = excluded.upcoming_bookings; -- first date and bookings
end; -- ends the code
$$; -- end of the function
revoke all on function private.raise_rematch_flag(uuid) from public; -- for the database's own use only

-- Raises the flag whenever an "end match" step is saved, so the step itself doesn't need changing.
create or replace function private.rematch_after_end_match() -- runs after a step is saved
returns trigger -- a trigger function
language plpgsql security definer -- calls the function above
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if new.kind = 'end_match' then -- an "end match" step
    perform private.raise_rematch_flag(new.id); -- raises the flag (if anything is booked)
  end if; -- end of the check
  return null; -- (an "after" trigger: the saved row isn't changed)
end; -- ends the code
$$; -- end of the function
revoke all on function private.rematch_after_end_match() from public; -- for the database's own use only
drop trigger if exists rematch_flag on public.safety_holds; -- removes the old trigger if the file is run again
create trigger rematch_flag after insert on public.safety_holds -- after a step is saved
  for each row execute function private.rematch_after_end_match(); -- runs the function above

-- ---------------------------------------------------------------------------
-- For the Matching page (admins who do matching)
-- ---------------------------------------------------------------------------

-- The open urgent flags, oldest first. No reason is given.
create or replace function public.urgent_rematches() -- no inputs
returns table (id uuid, student_id uuid, student_name text, tutor_name text, subjects text, upcoming_sessions integer, paid_sessions integer, first_session date, upcoming_bookings integer, created_at timestamptz) -- what the box shows
language sql stable security definer -- reads past the access rules, for matching admins only
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select f.id, f.student_id, s.full_name, a.full_name, f.subjects, f.upcoming_sessions, f.paid_sessions, f.first_session, f.upcoming_bookings, f.created_at -- the flag and names
  from public.safety_rematch_flags f -- each flag
  join public.students s on s.id = f.student_id -- with the child's name
  left join public.accounts a on a.id = f.tutor_id -- and the tutor's name (the sessions are still with them)
  where f.sorted_at is null -- still urgent
    and private.is_front_desk() -- only for admins who do matching (owner, operations, support)
    and f.tutor_id is distinct from auth.uid() -- never the tutor themselves (if they're also an admin)
  order by f.first_session nulls last, f.created_at -- soonest session first
$$; -- end of the function
revoke all on function public.urgent_rematches() from public, anon; -- not for signed-out visitors
grant execute on function public.urgent_rematches() to authenticated; -- signed-in people (only matching admins get rows)

-- Marks a flag sorted, with a short note on what was done.
create or replace function public.urgent_rematch_sorted(p_id uuid, p_note text) -- takes the flag and the note
returns void -- gives nothing back
language plpgsql security definer -- changes this module's table
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if not private.is_front_desk() then -- not an admin who does matching
    raise exception 'Only CLG admins who do matching can mark this sorted.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_note, ''))) < 2 then -- no note
    raise exception 'Please say what was done, e.g. "Moved to a new tutor from 20 Nov".' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.safety_rematch_flags -- marks it sorted
  set sorted_at = now(), sorted_by = auth.uid(), sorted_note = left(btrim(p_note), 1000) -- when, who and what
  where id = p_id and sorted_at is null and tutor_id is distinct from auth.uid(); -- (only an open flag, never by the tutor themselves)
  if not found then -- nothing changed
    raise exception 'That flag isn''t open any more.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  perform private.log_event('urgent_rematch_sorted', 'safety_rematch_flags', p_id::text, '{}'); -- notes it in the activity log (id only)
end; -- ends the code
$$; -- end of the function
revoke all on function public.urgent_rematch_sorted(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.urgent_rematch_sorted(uuid, text) to authenticated; -- signed-in people can try (the check is inside)

-- The person handling the concern sees the flag's state on the concern too.
create or replace function public.safety_concern_rematch(p_concern uuid) -- takes the concern
returns table (tutor_id uuid, upcoming_sessions integer, paid_sessions integer, first_session date, sorted_at timestamptz, sorted_note text) -- each flag's state
language sql stable security definer -- reads this module's table
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select f.tutor_id, f.upcoming_sessions, f.paid_sessions, f.first_session, f.sorted_at, f.sorted_note -- the state
  from public.safety_rematch_flags f join public.safety_holds h on h.id = f.hold_id -- each flag, with its step
  where h.concern_id = p_concern and private.handles_concern(p_concern) -- for this concern, only for people handling it
$$; -- end of the function
revoke all on function public.safety_concern_rematch(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.safety_concern_rematch(uuid) to authenticated; -- signed-in people (only handlers get rows)
