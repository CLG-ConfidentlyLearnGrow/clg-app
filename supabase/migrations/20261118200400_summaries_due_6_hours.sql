-- Progress: session summaries (notes) are due 6 hours after a session
-- (Carla, 16 Nov 2026). Families are still promised the summary within
-- 48 hours, so CLG has plenty of time to follow up a tutor who is late.
--
-- Before: the tutor was reminded 24 hr after the session, admins were told
-- at 48 hr, the admin to-do count showed notes 48 hr or more late, and the
-- "on time" measure counted notes written within 24 hr.
-- Now: at 6 hr the tutor is reminded and admins are told (so Lauren can
-- follow up), the admin to-do count shows notes 6 hr or more late, and the
-- "on time" measure counts notes written within 6 hr. Quiet hours (9pm to
-- 5am) still apply, so a reminder that falls overnight arrives at 5am.
--
-- Each function is edited in place (only the hours and their wording), so
-- anything else changed in them later is kept. The measure's column keeps
-- its old name (noted_within_24_hr) so the app keeps working; it now means
-- "within 6 hr".
--
-- Safe to run more than once.

-- The hourly note reminders: 6 hr for the tutor and for admins.
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's current code
begin -- start
  if to_regprocedure('private.queue_note_reminders()') is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef('private.queue_note_reminders()'::regprocedure); -- reads its current code
  if strpos(v_def, 'interval ''24 hours''') > 0 or strpos(v_def, 'interval ''48 hours''') > 0 then -- still on the old hours:
    v_def := replace(v_def, 'interval ''24 hours''', 'interval ''6 hours'''); -- tutor reminder at 6 hr,
    v_def := replace(v_def, 'interval ''48 hours''', 'interval ''6 hours'''); -- admins told at 6 hr,
    v_def := replace(v_def, 'Notes are due within 24 hr.', 'Notes are due within 6 hr of the session.'); -- the tutor's wording,
    v_def := replace(v_def, '(48 hr or more).', '(6 hr or more). Families must have it within 48 hr.'); -- the admins' wording,
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block

-- The admin to-do count: notes 6 hr or more late.
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's current code
begin -- start
  if to_regprocedure('public.to_do_counts()') is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef('public.to_do_counts()'::regprocedure); -- reads its current code
  if strpos(v_def, 'd.hours_since_end >= 48') > 0 then -- still on the old hours:
    v_def := replace(v_def, 'd.hours_since_end >= 48', 'd.hours_since_end >= 6'); -- counts notes 6 hr or more late
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block

-- The "noted on time" measure on Admin > Progress: within 6 hr.
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's current code
begin -- start
  if to_regprocedure('public.progress_measures(date, date)') is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef('public.progress_measures(date, date)'::regprocedure); -- reads its current code
  if strpos(v_def, 'h.ends_at + interval ''24 hours''') > 0 then -- still on the old hours:
    v_def := replace(v_def, 'h.ends_at + interval ''24 hours''', 'h.ends_at + interval ''6 hours'''); -- on time means within 6 hr
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block
