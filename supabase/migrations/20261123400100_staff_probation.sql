-- Summary: staff probation tracking (module: staff_probation). Carla, 20 Nov 2026.
--
-- Carla's rules:
--   * Tutors finish probation at 3 months or 30 sessions, whichever comes
--     first.
--   * Admin staff (such as Emma's admin role) finish probation at 3 months or
--     30 hours, whichever comes first.
--   * The app reminds Carla when someone is due for their probation review.
--
-- How it works:
--   1. staff_probations holds one probation record for each person and each
--      kind of role (tutor or admin). Someone who is both a tutor and an
--      admin has two records, one for each role.
--   2. Progress is counted from the probation start date: completed sessions
--      for tutors, and approved admin hours (from My pay) for admin staff.
--   3. A probation is due on whichever day comes first: 3 months after the
--      start date, or the day the 30th session or 30th hour was reached. If
--      the owner extends a probation, it is due on the new date instead.
--   4. The daily run (/api/probation/cron, about 7:30am Adelaide time):
--        * sets up a probation record for any tutor or admin (not the owner)
--          whose start date on their pay details is in the last 3 months and
--          who has no record for that role yet;
--        * sends the owner an app notice, once, when a probation becomes
--          due (and again on an extended date).
--   5. The owner opens Staff probation in the side menu, sees everyone on
--      probation with their progress, and marks each review as passed,
--      extended (with a new date) or ended.
--
-- Who can do what: only the owner can see or change probation records,
-- because they are part of a staff member's employment record. Every change
-- needs two-step login (private.is_owner includes it) and is kept in the
-- activity log.
--
-- This module writes only its own table. It reads accounts, account_roles,
-- admin_profiles, sessions, billing_hour_logs and billing_staff_pay (reading
-- only), and sends app notices with the shared private.add_notice helper.
-- See docs/features/staff-probation.md. Safe to run more than once.
-- Run after 20261123300100_training_goals_study_plans.sql.

-- ---------------------------------------------------------------------------
-- 1. Probation records
-- ---------------------------------------------------------------------------
create table if not exists public.staff_probations ( -- one row per person and kind of role
  id uuid primary key default gen_random_uuid(), -- the record's id
  account_id uuid not null references public.accounts (id) on delete cascade, -- the staff member
  kind text not null check (kind in ('tutor', 'admin')), -- which role the probation is for
  started_on date not null, -- the day the probation started (usually their first day)
  months smallint not null default 3 check (months between 1 and 12), -- how many months the probation lasts (3, Carla's rule)
  target smallint not null default 30 check (target between 1 and 500), -- how many sessions (tutors) or hours (admin) end it early (30, Carla's rule)
  extended_to date, -- a new review date when the owner extends the probation (empty if not extended)
  status text not null default 'on_probation' check (status in ('on_probation', 'passed', 'ended')), -- where it is up to
  reminded_on date, -- the due date the owner was last reminded about (so each reminder is sent once)
  note text check (char_length(note) <= 1000), -- the owner's private note
  decided_at timestamptz, -- when the owner marked it passed or ended
  decided_by uuid references public.accounts (id) on delete set null, -- who marked it
  created_by uuid references public.accounts (id) on delete set null, -- who set it up (empty when the daily run did)
  created_at timestamptz not null default now(), -- when it was set up
  unique (account_id, kind) -- one record per person for each kind of role
); -- end of the table
alter table public.staff_probations enable row level security; -- access rules apply
revoke all on public.staff_probations from anon; -- signed-out visitors get nothing
revoke insert, update, delete, truncate on public.staff_probations from authenticated; -- nobody writes it directly: only through the functions below
grant select on public.staff_probations to authenticated; -- signed-in people may read it, but only the rule below lets anyone see rows

drop policy if exists "owner reads probation records" on public.staff_probations; -- replaces the rule if run again
create policy "owner reads probation records" on public.staff_probations -- the reading rule:
  for select to authenticated -- for signed-in people,
  using (private.is_owner()); -- only the owner (with two-step login) sees any rows

drop trigger if exists audit on public.staff_probations; -- replaces the record-keeper if run again
create trigger audit after insert or update or delete on public.staff_probations -- after any change,
  for each row execute function private.audit_change(); -- writes a line in the activity log

-- ---------------------------------------------------------------------------
-- 2. Progress and due dates
-- ---------------------------------------------------------------------------
-- How far a probation has got: completed sessions (tutors) or approved admin
-- hours (admin staff) since the start date, and the day the target was
-- reached (empty if not reached yet).
create or replace function private.staff_probation_progress(p_id uuid) -- which probation
returns table (done numeric, reached_on date) -- the count so far, and the day the target was reached
language plpgsql stable security definer -- reads sessions and hours
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  p public.staff_probations; -- the probation record
begin -- start
  select * into p from public.staff_probations where id = p_id; -- reads the record
  if not found then -- no such record
    return; -- gives back nothing
  end if; -- end of the check
  if p.kind = 'tutor' then -- a tutor: count completed sessions
    return query -- gives back:
      select count(*)::numeric, -- how many sessions were completed
             (array_agg(s.day order by s.day))[p.target] -- the day of the target-th session (empty if there are fewer)
      from ( -- the tutor's completed sessions since the start date:
        select (x.starts_at at time zone 'Australia/Adelaide')::date as day -- each session's day in Adelaide
        from public.sessions x -- from all sessions
        where x.tutor_id = p.account_id -- taught by this tutor
          and x.status = 'completed' -- that were completed
          and (x.starts_at at time zone 'Australia/Adelaide')::date >= p.started_on -- on or after the start date
      ) s; -- (end of the sessions)
  else -- admin staff: add up approved hours
    return query -- gives back:
      select round(coalesce(sum(h.minutes), 0) / 60.0, 2), -- the hours so far, to two decimal places
             min(h.work_date) filter (where h.running >= p.target * 60) -- the first day the running total reached the target
      from ( -- the person's approved hours since the start date, with a running total:
        select l.work_date, l.minutes, -- the day and the minutes
               sum(l.minutes) over (order by l.work_date, l.created_at) as running -- the total up to and including this entry
        from public.billing_hour_logs l -- from logged admin hours
        where l.account_id = p.account_id -- this person's
          and l.status = 'approved' -- approved entries only
          and l.work_date >= p.started_on -- on or after the start date
      ) h; -- (end of the hours)
  end if; -- end of the kinds
end; -- finish
$$; -- end of the function
revoke all on function private.staff_probation_progress(uuid) from public, anon, authenticated; -- only used inside the database

-- The day a probation is due for review: an extended date if there is one,
-- otherwise whichever comes first of the time limit and the day the target
-- was reached.
create or replace function private.staff_probation_due_on(p_id uuid) -- which probation
returns date -- the due date
language sql stable security definer -- reads the record and its progress
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select case -- works it out:
    when p.extended_to is not null then p.extended_to -- extended: the new date
    else least((p.started_on + make_interval(months => p.months))::date, pr.reached_on) -- otherwise the earlier of the time limit and the target day (least ignores an empty target day)
  end -- end of the choice
  from public.staff_probations p -- the record
  left join lateral private.staff_probation_progress(p.id) pr on true -- with its progress
  where p.id = p_id -- the one asked for
$$; -- end of the function
revoke all on function private.staff_probation_due_on(uuid) from public, anon, authenticated; -- only used inside the database

-- ---------------------------------------------------------------------------
-- 3. The list for the Staff probation page (owner only)
-- ---------------------------------------------------------------------------
drop function if exists public.staff_probation_list(); -- replaces the function if its columns changed
create or replace function public.staff_probation_list() -- no inputs
returns table ( -- one row per probation record:
  id uuid, -- the record's id
  account_id uuid, -- the staff member
  full_name text, -- their name
  kind text, -- tutor or admin
  started_on date, -- the start date
  months smallint, -- how many months it lasts
  target smallint, -- how many sessions or hours end it early
  done numeric, -- sessions or hours so far
  time_ends_on date, -- the day the months are up
  reached_on date, -- the day the target was reached (if it has been)
  extended_to date, -- an extended review date (if any)
  due_on date, -- the day it is due for review
  state text, -- on_track, due_soon, due, passed or ended
  note text, -- the owner's private note
  decided_at timestamptz -- when it was marked passed or ended
) -- end of the columns
language sql stable security definer -- reads sessions and hours after checking who is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select p.id, p.account_id, a.full_name, p.kind, p.started_on, p.months, p.target, -- the record's details and the person's name
         pr.done, -- progress so far
         (p.started_on + make_interval(months => p.months))::date, -- when the months are up
         pr.reached_on, -- when the target was reached
         p.extended_to, -- the extended date
         d.due_on, -- the due date
         case -- where it is up to:
           when p.status <> 'on_probation' then p.status -- passed or ended
           when d.due_on <= private.billing_today() then 'due' -- due now (or overdue)
           when d.due_on <= private.billing_today() + 14 then 'due_soon' -- due in the next 2 weeks
           else 'on_track' -- otherwise still on probation
         end, -- end of the choice
         p.note, p.decided_at -- the note and the decision time
  from public.staff_probations p -- every probation record
  join public.accounts a on a.id = p.account_id -- with the person's name
  cross join lateral private.staff_probation_progress(p.id) pr -- with progress
  cross join lateral (select private.staff_probation_due_on(p.id) as due_on) d -- with the due date
  where private.is_owner() -- only for the owner
  order by (p.status = 'on_probation') desc, d.due_on, a.full_name -- open ones first, soonest due first
$$; -- end of the function
revoke all on function public.staff_probation_list() from public, anon; -- not for signed-out visitors
grant execute on function public.staff_probation_list() to authenticated; -- signed-in people (checked inside)

-- How many probations are due for review now (for the side menu number).
create or replace function public.staff_probation_due_count() -- no inputs
returns int -- the number due
language sql stable security definer -- reads records after checking who is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select count(*)::int -- counts
  from public.staff_probations p -- probation records
  where private.is_owner() -- only for the owner
    and p.status = 'on_probation' -- still on probation
    and private.staff_probation_due_on(p.id) <= private.billing_today() -- and due now or overdue
$$; -- end of the function
revoke all on function public.staff_probation_due_count() from public, anon; -- not for signed-out visitors
grant execute on function public.staff_probation_due_count() to authenticated; -- signed-in people (checked inside)

-- ---------------------------------------------------------------------------
-- 4. Changes by the owner
-- ---------------------------------------------------------------------------
-- Starts a probation for a staff member. With no start date given, the
-- start date on their pay details is used, or today if there is none.
create or replace function public.staff_probation_start(p_account uuid, p_kind text, p_started_on date default null, p_note text default null) -- who, which role, start date and note
returns uuid -- the new record's id
language plpgsql security definer -- writes the record after checking who is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_start date; -- the start date to use
  v_id uuid; -- the new record's id
begin -- start
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can set up a probation' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if p_kind not in ('tutor', 'admin') then -- an unknown role
    raise exception 'Choose tutor or admin' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if not exists (select 1 from public.account_roles r where r.account_id = p_account and r.role::text = p_kind) then -- they do not have that role
    raise exception 'That person is not a % in the app', case when p_kind = 'tutor' then 'tutor' else 'staff admin' end using errcode = '22023'; -- plain message
  end if; -- end of the check
  if exists (select 1 from public.staff_probations p where p.account_id = p_account and p.kind = p_kind) then -- already has one
    raise exception 'That person already has a probation record for this role. Change the existing one instead.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_start := coalesce(p_started_on, -- the date given, or
    (select sp.started_on from public.billing_staff_pay sp where sp.account_id = p_account), -- the start date on their pay details, or
    private.billing_today()); -- today
  if v_start > private.billing_today() + 180 then -- more than 6 months away
    raise exception 'The start date is too far in the future' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.staff_probations (account_id, kind, started_on, note, created_by) -- saves the record
  values (p_account, p_kind, v_start, nullif(btrim(coalesce(p_note, '')), ''), auth.uid()) -- with the details and who set it up
  returning id into v_id; -- keeps the new id
  return v_id; -- hands it back
end; -- finish
$$; -- end of the function
revoke all on function public.staff_probation_start(uuid, text, date, text) from public, anon; -- not for signed-out visitors
grant execute on function public.staff_probation_start(uuid, text, date, text) to authenticated; -- signed-in people (checked inside)

-- Corrects a probation's start date (for example if it was set up wrongly).
create or replace function public.staff_probation_set_start(p_id uuid, p_started_on date) -- which record and the right start date
returns void -- nothing to hand back
language plpgsql security definer -- writes the record after checking who is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can change a probation' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if p_started_on is null or p_started_on > private.billing_today() + 180 then -- missing or too far ahead
    raise exception 'Choose a start date no more than 6 months from today' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.staff_probations set started_on = p_started_on, reminded_on = null -- saves the date, and allows a fresh reminder for the new due date
  where id = p_id; -- for this record
  if not found then -- no such record
    raise exception 'That probation record was not found' using errcode = '22023'; -- plain message
  end if; -- end of the check
end; -- finish
$$; -- end of the function
revoke all on function public.staff_probation_set_start(uuid, date) from public, anon; -- not for signed-out visitors
grant execute on function public.staff_probation_set_start(uuid, date) to authenticated; -- signed-in people (checked inside)

-- Records the owner's review: passed, extended to a new date, or ended.
-- "Extended" keeps them on probation and reminds the owner again on the
-- new date. A finished review can be changed back by extending it.
create or replace function public.staff_probation_decide(p_id uuid, p_outcome text, p_extend_to date default null, p_note text default null) -- which record, the outcome, a new date (for extended) and a note
returns void -- nothing to hand back
language plpgsql security definer -- writes the record after checking who is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can record a probation review' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if p_outcome not in ('passed', 'extended', 'ended') then -- an unknown outcome
    raise exception 'Choose passed, extended or ended' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_outcome = 'extended' and (p_extend_to is null or p_extend_to <= private.billing_today()) then -- extended without a future date
    raise exception 'Choose a new review date after today' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.staff_probations set -- saves the review:
    status = case when p_outcome = 'extended' then 'on_probation' else p_outcome end, -- still on probation when extended
    extended_to = case when p_outcome = 'extended' then p_extend_to else extended_to end, -- the new date when extended
    decided_at = case when p_outcome = 'extended' then null else now() end, -- when it was decided (not for an extension)
    decided_by = case when p_outcome = 'extended' then null else auth.uid() end, -- who decided (not for an extension)
    note = coalesce(nullif(btrim(coalesce(p_note, '')), ''), note) -- a new note, or keeps the old one
  where id = p_id; -- for this record
  if not found then -- no such record
    raise exception 'That probation record was not found' using errcode = '22023'; -- plain message
  end if; -- end of the check
end; -- finish
$$; -- end of the function
revoke all on function public.staff_probation_decide(uuid, text, date, text) from public, anon; -- not for signed-out visitors
grant execute on function public.staff_probation_decide(uuid, text, date, text) to authenticated; -- signed-in people (checked inside)

-- ---------------------------------------------------------------------------
-- 5. The daily run: set up new records and remind the owner
-- ---------------------------------------------------------------------------
-- Run each morning by /api/probation/cron (and allowed for the owner).
-- Returns how many reminders were sent.
create or replace function public.staff_probation_daily() -- no inputs: uses today's date
returns int -- how many reminders were sent
language plpgsql security definer -- writes records and notices; checks who is asking below
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_today date := private.billing_today(); -- today in Adelaide
  r record; -- one probation at a time
  n int := 0; -- how many reminders were sent
begin -- start
  if not (private.is_backend() or private.is_owner()) then -- only the daily run or the owner
    raise exception 'Only the owner can run probation reminders' using errcode = '42501'; -- plain message
  end if; -- end of the check

  -- First, set up records for new staff (start date on their pay details in
  -- the last 3 months) who do not have one yet for their role.
  insert into public.staff_probations (account_id, kind, started_on) -- new records:
  select sp.account_id, r2.role::text, sp.started_on -- the person, their role and their start date
  from public.billing_staff_pay sp -- from pay details
  join public.account_roles r2 on r2.account_id = sp.account_id and r2.role::text in ('tutor', 'admin') -- each tutor or admin role they have
  left join public.admin_profiles ap on ap.account_id = sp.account_id -- their admin level, if any
  where sp.started_on is not null -- a start date is saved
    and sp.started_on > (v_today - interval '3 months')::date -- within the last 3 months
    and sp.started_on <= v_today + 180 -- and not silly far ahead
    and not (r2.role::text = 'admin' and coalesce(ap.level::text, 'owner') = 'owner') -- never the owner
  on conflict (account_id, kind) do nothing; -- already has one: leave it

  -- Then remind the owner about each probation that is due and has not been
  -- reminded about for this due date.
  for r in -- each probation due now:
    select p.id, p.kind, p.started_on, a.full_name, -- the record, the role, the start date and the name
           private.staff_probation_due_on(p.id) as due_on, -- the due date
           pr.done, pr.reached_on, p.extended_to, p.months, p.target -- the progress and the rules
    from public.staff_probations p -- probation records
    join public.accounts a on a.id = p.account_id -- with the name
    cross join lateral private.staff_probation_progress(p.id) pr -- with progress
    where p.status = 'on_probation' -- still on probation
  loop -- for each one:
    continue when r.due_on > v_today; -- not due yet: skip it
    continue when exists (select 1 from public.staff_probations x where x.id = r.id and x.reminded_on is not distinct from r.due_on); -- already reminded for this date: skip it
    update public.staff_probations set reminded_on = r.due_on where id = r.id; -- notes the reminder, so it is sent once
    perform private.add_notice(o.account_id, null, null, 'staff_alert', -- an app notice to each owner:
      'Probation review due: ' || r.full_name, -- the title
      r.full_name || ' (' || case when r.kind = 'tutor' then 'tutor' else 'admin' end || ') is due for their probation review. ' -- who
        || case -- why it is due:
             when r.extended_to is not null then 'Their extended probation ends on ' || to_char(r.extended_to, 'FMDD Month YYYY') || '.' -- an extension
             when r.reached_on is not null and r.reached_on <= (r.started_on + make_interval(months => r.months))::date -- the target came first
               then 'They reached ' || r.target || case when r.kind = 'tutor' then ' sessions' else ' hours' end || ' on ' || to_char(r.reached_on, 'FMDD Month YYYY') || '.' -- sessions or hours
             else 'They reached ' || r.months || ' months on ' || to_char((r.started_on + make_interval(months => r.months))::date, 'FMDD Month YYYY') || '.' -- the months came first
           end -- end of why
        || ' Open Staff probation to mark it passed, extended or ended.', -- what to do
      now()) -- now
    from ( -- the people to tell:
      select ar.account_id from public.account_roles ar -- admins
      join public.admin_profiles ap on ap.account_id = ar.account_id -- with their admin level
      where ar.role = 'admin' and ap.level = 'owner' -- the owner
    ) o; -- (end of the people)
    n := n + 1; -- counts it
  end loop; -- end of the probations
  return n; -- tells the caller how many reminders were sent
end; -- finish
$$; -- end of the function
revoke all on function public.staff_probation_daily() from public, anon; -- not for signed-out visitors
grant execute on function public.staff_probation_daily() to authenticated, service_role; -- the owner (checked inside) and the daily run
