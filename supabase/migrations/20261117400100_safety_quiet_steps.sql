-- Summary: quiet steps on a confidential flag about a tutor (Carla, 15 Nov 2026).
--
-- While a concern about a tutor is looked into, the person handling it
-- (the Child Safety Officer, or the deputy) can take two quiet steps from the
-- concern itself. Neither happens unless they press the button:
--   1. "Stop new students": the tutor keeps the students they have now, but
--      matching, offers and bookings won't pair them with anyone new;
--   2. "End this student's match": the tutor's match with the child in the
--      concern ends today, so the tutor can no longer open that child's
--      records, and they can't be matched with that child again.
-- The tutor is never told why. Admins doing matching only see the usual
-- "Can't be matched with this student", with no reason. Each step needs a
-- reason, which is kept with the step, and either step can be lifted later
-- (lifting doesn't restart an ended match).
--
-- How: the steps live in this module's own table. The shared "can this
-- tutor and student be paired?" check (private.blocked_pair, used by every
-- matching, offer and booking screen) is extended to read it. Ending a match
-- sets the end date on the tutor's current match, the same as ending any
-- match; upcoming bookings for the pair are counted and shown, so the
-- handler can change them in Sessions.
--
-- Needs 20261117100100_safety_concern_about_worker.sql and
-- 20261103000500_scheduling_blocks_and_libraries.sql. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The quiet steps
-- ---------------------------------------------------------------------------

