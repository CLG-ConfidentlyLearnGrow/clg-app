-- Summary: no no-show while a session change is waiting (Carla, 22 Nov 2026;
-- tutor contract v1.2 and v1.3, clause 3.4).
--
-- Clause 3.4: "Once a change has been requested, the original session does
-- not count as a no-show for you or the family if the change is not approved
-- in time. CLG follows up and rebooks it."
--
-- In the app, a change to a tutor's sessions (a new tutor, day or time) is a
-- "tutor change" that the new tutor and the family confirm. A session counts
-- as "changed but not approved in time" when the change was sent before the
-- session started, covers it (same student, tutor and subject, on or after
-- the change's first date), and was not confirmed before the session began
-- (still waiting, could not be made, or answered only after the start).
--
-- What this changes (module: scheduling, which owns sessions; billing's pay
-- builder is told to skip these sessions):
--   * A new cancel reason, "change_pending".
--   * private.session_change_pending(session): true for such a session.
--   * Recording a no-show for such a session (tutor or admin) does not save
--     a no-show. The session is closed as cancelled by CLG with the reason
--     "change_pending", and the owner and Operations admins are told to
--     follow up and rebook it.
--   * The family gets full credit (CLG cancelled), and the tutor gets no
--     no-show or late cancellation pay for it.
--
-- Safe to run more than once. Run after 20261124711000_quiet_hours_count_from_5am.sql.

-- ---------------------------------------------------------------------------
-- 1. The new cancel reason
-- ---------------------------------------------------------------------------
alter table public.sessions drop constraint if exists sessions_cancel_reason_kind; -- replaces the list of reasons
alter table public.sessions add constraint sessions_cancel_reason_kind -- the reasons a session can be cancelled for:
  check (cancel_reason_kind = any (array['sick', 'away', 'school_event', 'family', 'clash', 'other', 'change_pending'])); -- as before, plus a change not approved in time

-- Plain words for the new reason, where the app shows a reason's label.
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's code
begin -- start
  v_def := replace(pg_get_functiondef('private.cancel_reason_label(text)'::regprocedure), chr(13), ''); -- reads its current code
  if strpos(v_def, 'change_pending') > 0 then return; end if; -- already added: nothing to do
  if strpos(v_def, 'when ''other''') = 0 then -- the place has changed:
    raise exception 'cancel_reason_label has changed since this update was written. Ask for an updated file.'; -- stops, so nothing half-changes
  end if; -- end of the check
  execute replace(v_def, 'when ''other''', 'when ''change_pending'' then ''A change was waiting for approval'' when ''other'''); -- adds the new label before "other"
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 2. Is a change to this session waiting (or not approved in time)?
-- ---------------------------------------------------------------------------
create or replace function private.session_change_pending(p_session uuid) -- takes the session
returns boolean language sql stable security definer -- reads the changes for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the value
  select exists ( -- true if there is a change that:
    select 1
    from public.sessions s -- for this session
    join public.students st on st.id = s.student_id -- (with its student, for their local date)
    join public.tutor_change_offers o on o.student_id = s.student_id and o.from_tutor = s.tutor_id and lower(o.subject) = lower(s.subject) -- covers the same student, tutor and subject,
    where s.id = p_session -- (this session)
      and (s.starts_at at time zone private.state_timezone(st.state))::date >= o.from_date -- from the change's first date,
      and o.created_at < s.starts_at -- was sent before the session started,
      and (o.status = 'waiting' or o.status = 'failed' or o.closed_at > s.starts_at) -- and was not confirmed in time
  ); -- end of the check
$$; -- end of the function
revoke all on function private.session_change_pending(uuid) from public; -- inside use only
grant execute on function private.session_change_pending(uuid) to authenticated, service_role; -- (the page checks it as the signed-in person)

-- ---------------------------------------------------------------------------
-- 3. Recording a no-show for such a session closes it for CLG to rebook
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's code
  v_old text := E'  update public.sessions\n  set status = p_status'; -- the line where the outcome is saved
begin -- start
  v_def := replace(pg_get_functiondef('public.record_session_outcome(uuid, public.session_status)'::regprocedure), chr(13), ''); -- reads its current code
  if strpos(v_def, 'session_change_pending') > 0 then return; end if; -- already added: nothing to do
  if strpos(v_def, v_old) = 0 then -- the place has changed:
    raise exception 'record_session_outcome has changed since this update was written. Ask for an updated file.'; -- stops, so nothing half-changes
  end if; -- end of the check
  v_def := replace(v_def, v_old, -- before saving the outcome:
    E'  if p_status = ''no_show'' and private.session_change_pending(p_session) then -- a change was waiting (contract clause 3.4, Carla 22 Nov 2026):\n'
    || E'    update public.sessions set status = ''cancelled'', cancelled_at = now(), cancelled_by_role = ''admin'', cancel_reason_kind = ''change_pending'', -- closed by CLG, not a no-show,\n'
    || E'      cancel_reason = ''A change to this session was waiting for approval, so it is not a no-show. CLG will follow up and rebook it.'' where id = p_session; -- with a plain reason\n'
    || E'    perform private.notify_admins(''Session to rebook: change not approved in time'', -- tells the owner and Operations admins:\n'
    || E'      left((select coalesce(st.full_name, ''A student'') from public.students st where st.id = v_s.student_id) || '' '' || private.when_text(v_s.starts_at) -- who and when,\n'
    || E'        || '': a no-show was recorded, but a change to this session was waiting for approval. It is not a no-show for the tutor or the family (no charge, no no-show pay). Please follow up and rebook it.'', 1000), null); -- what to do\n'
    || E'    return; -- nothing else to save\n'
    || E'  end if; -- end of the change check\n'
    || v_old); -- then the outcome is saved as before
  execute v_def; -- saves the changed function
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 4. Billing: no pay lines for these sessions
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's code
  v_old text := E'    where (se.starts_at at time zone ''Australia/Adelaide'')::date between p_from and p_to\n'; -- the line that picks the sessions
begin -- start
  v_def := replace(pg_get_functiondef('public.billing_build_pay(date, date)'::regprocedure), chr(13), ''); -- reads its current code
  if strpos(v_def, 'change_pending') > 0 then return; end if; -- already added: nothing to do
  if strpos(v_def, v_old) = 0 then -- the place has changed:
    raise exception 'billing_build_pay has changed since this update was written. Ask for an updated file.'; -- stops, so nothing half-changes
  end if; -- end of the check
  execute replace(v_def, v_old, v_old || E'      and coalesce(se.cancel_reason_kind, '''') <> ''change_pending'' -- not a session closed because a change was waiting (no no-show pay)\n'); -- skips those sessions
end; -- finish
$$; -- end of the block
