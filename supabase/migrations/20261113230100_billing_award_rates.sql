-- Billing part 11 (module: billing): yearly award rates, and the summary
-- and planning time label.
--
-- Carla (2026-11-12):
--   * A place to upload the award pay rates at the start of each financial
--     year, so every employee's pay rate is right and changes on time.
--   * The 15 minutes after each session is now 5 minutes session summary
--     plus 10 minutes planning the next session. The pay line says so.
--
-- How the yearly rates work:
--   * The owner or a Finance admin uploads the new award minimums with the
--     date they start (usually 1 July). Earlier years are kept.
--   * On the start date, anyone whose rate is below the new minimum for
--     their employment type is raised to it. Each change is logged.
--   * Pay for work done before the start date still uses the old rate,
--     even if it's worked out after the change.
--   * Rates already above the minimum aren't changed; the admin page lists
--     them so CLG can decide.
--
-- Safe to run more than once. Run after 20261112230100_billing_summary_pay.sql.

-- ---------------------------------------------------------------------------
-- Log of automatic rate changes
-- ---------------------------------------------------------------------------
create table if not exists public.billing_staff_rate_changes ( -- one row for each rate the app raised
  id uuid primary key default gen_random_uuid(), -- the change's id
  account_id uuid not null references public.accounts (id) on delete cascade, -- whose rate changed
  work_kind text not null check (work_kind in ('school', 'tertiary', 'admin')), -- which of their rates
  old_cents int not null check (old_cents >= 0), -- the rate before, in cents per hour
  new_cents int not null check (new_cents >= 0), -- the rate after, in cents per hour
  effective_from date not null, -- the day the new rate starts
  reason text not null check (char_length(reason) <= 300), -- why, for example the award it follows
  created_at timestamptz not null default now() -- when the app made the change
);
create index if not exists billing_staff_rate_changes_person on public.billing_staff_rate_changes (account_id, work_kind, effective_from); -- quick look-ups by person and date
alter table public.billing_staff_rate_changes enable row level security; -- access rules apply
revoke all on public.billing_staff_rate_changes from anon; -- signed-out visitors see nothing
revoke insert, update, delete on public.billing_staff_rate_changes from authenticated; -- only the app's functions write it
drop policy if exists "admins see rate changes, staff their own" on public.billing_staff_rate_changes; -- replace the rule if re-run
create policy "admins see rate changes, staff their own" on public.billing_staff_rate_changes -- who can read the log
  for select to authenticated using (private.is_admin() or private.is_finance_admin() or (account_id = auth.uid() and private.has_aal2())); -- admins and Finance see all; staff see their own (with two-step login)

-- Finance admins can read the award rates too (they upload them).
drop policy if exists "finance reads award rates" on public.billing_award_rates; -- replace the rule if re-run
create policy "finance reads award rates" on public.billing_award_rates -- an extra read rule
  for select to authenticated using (private.is_finance_admin()); -- for Finance admins

-- ---------------------------------------------------------------------------
-- A person's rate on a given day. If the app raised the rate after that
-- day, the rate before the change is used.
-- ---------------------------------------------------------------------------
create or replace function private.billing_pay_rate_on(p_account uuid, p_kind text, p_day date) -- whose rate, which rate, which day
returns int language sql stable security definer -- runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
  select coalesce( -- the first of these that has a value:
    (select c.old_cents from public.billing_staff_rate_changes c -- the rate before a later change
     where c.account_id = p_account and c.work_kind = p_kind and c.effective_from > p_day -- a change that started after this day
     order by c.effective_from limit 1), -- the earliest such change
    private.billing_pay_rate(p_account, p_kind) -- otherwise today's rate
  )
$$;
revoke all on function private.billing_pay_rate_on(uuid, text, date) from public, anon, authenticated; -- only used inside the database

-- Adds one pay line, now using the rate for the day the work was done.
-- Skips quietly if there's no rate yet or the line is already there.
create or replace function private.billing_add_pay_line( -- same inputs as before:
  p_account uuid, p_day date, p_kind text, p_work_kind text, p_session uuid, p_minutes int, p_note text -- who, day, kind, rate kind, session, minutes, note
)
returns void language plpgsql security definer -- runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_rate int := private.billing_pay_rate_on(p_account, p_work_kind, p_day); -- the rate on the day of the work
begin
  if v_rate is null or p_minutes <= 0 then -- no rate entered, or no time
    return; -- nothing to add
  end if;
  insert into public.billing_pay_lines ( -- add the line
    account_id, staff_name, work_date, kind, work_kind, session_id, minutes, rate_cents, amount_cents, under_award, note, created_by -- its details
  )
  select p_account, a.full_name, p_day, p_kind, p_work_kind, p_session, p_minutes, v_rate, -- who, when, what, and the rate
         round(v_rate * p_minutes / 60.0)::int, -- the pay, in cents
         private.billing_under_award(p_account, p_work_kind, v_rate, p_day), -- flag if under the award on that day
         left(p_note, 300), auth.uid() -- the note, and who worked it out
  from public.accounts a where a.id = p_account -- the person's name
  on conflict do nothing; -- already there: leave it
