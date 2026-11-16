-- Summary: a tutor waits 15 minutes before recording a no-show (Carla, 16 Nov 2026).
--
-- Carla: if a learner is more than 15 minutes late, "the tutor will log
-- off/leave location". So a tutor can only record a session as a no-show
-- from 15 minutes after its start. Admins can still record or correct it at
-- any time after the start (for example, when a family rings to say the
-- learner won't come).
--
-- Scheduling module. Edits record_session_outcome in place, so other changes
-- to it are kept. Safe to run more than once.

do $$ -- (a block of steps)
declare -- working values:
  v_def text; -- the function's current code
  v_anchor text := E'raise exception ''This session hasn''''t started yet'' using errcode = ''22023'';\n  end if;\n'; -- the "not started yet" check the new check goes after
  v_new text := E'  if p_status = ''no_show'' and not private.is_admin() and v_s.starts_at + interval ''15 minutes'' > now() then -- a tutor recording a no-show within 15 minutes of the start:\n'
             || E'    raise exception ''Please wait 15 minutes after the start before recording a no-show'' using errcode = ''22023''; -- plain refusal\n'
             || E'  end if; -- (end of the 15-minute check)\n'; -- the new check
begin -- start
  v_def := replace(pg_get_functiondef('public.record_session_outcome(uuid, public.session_status)'::regprocedure), chr(13), ''); -- reads its code (without Windows line endings from pasting)
  if strpos(v_def, 'before recording a no-show') > 0 then -- already done:
    return; -- nothing to change
  end if; -- (end of that check)
  if strpos(v_def, v_anchor) = 0 then -- the code has changed since this was written:
    raise exception 'public.record_session_outcome has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- (end of that check)
  execute replace(v_def, v_anchor, v_anchor || v_new); -- saves the code with the new check
end; -- finish
$$; -- (end of the block)
