-- Summary: award classification levels for school tutoring, and the move
-- from Level 1 to Level 2 after 3 months (Carla, 18 Nov 2026).
--
-- Carla asked for the Miscellaneous Award rules to be checked and built.
-- The Miscellaneous Award 2020 (MA000104) clause 12.1 says:
--   * Level 1: employed for less than 3 months (and not doing Level 3 or 4
--     work).
--   * Level 2: employed for at least 3 months (and not doing Level 3 or 4
--     work).
--   * Level 3: has a trade qualification or equivalent and uses it.
--   * Level 4: has an advanced trade qualification, or is a sub-professional
--     employee.
-- So Level 1 and Level 2 depend only on time, and the move to Level 2 is
-- automatic at 3 months.
--
-- How it works:
--   * Each staff member's pay details get a start date and a school tutoring
--     level. "Level 1 or 2" is worked out from the start date. Level 3 or 4
--     is chosen by an admin when it applies.
--   * The award rates table gets a level, and the 2026-27 Level 2, 3 and 4
--     school rates are loaded (from the Fair Work pay guide, FY27).
--   * The daily billing run already raises any rate below the award minimum.
--     It now uses each person's level, so at 3 months a rate below the
--     Level 2 minimum is raised from that day, with a Xero to-do as before.
--   * At 3 months the owner and Finance admins get an app notice, and a Xero
--     to-do says to change the classification in Xero.
--
-- Billing module: changes only billing tables and functions. Edits
-- billing_note_pay_change in place, so other changes to it stay.
-- Safe to run more than once. Run after 20261120800400_award_rates_yearly_reminder.sql.

-- ---------------------------------------------------------------------------
-- 1. Start date and school tutoring level on each person's pay details
-- ---------------------------------------------------------------------------
alter table public.billing_staff_pay add column if not exists started_on date; -- the day they started working for CLG (needed to know when 3 months is up)
alter table public.billing_staff_pay add column if not exists school_level smallint not null default 1; -- 1 = "Level 1 or 2, worked out from the start date"; 3 or 4 = chosen by an admin
alter table public.billing_staff_pay drop constraint if exists billing_staff_pay_school_level_check; -- removes the old rule (so this file can run twice)
alter table public.billing_staff_pay add constraint billing_staff_pay_school_level_check check (school_level between 1 and 4); -- only Levels 1 to 4 exist

-- ---------------------------------------------------------------------------
-- 2. A level on each award rate
-- ---------------------------------------------------------------------------
alter table public.billing_award_rates add column if not exists level smallint not null default 1; -- which classification level the minimum is for (existing rates are Level 1)
alter table public.billing_award_rates drop constraint if exists billing_award_rates_level_check; -- removes the old rule (so this file can run twice)
alter table public.billing_award_rates add constraint billing_award_rates_level_check check (level between 1 and 4); -- only Levels 1 to 4
do $$ -- swaps the table's key so each level has its own rate
begin -- start
  if exists ( -- the old key (without the level) is still there:
    select 1 from pg_constraint c -- a table rule
    where c.conname = 'billing_award_rates_pkey' -- the key
      and c.conrelid = 'public.billing_award_rates'::regclass -- on the award rates table
      and not exists ( -- that does not yet include the level column
        select 1 from pg_attribute a -- a column
        where a.attrelid = c.conrelid and a.attnum = any (c.conkey) and a.attname = 'level' -- named level, in the key
      ) -- end of the column check
  ) then -- so:
    alter table public.billing_award_rates drop constraint billing_award_rates_pkey; -- removes the old key
    alter table public.billing_award_rates add constraint billing_award_rates_pkey primary key (work_kind, employment, level, effective_from); -- adds the new key with the level
  end if; -- end of the check
end; -- finish
$$; -- end of the block

