-- Reports: Operations admins see the parts without money, and the owner
-- sets quarterly and yearly goals (Carla, 20 Nov 2026, for Emma's role).
--
-- Before: Reports were for the owner only, because they include pay and
-- profit.
-- Now:
--   * Operations admins (Emma from 2027) can open every report, but the
--     money part (income, wages, profit) is taken out before it leaves the
--     database. They cannot make reports, delete them or change settings.
--   * The owner sets goals for a quarter or a financial year (for example
--     "match within 14 days: 20 students" or "average wait: 10 days or
--     less"). The owner and Operations admins see each goal with how it is
--     going so far, for the monthly check-in Carla wants, and quarterly and
--     yearly reports show whether each goal was met.
--   * Goals only use the figures without money.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Goals: one target per figure, per quarter or financial year.
-- ---------------------------------------------------------------------------
create table if not exists public.report_goals ( -- one goal
  id uuid primary key default gen_random_uuid(), -- its id
  kind text not null check (kind in ('quarterly', 'yearly')), -- a quarter or a financial year
  period_start date not null, -- the first day of that quarter (1 Jan, 1 Apr, 1 Jul, 1 Oct) or financial year (1 Jul)
  metric text not null check (metric in ( -- which figure (the figures without money):
    'matched', -- students matched with a tutor (more is better)
    'matched_within_14_days', -- students matched within 2 weeks (more is better)
    'average_wait_days', -- average days waited for a tutor (fewer is better)
    'new_students', -- new students added (more is better)
    'booked', -- new students who booked (more is better)
    'booked_percent', -- share of new students who booked (more is better)
    'families_left', -- families who left (fewer is better)
    'waiting_now' -- students still waiting at the end (fewer is better)
  )), -- (end of the figures)
  target numeric(10, 1) not null check (target >= 0 and target <= 100000), -- the target number
  note text check (char_length(note) <= 500), -- why, or how it will be reached (optional)
  set_by uuid references public.accounts (id) on delete set null, -- who set it
  set_at timestamptz not null default now(), -- when it was set
  unique (kind, period_start, metric), -- one goal per figure per period
  check ((kind = 'yearly' and extract(month from period_start) = 7 and extract(day from period_start) = 1) -- a financial year starts 1 July,
      or (kind = 'quarterly' and extract(month from period_start) in (1, 4, 7, 10) and extract(day from period_start) = 1)) -- a quarter on the 1st of Jan, Apr, Jul or Oct
); -- end of report_goals
alter table public.report_goals enable row level security; -- turns on access rules for goals
drop policy if exists "owner and operations see goals" on public.report_goals; -- removes the old rule (so this file can run twice)
create policy "owner and operations see goals" on public.report_goals -- the owner and Operations admins can read goals
  for select to authenticated using (private.is_admin()); -- (is_admin means owner or Operations)
revoke insert, update, delete on public.report_goals from authenticated, anon; -- changes only go through the functions below

-- The owner sets (or changes) a goal.
create or replace function public.report_set_goal(p_kind text, p_period_start date, p_metric text, p_target numeric, p_note text default null) -- the period, figure, target and note
returns uuid language plpgsql security definer -- saves with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_id uuid; -- the goal's id
begin -- start
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can set goals' using errcode = '42501'; -- plain message for anyone else
  end if; -- end of the check
  if p_target is null or p_target < 0 then -- no target, or below zero
    raise exception 'Enter a target of 0 or more' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.report_goals (kind, period_start, metric, target, note, set_by) -- saves the goal
  values (p_kind, p_period_start, p_metric, p_target, nullif(left(trim(coalesce(p_note, '')), 500), ''), auth.uid()) -- with who set it
  on conflict (kind, period_start, metric) do update -- or changes the existing goal for that figure
    set target = excluded.target, note = excluded.note, set_by = excluded.set_by, set_at = now() -- to the new target
  returning id into v_id; -- keeps its id
  return v_id; -- hands it back
exception when check_violation then -- a wrong period or figure:
  raise exception 'Choose a quarter or financial year and one of the listed figures' using errcode = '22023'; -- plain message
end; -- end of the code
$$; -- end of the function
revoke all on function public.report_set_goal(text, date, text, numeric, text) from public, anon; -- not for signed-out visitors
grant execute on function public.report_set_goal(text, date, text, numeric, text) to authenticated; -- signed-in people can try (the owner check is inside)

-- The owner removes a goal.
create or replace function public.report_remove_goal(p_id uuid) -- the goal
returns void language plpgsql security definer -- deletes with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can remove goals' using errcode = '42501'; -- plain message for anyone else
  end if; -- end of the check
  delete from public.report_goals where id = p_id; -- removes it
end; -- end of the code
$$; -- end of the function
revoke all on function public.report_remove_goal(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.report_remove_goal(uuid) to authenticated; -- signed-in people can try (the owner check is inside)

-- ---------------------------------------------------------------------------
-- Reports for the owner and Operations admins. The owner gets everything;
-- Operations gets the figures with the money part taken out.
-- ---------------------------------------------------------------------------

-- The list of reports.
create or replace function public.report_list() -- no inputs
returns table (id uuid, kind text, period_start date, period_end date, made_at timestamptz, read_at timestamptz) -- one row per report
language sql stable security definer -- reads reports for them; checks who is asking inside
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the list
  select r.id, r.kind, r.period_start, r.period_end, r.made_at, -- each report's details,
         case when private.is_owner() then r.read_at end -- and whether the owner has opened it (only the owner's own "new" marker)
  from public.reports r -- from the saved reports
  where private.is_admin() -- only for the owner and Operations admins
  order by r.made_at desc -- newest first
  limit 200 -- the newest 200
$$; -- end of the function
revoke all on function public.report_list() from public, anon; -- not for signed-out visitors
grant execute on function public.report_list() to authenticated; -- signed-in people (the check is inside)

-- One report.
create or replace function public.report_get(p_id uuid) -- the report
returns table (id uuid, kind text, period_start date, period_end date, made_at timestamptz, read_at timestamptz, figures jsonb, has_money boolean) -- the report
language sql stable security definer -- reads the report for them; checks who is asking inside
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the report
  select r.id, r.kind, r.period_start, r.period_end, r.made_at, -- its details,
         case when private.is_owner() then r.read_at end, -- the owner's "opened" marker,
         case when private.is_owner() then r.figures else r.figures - 'money' end, -- every figure for the owner; no money part for Operations
         private.is_owner() -- and whether the money part is included
  from public.reports r -- from the saved reports
  where r.id = p_id and private.is_admin() -- this one, for the owner and Operations admins only
$$; -- end of the function
revoke all on function public.report_get(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.report_get(uuid) to authenticated; -- signed-in people (the check is inside)

-- How a quarter or financial year is going so far: the figures without
-- money, from its first day to today (or its last day, if it has ended).
create or replace function public.report_goal_progress(p_kind text, p_period_start date) -- the period
returns jsonb language plpgsql stable security definer -- works the figures out with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_end date; -- the period's last day
  v_today date := (now() at time zone 'Australia/Adelaide')::date; -- today in Adelaide
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only the owner and Operations admins can see goals' using errcode = '42501'; -- plain message for anyone else
  end if; -- end of the check
  if p_kind = 'quarterly' then -- a quarter:
    v_end := (p_period_start + interval '3 months - 1 day')::date; -- ends 3 months later
  elsif p_kind = 'yearly' then -- a financial year:
    v_end := (p_period_start + interval '1 year - 1 day')::date; -- ends a year later
  else -- anything else:
    raise exception 'Choose a quarter or a financial year' using errcode = '22023'; -- plain message
  end if; -- end of the period
  if p_period_start > v_today then -- not started yet:
    return null; -- nothing to show yet
  end if; -- end of the check
  return private.report_figures(p_period_start, least(v_end, v_today)) - 'money' -- the figures so far, without money
         || jsonb_build_object('period_end', v_end, 'elapsed_days', least(v_end, v_today) - p_period_start + 1, 'total_days', v_end - p_period_start + 1); -- and how far through the period it is
end; -- end of the code
$$; -- end of the function
revoke all on function public.report_goal_progress(text, date) from public, anon; -- not for signed-out visitors
grant execute on function public.report_goal_progress(text, date) to authenticated; -- signed-in people (the check is inside)
