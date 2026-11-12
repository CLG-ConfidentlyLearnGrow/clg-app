-- Reports (module: reports). Carla, 12 Nov 2026.
--
-- "It would be much better for the app to just have the ability to spit out
-- all of these numbers (auto send monthly, quarterly and yearly report and
-- has the ability to generate a report for specified dates)."
--
-- Each report covers a range of days (Adelaide dates) and holds:
--   1. Matching: how long students waited for a tutor, and who is waiting now.
--   2. Enquiries: new students added, and how many went on to book.
--   3. Tutor weeks: how full each tutor's week is.
--   4. Leaving: why families and tutors left.
--   5. Money: income, wages (plus super) and profit per tutoring hour.
--
-- Reports are made automatically each day the timer runs:
--   * monthly, on the 1st, for the month just finished;
--   * quarterly, for the quarter just finished (Jul-Sep, Oct-Dec, Jan-Mar,
--     Apr-Jun);
--   * yearly, for the financial year just finished (1 July to 30 June).
-- The owner can also make one for any dates. Only the owner sees reports,
-- because they include pay and profit (operations and finance don't).
--
-- This module only reads other modules' tables; it writes its own two
-- tables (reports and report_settings) only.
--
-- See docs/features/reports.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Settings: super and other costs, so profit is worked out properly.
-- ---------------------------------------------------------------------------
create table if not exists public.report_settings ( -- one row of report settings
  id boolean primary key default true check (id), -- only ever one row (id is always true)
  -- Super paid on top of wages (12% from 1 July 2025), as a percentage.
  super_percent numeric(5, 2) not null default 12 check (super_percent between 0 and 50), -- e.g. 12 means 12%
  -- Other running costs per month that aren't wages (rent, software,
  -- insurance, fees and so on), in cents. Spread evenly over the days in a
  -- report so profit "after all costs" can be shown. 0 = not set.
  monthly_other_costs_cents bigint not null default 0 check (monthly_other_costs_cents between 0 and 100000000), -- up to $1,000,000 a month
  -- Automatic reports are only made for periods ending on or after this
  -- day, so switching reports on doesn't make old, empty ones.
  automatic_from date not null default date '2026-11-01', -- reports start with November 2026
  updated_by uuid references public.accounts (id) on delete set null, -- who last changed the settings
  updated_at timestamptz not null default now() -- when they were last changed
); -- end of report_settings
insert into public.report_settings (id) values (true) on conflict (id) do nothing; -- makes the one settings row if it isn't there yet
alter table public.report_settings enable row level security; -- turns on access rules for the settings
drop policy if exists "owner sees report settings" on public.report_settings; -- removes the old rule (so this file can run twice)
create policy "owner sees report settings" on public.report_settings -- the owner can read the settings
  for select to authenticated using (private.is_owner()); -- only when signed in as the owner
revoke insert, update, delete on public.report_settings from authenticated, anon; -- changes only go through report_save_settings below

-- ---------------------------------------------------------------------------
-- Saved reports. The figures are saved when the report is made, so an old
-- report always shows what it showed then, even after records change.
-- ---------------------------------------------------------------------------
create table if not exists public.reports ( -- one saved report
  id uuid primary key default gen_random_uuid(), -- its id
  kind text not null check (kind in ('monthly', 'quarterly', 'yearly', 'custom')), -- automatic kind, or custom (dates the owner chose)
  period_start date not null, -- first day the report covers (Adelaide date)
  period_end date not null, -- last day the report covers (Adelaide date)
  figures jsonb not null, -- every number in the report
  made_by uuid references public.accounts (id) on delete set null, -- who made it (empty for automatic reports)
  made_at timestamptz not null default now(), -- when it was made
  read_at timestamptz, -- when the owner first opened it (empty = new)
  check (period_end >= period_start) -- the range must run forwards
); -- end of reports
-- Only one automatic report for each period (custom ones can repeat).
create unique index if not exists reports_one_per_period on public.reports (kind, period_start) where kind <> 'custom'; -- stops the daily timer making the same report twice
create index if not exists reports_made_at on public.reports (made_at desc); -- quick list of newest reports first
alter table public.reports enable row level security; -- turns on access rules for reports
drop policy if exists "owner sees reports" on public.reports; -- removes the old rule (so this file can run twice)
create policy "owner sees reports" on public.reports -- the owner can read reports
  for select to authenticated using (private.is_owner()); -- only when signed in as the owner