-- The 2026-27 school tutoring minimums for Levels 2 to 4 (Fair Work pay
-- guide, Miscellaneous Award, from 1 July 2026). Level 1 is already loaded.
insert into public.billing_award_rates (work_kind, employment, level, min_rate_cents, award, effective_from) values -- adds these rates:
  ('school', 'casual', 2, 3385, 'Miscellaneous Award MA000104, Level 2 casual', '2026-07-01'), -- Level 2 casual $33.85
  ('school', 'part_time', 2, 2708, 'Miscellaneous Award MA000104, Level 2', '2026-07-01'), -- Level 2 part-time $27.08
  ('school', 'full_time', 2, 2708, 'Miscellaneous Award MA000104, Level 2', '2026-07-01'), -- Level 2 full-time $27.08
  ('school', 'casual', 3, 3681, 'Miscellaneous Award MA000104, Level 3 casual', '2026-07-01'), -- Level 3 casual $36.81
  ('school', 'part_time', 3, 2945, 'Miscellaneous Award MA000104, Level 3', '2026-07-01'), -- Level 3 part-time $29.45
  ('school', 'full_time', 3, 2945, 'Miscellaneous Award MA000104, Level 3', '2026-07-01'), -- Level 3 full-time $29.45
  ('school', 'casual', 4, 4016, 'Miscellaneous Award MA000104, Level 4 casual', '2026-07-01'), -- Level 4 casual $40.16
  ('school', 'part_time', 4, 3213, 'Miscellaneous Award MA000104, Level 4', '2026-07-01'), -- Level 4 part-time $32.13
  ('school', 'full_time', 4, 3213, 'Miscellaneous Award MA000104, Level 4', '2026-07-01') -- Level 4 full-time $32.13
on conflict do nothing; -- already there: leave it

-- ---------------------------------------------------------------------------
-- 3. A person's level and award minimum on a given day
-- ---------------------------------------------------------------------------
-- The day a person reaches 3 months (or nothing if no start date is saved).
create or replace function private.billing_level_two_from(p_account uuid) -- whose
returns date -- the day they become Level 2
language sql stable security definer -- reads pay details
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select (sp.started_on + interval '3 months')::date -- 3 calendar months after they started
  from public.billing_staff_pay sp where sp.account_id = p_account -- from their pay details
$$; -- end of the function
revoke all on function private.billing_level_two_from(uuid) from public, anon, authenticated; -- only used inside the database

-- A person's classification level for a kind of work on a day. Only school
-- tutoring has levels in the app so far; other work is Level 1.
create or replace function private.billing_level_on(p_account uuid, p_kind text, p_day date) -- whose, which work, which day
returns smallint -- the level (1 to 4)
language sql stable security definer -- reads pay details
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select case -- works it out:
    when p_kind <> 'school' then 1::smallint -- not school tutoring: Level 1
    when sp.school_level >= 3 then sp.school_level -- Level 3 or 4 chosen by an admin
    when sp.started_on is not null and p_day >= (sp.started_on + interval '3 months')::date then 2::smallint -- 3 months or more since starting: Level 2
    else 1::smallint -- otherwise (under 3 months, or no start date saved): Level 1
  end -- end of the choice
  from (select 1) one -- always one row,
  left join public.billing_staff_pay sp on sp.account_id = p_account -- with their pay details if they have them
$$; -- end of the function
revoke all on function private.billing_level_on(uuid, text, date) from public, anon, authenticated; -- only used inside the database

-- The award minimum hourly rate (in cents) for a person, kind of work and
-- employment type on a day. If no rate is loaded for their exact level, the
-- nearest lower level is used.
create or replace function private.billing_award_min_on(p_account uuid, p_kind text, p_employment text, p_day date) -- whose, which work, which employment type, which day
returns int -- cents per hour (or nothing if no award rate is loaded)
language sql stable security definer -- reads award rates
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select r.min_rate_cents -- the minimum
  from public.billing_award_rates r -- from the award rates
  where r.work_kind = p_kind and r.employment = p_employment -- for this work and employment type
    and r.effective_from <= p_day -- already started on that day
    and r.level <= private.billing_level_on(p_account, p_kind, p_day) -- at their level or below
  order by r.effective_from desc, r.level desc -- the newest year first, then the highest level
  limit 1 -- just one
$$; -- end of the function
revoke all on function private.billing_award_min_on(uuid, text, text, date) from public, anon, authenticated; -- only used inside the database

