-- Summary: a yearly reminder to enter the new award pay rates for each
-- financial year (Carla, 18 Nov 2026).
--
-- Carla: "Please add a reminder in the app to myself (or finance admin once
-- that is a position) to input the new pay rates for each new financial
-- year."
--
-- Background: the Fair Work Commission's Annual Wage Review usually
-- publishes new award minimums in early June. They start from the first
-- full pay period on or after 1 July.
--
-- How it works:
--   * From 1 June each year, if no award rates have been uploaded that start
--     on or after the coming 1 July, the new rates are "due".
--   * While they are due, the owner and every Finance admin get an app
--     notice on the first day, then again every 14 days, and the Billing
--     menu shows a to-do number. The Award rates card says what to do.
--   * Uploading the rates (Admin > Billing > Pay > Award rates) clears the
--     reminder. As before, the app then raises any staff rate below the new
--     minimum on the start date and adds a Xero to-do for each change, so
--     the rates are entered once in the app and copied into Xero from the
--     to-do list.
--
-- Billing module (billing_award_reminders is new; it reads
-- billing_award_rates). Uses the shared app notice helper. Edits
-- to_do_counts in place, so other changes to it stay.
-- Safe to run more than once. Run after 20261119910100_help_chat.sql.

-- ---------------------------------------------------------------------------
-- 1. When new rates are due
-- ---------------------------------------------------------------------------
-- The 1 July the rates are needed for, if they are due on a given day, or
-- nothing if they are not due. From 1 June to 31 December it looks at this
-- year's 1 July; from 1 January to 31 May, at last year's (so missing rates
-- keep being asked for).
create or replace function private.award_rates_due_on(p_day date) -- the day to check
returns date -- the 1 July the rates are needed for (or nothing)
language sql stable security definer -- reads the award rates
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  with fy as ( -- the financial year being checked:
    select make_date(case when extract(month from p_day) >= 6 then extract(year from p_day)::int else extract(year from p_day)::int - 1 end, 7, 1) as starts -- its 1 July
  ) -- end of the step
  select fy.starts from fy -- that 1 July,
  where not exists ( -- unless rates are already there
    select 1 from public.billing_award_rates ar -- an award rate
    where ar.effective_from >= fy.starts - 31 -- starting from about that 1 July (allowing a start up to a month early)
      and ar.effective_from < make_date(extract(year from fy.starts)::int + 1, 6, 1) -- and before the next year's reminders begin
  ) -- end of the check
$$; -- end of the function
revoke all on function private.award_rates_due_on(date) from public, anon, authenticated; -- only used inside the database

-- For the Billing page: the 1 July new rates are needed for, for the owner
-- and Finance admins only (nothing for anyone else, or when not due).
create or replace function public.award_rates_due() -- no inputs: uses today in Adelaide
returns date -- the 1 July the rates are needed for (or nothing)
language sql stable security definer -- reads the award rates after checking who is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select case when private.is_pay_admin() then private.award_rates_due_on(private.billing_today()) end -- only for the owner and Finance
$$; -- end of the function
revoke all on function public.award_rates_due() from public, anon; -- not for signed-out visitors
grant execute on function public.award_rates_due() to authenticated; -- signed-in people (checked inside)

