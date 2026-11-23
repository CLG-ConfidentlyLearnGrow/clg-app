-- Summary: anything done in quiet hours counts as done at 5am (Carla, 22 Nov
-- 2026).
--
-- Carla: "Quiet hours are implemented, it needs to be noted, anything done
-- during those quiet hours counts to have been done when it is no longer in
-- quiet hours time. Quiet is from 9pm to 5am." The contract update (v1.3) asks the same
-- for cancellations: a cancellation saved in quiet hours counts from 5am for
-- the 2-hour late cancellation pay rule.
--
-- What this changes (module: billing, which owns credits and pay; scheduling
-- keeps saving the real time a session was cancelled):
--   * private.counts_from(time): the moment something "counts" as done. A
--     time inside quiet hours (CLG's setting, 9pm to 5am Adelaide time) moves
--     to the end of quiet hours; any other time is unchanged.
--   * Family credit for a cancelled session (more than 24 hr, 24 to 2 hr,
--     under 2 hr) now measures notice from that moment.
--   * Tutor late cancellation pay (under 2 hr) does the same.
--   * The 24-hour "cancelled late" rule for logging a no-show's hours does
--     the same.
-- The real time of the cancellation is still saved and shown as it was.
--
-- Safe to run more than once. Run after 20261124710900_student_success_program.sql.

-- ---------------------------------------------------------------------------
-- 1. When something counts as done
-- ---------------------------------------------------------------------------
create or replace function private.counts_from(p_at timestamptz) -- takes the real time something was done
returns timestamptz language sql stable security definer -- reads the quiet hours setting for whoever asks
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the value
  select private.outside_quiet_hours(p_at, 'Australia/Adelaide') -- moved to 5am if it was in quiet hours (CLG's own clock), otherwise unchanged
$$; -- end of the function
revoke all on function private.counts_from(timestamptz) from public; -- inside use only
grant execute on function private.counts_from(timestamptz) to authenticated, service_role; -- (credit and pay functions run as the caller)

-- ---------------------------------------------------------------------------
-- 2. Notice is measured from that moment (functions changed in place)
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_fn text; -- the function being changed
  v_def text; -- its code
  v_old text; -- the text to find
  v_new text; -- what replaces it
begin -- start
  for v_fn, v_old, v_new in -- each change:
    select * from (values -- (function, old text, new text)
      ('private.billing_cancel_credit_percent(timestamptz,timestamptz,text,text)', 'p_starts_at - p_cancelled_at', 'p_starts_at - private.counts_from(p_cancelled_at)'), -- family credit
      ('private.billing_session_credit_percent(uuid)', 'se.starts_at - se.cancelled_at', 'se.starts_at - private.counts_from(se.cancelled_at)'), -- family credit with make-up times
      ('public.billing_build_pay(date,date)', 'r.starts_at - r.cancelled_at < make_interval(hours => s.half_credit_hours)', 'r.starts_at - private.counts_from(r.cancelled_at) < make_interval(hours => s.half_credit_hours) /* before 22 Nov 2026: r.starts_at - r.cancelled_at < make_interval(hours => s.half_credit_hours) */'), -- tutor late cancellation pay (the old rule is kept as a note, so the 18 Nov file still sees it is done if it is run again)
      ('public.billing_log_my_hours(date,integer,text,text,text,uuid)', 'v_s.cancelled_at > v_s.starts_at', 'private.counts_from(v_s.cancelled_at) > v_s.starts_at'), -- logging a no-show's hours
      ('public.my_no_show_sessions()', 's.cancelled_at > s.starts_at', 'private.counts_from(s.cancelled_at) > s.starts_at') -- the sessions offered for that
    ) as c (fn, old_text, new_text) -- (names for the columns)
  loop -- for each one:
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), chr(13), ''); -- reads its current code
    if strpos(v_def, 'private.counts_from(') > 0 then continue; end if; -- already changed: skips it
    if strpos(v_def, v_old) = 0 then -- the place has changed:
      raise exception '% has changed since this update was written. Ask for an updated file.', v_fn; -- stops, so nothing half-changes
    end if; -- end of the check
    execute replace(v_def, v_old, v_new); -- saves the changed function
  end loop; -- next change
end; -- finish
$$; -- end of the block