revoke insert, update, delete on public.reports from authenticated, anon; -- changes only go through the functions below

-- ---------------------------------------------------------------------------
-- Works out every figure for a range of days. Used inside the database
-- only (the public functions below check who is asking first).
-- ---------------------------------------------------------------------------
create or replace function private.report_figures(p_from date, p_to date) -- first and last day to report on
returns jsonb language plpgsql stable security definer -- reads other modules' tables with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_t0 timestamptz := p_from::timestamp at time zone 'Australia/Adelaide'; -- the very start of the first day, Adelaide time
  v_t1 timestamptz := (p_to + 1)::timestamp at time zone 'Australia/Adelaide'; -- the very start of the day after the last day
  v_days integer := p_to - p_from + 1; -- how many days the report covers
  v_weeks numeric := (p_to - p_from + 1) / 7.0; -- how many weeks that is (can be part weeks)
  v_today date := (now() at time zone 'Australia/Adelaide')::date; -- today in Adelaide
  v_set public.report_settings; -- the report settings
  v_matching jsonb; -- the matching figures
  v_waiting jsonb; -- who is waiting right now
  v_enquiries jsonb; -- the enquiry figures
  v_tutors jsonb; -- the tutor week figures
  v_leaving jsonb; -- the leaving figures
  v_money jsonb; -- the money figures
