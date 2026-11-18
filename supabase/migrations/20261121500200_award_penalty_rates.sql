-- Summary: award penalty rates for school tutoring at evenings, early
-- mornings, weekends and public holidays (Carla, 18 Nov 2026).
--
-- Carla asked for the Miscellaneous Award penalty rates to be checked and
-- built. The Miscellaneous Award 2020 (MA000104) clause 20 sets these, as a
-- percentage of the base (full-time) hourly rate for the person's level:
--
--   Time worked                                  Full/part-time   Casual
--   Monday to Friday, 7am to 7pm                 100%             125%
--   Monday to Friday, before 7am or after 7pm    120%             145%
--   Saturday (all day)                           120%             145%
--   Sunday (all day)                             150%             175%
--   Public holiday (all day)                     250%             250%
--
-- The casual figures already include the 25% casual loading, so nothing is
-- added on top. The Fair Work pay guide (FY27) gives the same dollar figures.
--
-- CLG's casual contract says: "Where an award sets a higher rate for the
-- time you work ... CLG pays that higher rate." So:
--   * For each school tutoring session, the app splits the time worked into
--     those bands (Adelaide time, using the public holidays list for the
--     learner's state).
--   * For each band, if the tutor's own hourly rate is below the award rate
--     for that band, the difference is paid as a "Penalty rate top-up" line.
--     A tutor whose rate is at or above the award rate gets no top-up.
--   * Top-up lines carry no minutes (the session line already counts the
--     time), so hours totals do not double.
--   * When timesheets go to Xero, the top-ups are not sent as hours. Each
--     person's top-ups become one Xero to-do with the dollar amount, so an
--     admin adds it to the pay run. Nothing in Xero is changed automatically.
--
-- Not covered yet: tertiary tutoring (Post-Secondary Award) and office admin
-- (Clerks Award) penalty rates, and the 15 minutes of summary and planning
-- time (the tutor chooses when to do it).
--
-- Billing module: billing tables and functions only; reads sessions,
-- students and public holidays. Edits billing_build_pay in place, so other
-- changes to it stay.
-- Safe to run more than once. Run after 20261121500100_award_levels_three_months.sql.

-- ---------------------------------------------------------------------------
-- 1. The penalty percentages
-- ---------------------------------------------------------------------------
create table if not exists public.billing_award_penalties ( -- one row per band of time
  work_kind text not null check (work_kind in ('school', 'tertiary', 'admin')), -- which kind of work
  employment_group text not null check (employment_group in ('casual', 'permanent')), -- casual, or part-time and full-time together
  band text not null check (band in ('ordinary', 'outside_span', 'saturday', 'sunday', 'public_holiday')), -- the time band
  percent numeric(5, 1) not null check (percent between 100 and 400), -- the percentage of the base hourly rate
  award text not null check (char_length(award) <= 200), -- where the figure comes from
  primary key (work_kind, employment_group, band) -- one figure for each
); -- end of the table
alter table public.billing_award_penalties enable row level security; -- access rules apply
revoke all on public.billing_award_penalties from anon; -- signed-out visitors see nothing
revoke insert, update, delete on public.billing_award_penalties from authenticated; -- only changed by an update file
drop policy if exists "admins read award penalties" on public.billing_award_penalties; -- replaces the rule if re-run
create policy "admins read award penalties" on public.billing_award_penalties -- who can read them
  for select to authenticated using (private.is_admin() or private.is_pay_admin()); -- admins and Finance

insert into public.billing_award_penalties (work_kind, employment_group, band, percent, award) values -- the Miscellaneous Award figures:
  ('school', 'casual', 'ordinary', 125, 'Miscellaneous Award MA000104 cl 11.1 (casual loading)'), -- casual, ordinary hours
  ('school', 'casual', 'outside_span', 145, 'Miscellaneous Award MA000104 cl 20'), -- casual, weekday before 7am or after 7pm
  ('school', 'casual', 'saturday', 145, 'Miscellaneous Award MA000104 cl 20'), -- casual, Saturday
  ('school', 'casual', 'sunday', 175, 'Miscellaneous Award MA000104 cl 20'), -- casual, Sunday
  ('school', 'casual', 'public_holiday', 250, 'Miscellaneous Award MA000104 cl 20'), -- casual, public holiday
  ('school', 'permanent', 'ordinary', 100, 'Miscellaneous Award MA000104 cl 15'), -- part-time or full-time, ordinary hours
  ('school', 'permanent', 'outside_span', 120, 'Miscellaneous Award MA000104 cl 20'), -- part-time or full-time, weekday before 7am or after 7pm
  ('school', 'permanent', 'saturday', 120, 'Miscellaneous Award MA000104 cl 20'), -- part-time or full-time, Saturday
  ('school', 'permanent', 'sunday', 150, 'Miscellaneous Award MA000104 cl 20'), -- part-time or full-time, Sunday
  ('school', 'permanent', 'public_holiday', 250, 'Miscellaneous Award MA000104 cl 20') -- part-time or full-time, public holiday
on conflict do nothing; -- already there: leave it

-- ---------------------------------------------------------------------------
-- 2. Pay lines: a new "penalty" kind, which carries no minutes
-- ---------------------------------------------------------------------------
alter table public.billing_pay_lines drop constraint if exists billing_pay_lines_kind_check; -- removes the old list of kinds
alter table public.billing_pay_lines add constraint billing_pay_lines_kind_check -- adds the list back with "penalty" included
  check (kind in ('session', 'late_cancel', 'min_topup', 'admin', 'tutoring_work', 'guaranteed', 'summary', 'training', 'penalty')); -- every kind of pay line
alter table public.billing_pay_lines drop constraint if exists billing_pay_lines_minutes_check; -- removes the old "more than 0 minutes" rule
alter table public.billing_pay_lines add constraint billing_pay_lines_minutes_check -- adds it back:
  check (minutes > 0 or (kind = 'penalty' and minutes = 0)); -- every line has minutes, except penalty top-ups (the session line already has them)

-- Xero to-dos: a new kind for penalty top-ups to add to a pay run.
alter table public.billing_xero_tasks drop constraint if exists billing_xero_tasks_kind_check; -- removes the old list of kinds
alter table public.billing_xero_tasks add constraint billing_xero_tasks_kind_check -- adds the list back with the new kind
  check (kind in ('pay_details', 'left', 'penalty_pay')); -- pay details changed, left CLG, or penalty top-ups to pay

-- ---------------------------------------------------------------------------
-- 3. Splitting a stretch of work into the award's time bands
-- ---------------------------------------------------------------------------
-- Counts the minutes from p_from to p_to in each band, in Adelaide time,
-- using the public holidays list for the given state.
create or replace function private.billing_time_bands(p_from timestamptz, p_to timestamptz, p_state public.au_state) -- start, end, and the state for public holidays
returns table (band text, minutes int) -- each band and its minutes
language sql stable security definer -- reads public holidays
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select b.band, count(*)::int -- each band and how many minutes fall in it
  from ( -- one row per minute worked:
    select case -- which band this minute is in:
      when exists (select 1 from public.public_holidays h where h.state = p_state and h.holiday_on = (m at time zone 'Australia/Adelaide')::date) then 'public_holiday' -- a public holiday
      when extract(isodow from m at time zone 'Australia/Adelaide') = 7 then 'sunday' -- a Sunday
      when extract(isodow from m at time zone 'Australia/Adelaide') = 6 then 'saturday' -- a Saturday
      when (m at time zone 'Australia/Adelaide')::time < time '07:00' or (m at time zone 'Australia/Adelaide')::time >= time '19:00' then 'outside_span' -- a weekday before 7am or from 7pm
      else 'ordinary' -- a weekday between 7am and 7pm
    end as band -- (end of the choice)
    from generate_series(p_from, p_to - interval '1 minute', interval '1 minute') m -- each minute from the start up to the end
  ) b -- (end of the minutes)
  group by b.band -- one row per band
$$; -- end of the function
revoke all on function private.billing_time_bands(timestamptz, timestamptz, public.au_state) from public, anon, authenticated; -- only used inside the database

-- Words for each band, for pay line notes.
create or replace function private.billing_band_words(p_band text) -- the band
returns text language sql immutable -- the same answer every time
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the answer:
  select case p_band -- in words:
    when 'outside_span' then 'weekday before 7am or after 7pm' -- outside 7am to 7pm
    when 'saturday' then 'Saturday' -- Saturday
    when 'sunday' then 'Sunday' -- Sunday
    when 'public_holiday' then 'public holiday' -- public holiday
    else 'weekday 7am to 7pm' -- ordinary hours
  end -- end of the choice
$$; -- end of the function
revoke all on function private.billing_band_words(text) from public, anon, authenticated; -- only used inside the database

-- ---------------------------------------------------------------------------
-- 4. Working out the penalty top-ups
-- ---------------------------------------------------------------------------
-- For each school tutoring session pay line in the dates, adds a top-up
-- line where the tutor's rate is below the award rate for any band of the
-- time worked. Pending top-ups in the dates are rebuilt; sent ones stay.
-- Returns how many top-up lines are waiting in the dates.
create or replace function private.billing_build_penalty_pay(p_from date, p_to date) -- first and last day
returns int language plpgsql security definer -- writes pay lines
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  r record; -- one session pay line at a time
  b record; -- one band at a time
  v_base int; -- the base (full-time) hourly rate for their level, in cents
  v_start timestamptz; -- when the paid time started
  v_short numeric; -- the top-up for this session, in cents
  v_short_minutes int; -- minutes that needed a top-up
  v_parts text[]; -- the notes for each band
  n int; -- how many top-ups are waiting
begin -- start
  delete from public.billing_pay_lines -- starts fresh for these dates
  where status = 'pending' and kind = 'penalty' and work_date between p_from and p_to; -- only top-ups not yet sent to Xero

  for r in -- each school tutoring session pay line in the dates:
    select l.account_id, l.staff_name, l.work_date, l.session_id, l.minutes, l.rate_cents, l.note, -- the line
           se.worked_from, se.starts_at, -- when the time started
           st.state, -- the learner's state (for public holidays)
           coalesce(sp.employment, 'casual') as employment -- the tutor's employment type
    from public.billing_pay_lines l -- pay lines
    join public.sessions se on se.id = l.session_id -- their session (sessions belong to scheduling; billing only reads them)
    join public.students st on st.id = se.student_id -- the learner
    left join public.billing_staff_pay sp on sp.account_id = l.account_id -- the tutor's pay details
    where l.kind = 'session' and l.work_kind = 'school' -- school tutoring session time
      and l.work_date between p_from and p_to -- in the dates
      and not exists ( -- no top-up already sent for this session
        select 1 from public.billing_pay_lines t where t.session_id = l.session_id and t.kind = 'penalty' -- a top-up line for it
      ) -- end of the check
  loop -- for each one:
    v_base := private.billing_award_min_on(r.account_id, 'school', 'full_time', r.work_date); -- the base hourly rate for their level that day
    if v_base is null then -- no award rate loaded
      continue; -- nothing to compare with
    end if; -- end of the check
    v_start := greatest(coalesce(r.worked_from, r.starts_at), r.starts_at); -- paid time starts at the later of sign-on and the start time
    v_short := 0; -- no top-up yet
    v_short_minutes := 0; -- no minutes yet
    v_parts := '{}'; -- no notes yet
    for b in -- each band of the paid time, with the award rate for it:
      select tb.band, tb.minutes, round(v_base * p.percent / 100.0)::int as award_cents, p.percent -- the band, its minutes, the award rate and the percentage
      from private.billing_time_bands(v_start, v_start + make_interval(mins => r.minutes), r.state) tb -- the time split into bands
      join public.billing_award_penalties p on p.work_kind = 'school' and p.band = tb.band -- the percentage for that band
        and p.employment_group = case when r.employment = 'casual' then 'casual' else 'permanent' end -- for casual or permanent staff
    loop -- for each band:
      if b.award_cents > r.rate_cents then -- their rate is below the award rate for this band:
        v_short := v_short + b.minutes * (b.award_cents - r.rate_cents) / 60.0; -- adds the difference for those minutes
        v_short_minutes := v_short_minutes + b.minutes; -- counts the minutes
        v_parts := v_parts || format('%s min %s at %s%% (%s)', b.minutes, private.billing_band_words(b.band), trim(to_char(b.percent, 'FM990.##')), private.billing_dollars(b.award_cents)); -- notes the band
      end if; -- end of the check
    end loop; -- end of the bands
    if round(v_short) >= 1 then -- at least 1 cent is owed:
      insert into public.billing_pay_lines ( -- adds the top-up line
        account_id, staff_name, work_date, kind, work_kind, session_id, minutes, rate_cents, amount_cents, under_award, note, created_by -- its details
      ) values ( -- the values:
        r.account_id, r.staff_name, r.work_date, 'penalty', 'school', r.session_id, -- who, when, a penalty top-up for school tutoring, for this session
        0, round(v_short * 60 / v_short_minutes)::int, round(v_short)::int, false, -- no minutes (the session line has them), the average extra per hour, and the amount
        left('Award penalty rate: ' || array_to_string(v_parts, '; ') || ' (' || coalesce(r.note, 'session') || ')', 300), -- what it is for
        auth.uid() -- who worked it out (nobody for the daily run)
      ) on conflict do nothing; -- already there: leave it
    end if; -- end of the check
  end loop; -- end of the session lines

  select count(*) into n from public.billing_pay_lines -- counts what is waiting
  where status = 'pending' and kind = 'penalty' and work_date between p_from and p_to; -- top-ups in the dates not yet sent
  return n; -- tells the caller
end; -- finish
$$; -- end of the function
revoke all on function private.billing_build_penalty_pay(date, date) from public, anon, authenticated; -- only used inside the database

-- Working out session pay now also works out the top-ups.
do $$ -- edits billing_build_pay in place
declare -- working values:
  v_def text; -- the function's code
  v_anchor text := E'  select count(*) into n from public.billing_pay_lines\n  where status = ''pending'' and work_date between p_from and p_to;\n'; -- the last step (counting the lines)
begin -- start
  v_def := replace(pg_get_functiondef('public.billing_build_pay(date, date)'::regprocedure), chr(13), ''); -- reads its code (without Windows line endings from pasting)
  if strpos(v_def, 'billing_build_penalty_pay') > 0 then -- already added
    return; -- nothing to do
  end if; -- end of the check
  if strpos(v_def, v_anchor) = 0 then -- the place has changed
    raise exception 'public.billing_build_pay has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- end of the check
  execute replace(v_def, v_anchor, -- adds the top-up step before the count:
    E'  perform private.billing_build_penalty_pay(p_from, p_to); -- award penalty rate top-ups (Carla, 18 Nov 2026)\n' || v_anchor); -- then the original count
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 5. Xero: each person's top-ups become one to-do
-- ---------------------------------------------------------------------------
-- Called by the server when it sends timesheets. Adds one Xero to-do per
-- person for the penalty top-ups among the given lines. Returns how many
-- to-dos were added.
create or replace function public.billing_note_penalty_pay(p_lines uuid[]) -- the pay lines being sent
returns int language plpgsql security definer -- writes the to-do list
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  r record; -- one person at a time
  n int := 0; -- how many to-dos were added
begin -- start
  if not private.is_backend() then -- only the server
    raise exception 'Only the server can do this' using errcode = '42501'; -- plain message
  end if; -- end of the check
  for r in -- each person with top-ups among the lines:
    select l.account_id, sum(l.amount_cents)::int as cents, count(*)::int as lines, min(l.work_date) as first_day, max(l.work_date) as last_day -- who, how much, how many, and the dates
    from public.billing_pay_lines l -- pay lines
    where l.id = any (p_lines) and l.kind = 'penalty' and l.account_id is not null -- top-ups among those being sent
    group by l.account_id -- one row per person
  loop -- for each one:
    insert into public.billing_xero_tasks (account_id, kind, details) -- adds the to-do
    values (r.account_id, 'penalty_pay', left(format( -- what to do:
      'Award penalty rate top-up of %s for work from %s to %s (%s session(s), evenings, early mornings, weekends or public holidays). Add it to their pay run in Xero as an extra earnings line. The Pay page lists each session.', -- the words
      '$' || to_char(r.cents / 100.0, 'FM999990.00'), to_char(r.first_day, 'FMDD Mon YYYY'), to_char(r.last_day, 'FMDD Mon YYYY'), r.lines), 1000)); -- the amount in dollars, the dates and the count
    n := n + 1; -- counts it
  end loop; -- end of the people
  return n; -- tells the caller
end; -- finish
$$; -- end of the function
revoke all on function public.billing_note_penalty_pay(uuid[]) from public, anon, authenticated; -- not for signed-in people
grant execute on function public.billing_note_penalty_pay(uuid[]) to service_role; -- only the server
