-- Summary: quiet hours are now 9pm to 5am in each person's own local time,
-- and they are one shared setting (shared core). Carla, 12 Nov 2026.
--
-- Before: nothing was delivered between 9pm and 6am Adelaide time (it was
-- 8pm to 8am until 2 Nov). Now:
--   1. The hours live in one row, public.quiet_hours_settings (9pm to 5am
--      to start). Owner and operations admins can change them in the app
--      (Sessions > Notices), and nothing else in the app has its own copy.
--   2. The hours follow the person getting the notice: a student's own
--      state, a parent's child's state, or a tutor's work state. Anyone
--      without a state (for example office staff) uses Adelaide time.
--   3. Every notice (scheduling and progress) has its delivery time checked
--      as it is saved, by one trigger on each notice table. Anything due in
--      quiet hours waits until they end (5am). A time that has already
--      passed is left alone (it counts as delivered already).
--   4. A "session in 1 hr" reminder that would wait past its session (a
--      very early session) comes the evening before, 30 min before quiet
--      hours start (8:30pm), in that person's local time.
--
-- The old one-input helper private.outside_quiet_hours(time) is kept so the
-- many functions that already call it keep working, but it now hands the
-- time straight back: the trigger does the real check, with the person's
-- own time zone. Security alerts to the owner still ignore quiet hours.
--
-- See docs/features/sending-emails.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. The shared setting
-- ---------------------------------------------------------------------------

-- One row holding CLG's quiet hours, used for every notice to everyone.
create table if not exists public.quiet_hours_settings ( -- the table, made only if it isn't there yet
  id boolean primary key default true check (id), -- only ever one row
  starts_at time not null default time '21:00', -- quiet hours start (9pm)
  ends_at time not null default time '05:00', -- quiet hours end, when held notices go out (5am)
  updated_at timestamptz not null default now(), -- when it last changed
  updated_by uuid references public.accounts (id) on delete set null, -- who changed it
  constraint quiet_hours_not_same check (starts_at <> ends_at) -- start and end can't be the same time
); -- end of the table
insert into public.quiet_hours_settings (id) values (true) on conflict do nothing; -- makes the one row (9pm to 5am)
alter table public.quiet_hours_settings enable row level security; -- access rules apply to this table
revoke all on public.quiet_hours_settings from anon; -- signed-out visitors can't see it
revoke insert, update, delete, truncate on public.quiet_hours_settings from authenticated; -- signed-in people can't edit it directly (only through set_quiet_hours)
drop policy if exists "signed-in people read quiet hours" on public.quiet_hours_settings; -- replaces the rule if this is run again
create policy "signed-in people read quiet hours" on public.quiet_hours_settings -- anyone signed in may read it
  for select to authenticated using (true); -- (two times of day, nothing personal); changes go through set_quiet_hours below

-- ---------------------------------------------------------------------------
-- 2. Whose local time
-- ---------------------------------------------------------------------------