-- Is this rate under the award minimum on that day? (Same as before, now
-- using the person's level.)
create or replace function private.billing_under_award(p_account uuid, p_kind text, p_rate int, p_day date) -- whose, which work, the rate, which day
returns boolean -- true if the rate is too low
language sql stable security definer -- reads pay details and award rates
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select coalesce(p_rate < private.billing_award_min_on( -- the rate is below the minimum
    p_account, p_kind, -- for this person and work
    coalesce((select employment from public.billing_staff_pay where account_id = p_account), 'casual'), -- for their employment type (casual if not set)
    p_day), false) -- on that day (and false if no minimum is loaded)
$$; -- end of the function

-- ---------------------------------------------------------------------------
-- 4. Raising rates: now by level, and noticing the 3-month mark
-- ---------------------------------------------------------------------------
-- Notes who has been told about reaching Level 2, so it happens once each.
create table if not exists public.billing_level_notices ( -- one row per person told
  account_id uuid not null references public.accounts (id) on delete cascade, -- who reached the level
  level smallint not null check (level between 2 and 4), -- the level they reached
  reached_on date not null, -- the day they reached it
  created_at timestamptz not null default now(), -- when the app noticed
  primary key (account_id, level) -- each person once for each level
); -- end of the table
alter table public.billing_level_notices enable row level security; -- access rules apply
revoke all on public.billing_level_notices from anon, authenticated; -- nobody signed in reads or writes it directly (only the database's own functions)

-- Raises rates below the award minimum in force today, by each person's
-- level. Run by the daily billing run, and straight after an upload.
-- Returns how many rates were raised.
create or replace function public.billing_apply_award_rates() -- no inputs: uses today's date
returns int language plpgsql security definer -- runs with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the steps
declare -- working values:
  v_today date := private.billing_today(); -- today in Adelaide
  r record; -- one rate or person at a time
  n int := 0; -- how many rates were raised
begin -- start
  if not (private.is_backend() or private.is_pay_admin()) then -- only the daily run, the owner or Finance
    raise exception 'Only the owner or a Finance admin can update pay rates' using errcode = '42501'; -- plain message
  end if; -- end of the check

  -- First, anyone who has reached 3 months and has not been noted yet.
  for r in -- each person now at Level 2 because of time:
    select sp.account_id, (sp.started_on + interval '3 months')::date as reached_on, a.full_name -- who, the day, and their name
    from public.billing_staff_pay sp -- pay details
    join public.accounts a on a.id = sp.account_id -- for their name
    where sp.school_rate_cents is not null -- they do school tutoring
      and sp.school_level < 3 -- not set to Level 3 or 4
      and sp.started_on is not null -- their start date is saved
      and (sp.started_on + interval '3 months')::date <= v_today -- 3 months have passed
      and not exists (select 1 from public.billing_level_notices ln where ln.account_id = sp.account_id and ln.level = 2) -- not noted yet
  loop -- for each one:
    insert into public.billing_level_notices (account_id, level, reached_on) values (r.account_id, 2, r.reached_on); -- notes it once
    if r.reached_on > v_today - 31 then -- only reached recently (not someone whose start date was entered long after):
      insert into public.billing_xero_tasks (account_id, kind, details) -- adds a Xero to-do
      values (r.account_id, 'pay_details', left(format( -- with what to change:
        'School tutoring classification: Miscellaneous Award Level 1 to Level 2 from %s (3 months after starting). Change their classification in Xero.', -- the words
        to_char(r.reached_on, 'FMDD Mon YYYY')), 1000)); -- the day
      perform private.add_notice(x.account_id, null, null, 'staff_alert', -- an app notice to each owner and Finance admin:
        'A tutor is now Level 2', -- the title
        r.full_name || ' reached 3 months with CLG on ' || to_char(r.reached_on, 'FMDD Month YYYY') -- who and when
          || '. Under the Miscellaneous Award they are now Level 2. The app raises their school tutoring rate if it is below the Level 2 minimum. Please change their classification in Xero (it is on the Xero to-do list).', -- what happens and what to do
        now()) -- now
      from ( -- the people to tell:
        select ar.account_id from public.account_roles ar -- admins
        left join public.admin_profiles ap on ap.account_id = ar.account_id -- with their admin level
        where ar.role = 'admin' and coalesce(ap.level::text, 'owner') in ('owner', 'finance') -- owner or Finance
      ) x; -- (end of the people)
    end if; -- end of the recent check
  end loop; -- end of the people

  -- Then raise any rate below the minimum for that person's level.
  for r in -- each person's rate that is now under the award
    select sp.account_id, k.kind, k.cents, -- who, which rate, and the rate now
           a.min_rate_cents, a.award, -- the minimum and its award
           greatest(a.effective_from, -- the change starts when the award rate started,
             case when a.level = 2 and sp.school_level < 3 and sp.started_on is not null -- or, for a Level 2 rate reached by time,
                  then (sp.started_on + interval '3 months')::date end) as effective_from -- when they reached 3 months (whichever is later)
    from public.billing_staff_pay sp -- everyone with pay details
    cross join lateral (values ('school', sp.school_rate_cents), ('tertiary', sp.tertiary_rate_cents), ('admin', sp.admin_rate_cents)) as k(kind, cents) -- their three rates, one row each
    join lateral ( -- the award minimum in force today for that work, employment type and level
      select ar.min_rate_cents, ar.effective_from, ar.award, ar.level from public.billing_award_rates ar -- award rates
      where ar.work_kind = k.kind and ar.employment = sp.employment and ar.effective_from <= v_today -- matching, and already started
        and ar.level <= private.billing_level_on(sp.account_id, k.kind, v_today) -- at their level or below
      order by ar.effective_from desc, ar.level desc limit 1 -- the newest, highest one
    ) a on true -- (only where an award rate exists)
    where k.cents is not null and k.cents < a.min_rate_cents -- has a rate, and it is under the minimum
  loop -- for each one:
    insert into public.billing_staff_rate_changes (account_id, work_kind, old_cents, new_cents, effective_from, reason) -- logs the change
    values (r.account_id, r.kind, r.cents, r.min_rate_cents, r.effective_from, left('Raised to the award minimum: ' || r.award, 300)); -- old and new rate, start date and why
    update public.billing_staff_pay set -- raises the rate
      school_rate_cents = case when r.kind = 'school' then r.min_rate_cents else school_rate_cents end, -- the school rate, if that is the one
      tertiary_rate_cents = case when r.kind = 'tertiary' then r.min_rate_cents else tertiary_rate_cents end, -- the tertiary rate, if that is the one
      admin_rate_cents = case when r.kind = 'admin' then r.min_rate_cents else admin_rate_cents end -- the admin rate, if that is the one
    where account_id = r.account_id; -- for this person
    n := n + 1; -- counts it
  end loop; -- end of the rates
  return n; -- tells the caller how many were raised
end; -- finish
$$; -- end of the function
revoke all on function public.billing_apply_award_rates() from public, anon; -- not for signed-out visitors
grant execute on function public.billing_apply_award_rates() to authenticated, service_role; -- admins (checked inside) and the daily run

-- ---------------------------------------------------------------------------
-- 5. Uploading award rates: each line can now say its level
-- ---------------------------------------------------------------------------
-- p_rows is a list like
--   [{"work_kind":"school","employment":"casual","level":2,"rate_cents":3385,"award":"..."}]
-- A line without a level is Level 1. Replaces any rates already saved for
-- that start date. If the date has already come, rates are applied now.
create or replace function public.billing_upload_award_rates(p_effective date, p_rows jsonb) -- start date and the rates
returns int language plpgsql security definer -- runs with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the steps
declare -- working values:
  v jsonb; -- one row of the upload
  v_level int; -- that row's level
begin -- start
  if not private.is_pay_admin() then -- only the owner or Finance
    raise exception 'Only the owner or a Finance admin can upload award rates' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if p_effective is null then -- no start date
    raise exception 'Choose the date the new rates start (usually 1 July)' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then -- nothing to upload
    raise exception 'The file has no rates in it' using errcode = '22023'; -- plain message
  end if; -- end of the check
  delete from public.billing_award_rates where effective_from = p_effective; -- replaces an earlier upload for the same date
  for v in select * from jsonb_array_elements(p_rows) loop -- each row of the upload
    if (v->>'work_kind') not in ('school', 'tertiary', 'admin') then -- unknown kind of work
      raise exception 'Work must be school, tertiary or admin (found "%")', coalesce(v->>'work_kind', '') using errcode = '22023'; -- plain message
    end if; -- end of the check
    if (v->>'employment') not in ('casual', 'part_time', 'full_time') then -- unknown employment type
      raise exception 'Employment must be casual, part_time or full_time (found "%")', coalesce(v->>'employment', '') using errcode = '22023'; -- plain message
    end if; -- end of the check
    if coalesce(v->>'level', '1') !~ '^[1-4]$' then -- a level that is not 1, 2, 3 or 4
      raise exception 'Level must be 1, 2, 3 or 4 (found "%")', v->>'level' using errcode = '22023'; -- plain message
    end if; -- end of the check
    v_level := coalesce(v->>'level', '1')::int; -- the level (1 if not given)
    if (v->>'rate_cents') is null or (v->>'rate_cents')::int < 100 or (v->>'rate_cents')::int > 100000 then -- missing or silly amount
      raise exception 'Each rate must be an hourly amount between $1 and $1000' using errcode = '22023'; -- plain message
    end if; -- end of the check
    insert into public.billing_award_rates (work_kind, employment, level, min_rate_cents, award, effective_from) -- saves the rate
    values (v->>'work_kind', v->>'employment', v_level, (v->>'rate_cents')::int, -- work, employment, level and amount
            left(coalesce(nullif(trim(v->>'award'), ''), 'Award minimum'), 200), p_effective) -- the award's name (or a default) and the start date
    on conflict (work_kind, employment, level, effective_from) do update -- the same row twice in one file:
      set min_rate_cents = excluded.min_rate_cents, award = excluded.award; -- the later one wins
  end loop; -- end of the rows
  if p_effective <= private.billing_today() then -- the start date has already come
    return public.billing_apply_award_rates(); -- raises rates now
  end if; -- end of the check
  return 0; -- rates will be raised on the start date
end; -- finish
$$; -- end of the function
revoke all on function public.billing_upload_award_rates(date, jsonb) from public, anon; -- not for signed-out visitors
grant execute on function public.billing_upload_award_rates(date, jsonb) to authenticated; -- admins (checked inside)

-- ---------------------------------------------------------------------------
-- 6. The Xero to-do also lists a changed start date or level
-- ---------------------------------------------------------------------------
do $$ -- edits the "pay details changed" trigger in place
declare -- working values:
  v_def text; -- the function's code
  v_anchor text := E'  if cardinality(v_parts) = 0 then -- nothing Xero holds changed\n'; -- the place to add the new lines
begin -- start
  v_def := replace(pg_get_functiondef('private.billing_note_pay_change()'::regprocedure), chr(13), ''); -- reads its code (without Windows line endings from pasting)
  if strpos(v_def, 'started_on') > 0 then -- already added
    return; -- nothing to do
  end if; -- end of the check
  if strpos(v_def, v_anchor) = 0 then -- the place has changed
    raise exception 'billing_note_pay_change has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- end of the check
  execute replace(v_def, v_anchor, -- adds two checks before that place:
    E'  if v_old.started_on is distinct from new.started_on then -- start date changed\n'
    || E'    v_parts := v_parts || format(''Start date: %s to %s'', coalesce(to_char(v_old.started_on, ''FMDD Mon YYYY''), ''none''), coalesce(to_char(new.started_on, ''FMDD Mon YYYY''), ''none'')); -- from what to what\n'
    || E'  end if; -- end of the start date check\n'
    || E'  if tg_op = ''UPDATE'' and v_old.school_level is distinct from new.school_level then -- school tutoring level changed by an admin\n'
    || E'    v_parts := v_parts || format(''School tutoring classification: %s to %s'', case when v_old.school_level >= 3 then ''Level '' || v_old.school_level else ''Level 1 or 2 (from start date)'' end, case when new.school_level >= 3 then ''Level '' || new.school_level else ''Level 1 or 2 (from start date)'' end); -- from what to what\n'
    || E'  end if; -- end of the level check\n'
    || v_anchor); -- then the original line
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 7. For the Pay page: each person's level today and their 3-month day
-- ---------------------------------------------------------------------------
create or replace function public.billing_staff_levels() -- no inputs
returns table (account_id uuid, level smallint, level_two_from date, started_on date) -- who, their level today, the day they reach 3 months, and their start date
language sql stable security definer -- reads pay details after checking who is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select sp.account_id, -- who
         private.billing_level_on(sp.account_id, 'school', private.billing_today()), -- their school tutoring level today
         private.billing_level_two_from(sp.account_id), -- the day they reach (or reached) 3 months
         sp.started_on -- their start date
  from public.billing_staff_pay sp -- everyone with pay details
  where private.is_pay_admin() -- only for the owner and Finance
$$; -- end of the function
revoke all on function public.billing_staff_levels() from public, anon; -- not for signed-out visitors
grant execute on function public.billing_staff_levels() to authenticated; -- signed-in people (checked inside)
