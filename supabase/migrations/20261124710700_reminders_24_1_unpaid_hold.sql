-- Summary: session reminders at 24 hours and 1 hour for everyone, and a
-- 48-hour notice when a family's sessions are on hold for an overdue
-- payment (Carla, 22 Nov 2026):
--   "Reminders; just have 24 and 1 hour reminders. The family gets a
--   reminder at 48 hours if they have not paid and that everything has gone
--   on hold until payment has been made - and that if payment is not
--   received or something is not organised, the next session will be
--   cancelled. If this occurs and a session is cancelled due to no payment,
--   a meeting is to be set up between Carla and the family (person in
--   charge of paying)."
--
-- What changes (module: scheduling, which owns sessions and their notices;
-- it only reads billing through billing's own functions):
--   1. The first session reminder is now 24 hours before for everyone. The
--      "First reminder" setting (48 hours by default) is no longer used.
--      The final reminder stays at 1 hour before.
--   2. 48 hours before a session, if the family is on hold for an overdue
--      payment, the people who pay get a notice: sessions are on hold until
--      the payment is made, and the session will be cancelled if it is not
--      paid, or a plan agreed with CLG, at least 2 hours before it starts.
--   3. 2 hours before the session, if the family is still on hold, the
--      session is cancelled by CLG (the family gets full credit, as with any
--      CLG cancel), the people linked to it are told, and the owner and
--      Operations admins are asked to set up a meeting between Carla and
--      the person who pays.
--
-- Safe to run more than once. Run after every earlier scheduling and
-- billing file.

-- ---------------------------------------------------------------------------
-- 1. Billing: who pays for a family (billing owns these tables)
-- ---------------------------------------------------------------------------
create or replace function private.billing_family_payer_ids(p_family uuid) -- the family
returns setof uuid -- each person who pays for it
language sql stable security definer -- reads billing's tables for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select b.bill_payer_id from public.billing_accounts b -- the family's bill payer,
  where b.family_id = p_family and b.bill_payer_id is not null -- if one is named
  union -- and
  select p.account_id from public.billing_payers p -- any extra payer sharing the invoices
  where p.family_id = p_family; -- for this family
$$; -- end of the function
revoke all on function private.billing_family_payer_ids(uuid) from public; -- inside use only

-- ---------------------------------------------------------------------------
-- 2. Two new kinds of session notice
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
begin -- start
  if not exists ( -- the new kinds are not allowed yet:
    select 1 from pg_constraint -- (looks at the table's rules)
    where conname = 'session_notices_kind_check' -- the rule listing the kinds
      and pg_get_constraintdef(oid) like '%unpaid_hold%' -- already includes them
  ) then -- not yet:
    alter table public.session_notices drop constraint if exists session_notices_kind_check; -- removes the old list
    alter table public.session_notices add constraint session_notices_kind_check check (kind in ( -- adds the list back:
      'reminder_first', 'reminder_final', -- session reminders
      'booking_requested', 'booking_confirmed', 'booking_declined', -- booking changes
      'session_cancelled', 'renewal_due', 'availability_check', -- cancels, renewals and availability checks
      'offer_follow_up', 'tutor_away', 'request_update', 'staff_alert', 'check_renewal', -- the other kinds already in use
      'running_late', -- the tutor is running late
      'unpaid_hold', 'unpaid_cancelled' -- and the two new ones: the 48-hour payment notice, and the cancel for no payment
    )); -- end of the list
  end if; -- end of the check
end; -- finish
$$; -- end of the block
-- Each payment notice once per person per session.
create unique index if not exists session_notices_unpaid_once -- the rule
  on public.session_notices (account_id, session_id, kind) -- one per person, session and kind
  where kind in ('unpaid_hold', 'unpaid_cancelled'); -- for the payment notices

-- ---------------------------------------------------------------------------
-- 3. The first reminder is 24 hours before, for everyone
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's code
  v_old text := 'coalesce(ns.first_reminder_hours, 48) as hours'; -- each person's chosen time (48 hours if not set)
begin -- start
  v_def := replace(pg_get_functiondef('private.queue_reminders()'::regprocedure), chr(13), ''); -- reads its current code
  if strpos(v_def, v_old) = 0 then -- already changed (or changed elsewhere):
    if strpos(v_def, '24 as hours') > 0 then return; end if; -- already done: nothing to do
    raise exception 'queue_reminders has changed since this update was written. Ask for an updated file.'; -- stops, so nothing half-changes
  end if; -- end of the check
  v_def := replace(v_def, v_old, '24 as hours'); -- 24 hours before, for everyone (Carla, 22 Nov 2026)
  execute v_def; -- saves the changed function
end; -- finish
$$; -- end of the block
-- First reminders already queued at another time are moved to 24 hours before.
update public.session_notices n -- the reminders,
set deliver_at = greatest(x.starts_at - interval '24 hours', now()) -- now at 24 hours before (or now, if that has passed)
from public.sessions x -- with their sessions
where x.id = n.session_id and n.kind = 'reminder_first' -- first reminders
  and n.deliver_at > now() and n.read_at is null -- not yet delivered
  and n.deliver_at <> x.starts_at - interval '24 hours'; -- at a different time

-- ---------------------------------------------------------------------------
-- 4. The 48-hour payment notice, and the cancel 2 hours before
-- ---------------------------------------------------------------------------
create or replace function private.queue_unpaid_holds() -- no inputs
returns integer -- how many notices were sent and sessions cancelled
language plpgsql security definer -- reads sessions and writes notices for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  r record; -- one session
  v_count integer := 0; -- how many things were done
  v_n integer; -- rows from one step
  v_payers text; -- the names of the people who pay
begin -- start
  -- The notice: sessions in the next 48 hours (more than 2 hours away) for families on hold.
  insert into public.session_notices (account_id, session_id, kind, title, body, deliver_at) -- saves a notice
  select p.payer, x.id, 'unpaid_hold', -- to each person who pays, about this session,
         'Payment needed for ' || split_part(s.full_name, ' ', 1) || '''s session', -- its title,
         left('A payment is overdue, so sessions are on hold until it is paid. ' -- what has happened,
           || 'If it is not paid, or a payment plan agreed with CLG, at least 2 hours before ' -- what is needed,
           || split_part(s.full_name, ' ', 1) || '''s ' || x.subject || ' session (' || private.when_text(x.starts_at) || '), ' -- for which session,
           || 'the session will be cancelled. You can pay under Billing, or ask in the help chat to organise it.', 1000), -- and how to sort it
         now() -- now (quiet hours apply through the notice trigger)
  from public.sessions x -- from the sessions
  join public.students s on s.id = x.student_id -- with their students
  cross join lateral private.billing_family_payer_ids(x.family_id) as p(payer) -- and each person who pays
  where x.status = 'scheduled' -- still booked
    and x.starts_at > now() + interval '2 hours' -- more than 2 hours away
    and x.starts_at <= now() + interval '48 hours' -- within 48 hours
    and private.family_paused(x.family_id) -- the family is on hold for an overdue payment
  on conflict do nothing; -- each person once per session
  get diagnostics v_n = row_count; -- how many
  v_count := v_count + v_n; -- added to the total

  -- The cancel: sessions 2 hours away or less whose family is still on hold.
  for r in -- for each one:
    select x.id, x.family_id, x.student_id, x.tutor_id, x.starts_at, x.subject, s.full_name as student_name -- the session and student
    from public.sessions x join public.students s on s.id = x.student_id -- from the sessions, with their students
    where x.status = 'scheduled' -- still booked
      and x.starts_at > now() -- not started yet
      and x.starts_at <= now() + interval '2 hours' -- 2 hours away or less
      and private.family_paused(x.family_id) -- still on hold
      and exists (select 1 from public.session_notices n where n.session_id = x.id and n.kind = 'unpaid_hold') -- and the family was warned
    for update of x -- holds each session while it is changed
  loop -- (each one)
    update public.sessions -- cancels it:
    set status = 'cancelled', cancelled_at = now(), cancelled_by = null, -- now, by the system,
        cancelled_by_role = 'admin', cancel_reason_kind = 'other', -- as a CLG cancel (full credit),
        cancel_reason = 'Cancelled because the overdue payment was not made or organised in time.' -- the reason everyone sees
    where id = r.id and status = 'scheduled'; -- this session, if still booked
    -- The people linked to the session are told (the tutor only that it is cancelled, never why money is involved).
    insert into public.session_notices (account_id, session_id, kind, title, body, deliver_at) -- saves a notice
    select p.account_id, r.id, 'unpaid_cancelled', -- to each person linked to the session,
           'Session cancelled', -- its title,
           left(case when p.is_tutor -- for the tutor:
             then r.subject || ' with ' || r.student_name || ' (' || private.when_text(r.starts_at) || ') is cancelled. CLG will be in touch about the next one.' -- no money details,
             else split_part(r.student_name, ' ', 1) || '''s ' || r.subject || ' session (' || private.when_text(r.starts_at) || ') is cancelled because sessions are on hold for an overdue payment. ' -- for the family: what and why,
               || 'CLG will contact the person who pays to find a time to talk about how we can help.' end, 1000), -- and what happens next
           now() -- now
    from private.session_people(r.student_id, r.tutor_id) p -- the people linked to the session
    on conflict do nothing; -- once each
    -- The owner and Operations admins are asked to set up the meeting with Carla.
    select string_agg(a.full_name, ' and ' order by a.full_name) into v_payers -- the names of the people who pay
    from private.billing_family_payer_ids(r.family_id) as p(payer) join public.accounts a on a.id = p.payer; -- from their accounts
    perform private.notify_admins('Session cancelled for no payment', -- tells the admins:
      r.student_name || '''s ' || r.subject || ' session (' || private.when_text(r.starts_at) || ') was cancelled because the overdue payment was not made or organised. ' -- what happened,
      || 'Set up a meeting between Carla and ' || coalesce(v_payers, 'the person who pays') -- the meeting,
      || ' to talk about whether anything needs to change, how to support them, and how to stop this happening again.'); -- and what it is for
    v_count := v_count + 1; -- counted
  end loop; -- next session
  return v_count; -- hands back the total
end; -- end of the code
$$; -- end of the function
revoke all on function private.queue_unpaid_holds() from public; -- only run by the scheduled job

-- Every 15 minutes, with the other reminders.
do $$ -- a one-off block
begin -- start
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then -- the job runner is available:
    execute 'create extension if not exists pg_cron with schema pg_catalog'; -- turns it on (if it is not already)
    execute $job$ select cron.schedule('clg-unpaid-holds', '*/15 * * * *', 'select private.queue_unpaid_holds()') $job$; -- every 15 minutes (replaces one with the same name)
  end if; -- end of the check
end; -- finish
$$; -- end of the block
