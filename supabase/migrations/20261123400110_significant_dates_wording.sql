-- Scheduling: "event" becomes "significant date" (Carla, 20 Nov 2026).
--
-- Families ask for an extra session before a test, an exam or an
-- assignment due date. Carla wants these called "significant dates", not
-- "events", because most of them are not events. This file changes only
-- the words people read in the app's notices and error messages. The
-- stored columns keep their names (event_on, event_label), so nothing
-- else in the app changes.
--
-- Each function is edited in place (only these words), so anything else
-- changed in them later is kept. If a function no longer has the old words
-- (already changed), it is left alone.
--
-- Safe to run more than once.

-- The family's request: the error message and the notices to admins and the tutor.
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's current code
begin -- start
  if to_regprocedure('public.make_session_request(uuid, text, text, date, text, text, text)') is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef('public.make_session_request(uuid, text, text, date, text, text, text)'::regprocedure); -- reads its current code
  if strpos(v_def, 'Give the date of the test or event') > 0 then -- still on the old words:
    v_def := replace(v_def, -- the error when the date is missing or past:
      'Give the date of the test or event (in the future)', -- old words,
      'Give the significant date (the test, exam or assignment due date), which must be in the future'); -- new words,
    v_def := replace(v_def, -- the admins' notice when no label was given:
      'coalesce(nullif(trim(p_event_label), ''''), ''event'')', -- old words,
      'coalesce(nullif(trim(p_event_label), ''''), ''significant date'')'); -- new words,
    v_def := replace(v_def, -- the tutor's notice when no label was given:
      'coalesce(nullif(trim(p_event_label), ''''), ''an event'')', -- old words,
      'coalesce(nullif(trim(p_event_label), ''''), ''a significant date'')'); -- new words,
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block

-- The one-off offer: the error when the date is too late, and the booking's note.
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's current code
begin -- start
  if to_regprocedure('public.offer_one_off(uuid, uuid, date, time, integer, public.session_delivery, uuid, text)') is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef('public.offer_one_off(uuid, uuid, date, time, integer, public.session_delivery, uuid, text)'::regprocedure); -- reads its current code
  if strpos(v_def, 'before the event (%)') > 0 or strpos(v_def, 'coalesce(v_r.event_label, ''an event'')') > 0 then -- still on the old words:
    v_def := replace(v_def, 'before the event (%)', 'before the significant date (%)'); -- the error,
    v_def := replace(v_def, 'coalesce(v_r.event_label, ''an event'')', 'coalesce(v_r.event_label, ''a significant date'')'); -- the note,
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block
