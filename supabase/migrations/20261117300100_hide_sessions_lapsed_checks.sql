-- Hide a tutor's sessions while their checks have lapsed (Carla, 16 Nov 2026).
--
-- "Should hide them until the checks are current again."
--
-- Tutors already lose sight of a student the moment a check they need for
-- that student's state (WWCC, RRHAN-EC) lapses. Their own Sessions list
-- still showed that student's name, times and meeting link, along with
-- offers waiting for an answer and notes to write. From now on those are
-- hidden too, and they come back by themselves once CLG confirms the renewed
-- check. Nothing is deleted or cancelled: CLG still sees every session and
-- decides whether to move it to another tutor.
--
-- Each function is edited in place, so other changes to it stay. Safe to run
-- more than once.

-- ---------------------------------------------------------------------------
-- 1. The tutor's lists: sessions, offers, notes to write, offer details
-- ---------------------------------------------------------------------------
do $$ -- (a block of steps)
declare -- The block's working values:
  f record; -- one function to change: its name, the text to find, and the text to put instead.
  v_def text; -- that function's code.
begin -- Starts the steps.
  for f in -- For each function below:
    select * from (values -- (the list)
      ('public.list_sessions(date, date)', -- the sessions list,
       'x.tutor_id = auth.uid() and private.has_role(''tutor'') and private.has_aal2()', -- the tutor's part of its rule,
       'x.tutor_id = auth.uid() and private.has_role(''tutor'') and private.has_aal2() and private.tutor_cleared_for_student(x.tutor_id, x.student_id)'), -- plus "checks in date for this student".
      ('public.list_bookings()', -- the bookings and offers list,
       'b.tutor_id = auth.uid() and private.has_role(''tutor'') and private.has_aal2()', -- the tutor's part,
       'b.tutor_id = auth.uid() and private.has_role(''tutor'') and private.has_aal2() and private.tutor_cleared_for_student(b.tutor_id, b.student_id)'), -- plus the checks.
      ('public.list_notes_due()', -- the notes still to write,
       'se.tutor_id = auth.uid() and private.has_role(''tutor'') and private.has_aal2()', -- the tutor's part,
       'se.tutor_id = auth.uid() and private.has_role(''tutor'') and private.has_aal2() and private.tutor_cleared_for_student(se.tutor_id, se.student_id)'), -- plus the checks.
      ('public.offer_card(uuid)', -- an offer's details,
       'b.tutor_id = auth.uid() and private.has_role(''tutor'') and private.has_aal2()', -- the tutor's part,
       'b.tutor_id = auth.uid() and private.has_role(''tutor'') and private.has_aal2() and private.tutor_cleared_for_student(b.tutor_id, b.student_id)'), -- plus the checks.
      ('public.my_offers_to_answer()', -- the "waiting for your answer" number,
       'where b.tutor_id = auth.uid() -- the viewer is the tutor', -- the tutor's part,
       'where b.tutor_id = auth.uid() and private.tutor_cleared_for_student(b.tutor_id, b.student_id) -- the viewer is the tutor, with checks in date for this student') -- plus the checks.
    ) as t(fn, find_text, new_text) -- (named: function, text to find, new text)
  loop -- (each one)
    v_def := replace(pg_get_functiondef(f.fn::regprocedure), chr(13), ''); -- Reads its current code (without Windows line endings from pasting).
    continue when strpos(v_def, f.new_text) > 0; -- Already changed: skips it.
    if strpos(v_def, f.find_text) = 0 then -- The text to change isn't there any more:
      raise exception '% has changed since this update was written. Ask for an updated file.', f.fn; -- plain message naming it.
    end if; -- (end of that check)
    execute replace(v_def, f.find_text, f.new_text); -- Saves the changed code.
  end loop; -- Next function.
end; -- End of the steps.
$$; -- (end of the block)

-- ---------------------------------------------------------------------------
-- 2. The same rule on the sessions and bookings tables themselves
-- ---------------------------------------------------------------------------
-- Admins, the family and the student see them as before. The tutor sees
-- their own only while their checks for that student are in date.
drop policy if exists "see own sessions" on public.sessions; -- Removes the old rule (so this can be run again).
create policy "see own sessions" on public.sessions for select to authenticated -- Who can read sessions:
  using ( -- (the rule)
    private.is_admin() -- admins,
    or (tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2() -- the session's tutor (signed in with two steps),
        and private.tutor_cleared_for_student(tutor_id, student_id)) -- while their checks for this student are in date,
    or private.is_parent_of(student_id) -- the student's parents,
    or private.is_student_self(student_id) -- or the student.
  ); -- (end of the rule)
drop policy if exists "see own bookings" on public.bookings; -- Removes the old rule (so this can be run again).
create policy "see own bookings" on public.bookings for select to authenticated -- Who can read bookings:
  using ( -- (the rule)
    private.is_admin() -- admins,
    or (tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2() -- the booking's tutor (signed in with two steps),
        and private.tutor_cleared_for_student(tutor_id, student_id)) -- while their checks for this student are in date,
    or private.is_parent_of(student_id) -- the student's parents,
    or private.is_student_self(student_id) -- or the student.
  ); -- (end of the rule)
