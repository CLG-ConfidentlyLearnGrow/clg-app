-- Progress: admins are told when a family adds a significant date (Carla,
-- 22 Nov 2026, from her notes on Emma's Job Proposal: "When a family adds
-- a significant date, flag it to admin").
--
-- A significant date is a test, exam or assignment due date. Families and
-- students add them on the student's Progress page (an assessment on the
-- learning roadmap). Tutors and admins add them too, but only one added by
-- a parent or the student needs flagging, because CLG may not know about
-- it yet. Admins (owner and Operations) get a notice in the app straight
-- away, so they can check the tutor knows and offer an extra session if it
-- would help.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- After a significant date is added: tell admins if a family added it.
-- ---------------------------------------------------------------------------
create or replace function private.tell_admins_significant_date() -- runs after a roadmap target is added
returns trigger language plpgsql security definer -- reads names and adds notices with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_student text; -- the student's name
  v_who text; -- who added it
begin -- start
  if new.kind <> 'assessment' or new.due_on is null then -- not a significant date (a goal, or no date):
    return null; -- nothing to tell
  end if; -- end of the check
  if private.is_front_desk() or private.is_tutor_of(new.student_id) then -- added by CLG staff or the student's tutor:
    return null; -- CLG already knows
  end if; -- end of the check
  select full_name into v_student from public.students where id = new.student_id; -- the student's name
  select full_name into v_who from public.accounts where id = auth.uid(); -- who added it
  perform private.notify_admins( -- tells the owner and Operations admins:
    'New significant date from a family', -- the title,
    left(format('%s added a significant date for %s: %s on %s. Check their tutor knows, and whether an extra session would help.', -- the message:
      coalesce(v_who, 'The family'), coalesce(v_student, 'a student'), new.title, trim(to_char(new.due_on, 'FMDD Mon YYYY'))), 1000)); -- who, which student, what and when
  return null; -- (an "after" trigger hands nothing back)
end; -- end of the code
$$; -- end of the function
revoke all on function private.tell_admins_significant_date() from public; -- only used by the trigger below

drop trigger if exists tell_admins_significant_date on public.roadmap_targets; -- removes the old trigger (so this file can run twice)
create trigger tell_admins_significant_date after insert on public.roadmap_targets -- after each new roadmap target:
  for each row execute function private.tell_admins_significant_date(); -- tells admins if a family added a significant date
