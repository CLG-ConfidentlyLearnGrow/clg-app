-- Progress: admins are told about a missing session summary at 12 hours
-- (Carla, 20 Nov 2026).
--
-- Before: at 6 hr after a session the tutor was reminded and admins were
-- told at the same time, and the admin to-do count showed notes 6 hr or
-- more late.
-- Now: the tutor is still reminded at 6 hr (summaries are still due within
-- 6 hr). Admins are only told, and the to-do count only counts the note, if
-- it is still missing at 12 hr. This gives the tutor's own reminder time to
-- work, so admins (Emma) only follow up the ones that need it. Families are
-- still promised the summary within 48 hr. Quiet hours (9pm to 5am) still
-- apply.
--
-- The "noted on time" measure on Admin > Progress still means within 6 hr.
--
-- Each function is edited in place (only the admins' hours and wording),
-- so anything else changed in them later is kept.
--
-- Safe to run more than once.

-- The hourly note reminders: admins told at 12 hr (the tutor stays at 6 hr).
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's current code
  v_admin_part text; -- the part of the code that tells admins
  v_pos integer; -- where that part starts
begin -- start
  if to_regprocedure('private.queue_note_reminders()') is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef('private.queue_note_reminders()'::regprocedure); -- reads its current code
  v_pos := strpos(v_def, '''note_overdue'''); -- finds where the admins' part starts (the tutor's part comes first)
  if v_pos = 0 then -- the admins' part is not there:
    raise exception 'queue_note_reminders has changed since this was written; please ask for help'; -- stops, so nothing half-changes
  end if; -- end of the check
  v_admin_part := substr(v_def, v_pos); -- the admins' part, to the end
  if strpos(v_admin_part, 'interval ''6 hours''') > 0 then -- the admins' part is still on 6 hr:
    v_admin_part := replace(v_admin_part, 'interval ''6 hours''', 'interval ''12 hours'''); -- admins told at 12 hr,
    v_admin_part := replace(v_admin_part, '(6 hr or more).', '(12 hr or more). It was due within 6 hr and the tutor has been reminded.'); -- the admins' wording,
    execute substr(v_def, 1, v_pos - 1) || v_admin_part; -- saves the function with the tutor's part unchanged
  end if; -- done
end; -- finish
$$; -- end of the block

-- The admin to-do count: notes 12 hr or more late.
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's current code
begin -- start
  if to_regprocedure('public.to_do_counts()') is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef('public.to_do_counts()'::regprocedure); -- reads its current code
  if strpos(v_def, 'd.hours_since_end >= 6') > 0 then -- still on 6 hr:
    v_def := replace(v_def, 'd.hours_since_end >= 6', 'd.hours_since_end >= 12'); -- counts notes 12 hr or more late
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block