end;
$$;
revoke all on function private.billing_add_pay_line(uuid, date, text, text, uuid, int, text) from public; -- only used inside the database

-- ---------------------------------------------------------------------------
-- Raise rates that are below the award minimum in force today.
-- Run by the daily billing run, and straight after an upload.
-- Returns how many rates were raised.
-- ---------------------------------------------------------------------------
create or replace function public.billing_apply_award_rates() -- no inputs: uses today's date
returns int language plpgsql security definer -- runs with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_today date := private.billing_today(); -- today in Adelaide
  r record; -- one rate at a time
  n int := 0; -- how many were raised
begin
  if not (private.is_backend() or private.is_pay_admin()) then -- only the daily run, the owner or Finance
    raise exception 'Only the owner or a Finance admin can update pay rates' using errcode = '42501'; -- plain message
  end if;
  for r in -- each person's rate that is now under the award
    select sp.account_id, k.kind, k.cents, a.min_rate_cents, a.effective_from, a.award -- who, which rate, current and new amounts
    from public.billing_staff_pay sp -- everyone with pay details
    cross join lateral (values ('school', sp.school_rate_cents), ('tertiary', sp.tertiary_rate_cents), ('admin', sp.admin_rate_cents)) as k(kind, cents) -- their three rates, one row each
    join lateral ( -- the award minimum in force today for that work and employment type
      select ar.min_rate_cents, ar.effective_from, ar.award from public.billing_award_rates ar -- award rates
      where ar.work_kind = k.kind and ar.employment = sp.employment and ar.effective_from <= v_today -- matching, and already started
      order by ar.effective_from desc limit 1 -- the latest one
    ) a on true -- (only where an award rate exists)
    where k.cents is not null and k.cents < a.min_rate_cents -- has a rate, and it's under the minimum
  loop
    insert into public.billing_staff_rate_changes (account_id, work_kind, old_cents, new_cents, effective_from, reason) -- log the change
    values (r.account_id, r.kind, r.cents, r.min_rate_cents, r.effective_from, left('Raised to the award minimum: ' || r.award, 300)); -- old and new rate, start date and why
    update public.billing_staff_pay set -- raise the rate
      school_rate_cents = case when r.kind = 'school' then r.min_rate_cents else school_rate_cents end, -- the school rate, if that's the one
      tertiary_rate_cents = case when r.kind = 'tertiary' then r.min_rate_cents else tertiary_rate_cents end, -- the tertiary rate, if that's the one
      admin_rate_cents = case when r.kind = 'admin' then r.min_rate_cents else admin_rate_cents end -- the admin rate, if that's the one
    where account_id = r.account_id; -- for this person
    n := n + 1; -- count it
  end loop;
  return n; -- tell the caller how many were raised
end;
$$;

-- ---------------------------------------------------------------------------
-- Upload a year's award rates. p_rows is a list like
--   [{"work_kind":"school","employment":"casual","rate_cents":3300,"award":"..."}]
-- Replaces any rates already saved for that start date. If the date has
-- already come, rates are applied straight away.
-- Returns how many rates were raised.
-- ---------------------------------------------------------------------------
create or replace function public.billing_upload_award_rates(p_effective date, p_rows jsonb) -- start date and the rates
returns int language plpgsql security definer -- runs with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v jsonb; -- one row of the upload
  n int := 0; -- how many rows were saved