create table if not exists public.safety_holds ( -- one row per quiet step taken
  id uuid primary key default gen_random_uuid(), -- the step's id
  concern_id uuid not null references public.safety_concerns (id) on delete cascade, -- the concern it was taken from
  tutor_id uuid not null references public.accounts (id) on delete cascade, -- the tutor it applies to
  kind text not null check (kind in ('no_new_students', 'end_match')), -- which step: stop new students, or end one student's match
  student_id uuid references public.students (id) on delete cascade, -- the student whose match was ended (only for "end_match")
  reason text not null check (char_length(reason) between 2 and 1000), -- why the step was taken
  placed_by uuid references public.accounts (id) on delete set null, -- who took it
  placed_at timestamptz not null default now(), -- when
  lifted_by uuid references public.accounts (id) on delete set null, -- who lifted it (empty while it's in place)
  lifted_at timestamptz, -- when it was lifted (empty while it's in place)
  check ((kind = 'end_match') = (student_id is not null)) -- "end_match" always names a student; "no_new_students" never does
); -- end of the table
create index if not exists safety_holds_tutor on public.safety_holds (tutor_id) where lifted_at is null; -- finds a tutor's steps in place quickly (the pairing check runs often)
create index if not exists safety_holds_concern on public.safety_holds (concern_id); -- finds a concern's steps quickly
alter table public.safety_holds enable row level security; -- turns on access rules
revoke all on public.safety_holds from anon, authenticated; -- changed only through the functions below
grant select on public.safety_holds to authenticated; -- signed-in people may read, but only the rows the rule below allows
drop policy if exists "handlers read holds" on public.safety_holds; -- removes the old rule if the file is run again
create policy "handlers read holds" on public.safety_holds -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (private.handles_concern(concern_id) and tutor_id is distinct from auth.uid()); -- only the people handling its concern, and never the tutor

-- ---------------------------------------------------------------------------
-- The shared pairing check, extended
-- ---------------------------------------------------------------------------

-- Is this tutor and student pair blocked? True when (as before) either side
-- blocked the other, or (new) a quiet step applies: the pair's match was
-- ended from a concern, or the tutor is stopped from new students and this
-- student isn't one of their current students.
create or replace function private.blocked_pair(p_tutor uuid, p_student uuid) -- takes the tutor and the student
returns boolean language sql stable security definer -- gives back yes or no; reads tables people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- a block from either side (unchanged):
    select 1 from public.match_blocks b -- a block
    where b.tutor_id = p_tutor and b.student_id = p_student and b.lifted_at is null -- on this pair, still in place
  ) -- end of the first case
  or exists ( -- or a quiet step:
    select 1 from public.safety_holds h -- a step
    where h.tutor_id = p_tutor and h.lifted_at is null -- for this tutor, still in place,
      and ( -- that is either:
        (h.kind = 'end_match' and h.student_id = p_student) -- this pair's match was ended,
        or ( -- or
          h.kind = 'no_new_students' -- the tutor is stopped from new students
          and not exists ( -- and this student isn't a current student of theirs:
            select 1 from public.tutor_assignments a -- a match
            where a.tutor_id = p_tutor and a.student_id = p_student -- for this pair
              and private.assignment_is_current(a.starts_on, a.ends_on) -- that's running now
          ) -- end of the current-student check
        ) -- end of the second kind
      ) -- end of the either
  ) -- end of the second case
$$; -- end of the function
revoke all on function private.blocked_pair(uuid, uuid) from public; -- not for everyone by default
grant execute on function private.blocked_pair(uuid, uuid) to authenticated, service_role; -- the matching screens and the server use it (as before)

-- ---------------------------------------------------------------------------
-- What the handler can do for each person a concern names
-- ---------------------------------------------------------------------------

-- For each tutor a concern names: whether each step is in place, whether a
-- match can be ended (the concern is about a CLG student they're matched
-- with), and how many upcoming bookings the pair still has.
create or replace function public.safety_concern_quiet_steps(p_concern uuid) -- takes the concern
returns table ( -- one row per tutor named:
  tutor_id uuid, -- the tutor
  full_name text, -- their name
  no_new_students_id uuid, -- the "stop new students" step in place (empty if none)
  end_match_id uuid, -- the "end match" step in place for this concern's student (empty if none)
  matched_now boolean, -- whether they're matched with the concern's student right now
  upcoming_bookings integer -- how many bookings the pair has from today on
) -- end of the columns
language plpgsql stable security definer -- reads tables people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_student uuid; -- the concern's student (if a CLG student)
begin -- starts the code
  if not private.handles_concern(p_concern) then -- not someone handling this concern
    return; -- gives back nothing
  end if; -- end of the check
  select c.student_id into v_student from public.safety_concerns c where c.id = p_concern; -- the concern's student
  return query -- hands back:
  select p.account_id, -- the tutor,
    p.full_name, -- their name,
    (select h.id from public.safety_holds h where h.tutor_id = p.account_id and h.kind = 'no_new_students' and h.lifted_at is null limit 1), -- the "stop new students" step, if in place,
    (select h.id from public.safety_holds h where h.tutor_id = p.account_id and h.kind = 'end_match' and h.student_id = v_student and h.lifted_at is null limit 1), -- the "end match" step, if in place,
    v_student is not null and exists ( -- matched with the student now?
      select 1 from public.tutor_assignments a -- a match
      where a.tutor_id = p.account_id and a.student_id = v_student -- for this pair
        and private.assignment_is_current(a.starts_on, a.ends_on) -- running now
    ), -- end of the check
    coalesce(( -- the upcoming bookings:
      select count(*)::integer from public.bookings b -- bookings
      where b.tutor_id = p.account_id and b.student_id = v_student -- for this pair
        and b.status in ('requested', 'confirmed') and b.last_date >= current_date -- still running or waiting
    ), 0) -- (none when there's no student)
  from public.safety_concern_people p -- each person the concern names
  where p.concern_id = p_concern -- for this concern
    and exists (select 1 from public.tutor_profiles t where t.account_id = p.account_id) -- who is a tutor
  order by p.full_name; -- in name order
end; -- ends the code
$$; -- end of the function
revoke all on function public.safety_concern_quiet_steps(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.safety_concern_quiet_steps(uuid) to authenticated; -- signed-in people (only handlers get rows)

-- ---------------------------------------------------------------------------
-- Taking and lifting the steps
-- ---------------------------------------------------------------------------

-- Checks the person handles the concern and the tutor is named in it, as a
-- tutor, and that a reason was given. Stops with a plain message otherwise.
create or replace function private.check_quiet_step(p_concern uuid, p_tutor uuid, p_reason text) -- takes the concern, the tutor and the reason
returns void -- gives nothing back
language plpgsql stable security definer -- reads tables people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  perform private.my_received_concern(p_concern); -- checks they handle the concern (stops otherwise)
  if not private.concern_names(p_concern, p_tutor) then -- the tutor isn't named in it
    raise exception 'Quiet steps can only be taken for a tutor this concern names.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if not exists (select 1 from public.tutor_profiles where account_id = p_tutor) then -- not a tutor
    raise exception 'Quiet steps are only for tutors.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_reason, ''))) < 2 then -- no reason
    raise exception 'Please say why you are taking this step.' using errcode = '22023'; -- plain message
  end if; -- end of the check
end; -- ends the code
$$; -- end of the function
revoke all on function private.check_quiet_step(uuid, uuid, text) from public; -- for the database's own use only

-- Step 1: stops a tutor from being paired with new students.
create or replace function public.safety_stop_new_students(p_concern uuid, p_tutor uuid, p_reason text) -- takes the concern, the tutor and why
returns void -- gives nothing back
language plpgsql security definer -- writes to a table people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  perform private.check_quiet_step(p_concern, p_tutor, p_reason); -- the checks above
  if exists (select 1 from public.safety_holds where tutor_id = p_tutor and kind = 'no_new_students' and lifted_at is null) then -- already in place
    raise exception 'This tutor is already stopped from new students.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.safety_holds (concern_id, tutor_id, kind, reason, placed_by) -- saves the step:
  values (p_concern, p_tutor, 'no_new_students', left(btrim(p_reason), 1000), auth.uid()); -- the concern, tutor, kind, reason and who
  insert into public.safety_concern_notes (concern_id, author_id, author_name, note) -- records it on the concern:
  select p_concern, a.id, a.full_name, left('Stopped ' || coalesce((select full_name from public.accounts where id = p_tutor), 'the tutor') || ' from new students. Reason: ' || btrim(p_reason), 4000) -- who and why
  from public.accounts a where a.id = auth.uid(); -- from their account
  perform private.log_event('safety_stop_new_students', 'safety_concerns', p_concern::text, '{}'); -- notes it in the activity log (id only, no names)
end; -- ends the code
$$; -- end of the function
revoke all on function public.safety_stop_new_students(uuid, uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.safety_stop_new_students(uuid, uuid, text) to authenticated; -- signed-in people can try (the checks are inside)

-- Step 2: ends the tutor's match with the concern's student, and stops them being paired again.
create or replace function public.safety_end_match(p_concern uuid, p_tutor uuid, p_reason text) -- takes the concern, the tutor and why
returns integer -- gives back how many upcoming bookings the pair still has (to change in Sessions)
language plpgsql security definer -- writes to tables people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_student uuid; -- the concern's student
  v_bookings integer; -- upcoming bookings for the pair
begin -- starts the code
  perform private.check_quiet_step(p_concern, p_tutor, p_reason); -- the checks above
  select student_id into v_student from public.safety_concerns where id = p_concern; -- the concern's student
  if v_student is null then -- not a CLG student (or the record was deleted)
    raise exception 'This concern isn''t about a CLG student, so there is no match to end.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if exists (select 1 from public.safety_holds where tutor_id = p_tutor and student_id = v_student and kind = 'end_match' and lifted_at is null) then -- already done
    raise exception 'This match has already been ended from a concern.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.safety_holds (concern_id, tutor_id, kind, student_id, reason, placed_by) -- saves the step (this also stops the pair being matched again):
  values (p_concern, p_tutor, 'end_match', v_student, left(btrim(p_reason), 1000), auth.uid()); -- the concern, tutor, kind, student, reason and who
  update public.tutor_assignments a -- ends the pair's current matches:
  set ends_on = greatest(a.starts_on, current_date - 1) -- ending yesterday, so access stops today (or on the start day, for a match that starts today)
  where a.tutor_id = p_tutor and a.student_id = v_student -- for this pair
    and private.assignment_is_current(a.starts_on, a.ends_on); -- that are running now
  update public.tutor_assignments a -- and cancels any matches due to start later:
  set ends_on = a.starts_on -- (ending on the day they start; the pairing check stops them being redone)
  where a.tutor_id = p_tutor and a.student_id = v_student -- for this pair
    and a.starts_on > current_date and (a.ends_on is null or a.ends_on > a.starts_on); -- that haven't started yet
  select count(*)::integer into v_bookings from public.bookings b -- counts the pair's upcoming bookings
  where b.tutor_id = p_tutor and b.student_id = v_student -- for this pair
    and b.status in ('requested', 'confirmed') and b.last_date >= current_date; -- still running or waiting
  insert into public.safety_concern_notes (concern_id, author_id, author_name, note) -- records it on the concern:
  select p_concern, a.id, a.full_name, left('Ended ' || coalesce((select full_name from public.accounts where id = p_tutor), 'the tutor') || '''s match with this student. Reason: ' || btrim(p_reason) -- who and why,
    || case when v_bookings > 0 then ' (' || v_bookings || ' upcoming booking(s) still to change in Sessions.)' else '' end, 4000) -- and any bookings left to change
  from public.accounts a where a.id = auth.uid(); -- from their account
  perform private.log_event('safety_end_match', 'safety_concerns', p_concern::text, '{}'); -- notes it in the activity log (id only, no names)
  return v_bookings; -- hands back the number of bookings to change
end; -- ends the code
$$; -- end of the function
revoke all on function public.safety_end_match(uuid, uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.safety_end_match(uuid, uuid, text) to authenticated; -- signed-in people can try (the checks are inside)

-- Lifts a step. Lifting "end match" lets the pair be matched again, but
-- doesn't restart the match: that's done the usual way, on purpose.
create or replace function public.safety_lift_hold(p_hold uuid, p_reason text) -- takes the step and why
returns void -- gives nothing back
language plpgsql security definer -- changes a table people can't change directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_row public.safety_holds; -- the step
begin -- starts the code
  select * into v_row from public.safety_holds where id = p_hold and lifted_at is null; -- finds the step, if still in place
  if v_row.id is null then -- not found (or already lifted)
    raise exception 'That step isn''t in place any more.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  perform private.my_received_concern(v_row.concern_id); -- checks they handle its concern (stops otherwise)
  if char_length(btrim(coalesce(p_reason, ''))) < 2 then -- no reason
    raise exception 'Please say why you are lifting this step.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.safety_holds set lifted_at = now(), lifted_by = auth.uid() where id = p_hold; -- lifts it
  insert into public.safety_concern_notes (concern_id, author_id, author_name, note) -- records it on the concern:
  select v_row.concern_id, a.id, a.full_name, -- the concern, who and
    left('Lifted "' || case v_row.kind when 'no_new_students' then 'stop new students' else 'match ended' end || '" for ' || coalesce((select full_name from public.accounts where id = v_row.tutor_id), 'the tutor') || '. Reason: ' || btrim(p_reason), 4000) -- what was lifted, and why
  from public.accounts a where a.id = auth.uid(); -- from their account
  perform private.log_event('safety_lift_hold', 'safety_concerns', v_row.concern_id::text, '{}'); -- notes it in the activity log (id only)
end; -- ends the code
$$; -- end of the function
revoke all on function public.safety_lift_hold(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.safety_lift_hold(uuid, text) to authenticated; -- signed-in people can try (the checks are inside)
