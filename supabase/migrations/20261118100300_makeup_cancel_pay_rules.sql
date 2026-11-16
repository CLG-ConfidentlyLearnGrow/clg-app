-- Summary: what families pay and tutors get when a session is cancelled and made up (Carla, 16 Nov 2026).
--
-- Carla: "If it is cancelled within the 2 hours and is rescheduled, the
-- parent is required to pay for 50% of the session. If cancelled earlier
-- than this and rescheduled, no further payment required. The 2 hours
-- notice is when the cancellation and possible rescheduling times have been
-- uploaded into the app, which is when the tutor would be notified."
-- And: the tutor's 50% pay for a cancel or no-show "only stands when there
-- is less than 2 hours notice given".
--
-- Notice is measured from when the cancel was saved in the app
-- (sessions.cancelled_at), which is when the tutor is notified, not when
-- they read it.
--
-- Families (credit for a cancelled session they had paid for):
--   * family cancels and a make-up session is booked:
--       2 hr or more notice -> full credit (they pay only for the make-up);
--       under 2 hr notice   -> 50% credit (they pay half the cancelled session).
--   * family cancels with no make-up: the usual rules (more than 24 hr full
--     credit, 24 to 2 hr 50%, under 2 hr none).
--   * tutor or CLG cancels: full credit, as before.
--   * While make-up times are still waiting for an answer, the credit waits
--     too, so it's worked out once everyone knows whether a make-up is booked.
-- Tutors (pay for a session cancelled by the family or CLG, or a no-show,
-- before they signed on): 50% of the session (up to 1 hr) only when the
-- cancel came with less than 2 hr notice. It used to be 24 hr or less.
-- The make-up session is paid in full as usual.
--
-- Billing reads sessions and make-up offers; it never writes them. Edits the
-- billing functions in place, so other changes to them are kept.
-- Needs 20261118100100 and 20261118100200 first. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. The credit for one cancelled session, knowing about make-ups
-- ---------------------------------------------------------------------------
-- Hands back the percentage of the session's charge to give back as credit,
-- or nothing while make-up times are still waiting for an answer.
create or replace function private.billing_session_credit_percent(p_session uuid) -- takes the session
returns int -- the credit percentage (0, 50 or 100), or nothing while waiting
language sql stable security definer -- reads sessions and offers whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the rule
  select case -- in order:
    when exists (select 1 from public.session_makeup_offers o -- make-up times
                 where o.session_id = se.id and o.status in ('waiting', 'confirming')) -- still waiting for an answer:
      then null -- wait before giving any credit
    when se.status::text = 'cancelled' and se.cancelled_by_role = 'family' -- the family cancelled,
         and exists (select 1 from public.session_makeup_offers o -- and a make-up
                     where o.session_id = se.id and o.status = 'picked') -- was booked:
      then case when se.starts_at - se.cancelled_at < make_interval(hours => s.half_credit_hours) -- under 2 hr notice:
                then 50 -- half credit (they pay half the cancelled session),
                else 100 end -- otherwise full credit (they pay only for the make-up)
    else private.billing_cancel_credit_percent(se.starts_at, se.cancelled_at, se.cancelled_by_role::text, se.status::text) -- otherwise the usual rules
  end -- (end of the rule)
  from public.sessions se -- the session
  cross join public.billing_settings s -- with the notice settings (2 hr is half_credit_hours)
  where se.id = p_session -- this session
$$; -- end of the function
revoke all on function private.billing_session_credit_percent(uuid) from public, anon, authenticated; -- only used inside the database

-- ---------------------------------------------------------------------------
-- 2. The daily credit run uses it (edits billing_credit_cancellations in place)
-- ---------------------------------------------------------------------------
do $$ -- (a block of steps)
declare -- working values:
  v_def text; -- the function's current code
  v_old_call text := 'private.billing_cancel_credit_percent(se.starts_at, se.cancelled_at, se.cancelled_by_role::text, se.status::text)'; -- the old credit rule, as written in it
  v_status text := E'    and se.status::text in (''cancelled'', ''no_show'')\n'; -- the line the "wait" check goes after
begin -- start
  v_def := replace(pg_get_functiondef('public.billing_credit_cancellations()'::regprocedure), chr(13), ''); -- reads its code (without Windows line endings from pasting)
  if strpos(v_def, 'billing_session_credit_percent') > 0 then -- already done:
    return; -- nothing to change
  end if; -- (end of that check)
  if strpos(v_def, v_old_call) = 0 or strpos(v_def, v_status) = 0 then -- the code has changed since this was written:
    raise exception 'public.billing_credit_cancellations has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- (end of that check)
  v_def := replace(v_def, v_old_call, 'private.billing_session_credit_percent(se.id)'); -- uses the new rule (both places)
  v_def := replace(v_def, v_status, v_status || E'    and private.billing_session_credit_percent(se.id) is not null\n'); -- skips sessions still waiting on make-up times
  execute v_def; -- saves the changed code
end; -- finish
$$; -- (end of the block)

-- ---------------------------------------------------------------------------
-- 3. Tutor late-cancel pay only under 2 hr notice (edits billing_build_pay in place)
-- ---------------------------------------------------------------------------
do $$ -- (a block of steps)
declare -- working values:
  v_def text; -- the function's current code
  v_old text := 'r.starts_at - r.cancelled_at <= make_interval(hours => s.full_credit_hours)'; -- the old rule: 24 hr or less notice
  v_new text := 'r.starts_at - r.cancelled_at < make_interval(hours => s.half_credit_hours)'; -- the new rule: less than 2 hr notice
begin -- start
  v_def := replace(pg_get_functiondef('public.billing_build_pay(date, date)'::regprocedure), chr(13), ''); -- reads its code (without Windows line endings from pasting)
  if strpos(v_def, v_new) > 0 then -- already done:
    return; -- nothing to change
  end if; -- (end of that check)
  if strpos(v_def, v_old) = 0 then -- the code has changed since this was written:
    raise exception 'public.billing_build_pay has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- (end of that check)
  execute replace(v_def, v_old, v_new); -- saves the code with the new rule
end; -- finish
$$; -- (end of the block)
