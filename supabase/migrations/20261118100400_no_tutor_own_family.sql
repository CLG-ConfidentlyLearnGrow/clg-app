-- Summary: a tutor can never be matched with their own child (Carla, 16 Nov
-- 2026). "Their own child" means any student the tutor is a linked parent
-- or guardian of, any other student in that same family (for example a
-- stepchild or sibling), or the tutor themselves as a learner. Two layers:
--   1. private.blocked_pair (the shared "can this pair work together?" check
--      used by matching, booking, offers and change of tutor) now also says
--      "blocked" for a tutor's own family, so they're never suggested.
--   2. A guard on tutor_assignments refuses any new match (or a match moved
--      to a new tutor or student) between a tutor and their own family,
--      whichever screen or function tries it.
-- Safe to run more than once. Run after 20261117400100_safety_quiet_steps.sql.

-- ---------------------------------------------------------------------------
-- Is this student part of the tutor's own family?
-- ---------------------------------------------------------------------------

-- True when the tutor is the student (learning with CLG themselves), or is a
-- linked parent or guardian of the student or of any student in the same
-- family. Reads past the access rules because tutors can't read these links.
create or replace function private.tutor_is_family(p_tutor uuid, p_student uuid) -- takes the tutor and the student
returns boolean language sql stable security definer -- gives back yes or no; reads tables people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- the tutor is the student themselves:
    select 1 from public.students s -- the student record
    where s.id = p_student and s.account_id = p_tutor -- whose own login is the tutor's
  ) -- end of the first case
  or exists ( -- or the tutor is a parent or guardian of this student:
    select 1 from public.parent_student_links l -- a parent link
    where l.student_id = p_student and l.parent_id = p_tutor -- between this student and the tutor
  ) -- end of the second case
  or exists ( -- or the tutor is a parent or guardian of another student in the same family:
    select 1 from public.students s -- the student
    join public.students other on other.family_id = s.family_id -- any student in the same family
    join public.parent_student_links l on l.student_id = other.id -- that has a parent link
    where s.id = p_student and s.family_id is not null and l.parent_id = p_tutor -- to the tutor (only when the student has a family)
  ) -- end of the third case
$$; -- end of the function
revoke all on function private.tutor_is_family(uuid, uuid) from public; -- not for everyone by default
grant execute on function private.tutor_is_family(uuid, uuid) to authenticated, service_role; -- used inside blocked_pair, which signed-in people and the server call

-- ---------------------------------------------------------------------------
-- The shared pairing check, extended again
-- ---------------------------------------------------------------------------

-- Is this tutor and student pair blocked? True when either side blocked the
-- other, a quiet safety step applies (both unchanged from
-- 20261117400100_safety_quiet_steps.sql), or (new) the student is the
-- tutor's own family.
create or replace function private.blocked_pair(p_tutor uuid, p_student uuid) -- takes the tutor and the student
returns boolean language sql stable security definer -- gives back yes or no; reads tables people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- a block from either side (unchanged):
    select 1 from public.match_blocks b -- a block
    where b.tutor_id = p_tutor and b.student_id = p_student and b.lifted_at is null -- on this pair, still in place
  ) -- end of the first case
  or exists ( -- or a quiet step (unchanged):
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
  or private.tutor_is_family(p_tutor, p_student) -- or (new) the student is the tutor's own family
$$; -- end of the function
revoke all on function private.blocked_pair(uuid, uuid) from public; -- not for everyone by default
grant execute on function private.blocked_pair(uuid, uuid) to authenticated, service_role; -- the matching screens and the server use it (as before)

-- ---------------------------------------------------------------------------
-- The guard on matches
-- ---------------------------------------------------------------------------

-- Refuses a new match, or a match changed to a different tutor or student,
-- when the student is the tutor's own family. Ending or editing the dates
-- of an existing match is still allowed, so any old match can be closed.
create or replace function private.refuse_tutor_own_family() -- no inputs: it reads the row being saved
returns trigger language plpgsql security definer -- runs for each saved row; reads past the access rules
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if tg_op = 'UPDATE' and new.tutor_id = old.tutor_id and new.student_id = old.student_id then -- an edit that keeps the same tutor and student
    return new; -- is fine (for example ending the match)
  end if; -- end of the edit check
  if private.tutor_is_family(new.tutor_id, new.student_id) then -- the student is the tutor's own family
    raise exception 'A tutor can''t be matched with their own child or family member. Please choose another tutor' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of the family check
  return new; -- otherwise the match is saved
end; -- end of the code
$$; -- end of the function
revoke all on function private.refuse_tutor_own_family() from public; -- only the trigger uses it

-- Named so it runs before the other checks on matches (they run in name
-- order), so the person sees this plain reason first.
drop trigger if exists check_a_family_conflict on public.tutor_assignments; -- removes an older copy (so this can run twice)
create trigger check_a_family_conflict before insert or update on public.tutor_assignments -- before each match is added or changed
for each row execute function private.refuse_tutor_own_family(); -- runs the guard