begin
  select * into v_set from public.report_settings where id; -- reads the settings row
  if v_set is null then -- no settings row (shouldn't happen)
    v_set := row(true, 12, 0, date '2026-11-01', null, now())::public.report_settings; -- use the defaults
  end if;

  -- 1. Matching: each student-subject that got a tutor in the period, and
  -- how many days they waited. A wait starts when the subject was asked for
  -- (or first waitlisted or requested, if earlier), or when their last tutor
  -- finished. Renewals and straight swaps from one booking to the next (less
  -- than two weeks apart) aren't new matches, so they're left out.
  with matched as ( -- each new match in the period
    select b.id, -- the booking
           extract(epoch from b.confirmed_at - greatest( -- seconds from the wait starting to the booking being confirmed
             least( -- the earliest sign they needed a tutor:
               coalesce((select min(ss.added_at) from public.student_subjects ss -- when the subject was added
                         where ss.student_id = b.student_id and lower(ss.subject) = lower(b.subject)), b.requested_at), -- (or the request, if no subject row)
               coalesce((select min(w.created_at) from public.waitlist w -- when they first joined the waitlist for it
                         where w.student_id = b.student_id and lower(w.subject) = lower(b.subject)
                           and w.created_at <= b.confirmed_at), b.requested_at), -- (only waits before this booking)
               b.requested_at), -- when this booking was asked for
             coalesce(prev.finished, '-infinity'::timestamptz) -- or when their last tutor finished, if that's later
           )) / 86400.0 as days -- turned into days
    from public.bookings b -- bookings belong to scheduling; reports only read them
    left join lateral ( -- the student's last confirmed booking in this subject before this one
      select max(coalesce(p.ended_at, (p.last_date + 1)::timestamp at time zone 'Australia/Adelaide')) as finished -- when it finished (or will)
      from public.bookings p -- earlier bookings
      where p.student_id = b.student_id and lower(p.subject) = lower(b.subject) -- same student and subject
        and p.id <> b.id and p.confirmed_at is not null and p.confirmed_at < b.confirmed_at -- confirmed before this one
    ) prev on true
    where b.confirmed_at >= v_t0 and b.confirmed_at < v_t1 -- confirmed during the period
      and b.renews_booking is null -- not a next-term renewal
      and (prev.finished is null or prev.finished < b.confirmed_at - interval '14 days') -- not a straight swap from another booking
  )
  select jsonb_build_object( -- the matching figures:
           'matched', count(*), -- how many got a tutor
           'average_days', round(avg(greatest(days, 0))::numeric, 1), -- average days waited
           'median_days', round((percentile_cont(0.5) within group (order by greatest(days, 0)))::numeric, 1), -- the middle wait
           'longest_days', round(max(greatest(days, 0))::numeric, 1), -- the longest wait
           'within_7_days', count(*) filter (where days <= 7), -- matched within a week
           'within_14_days', count(*) filter (where days <= 14), -- within two weeks
           'within_28_days', count(*) filter (where days <= 28)) -- within four weeks
    into v_matching
  from matched; -- from the new matches

  -- Who is waiting right now (the same list as the Matching tab), so the
  -- report shows the queue on the day it was made.
  select jsonb_build_object( -- the waiting figures:
           'as_at', v_today, -- the day counted
           'waiting', count(*), -- how many student-subjects are waiting
           'on_waitlist', count(*) filter (where r.stage = 'waitlist'), -- of those, on the waitlist
           'average_days', round(avg(v_today - (r.since at time zone 'Australia/Adelaide')::date)::numeric, 1), -- average days waiting so far
           'longest_days', max(v_today - (r.since at time zone 'Australia/Adelaide')::date)) -- longest wait so far
    into v_waiting
  from private.matching_rows() r -- the matching list
  where r.stage in ('needs_tutor', 'waitlist'); -- only those still with no tutor

  -- 2. Enquiries: students added in the period, and whether they went on to
  -- book. "Booked" means at least one booking was confirmed (by the day the
  -- report was made).
  with added as ( -- each student added in the period
    select s.id, -- the student
           (select min(b.confirmed_at) from public.bookings b where b.student_id = s.id and b.confirmed_at is not null) as first_booked, -- their first confirmed booking (if any)
           exists (select 1 from private.matching_rows() r where r.student_id = s.id -- whether they're still waiting for a tutor
                   and r.stage in ('needs_tutor', 'waitlist', 'tutor_to_confirm', 'assigned')) as waiting, -- (no tutor yet, or an offer open)
           s.created_at -- when they were added
    from public.students s -- students belong to the shared core; reports only read them
    where s.created_at >= v_t0 and s.created_at < v_t1 -- added during the period
  )
  select jsonb_build_object( -- the enquiry figures:
           'new_students', count(*), -- how many were added
           'booked', count(*) filter (where first_booked is not null), -- how many booked
           'still_waiting', count(*) filter (where first_booked is null and waiting), -- how many are still waiting
           'did_not_go_ahead', count(*) filter (where first_booked is null and not waiting), -- how many stopped without booking
           'booked_percent', case when count(*) = 0 then null -- share that booked (none if nobody was added)
                                  else round(100.0 * count(*) filter (where first_booked is not null) / count(*), 1) end,
           'average_days_to_book', round(avg(extract(epoch from first_booked - created_at) / 86400.0) -- average days from being added to booking
                                     filter (where first_booked is not null)::numeric, 1))
    into v_enquiries
  from added; -- from the students added

  -- 3. Tutor weeks: for each tutor, the hours they're booked each week now,
  -- the average hours of sessions each week in the period, and how full
  -- that is compared with the most hours they want (or, if not set, the
  -- hours they're available).
  with t as ( -- each tutor's numbers
    select tp.account_id, -- the tutor
           a.full_name, -- their name
           ws.max_weekly_hours::numeric as max_hours, -- the most hours a week they want (if set)
           (select round(coalesce(sum(extract(epoch from av.ends_at - av.starts_at)) / 3600.0, 0)::numeric, 1) -- hours a week they're available
              from public.tutor_availability av where av.tutor_id = tp.account_id) as available_hours,
           (select round(coalesce(sum(b.minutes), 0) / 60.0, 1) from public.bookings b -- hours a week booked right now
              where b.tutor_id = tp.account_id and b.status = 'confirmed' -- confirmed bookings
                and b.first_date <= v_today and b.last_date >= v_today) as booked_now, -- running today
           (select round(coalesce(sum(extract(epoch from se.ends_at - se.starts_at)), 0) / 3600.0 / v_weeks, 1) -- average hours a week of sessions in the period
              from public.sessions se where se.tutor_id = tp.account_id -- this tutor's sessions
                and se.starts_at >= v_t0 and se.starts_at < v_t1 -- in the period
                and se.status::text in ('scheduled', 'completed', 'no_show')) as period_weekly -- not cancelled (no-shows still took the time)
    from public.tutor_profiles tp -- every tutor
    join public.accounts a on a.id = tp.account_id -- for their name
    left join public.tutor_work_settings ws on ws.tutor_id = tp.account_id -- for their most hours
    where not exists (select 1 from public.leaving_records lr -- leaves out tutors who had left before the period started
                      where lr.who = 'tutor' and lr.tutor_id = tp.account_id and lr.left_on < p_from)
  )
  select coalesce(jsonb_agg(jsonb_build_object( -- one entry per tutor:
           'name', full_name, -- their name
           'max_hours', max_hours, -- most hours a week they want
           'available_hours', available_hours, -- hours a week they're available
           'booked_now', booked_now, -- hours a week booked now
           'period_weekly', period_weekly, -- average hours a week in the period
           'full_now_percent', case when coalesce(nullif(max_hours, 0), nullif(available_hours, 0)) is null then null -- how full now, against their limit
                                    else round(100 * booked_now / coalesce(nullif(max_hours, 0), nullif(available_hours, 0)), 0) end,
           'full_period_percent', case when coalesce(nullif(max_hours, 0), nullif(available_hours, 0)) is null then null -- how full in the period, against their limit
                                       else round(100 * period_weekly / coalesce(nullif(max_hours, 0), nullif(available_hours, 0)), 0) end,
           'room_hours', greatest(coalesce(nullif(max_hours, 0), available_hours) - booked_now, 0)) -- hours a week still free now
         order by booked_now desc, full_name), '[]'::jsonb) -- fullest first
    into v_tutors
  from t; -- from the tutors

  -- 4. Leaving: how many families and tutors left in the period, by reason.
  select jsonb_build_object( -- the leaving figures:
           'families', count(*) filter (where who = 'family'), -- families who left
           'tutors', count(*) filter (where who = 'tutor'), -- tutors who left
           'families_happy', count(*) filter (where who = 'family' and left_happy), -- families who left happy
           'reasons', coalesce((select jsonb_agg(jsonb_build_object('who', x.who, 'reason', x.reason, 'count', x.n) -- each reason and how many
                                                 order by x.who, x.n desc, x.reason) -- most common first
                                from (select lr.who, lr.reason, count(*) as n from public.leaving_records lr -- counts each reason
                                      where lr.left_on between p_from and p_to group by lr.who, lr.reason) x), '[]'::jsonb)) -- in the period
    into v_leaving
  from public.leaving_records -- the leaving records
  where left_on between p_from and p_to; -- in the period

  -- 5. Money. Income is the invoice lines dated in the period (voided
  -- invoices left out; amounts before GST), less bank-debit discounts on
  -- invoices whose first session is in the period. Wages are the pay lines
  -- dated in the period, plus super. Tutoring wages are matched to school or
  -- tertiary; admin wages are an overhead. Other costs come from settings.
  with inc as ( -- income by level
    select coalesce(se.level_kind, 'other') as kind, -- school, tertiary, or other (no session, e.g. a one-off item)
           sum(l.billed_minutes) as minutes, -- minutes billed
           sum(l.amount_cents) as cents -- income before GST
    from public.billing_invoice_lines l -- invoice lines belong to billing; reports only read them
    join public.billing_invoices i on i.id = l.invoice_id -- for the invoice's status
    left join public.sessions se on se.id = l.session_id -- for school or tertiary
    where l.active and i.status <> 'void' -- leaves out voided lines and invoices
      and l.line_date between p_from and p_to -- dated in the period
    group by 1 -- one row per level
  ), pay as ( -- wages by kind of work
    select pl.work_kind as kind, -- school, tertiary or admin
           sum(pl.amount_cents) as cents, -- wages before super
           sum(pl.minutes) as minutes -- minutes paid
    from public.billing_pay_lines pl -- pay lines belong to billing; reports only read them
    where pl.work_date between p_from and p_to -- worked in the period
    group by 1 -- one row per kind
  ), lv as ( -- the numbers for school and tertiary side by side
    select k.kind, -- the level
           coalesce(inc.minutes, 0) as minutes, -- minutes billed
           coalesce(inc.cents, 0) as income, -- income
           round(coalesce(pay.cents, 0) * (1 + v_set.super_percent / 100.0)) as wages -- tutor wages plus super
    from (values ('school'), ('tertiary')) k(kind) -- both levels, even if one has nothing
    left join inc on inc.kind = k.kind -- their income
    left join pay on pay.kind = k.kind -- their wages
  ), tot as ( -- the totals
    select (select coalesce(sum(cents), 0) from inc) as income, -- all income
           (select coalesce(sum(minutes), 0) from inc where kind in ('school', 'tertiary')) as tutoring_minutes, -- all tutoring minutes billed
           (select coalesce(sum(i.discount_cents), 0) from public.billing_invoices i -- bank-debit discounts given
              where i.status <> 'void' and i.first_session_on between p_from and p_to) as discounts, -- on invoices starting in the period
           (select round(coalesce(sum(cents), 0) * (1 + v_set.super_percent / 100.0)) from pay where kind in ('school', 'tertiary')) as tutor_wages, -- all tutor wages plus super
           (select round(coalesce(sum(cents), 0) * (1 + v_set.super_percent / 100.0)) from pay where kind = 'admin') as admin_wages, -- admin wages plus super
           round(v_set.monthly_other_costs_cents * 12.0 / 365.25 * v_days) as other_costs -- other costs spread over the days
  )
  select jsonb_build_object( -- the money figures:
           'super_percent', v_set.super_percent, -- super used
           'levels', (select jsonb_agg(jsonb_build_object( -- school and tertiary:
                        'kind', lv.kind, -- the level
                        'hours', round(lv.minutes / 60.0, 1), -- hours billed
                        'income_cents', lv.income, -- income
                        'wages_cents', lv.wages, -- tutor wages plus super
                        'profit_cents', lv.income - lv.wages, -- what's left after tutor wages
                        'profit_per_hour_cents', case when lv.minutes = 0 then null -- what's left per hour billed
                                                      else round((lv.income - lv.wages) * 60.0 / lv.minutes) end)
                      order by lv.kind) from lv), -- school first
           'other_income_cents', (select coalesce(sum(cents), 0) from inc where kind = 'other'), -- income not from sessions
           'income_cents', tot.income, -- all income
           'discounts_cents', tot.discounts, -- bank-debit discounts
           'tutor_wages_cents', tot.tutor_wages, -- tutor wages plus super
           'admin_wages_cents', tot.admin_wages, -- admin wages plus super
           'other_costs_cents', tot.other_costs, -- other costs
           'other_costs_set', v_set.monthly_other_costs_cents > 0, -- whether other costs have been entered
           'tutoring_hours', round(tot.tutoring_minutes / 60.0, 1), -- tutoring hours billed
           'profit_after_tutors_cents', tot.income - tot.discounts - tot.tutor_wages, -- left after tutor wages
           'profit_after_all_cents', tot.income - tot.discounts - tot.tutor_wages - tot.admin_wages - tot.other_costs, -- left after all costs
           'profit_per_hour_after_tutors_cents', case when tot.tutoring_minutes = 0 then null -- per tutoring hour, after tutor wages
                                                      else round((tot.income - tot.discounts - tot.tutor_wages) * 60.0 / tot.tutoring_minutes) end,
           'profit_per_hour_after_all_cents', case when tot.tutoring_minutes = 0 then null -- per tutoring hour, after all costs
                                                   else round((tot.income - tot.discounts - tot.tutor_wages - tot.admin_wages - tot.other_costs) * 60.0 / tot.tutoring_minutes) end,
           -- Sessions that went ahead but have no pay worked out yet: their
           -- wages are missing, so profit looks higher until pay is done.
           'sessions_without_pay', (select count(*) from public.sessions se -- sessions in the period
                                    where se.starts_at >= v_t0 and se.starts_at < v_t1 -- in the period
                                      and se.status::text = 'completed' -- that went ahead
                                      and not exists (select 1 from public.billing_pay_lines pl where pl.session_id = se.id)), -- with no pay line yet
           -- Sessions that went ahead but aren't on an invoice yet: their
           -- income is missing, so profit looks lower until they're billed.
           'sessions_not_billed', (select count(*) from public.sessions se -- sessions in the period
                                   where se.starts_at >= v_t0 and se.starts_at < v_t1 -- in the period
                                     and se.status::text = 'completed' -- that went ahead
                                     and not exists (select 1 from public.billing_invoice_lines l where l.session_id = se.id and l.active))) -- with no invoice line
    into v_money
  from tot; -- from the totals

  return jsonb_build_object( -- everything together:
    'from', p_from, -- first day
    'to', p_to, -- last day
    'days', v_days, -- number of days
    'matching', v_matching, -- matching
    'waiting_now', v_waiting, -- waiting now
    'enquiries', v_enquiries, -- enquiries
    'tutors', v_tutors, -- tutor weeks
    'leaving', v_leaving, -- leaving
    'money', v_money); -- money
end;
$$;
revoke all on function private.report_figures(date, date) from public, anon, authenticated; -- only used inside the database

-- ---------------------------------------------------------------------------
-- The owner makes a report for any dates. Returns the new report's id.
-- ---------------------------------------------------------------------------
create or replace function public.report_make(p_from date, p_to date) -- first and last day
returns uuid language plpgsql security definer -- saves with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_id uuid; -- the new report's id
begin
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can make reports' using errcode = '42501'; -- plain message for anyone else
  end if;
  if p_from is null or p_to is null or p_to < p_from then -- dates missing or backwards
    raise exception 'Choose a start date on or before the end date' using errcode = '22023'; -- plain message
  end if;
  if p_to - p_from > 366 * 5 then -- more than about five years
    raise exception 'Choose up to five years at a time' using errcode = '22023'; -- plain message
  end if;
  insert into public.reports (kind, period_start, period_end, figures, made_by, read_at) -- saves the report
  values ('custom', p_from, p_to, private.report_figures(p_from, p_to), auth.uid(), now()) -- already read, since the owner asked for it
  returning id into v_id; -- keeps its id
  return v_id; -- hands back the id
end;
$$;
revoke all on function public.report_make(date, date) from public, anon; -- not for signed-out visitors
grant execute on function public.report_make(date, date) to authenticated; -- signed-in people can try (the owner check is inside)

-- ---------------------------------------------------------------------------
-- The periods an automatic report is due for on a given day: the month,
-- quarter and financial year that most recently finished.
-- ---------------------------------------------------------------------------
create or replace function private.report_due_periods(p_today date) -- the day to check
returns table (kind text, period_start date, period_end date) -- each due period
language sql immutable -- the same day always gives the same answer
set search_path = '' -- no hidden schema lookups (safety)
as $$
  select 'monthly', -- last month:
         (date_trunc('month', p_today) - interval '1 month')::date, -- its first day
         (date_trunc('month', p_today) - interval '1 day')::date -- its last day
  union all
  select 'quarterly', -- last quarter (calendar quarters line up with the financial year's quarters):
         (date_trunc('quarter', p_today) - interval '3 months')::date, -- its first day
         (date_trunc('quarter', p_today) - interval '1 day')::date -- its last day
  union all
  select 'yearly', -- last financial year (1 July to 30 June):
         make_date(extract(year from p_today - interval '6 months')::int - 1, 7, 1), -- its first day
         make_date(extract(year from p_today - interval '6 months')::int, 6, 30) -- its last day
$$;
revoke all on function private.report_due_periods(date) from public, anon, authenticated; -- only used inside the database

-- ---------------------------------------------------------------------------
-- The daily timer: makes any monthly, quarterly or yearly report that's due
-- and not yet made. Running it again the same day does nothing. Returns how
-- many reports were made.
-- ---------------------------------------------------------------------------
create or replace function public.reports_make_due() -- no settings needed
returns integer language plpgsql security definer -- saves with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_today date := (now() at time zone 'Australia/Adelaide')::date; -- today in Adelaide
  v_from date; -- the first period end that counts
  r record; -- one due period at a time
  n integer := 0; -- how many were made
begin
  if not (private.is_backend() or private.is_owner()) then -- only the daily timer or the owner
    raise exception 'Only the owner can make reports' using errcode = '42501'; -- plain message for anyone else
  end if;
  select automatic_from into v_from from public.report_settings where id; -- the first day automatic reports cover
  for r in select * from private.report_due_periods(v_today) d -- each due period
           where d.period_end >= coalesce(v_from, date '2026-11-01') -- only periods ending after reports started
             and not exists (select 1 from public.reports x where x.kind = d.kind and x.period_start = d.period_start) -- and not made yet
  loop
    insert into public.reports (kind, period_start, period_end, figures) -- saves the report
    values (r.kind, r.period_start, r.period_end, private.report_figures(r.period_start, r.period_end)) -- with its figures
    on conflict do nothing; -- another run beat this one to it: fine
    if found then n := n + 1; end if; -- counts it if it was saved
  end loop;
  return n; -- hands back how many were made
end;
$$;
revoke all on function public.reports_make_due() from public, anon; -- not for signed-out visitors
grant execute on function public.reports_make_due() to authenticated, service_role; -- the timer (service role) and the owner (checked inside)

-- ---------------------------------------------------------------------------
-- The owner opens a report: marks it read, so it no longer counts as new.
-- ---------------------------------------------------------------------------
create or replace function public.report_mark_read(p_id uuid) -- the report
returns void language plpgsql security definer -- saves with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can see reports' using errcode = '42501'; -- plain message for anyone else
  end if;
  update public.reports set read_at = now() where id = p_id and read_at is null; -- marks it read (once)
end;
$$;
revoke all on function public.report_mark_read(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.report_mark_read(uuid) to authenticated; -- signed-in people can try (the owner check is inside)

-- ---------------------------------------------------------------------------
-- The owner deletes a report they made for their own dates. Automatic
-- reports stay, so the monthly, quarterly and yearly history is complete.
-- ---------------------------------------------------------------------------
create or replace function public.report_delete(p_id uuid) -- the report
returns void language plpgsql security definer -- deletes with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can delete reports' using errcode = '42501'; -- plain message for anyone else
  end if;
  delete from public.reports where id = p_id and kind = 'custom'; -- deletes it, only if it's a custom report
  if not found then -- nothing deleted
    raise exception 'Only reports made for your own dates can be deleted' using errcode = '22023'; -- plain message
  end if;
end;
$$;
revoke all on function public.report_delete(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.report_delete(uuid) to authenticated; -- signed-in people can try (the owner check is inside)

-- ---------------------------------------------------------------------------
-- The owner changes the report settings (super and other monthly costs).
-- ---------------------------------------------------------------------------
create or replace function public.report_save_settings(p_super_percent numeric, p_monthly_other_costs_cents bigint) -- super % and other costs per month
returns void language plpgsql security definer -- saves with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can change report settings' using errcode = '42501'; -- plain message for anyone else
  end if;
  if p_super_percent is null or p_super_percent < 0 or p_super_percent > 50 then -- super out of range
    raise exception 'Super must be between 0%% and 50%%' using errcode = '22023'; -- plain message
  end if;
  if p_monthly_other_costs_cents is null or p_monthly_other_costs_cents < 0 or p_monthly_other_costs_cents > 100000000 then -- costs out of range
    raise exception 'Other costs must be between $0 and $1,000,000 a month' using errcode = '22023'; -- plain message
  end if;
  update public.report_settings -- saves the settings
  set super_percent = p_super_percent, -- the super
      monthly_other_costs_cents = p_monthly_other_costs_cents, -- the other costs
      updated_by = auth.uid(), -- who changed them
      updated_at = now() -- when
  where id; -- the one settings row
end;
$$;
revoke all on function public.report_save_settings(numeric, bigint) from public, anon; -- not for signed-out visitors
grant execute on function public.report_save_settings(numeric, bigint) to authenticated; -- signed-in people can try (the owner check is inside)

-- ---------------------------------------------------------------------------
-- To-do numbers: the owner sees "Reports 1" on the menu when a new report
-- is ready. to_do_counts is edited in place, so other changes to it stay.
-- ---------------------------------------------------------------------------
do $$
declare
  v_def text; -- the to-do function's code
begin
  v_def := pg_get_functiondef('public.to_do_counts()'::regprocedure); -- reads the current code
  v_def := replace(v_def, chr(13), ''); -- line endings from pasting on Windows
  if strpos(v_def, 'section := ''reports''') > 0 then -- already added
    return; -- nothing to do
  end if;
  if strpos(v_def, E'  -- Billing (owner, operations and finance).\n') = 0 then -- the place to add it has changed
    raise exception 'to_do_counts has changed since this update was written. Ask for an updated file.'; -- plain message
  end if;
  v_def := replace(v_def, -- adds the reports number just before the billing numbers
    E'  -- Billing (owner, operations and finance).\n',
    E'  -- Reports (owner only): new reports not yet opened.\n'
    || E'  if private.is_owner() then\n'
    || E'    area := ''admin''; section := ''reports'';\n'
    || E'    n := (select count(*) from public.reports where read_at is null);\n'
    || E'    return next;\n'
    || E'  end if;\n\n'
    || E'  -- Billing (owner, operations and finance).\n');
  execute v_def; -- saves the new code
end;
$$;
