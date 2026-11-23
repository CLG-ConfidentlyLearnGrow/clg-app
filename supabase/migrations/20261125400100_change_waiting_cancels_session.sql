-- Summary: a session is cancelled while a change to it is still waiting for
-- confirmation (Carla, 23 Nov 2026).
--
-- Carla: "when a session change is waiting it cancels the session
-- (notifying the tutor/family that they need to confirm the session change,
-- give a different availability, or continue with the session
-- cancellation)."
--
-- In the app, a change to a student's sessions (a new tutor, and maybe a new
-- day and time) is a "tutor change" that the new tutor and the family both
-- confirm before anything moves. Until now the old session stayed booked
-- while the change waited. With this file:
--   * A check every 15 minutes finds each booked session covered by a
--     change that is still waiting (same student, tutor and subject, on or
--     after the change's first date, change sent before the session) that
--     starts within the "cancel while waiting" time (24 hr by default, a
--     setting) but more than 2 hr from now. It cancels the session as a CLG
--     cancel, with the reason "A change was waiting for approval".
--   * Money follows the rules already in place for a CLG cancel made 2 hr
--     or more ahead: the family gets full credit and the tutor gets no
--     late-cancel pay (PR 219 already keeps these sessions out of pay).
--   * The current tutor is told the session is cancelled. The new tutor and
--     the family (parents, and the student with their own login) are told
--     the session is cancelled and asked to choose one of three things:
--       1. Confirm the change: the existing "Please confirm a change" step.
--          Once everyone has confirmed, the cancelled session comes back at
--          the new tutor, day and time, if it is still more than 2 hr away
--          and no credit has been given for it yet.
--       2. Offer other times: the family's times go to CLG's Requests list
--          (or, from the new tutor, to the admins) so CLG can rebook it.
--       3. Keep it cancelled: the session stays cancelled with full credit.
--     The first answer from anyone asked counts for that session (for the
--     family, the first answer from a parent or the student).
--   * The owner and Operations admins are told each time a session is
--     cancelled this way, and when someone chooses 2 or 3.
--   * Sessions less than 2 hr away when the change is noticed are left as
--     booked. If one of those is recorded as a no-show, PR 219 already
--     closes it as a CLG cancel instead (no charge, no no-show pay).
--
-- Module: scheduling (owns sessions, tutor changes, notices and requests).
-- Teams links: a small Teams helper lets a session that comes back get a
-- new meeting link (the Teams part only changes its own records).
--
-- This file also includes everything in
-- 20261124711100_pending_change_no_no_show.sql (PR 219), as part 0 below,
-- so it does not matter whether that file was run before. Safe to run more
-- than once.

-- ===========================================================================
-- 0. Everything from 20261124711100_pending_change_no_no_show.sql (PR 219),
--    copied here unchanged. Each step checks whether it is already done.
-- ===========================================================================
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

-- ===========================================================================
-- End of part 0. The new steps for this file follow.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The setting: how long before a session a waiting change cancels it
-- ---------------------------------------------------------------------------
alter table public.scheduling_settings -- the one row of scheduling settings
  add column if not exists change_cancel_hours integer not null default 24 -- hours before a session that a waiting change cancels it (24 by default)
  check (change_cancel_hours between 2 and 336); -- at least 2 hr (so no tutor is paid for a late cancel), at most 2 weeks

-- ---------------------------------------------------------------------------
-- 2. The record of each session cancelled this way, and what was chosen
-- ---------------------------------------------------------------------------
create table if not exists public.change_cancelled_sessions ( -- one row per session cancelled while a change waited
  session_id uuid primary key references public.sessions (id) on delete cascade, -- the cancelled session (once each)
  offer_id uuid not null references public.tutor_change_offers (id) on delete cascade, -- the change that was waiting
  student_id uuid not null references public.students (id) on delete cascade, -- the student (for checking who may answer)
  to_tutor uuid not null references public.accounts (id) on delete cascade, -- the new tutor in the change (who may answer)
  status text not null default 'open' -- where it is up to:
    check (status in ('open', 'restored', 'other_times', 'kept_cancelled', 'closed')), -- waiting for a choice, back on, other times offered, kept cancelled, or closed
  chosen_by uuid references public.accounts (id) on delete set null, -- who chose (for other times or keep cancelled)
  chosen_role text check (chosen_role in ('tutor', 'family')), -- whether the new tutor or the family chose
  chosen_note text check (char_length(chosen_note) <= 1000), -- the times offered, if any
  chosen_at timestamptz, -- when they chose
  request_id uuid references public.session_requests (id) on delete set null, -- the family's request for another time, if one was made
  created_at timestamptz not null default now() -- when the session was cancelled
); -- end of the table
create index if not exists change_cancelled_sessions_open -- quick lookup of the sessions still waiting for a choice
  on public.change_cancelled_sessions (offer_id) where status = 'open'; -- by change, only the open ones
alter table public.change_cancelled_sessions enable row level security; -- turns on access rules (no rule: read only through the functions below)
revoke all on public.change_cancelled_sessions from anon, authenticated; -- nobody reads or changes it directly
drop trigger if exists audit on public.change_cancelled_sessions; -- removes the old audit trigger if the file is run again
create trigger audit after insert or update or delete on public.change_cancelled_sessions -- records every change in the audit log
  for each row execute function private.audit_change(); -- using the shared audit step

-- ---------------------------------------------------------------------------
-- 3. A new kind of notice: "cancelled while a change waits" (once each)
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_def text; -- the current list of kinds, as the database writes it
begin -- start
  select pg_get_constraintdef(oid) into v_def from pg_constraint where conname = 'session_notices_kind_check'; -- reads the current list
  if v_def is null or strpos(v_def, 'change_cancelled') > 0 then return; end if; -- no list, or already added: nothing to do
  if strpos(v_def, 'ARRAY[') = 0 then -- the list is written in an unexpected way:
    raise exception 'The notice kinds list has changed since this update was written. Ask for an updated file.'; -- stops, so nothing half-changes
  end if; -- end of the check
  alter table public.session_notices drop constraint session_notices_kind_check; -- removes the old list
  execute 'alter table public.session_notices add constraint session_notices_kind_check ' -- adds the list back,
    || replace(v_def, 'ARRAY[', 'ARRAY[''change_cancelled''::text, '); -- with the new kind at the front
end; -- finish
$$; -- end of the block
create unique index if not exists session_notices_change_cancelled_once -- each person is told once per session
  on public.session_notices (account_id, session_id, kind) -- one per person, session and kind
  where kind = 'change_cancelled'; -- for the new kind only

-- ---------------------------------------------------------------------------
-- 4. Teams helper: lets a session that comes back get a new meeting link
-- ---------------------------------------------------------------------------
-- When a cancelled online session's meeting has already been deleted, the
-- Teams job would never make a new one. This clears that finished record so
-- the next Teams run makes a fresh link. Only removed meetings are cleared.
create or replace function private.teams_forget_removed(p_session uuid) -- takes the session
returns void language sql security definer -- changes the Teams records for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  delete from public.teams_meetings where session_id = p_session and status = 'removed'; -- clears a deleted meeting's record for this session
$$; -- end of the function
revoke all on function private.teams_forget_removed(uuid) from public; -- inside use only

-- ---------------------------------------------------------------------------
-- 5. The check every 15 minutes: cancel sessions while a change waits
-- ---------------------------------------------------------------------------
create or replace function private.cancel_sessions_for_waiting_changes() -- no inputs
returns integer -- how many sessions were cancelled
language plpgsql security definer -- changes sessions and writes notices for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_hours integer; -- the "cancel while waiting" time, in hours
  r record; -- one session to cancel
  v_count integer := 0; -- how many were cancelled
  v_first text; -- the student's first name
  v_to_name text; -- the new tutor's name
begin -- start
  select coalesce(change_cancel_hours, 24) into v_hours from public.scheduling_settings limit 1; -- reads the setting
  v_hours := coalesce(v_hours, 24); -- 24 hr if the setting is missing

  for r in -- for each session to cancel:
    select x.id, x.student_id, x.tutor_id, x.subject, x.starts_at, -- the session,
           s.full_name as student_name, o.id as offer_id, o.to_tutor -- its student and the waiting change
    from public.tutor_change_offers o -- from the waiting changes
    join public.sessions x on x.student_id = o.student_id and x.tutor_id = o.from_tutor and lower(x.subject) = lower(o.subject) -- each session the change covers (same student, tutor and subject)
    join public.students s on s.id = x.student_id -- with its student (for the name and time zone)
    where o.status = 'waiting' -- the change is still waiting
      and x.status = 'scheduled' -- the session is still booked
      and x.starts_at > now() + interval '2 hours' -- more than 2 hr away (so it is not a late cancel)
      and x.starts_at <= now() + make_interval(hours => v_hours) -- within the "cancel while waiting" time
      and o.created_at < x.starts_at -- the change was sent before the session
      and (x.starts_at at time zone coalesce(private.state_timezone(s.state), 'Australia/Adelaide'))::date >= o.from_date -- on or after the change's first date
    for update of x skip locked -- holds each session while it is changed
  loop -- (each one)
    update public.sessions -- cancels it:
    set status = 'cancelled', cancelled_at = now(), cancelled_by = null, -- now, by the system,
        cancelled_by_role = 'admin', cancel_reason_kind = 'change_pending', -- as a CLG cancel (full credit), because a change was waiting,
        cancel_reason = 'Cancelled because a change to this session was still waiting for confirmation.' -- the reason everyone sees
    where id = r.id and status = 'scheduled'; -- this session, if still booked
    if not found then continue; end if; -- already changed by something else: skips it
    insert into public.change_cancelled_sessions (session_id, offer_id, student_id, to_tutor) -- keeps a record, waiting for a choice
    values (r.id, r.offer_id, r.student_id, r.to_tutor) -- this session and its change
    on conflict (session_id) do nothing; -- once per session
    v_first := split_part(r.student_name, ' ', 1); -- the student's first name
    select full_name into v_to_name from public.accounts where id = r.to_tutor; -- the new tutor's name

    -- The current tutor: the session is off (no choice to make).
    insert into public.session_notices (account_id, session_id, kind, title, body, deliver_at) -- saves a notice
    values (r.tutor_id, r.id, 'change_cancelled', 'Session cancelled', -- to the current tutor,
      left(r.subject || ' with ' || r.student_name || ' (' || private.when_text(r.starts_at) || ') is cancelled because a change to these sessions is still waiting for confirmation. Please do not go to this session.', 1000), -- what and why,
      now()) -- now (quiet hours apply through the notice trigger)
    on conflict do nothing; -- once

    -- The new tutor: the session is off, and the three choices.
    insert into public.session_notices (account_id, session_id, kind, title, body, deliver_at) -- saves a notice
    values (r.to_tutor, r.id, 'change_cancelled', 'Session cancelled: please choose what happens', -- to the new tutor,
      left(v_first || '''s ' || r.subject || ' session (' || private.when_text(r.starts_at) || ') is cancelled because the change to you is still waiting for confirmation. ' -- what and why,
        || 'Under Sessions you can confirm the change (the session comes back with you if everyone confirms in time), offer other times, or keep it cancelled.', 1000), -- the three choices
      now()) -- now
    on conflict do nothing; -- once

    -- The family: the session is off, there is no charge, and the three choices.
    insert into public.session_notices (account_id, session_id, kind, title, body, deliver_at) -- saves a notice
    select p.account_id, r.id, 'change_cancelled', 'Session cancelled: please choose what happens', -- to each parent (and the student, with their own login),
      left(v_first || '''s ' || r.subject || ' session (' || private.when_text(r.starts_at) || ') is cancelled because the change to ' || coalesce(v_to_name, 'a new tutor') || ' is still waiting for confirmation. There is no charge for it. ' -- what, why and the money,
        || 'Under Sessions you can confirm the change (the session comes back if everyone confirms in time), offer other times that suit, or keep it cancelled.', 1000), -- the three choices
      now() -- now
    from private.session_people(r.student_id, null) p -- the people told about the student's sessions
    where not p.is_tutor and p.account_id is not null -- the family only
    on conflict do nothing; -- once each

    -- The owner and Operations admins: so they can follow up.
    perform private.notify_admins('Session cancelled: change still waiting', -- the title,
      left(r.student_name || ', ' || r.subject || ' (' || private.when_text(r.starts_at) || ') was cancelled because the change of tutor is still waiting for confirmation. ' -- who and when,
        || 'The family gets full credit. Please follow up the change under Sessions > Change tutor.', 1000), null); -- what to do
    v_count := v_count + 1; -- counts it
  end loop; -- end of each session

  -- Tidies up: records left open a week after the session, or whose change is finished and session has passed, are closed.
  update public.change_cancelled_sessions c set status = 'closed' -- closes them
  from public.sessions x, public.tutor_change_offers o -- (with the session and the change)
  where c.status = 'open' and x.id = c.session_id and o.id = c.offer_id -- open records, with their session and change
    and (x.starts_at < now() - interval '7 days' or (o.status <> 'waiting' and x.starts_at < now())); -- old, or finished and passed
  return v_count; -- how many were cancelled
end; -- finish
$$; -- end of the function
revoke all on function private.cancel_sessions_for_waiting_changes() from public; -- only run by the scheduled job

-- Every 15 minutes, with the other session checks.
do $$ -- a one-off block
begin -- start
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then -- the job runner is available:
    execute 'create extension if not exists pg_cron with schema pg_catalog'; -- turns it on (if it is not already)
    execute $job$ select cron.schedule('clg-change-waiting-cancels', '*/15 * * * *', 'select private.cancel_sessions_for_waiting_changes()') $job$; -- every 15 minutes (replaces one with the same name)
  end if; -- end of the check
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 6. When everyone confirms, cancelled sessions still ahead come back
-- ---------------------------------------------------------------------------
-- Puts back each session cancelled while this change waited, if: nobody
-- chose another time or to keep it cancelled, it is still more than 2 hr
-- away, and no credit has been given for it yet. The change then moves it
-- to the new tutor, day and time with the other sessions. If the change
-- cannot be made, everything here is undone with it.
create or replace function private.restore_change_cancelled_sessions(p_offer uuid) -- takes the change
returns integer -- how many sessions came back
language plpgsql security definer -- changes sessions for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  r record; -- one session to bring back
  v_count integer := 0; -- how many came back
begin -- start
  for r in -- for each one:
    select c.session_id -- the session
    from public.change_cancelled_sessions c -- from the record
    join public.sessions x on x.id = c.session_id -- with the session
    where c.offer_id = p_offer and c.status = 'open' -- this change, still waiting for a choice
      and x.status = 'cancelled' and x.cancel_reason_kind = 'change_pending' -- still cancelled for this reason
      and x.starts_at > now() + interval '2 hours' -- still more than 2 hr away
      and not exists (select 1 from public.billing_credits b where b.session_id = x.id) -- no credit given for it yet
    for update of c -- holds each record while it is changed
  loop -- (each one)
    update public.sessions -- puts the session back:
    set status = 'scheduled', cancelled_at = null, cancelled_by = null, -- booked again,
        cancelled_by_role = null, cancel_reason_kind = null, cancel_reason = null -- with the cancel details cleared
    where id = r.session_id; -- this session
    perform private.teams_forget_removed(r.session_id); -- lets it get a new Teams link if its old one was deleted
    update public.change_cancelled_sessions set status = 'restored' where session_id = r.session_id; -- marks it back on
    v_count := v_count + 1; -- counts it
  end loop; -- end of each one
  return v_count; -- how many came back
end; -- finish
$$; -- end of the function
revoke all on function private.restore_change_cancelled_sessions(uuid) from public; -- inside use only

-- Adds the step to "make the change once everyone has confirmed", just
-- before the change is made (so the sessions that came back move too).
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's code
  v_old text := '    perform private.apply_tutor_change(o.student_id'; -- the line where the change is made
begin -- start
  v_def := replace(pg_get_functiondef('private.finish_tutor_change(uuid)'::regprocedure), chr(13), ''); -- reads its current code
  if strpos(v_def, 'restore_change_cancelled_sessions') > 0 then return; end if; -- already added: nothing to do
  if strpos(v_def, v_old) = 0 then -- the place has changed:
    raise exception 'finish_tutor_change has changed since this update was written. Ask for an updated file.'; -- stops, so nothing half-changes
  end if; -- end of the check
  execute replace(v_def, v_old, -- before making the change:
    E'    perform private.restore_change_cancelled_sessions(o.id); -- brings back sessions cancelled while it waited (Carla, 23 Nov 2026)\n'
    || v_old); -- then the change is made as before
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 7. The list for the new tutor and the family: sessions to choose for
-- ---------------------------------------------------------------------------
create or replace function public.my_change_cancelled_sessions() -- no inputs
returns table (session_id uuid, offer_id uuid, answer_as text, student_name text, subject text, starts_at timestamptz, -- the session, the change, who they answer as, the student, subject and time,
               from_tutor_name text, to_tutor_name text, change_waiting boolean, can_confirm boolean) -- the tutors, whether the change still waits, and whether they can still confirm it
language sql stable security definer -- reads past the access rules, only the person's own
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the list
  select c.session_id, c.offer_id, x.role, s.full_name, se.subject, se.starts_at, -- the session, change, role, student, subject and time,
    case when x.role = 'family' then f.full_name end, t.full_name, -- the current tutor's name (families only) and the new tutor's,
    o.status = 'waiting', -- whether the change is still waiting,
    o.status = 'waiting' and ((x.role = 'tutor' and o.tutor_ok_at is null) or (x.role = 'family' and o.family_ok_at is null)) -- and whether they have not confirmed it yet
  from public.change_cancelled_sessions c -- each cancelled session
  join public.tutor_change_offers o on o.id = c.offer_id -- with its change
  join public.sessions se on se.id = c.session_id -- and the session
  join public.students s on s.id = c.student_id -- and the student's name
  left join public.accounts f on f.id = o.from_tutor -- the current tutor's name
  left join public.accounts t on t.id = o.to_tutor -- the new tutor's name
  cross join lateral (select case -- who they answer as:
      when c.to_tutor = (select auth.uid()) and private.has_aal2() then 'tutor' -- the new tutor, with two-step sign-in,
      when private.is_family_of(c.student_id) then 'family' -- or the family
    end as role) x -- (or nobody)
  where c.status = 'open' and x.role is not null -- still waiting for a choice, and theirs to answer
  order by se.starts_at -- soonest first
$$; -- end of the function
revoke all on function public.my_change_cancelled_sessions() from public, anon; -- not for signed-out visitors
grant execute on function public.my_change_cancelled_sessions() to authenticated; -- signed-in people (only their own)

-- ---------------------------------------------------------------------------
-- 8. Choosing "Offer other times" or "Keep it cancelled"
-- ---------------------------------------------------------------------------
-- (Confirming the change uses the existing answer_tutor_change step.)
create or replace function public.answer_change_cancelled_session(p_session uuid, p_choice text, p_note text default null) -- takes the session, the choice, and the times for "other times"
returns text -- gives back the choice saved
language plpgsql security definer -- saves the choice and notices past the access rules
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  c public.change_cancelled_sessions; -- the record
  se public.sessions; -- the session
  v_role text; -- who is answering: 'tutor' or 'family'
  v_note text := nullif(left(btrim(coalesce(p_note, '')), 1000), ''); -- the times given, trimmed
  v_student text; -- the student's name
  v_request uuid; -- the family's request for another time
  v_when text; -- the session's time in words
begin -- start
  if p_choice is null or p_choice not in ('other_times', 'kept_cancelled') then -- not one of the two choices
    raise exception 'Please choose to offer other times or to keep the session cancelled.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select * into c from public.change_cancelled_sessions where session_id = p_session for update; -- the record, held
  if c.session_id is not null and c.to_tutor = (select auth.uid()) and private.has_aal2() then -- the new tutor, with two-step sign-in
    v_role := 'tutor'; -- answers as the tutor
  elsif c.session_id is not null and private.is_family_of(c.student_id) then -- someone in the family
    v_role := 'family'; -- answers for the family
  else -- anyone else
    raise exception 'Session not found.' using errcode = '22023'; -- plain message (does not say whether it exists)
  end if; -- end of the check
  if c.status <> 'open' then -- someone has already chosen, or it is back on
    raise exception 'A choice has already been made for this session.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_choice = 'other_times' and (v_note is null or char_length(v_note) < 2) then -- no times given
    raise exception 'Please say which days and times suit, so CLG can rebook the session.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select * into se from public.sessions where id = c.session_id; -- the session
  select full_name into v_student from public.students where id = c.student_id; -- the student's name
  v_when := private.when_text(se.starts_at); -- the session's time in words

  if p_choice = 'other_times' and v_role = 'family' then -- the family offers other times:
    insert into public.session_requests (student_id, kind, subject, tutor_id, event_on, event_label, wants, note, created_by) -- adds it to CLG's Requests list
    values (c.student_id, 'away_cover', se.subject, c.to_tutor, -- for this student and subject, with the new tutor,
      (se.starts_at at time zone coalesce((select private.state_timezone(st.state) from public.students st where st.id = c.student_id), 'Australia/Adelaide'))::date, 'Session cancelled while a change was waiting', 'time', v_note, (select auth.uid())) -- the session's date, why, a different time, the times that suit, and who asked
    returning id into v_request; -- keeps its id
  end if; -- end of the request

  update public.change_cancelled_sessions -- saves the choice:
  set status = p_choice, chosen_by = (select auth.uid()), chosen_role = v_role, -- what and who,
      chosen_note = case when p_choice = 'other_times' then v_note end, chosen_at = now(), request_id = v_request -- the times, when, and any request
  where session_id = c.session_id; -- this session

  perform private.notify_admins( -- tells the owner and Operations admins:
    case when p_choice = 'other_times' then 'Other times offered for a cancelled session' else 'Cancelled session kept cancelled' end, -- the title,
    left('The ' || v_role || ' chose to ' || case when p_choice = 'other_times' then 'offer other times' else 'keep it cancelled' end -- who chose what,
      || ' for ' || v_student || ', ' || se.subject || ' (' || v_when || '), which was cancelled while a change was waiting.' -- for which session,
      || case when p_choice = 'other_times' then ' Times that suit: ' || v_note || case when v_request is not null then ' See Sessions > Requests.' else '' end else '' end, 1000), -- and the times, with where to find the request
    null); -- (no booking)

  if v_role = 'family' then -- the family chose: tells the new tutor
    perform private.add_notice(c.to_tutor, c.session_id, null, 'request_update', -- a notice to the new tutor,
      case when p_choice = 'other_times' then 'Family offered other times' else 'Session staying cancelled' end, -- the title,
      split_part(v_student, ' ', 1) || '''s family chose to ' || case when p_choice = 'other_times' then 'offer other times for the ' else 'keep the ' end -- what they chose,
        || se.subject || ' session (' || v_when || ')' || case when p_choice = 'other_times' then '. CLG will be in touch to rebook it.' else ' cancelled.' end, now()); -- for which session, and what happens next
  else -- the tutor chose: tells the family
    perform private.add_notice(p.account_id, c.session_id, null, 'request_update', -- a notice to each parent (and the student, with their own login),
      case when p_choice = 'other_times' then 'Tutor offered other times' else 'Session staying cancelled' end, -- the title,
      'The new tutor chose to ' || case when p_choice = 'other_times' then 'offer other times for ' else 'keep ' end -- what they chose,
        || split_part(v_student, ' ', 1) || '''s ' || se.subject || ' session (' || v_when || ')' -- for which session,
        || case when p_choice = 'other_times' then '. CLG will be in touch to rebook it.' else ' cancelled. There is no charge for it.' end, now()) -- and what happens next
    from private.session_people(c.student_id, null) p where not p.is_tutor and p.account_id is not null; -- (the family only)
  end if; -- end of telling the other side

  perform private.log_event('change_cancelled_session_answered', 'change_cancelled_sessions', c.session_id::text, jsonb_build_object('role', v_role, 'choice', p_choice)); -- the activity log entry (id, who and what)
  return p_choice; -- the choice saved
end; -- finish
$$; -- end of the function
revoke all on function public.answer_change_cancelled_session(uuid, text, text) from public, anon; -- not for signed-out visitors
grant execute on function public.answer_change_cancelled_session(uuid, text, text) to authenticated; -- signed-in people can try (the check is inside)