-- The time zone a person lives or works in, for quiet hours. Checks, in
-- order: their own student record, the children they look after, their
-- tutor work state. Anyone else uses Adelaide time (CLG's home).
create or replace function private.account_timezone(p_account uuid) -- takes the person's account id
returns text -- a time zone name, e.g. 'Australia/Adelaide'
language sql stable security definer -- reads students and tutor settings whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the value
  select coalesce( -- the first of these that has an answer:
    (select private.state_timezone(s.state) from public.students s where s.account_id = p_account limit 1), -- a student with their own login: their state
    (select private.state_timezone(s.state) -- a parent: their child's state,
       from public.parent_student_links l -- from the parent-child links,
       join public.students s on s.id = l.student_id -- joined to each child,
       where l.parent_id = p_account -- for this parent,
       order by s.created_at -- oldest child record first, so the answer is always the same,
       limit 1), -- just one
    (select private.state_timezone(w.work_state) from public.tutor_work_settings w where w.tutor_id = p_account), -- a tutor: the state they work from
    'Australia/Adelaide' -- otherwise Adelaide time
  ) -- end of the choices
$$; -- end of the function
revoke all on function private.account_timezone(uuid) from public; -- only used inside other functions

-- ---------------------------------------------------------------------------
-- 3. The quiet hours check
-- ---------------------------------------------------------------------------

-- Moves a time out of quiet hours, in the given time zone. A time inside
-- quiet hours becomes the moment they end (5am local); any other time is
-- handed back unchanged. Works for hours that cross midnight (9pm to 5am)
-- and for hours that don't (for example midnight to 6am).
create or replace function private.outside_quiet_hours(p_at timestamptz, p_tz text) -- takes a moment and a time zone
returns timestamptz -- the moment it may be delivered
language plpgsql stable security definer -- reads the setting whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values
  v_start time; -- when quiet hours start
  v_end time; -- when quiet hours end
  v_tz text; -- the time zone used
  v_local timestamp; -- the moment as a local date and time
  v_t time; -- just the local time of day
begin -- start
  if p_at is null then -- no time given:
    return null; -- nothing to move
  end if; -- checked for a missing time
  select q.starts_at, q.ends_at into v_start, v_end from public.quiet_hours_settings q where q.id; -- reads the shared setting
  v_start := coalesce(v_start, time '21:00'); -- 9pm if the setting is missing
  v_end := coalesce(v_end, time '05:00'); -- 5am if the setting is missing
  v_tz := coalesce(nullif(p_tz, ''), 'Australia/Adelaide'); -- Adelaide if no time zone was given
  v_local := p_at at time zone v_tz; -- the moment in that person's local time
  v_t := v_local::time; -- the time of day there
  if v_start > v_end then -- quiet hours cross midnight (e.g. 9pm to 5am):
    if v_t >= v_start then -- late evening, after the start:
      return ((v_local::date + 1) + v_end) at time zone v_tz; -- waits until the end time tomorrow morning
    elsif v_t < v_end then -- early morning, before the end:
      return (v_local::date + v_end) at time zone v_tz; -- waits until the end time this morning
    end if; -- checked both sides of midnight
  elsif v_t >= v_start and v_t < v_end then -- quiet hours within one day (e.g. midnight to 6am), and inside them:
    return (v_local::date + v_end) at time zone v_tz; -- waits until the end time today
  end if; -- checked the quiet hours
  return p_at; -- outside quiet hours: unchanged
end; -- finish
$$; -- end of the function
revoke all on function private.outside_quiet_hours(timestamptz, text) from public; -- only used inside other functions

-- The same check in one person's own local time.
create or replace function private.outside_quiet_hours_for(p_account uuid, p_at timestamptz) -- takes the person and a moment
returns timestamptz -- the moment it may be delivered to them
language sql stable security definer -- reads their details and the setting whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the value
  select private.outside_quiet_hours(p_at, private.account_timezone(p_account)) -- quiet hours in their time zone
$$; -- end of the function
revoke all on function private.outside_quiet_hours_for(uuid, timestamptz) from public; -- only used inside other functions

-- The old one-input helper. Many existing functions still call it when
-- they save a notice; it now hands the time back unchanged, because the
-- trigger below checks quiet hours in the person's own time zone as the
-- notice is saved (doing it here too would use the wrong time zone).
create or replace function private.outside_quiet_hours(p_at timestamptz) -- takes a moment
returns timestamptz -- the same moment
language sql immutable -- always the same answer for the same input
set search_path = '' -- only fully named tables, for safety
as $$ -- the value
  select p_at -- unchanged: the notice tables' trigger applies quiet hours
$$; -- end of the function

-- ---------------------------------------------------------------------------
-- 4. Every notice is checked as it is saved
-- ---------------------------------------------------------------------------

-- Moves a new notice's delivery time out of the person's quiet hours. Used
-- by the scheduling and progress notice tables; it only changes the
-- delivery time, never what the notice says or who gets it. A time that
-- has already passed is left as it is: that notice counts as delivered.
create or replace function private.notice_quiet_hours() -- a trigger function (no inputs)
returns trigger -- hands back the row to save
language plpgsql security definer -- reads the person's details whoever saves the notice
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  if new.deliver_at >= now() then -- only a time that hasn't passed yet:
    new.deliver_at := private.outside_quiet_hours_for(new.account_id, new.deliver_at); -- the delivery time, moved out of their quiet hours
  end if; -- checked the time
  return new; -- saves the row with that time
end; -- finish
$$; -- end of the function
revoke all on function private.notice_quiet_hours() from public; -- only run by the triggers below

drop trigger if exists quiet_hours on public.session_notices; -- replaces the trigger if this is run again
create trigger quiet_hours before insert on public.session_notices -- before a new session notice is saved:
  for each row execute function private.notice_quiet_hours(); -- check quiet hours

drop trigger if exists quiet_hours on public.progress_notices; -- replaces the trigger if this is run again
create trigger quiet_hours before insert on public.progress_notices -- before a new progress notice is saved:
  for each row execute function private.notice_quiet_hours(); -- check quiet hours

-- ---------------------------------------------------------------------------
-- 5. Owner and operations admins change the hours
-- ---------------------------------------------------------------------------

-- Saves new quiet hours for all of CLG. Times are whole or half hours.
create or replace function public.set_quiet_hours(p_starts time, p_ends time) -- takes the start and end times
returns void -- nothing back
language plpgsql security definer -- writes the setting after checking who's asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  if not private.is_admin() then -- only owner and operations admins
    raise exception 'Only CLG''s owner or operations admins can change quiet hours' using errcode = '42501'; -- plain message
  end if; -- checked who
  if p_starts is null or p_ends is null then -- both times are needed
    raise exception 'Please choose when quiet hours start and end' using errcode = '22023'; -- plain message
  end if; -- checked both are there
  if p_starts = p_ends then -- the same time would mean no quiet hours, or all day
    raise exception 'Quiet hours must start and end at different times' using errcode = '22023'; -- plain message
  end if; -- checked they differ
  if extract(minute from p_starts) not in (0, 30) or extract(minute from p_ends) not in (0, 30) -- only on the hour or half hour,
     or extract(second from p_starts) <> 0 or extract(second from p_ends) <> 0 then -- with no seconds
    raise exception 'Quiet hours start and end on the hour or half hour' using errcode = '22023'; -- plain message
  end if; -- checked the minutes
  update public.quiet_hours_settings -- saves it in the one row:
  set starts_at = p_starts, ends_at = p_ends, updated_at = now(), updated_by = auth.uid() -- the new times, when, and who
  where id; -- (the only row)
end; -- finish
$$; -- end of the function
revoke all on function public.set_quiet_hours(time, time) from public, anon; -- not for signed-out visitors
grant execute on function public.set_quiet_hours(time, time) to authenticated; -- signed-in people (the function checks for admins)

-- ---------------------------------------------------------------------------
-- 6. Session reminders use each person's quiet hours
-- ---------------------------------------------------------------------------

-- Queues reminders for sessions in the next 8 days (run every 15 min).
-- Same as before, except the "session in 1 hr" fallback: if quiet hours
-- would hold that reminder until less than 15 min before the session, it
-- comes the evening before instead, 30 min before that person's quiet
-- hours start (8:30pm with 9pm to 5am), in their local time.
create or replace function private.queue_reminders() -- no inputs
returns integer -- how many reminders were queued
language plpgsql security definer -- reads sessions and writes notices whoever runs it
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values
  v_count integer; -- reminders queued this time
  v_start time; -- when quiet hours start
begin -- start
  select q.starts_at into v_start from public.quiet_hours_settings q where q.id; -- reads the quiet hours start
  v_start := coalesce(v_start, time '21:00'); -- 9pm if the setting is missing

  -- Reminders for sessions that were cancelled are withdrawn if not yet due.
  delete from public.session_notices n -- removes notices,
  using public.sessions x -- looking at their sessions,
  where x.id = n.session_id -- (each notice's session)
    and n.kind in ('reminder_first', 'reminder_final') -- that are reminders,
    and n.deliver_at > now() -- not yet delivered,
    and x.status <> 'scheduled'; -- for sessions no longer going ahead

  with upcoming as ( -- sessions coming up:
    select x.id, x.student_id, x.tutor_id, x.subject, x.starts_at, x.delivery, -- the session's details,
           st.full_name as student_name, tu.full_name as tutor_name, l.name as library_name -- and the names shown in the reminder
    from public.sessions x -- from sessions,
    join public.students st on st.id = x.student_id -- with the student,
    join public.accounts tu on tu.id = x.tutor_id -- the tutor,
    left join public.libraries l on l.id = x.library_id -- and the library, if any,
    where x.status = 'scheduled' -- still going ahead,
      and x.starts_at > now() -- not started yet,
      and x.starts_at <= now() + interval '8 days' -- within 8 days
  ), -- end of upcoming
  wanted as ( -- everyone who hears about each session:
    select u.*, p.account_id, p.is_tutor, -- the session, the person, and whether they're the tutor,
           coalesce(ns.first_reminder_hours, 48) as hours -- their first reminder time (48 hr if not set)
    from upcoming u -- for each session,
    cross join lateral private.session_people(u.student_id, u.tutor_id) p -- each person involved,
    left join public.notice_settings ns on ns.account_id = p.account_id -- with their settings, if any
  ), -- end of wanted
  rows as ( -- the reminders wanted:
    select w.account_id, w.id as session_id, 'reminder_first' as kind, -- a first reminder,
           w.starts_at - make_interval(hours => w.hours) as at, w -- at their chosen time before
    from wanted w -- for each person and session,
    -- Skip the first reminder when it would be within 2 hr of the final one.
    where w.hours > 3 -- (only when it's more than 3 hr before)
    union all -- and
    select w.account_id, w.id, 'reminder_final', -- a final reminder,
           w.starts_at - interval '1 hour', w -- 1 hr before
    from wanted w -- for each person and session
  ) -- end of rows
  insert into public.session_notices (account_id, session_id, kind, title, body, deliver_at) -- saves each reminder
  select r.account_id, r.session_id, r.kind, -- for that person, session and kind,
         case when r.kind = 'reminder_final' then 'Session in 1 hour' else 'Upcoming session' end, -- its title,
         left( -- its words (at most 1000 letters):
           case when (r.w).is_tutor -- for the tutor:
                then (r.w).subject || ' with ' || (r.w).student_name -- "Maths with Sam",
                else (r.w).student_name || ': ' || (r.w).subject || ' with ' || (r.w).tutor_name end -- for the family: "Sam: Maths with Jo",
           || ', ' || private.when_text((r.w).starts_at) || ', ' -- then when,
           || case (r.w).delivery when 'online' then 'online' when 'home' then 'at home' -- then where:
                   else coalesce((r.w).library_name, 'library') end -- online, at home, or the library
           || '.', 1000), -- (end of the words)
         case -- when it's delivered:
           when r.kind = 'reminder_final' -- a final reminder
                and private.outside_quiet_hours_for(r.account_id, r.at) > (r.w).starts_at - interval '15 minutes' -- that quiet hours would hold until too close to the start:
           then ((((r.w).starts_at at time zone private.account_timezone(r.account_id))::date - 1) -- the evening before, in their local time,
                 + (v_start - interval '30 minutes')) at time zone private.account_timezone(r.account_id) -- 30 min before quiet hours start
           else greatest(r.at, now()) -- otherwise its time (or now, if that's passed); the trigger applies quiet hours
         end -- end of the delivery time
  from rows r -- for each reminder wanted
  on conflict do nothing; -- each reminder only once
  get diagnostics v_count = row_count; -- counts how many were saved
  return v_count; -- hands back the count
end; -- finish
$$; -- end of the function
revoke all on function private.queue_reminders() from public; -- only run by the scheduled job

-- ---------------------------------------------------------------------------
-- 7. Billing's tutor emails (switched off since 2 Nov) use the same rule
-- ---------------------------------------------------------------------------

-- The billing module's email claim function is no longer called, but if
-- email is switched back on it should follow the tutor's own quiet hours.
-- Edited in place (only that one check changes), as earlier changes did.
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's full text
begin -- start
  if to_regprocedure('public.billing_tutor_notice_emails_claim(integer)') is null then -- the function isn't there:
    return; -- nothing to change
  end if; -- checked it exists
  v_def := pg_catalog.pg_get_functiondef('public.billing_tutor_notice_emails_claim(integer)'::regprocedure); -- its current text
  if strpos(v_def, 'private.outside_quiet_hours(n.created_at)') > 0 then -- still the old Adelaide-only check:
    v_def := replace(v_def, 'private.outside_quiet_hours(n.created_at)', 'private.outside_quiet_hours_for(n.tutor_id, n.created_at)'); -- use the tutor's own quiet hours
    execute v_def; -- saves the changed function
  end if; -- checked for the old text
end; -- finish
$$; -- end of the block