-- ---------------------------------------------------------------------------
-- 2. App notices: on the first due day, then every 14 days
-- ---------------------------------------------------------------------------
create table if not exists public.billing_award_reminders ( -- one row per reminder sent
  fy_starts date not null, -- the 1 July the rates were needed for
  account_id uuid not null references public.accounts (id) on delete cascade, -- who was reminded
  sent_on date not null, -- the day the reminder was sent
  primary key (fy_starts, account_id, sent_on) -- each person once a day for each year
); -- (end of the table)
alter table public.billing_award_reminders enable row level security; -- access rules apply (no rule, so only the database's own functions can read it)
revoke all on public.billing_award_reminders from anon, authenticated; -- nobody signed in reads or writes it directly

-- Sends the reminders due today. Run every day. Returns how many were sent.
create or replace function private.queue_award_rate_reminders() -- no inputs: uses today in Adelaide
returns integer -- how many reminders were sent
language plpgsql security definer -- writes notices
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_today date := private.billing_today(); -- today in Adelaide
  v_fy date := private.award_rates_due_on(v_today); -- the 1 July the rates are needed for (or nothing)
  r record; -- one person at a time
  n integer := 0; -- how many were sent
begin -- start
  if v_fy is null then -- not due:
    return 0; -- nothing to send
  end if; -- end of the check
  for r in -- each owner and Finance admin not reminded in the last 14 days:
    select ar.account_id -- the person
    from public.account_roles ar -- with the admin role
    left join public.admin_profiles ap on ap.account_id = ar.account_id -- and their admin level
    where ar.role = 'admin' and coalesce(ap.level::text, 'owner') in ('owner', 'finance') -- owner or Finance
      and not exists ( -- and no recent reminder
        select 1 from public.billing_award_reminders b -- a reminder
        where b.fy_starts = v_fy and b.account_id = ar.account_id and b.sent_on > v_today - 14 -- for this year, to them, in the last 14 days
      ) -- end of the check
  loop -- for each one:
    insert into public.billing_award_reminders (fy_starts, account_id, sent_on) values (v_fy, r.account_id, v_today); -- notes the reminder
    perform private.add_notice( -- sends an app notice:
      r.account_id, null, null, 'staff_alert', -- to them, about no session or booking, as a staff alert
      'New award pay rates are due', -- the title
      'The award pay rates for the financial year starting ' || trim(to_char(v_fy, 'FMDD Month YYYY')) || ' have not been entered yet. ' -- which year
        || 'The Fair Work Commission usually publishes them in early June. Please upload them on Admin, Billing, Pay, Award rates. ' -- where to do it
        || 'The app then raises any staff rate below the new minimum and adds a Xero to-do for each change, so Xero can be updated to match.', -- what happens next
      now()); -- now
    n := n + 1; -- counts it
  end loop; -- end of the people
  return n; -- how many were sent
end; -- finish
$$; -- end of the function
revoke all on function private.queue_award_rate_reminders() from public; -- only run by the daily job

do $$ -- schedules the daily job (where the scheduler is available)
begin -- start
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then -- Supabase has the scheduler:
    execute 'create extension if not exists pg_cron with schema pg_catalog'; -- turns it on if needed
    execute $job$ select cron.schedule('clg-award-rate-reminders', '0 23 * * *', 'select private.queue_award_rate_reminders()') $job$; -- every day at 11pm UTC (about 9:30am in Adelaide; re-running replaces the same named job)
  end if; -- end of the check
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 3. The Billing to-do number counts the due rates as one job
-- ---------------------------------------------------------------------------
do $$ -- a small block of code
declare -- working values:
  v_def text; -- the to-do function's code
  v_old text := E'    n := (select count(*) from public.billing_hour_logs where status = ''submitted'');\n'; -- the pay count line
begin -- start
  if to_regprocedure('public.to_do_counts()') is null then -- the to-do numbers are not there
    return; -- nothing to do
  end if; -- end of the check
  v_def := replace(pg_get_functiondef('public.to_do_counts()'::regprocedure), chr(13), ''); -- reads the current code (without Windows line endings)
  if strpos(v_def, 'award_rates_due') > 0 then -- already added
    return; -- nothing to do
  end if; -- end of the check
  if strpos(v_def, v_old) = 0 then -- the place to add it has changed
    raise exception 'to_do_counts has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- end of the check
  v_def := replace(v_def, v_old, -- adds one job when new award rates are due:
    E'    n := (select count(*) from public.billing_hour_logs where status = ''submitted'')\n' -- the hours waiting for approval,
    || E'       + (case when public.award_rates_due() is not null then 1 else 0 end); -- plus one when new award rates are due (owner and Finance only)\n'); -- plus the award rates job
  execute v_def; -- saves the new code
end; -- finish
$$; -- end of the block