begin
  if not private.is_pay_admin() then -- only the owner or Finance
    raise exception 'Only the owner or a Finance admin can upload award rates' using errcode = '42501'; -- plain message
  end if;
  if p_effective is null then -- no start date
    raise exception 'Choose the date the new rates start (usually 1 July)' using errcode = '22023'; -- plain message
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then -- nothing to upload
    raise exception 'The file has no rates in it' using errcode = '22023'; -- plain message
  end if;
  delete from public.billing_award_rates where effective_from = p_effective; -- replace an earlier upload for the same date
  for v in select * from jsonb_array_elements(p_rows) loop -- each row of the upload
    if (v->>'work_kind') not in ('school', 'tertiary', 'admin') then -- unknown kind of work
      raise exception 'Work must be school, tertiary or admin (found "%")', coalesce(v->>'work_kind', '') using errcode = '22023'; -- plain message
    end if;
    if (v->>'employment') not in ('casual', 'part_time', 'full_time') then -- unknown employment type
      raise exception 'Employment must be casual, part_time or full_time (found "%")', coalesce(v->>'employment', '') using errcode = '22023'; -- plain message
    end if;
    if (v->>'rate_cents') is null or (v->>'rate_cents')::int < 100 or (v->>'rate_cents')::int > 100000 then -- missing or silly amount
      raise exception 'Each rate must be an hourly amount between $1 and $1000' using errcode = '22023'; -- plain message
    end if;
    insert into public.billing_award_rates (work_kind, employment, min_rate_cents, award, effective_from) -- save the rate
    values (v->>'work_kind', v->>'employment', (v->>'rate_cents')::int, -- work, employment and amount
            left(coalesce(nullif(trim(v->>'award'), ''), 'Award minimum'), 200), p_effective) -- the award's name (or a default) and the start date
    on conflict (work_kind, employment, effective_from) do update -- the same row twice in one file:
      set min_rate_cents = excluded.min_rate_cents, award = excluded.award; -- the later one wins
    n := n + 1; -- count it
  end loop;
  if p_effective <= private.billing_today() then -- the start date has already come
    return public.billing_apply_award_rates(); -- raise rates now
  end if;
  return 0; -- rates will be raised on the start date
end;
$$;

revoke all on function public.billing_apply_award_rates() from public, anon; -- not for signed-out visitors
revoke all on function public.billing_upload_award_rates(date, jsonb) from public, anon; -- not for signed-out visitors
grant execute on function public.billing_apply_award_rates() to authenticated, service_role; -- admins (checked inside) and the daily run
grant execute on function public.billing_upload_award_rates(date, jsonb) to authenticated; -- admins (checked inside)

-- ---------------------------------------------------------------------------
-- Session summary and planning time: same as before, with the new label.
-- (5 min summary + 10 min planning the next session = 15 min.)
-- ---------------------------------------------------------------------------
create or replace function public.billing_build_summary_pay(p_from date, p_to date) -- days to work out, first and last
returns int language plpgsql security definer -- runs with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_minutes int := private.billing_summary_minutes(); -- minutes per session (from the scheduling setting)
  r record; -- one session at a time
  n int := 0; -- how many lines are waiting
begin
  if not (private.is_backend() or private.is_pay_admin()) then -- only the daily run, the owner or Finance
    raise exception 'Only the owner or a Finance admin can work out pay' using errcode = '42501'; -- plain message for anyone else
  end if;
  if p_to < p_from or p_to - p_from > 62 then -- same limit as working out session pay
    raise exception 'Choose up to about two months at a time' using errcode = '22023'; -- plain message
  end if;
  delete from public.billing_pay_lines -- start fresh for this range
  where status = 'pending' and kind = 'summary' -- only summary lines not yet sent to Xero
    and work_date between p_from and p_to; -- only in the days asked for
  if v_minutes <= 0 then -- summary time switched off (set to 0)
    return 0; -- nothing to add
  end if;
  for r in -- each session in the range that earns this time
    select se.id, se.tutor_id, se.level_kind, -- the session, its tutor, and school or tertiary
           (se.starts_at at time zone 'Australia/Adelaide')::date as day, -- the day it happened (Adelaide time)
           left(to_char(se.starts_at at time zone 'Australia/Adelaide', 'FMHH12:MIam') || ' ' -- start time, for example 4:00pm
                || split_part(trim(st.full_name), ' ', 1) || ', ' || se.subject, 160) as label -- student's first name and subject
    from public.sessions se -- sessions belong to scheduling; billing only reads them
    join public.students st on st.id = se.student_id -- for the student's first name
    where (se.starts_at at time zone 'Australia/Adelaide')::date between p_from and p_to -- in the days asked for
      and se.status::text = 'completed' -- only sessions that went ahead (not cancelled or no-show)
      and se.worked_from is not null and se.worked_to is not null -- the tutor signed on and off
      and not exists ( -- not already paid
        select 1 from public.billing_pay_lines l -- an existing line
        where l.session_id = se.id and l.kind = 'summary' and l.status = 'sent' -- already sent to Xero
      )
  loop
    perform private.billing_add_pay_line(r.tutor_id, r.day, 'summary', r.level_kind, r.id, -- add the line at the tutor's rate for that day and level
      v_minutes, r.label || ' (session summary and next session planning)'); -- the minutes, and what they're for
  end loop;
  select count(*) into n from public.billing_pay_lines -- count what's waiting
  where status = 'pending' and kind = 'summary' and work_date between p_from and p_to; -- summary lines in the range not yet sent
  return n; -- tell the caller
end;
$$;
revoke all on function public.billing_build_summary_pay(date, date) from public, anon; -- not for signed-out visitors
grant execute on function public.billing_build_summary_pay(date, date) to authenticated, service_role; -- admins (checked inside) and the daily run
