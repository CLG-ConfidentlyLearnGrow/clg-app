-- Billing part 12 (module: billing): keeping Xero's employee records in step
-- with the app.
--
-- Carla (2026-11-16): when a staff member's pay details change, or they
-- leave CLG, the same change has to be made to their employee record in
-- Xero. The app should remind whoever made the change. Lots of new staff
-- are coming soon, so this needs to be easy to keep on top of.
--
-- How it works:
--   * A "Xero to-do" list on Admin > Billing > Staff pay. One line each
--     time something changes that Xero also needs to know about:
--       - employment type, agreed hours or an hourly rate changes
--         (including the app raising a rate to a new award minimum);
--       - someone is removed from the team (their last day and reason).
--   * The owner or a Finance admin ticks a line off once Xero matches.
--     When the app ends someone's employment in Xero itself, it ticks the
--     line off automatically.
--   * Billing only reads the staff directory's "who left" record; it never
--     changes it. This file writes only billing tables.
--
-- Safe to run more than once. Run after 20261114300100_staff_leaving.sql
-- and 20261113230100_billing_award_rates.sql.

-- ---------------------------------------------------------------------------
-- The Xero to-do list
-- ---------------------------------------------------------------------------
create table if not exists public.billing_xero_tasks ( -- one row for each change Xero needs to match
  id uuid primary key default gen_random_uuid(), -- the to-do's id
  account_id uuid not null references public.accounts (id) on delete cascade, -- whose Xero record needs changing
  kind text not null check (kind in ('pay_details', 'left')), -- pay details changed, or they left CLG
  details text not null check (char_length(details) <= 1000), -- what changed, in plain words
  left_on date, -- their last day (only for someone who left)
  departure_id uuid unique, -- the "who left" record this came from (so each leaving makes only one to-do)
  done_at timestamptz, -- when it was ticked off (empty while still to do)
  done_by uuid references public.accounts (id) on delete set null, -- who ticked it off (empty if the app did it)
  done_how text check (done_how in ('by_hand', 'app')), -- ticked off by a person, or done by the app in Xero
  created_at timestamptz not null default now() -- when the change happened
);
create index if not exists billing_xero_tasks_open on public.billing_xero_tasks (created_at) where done_at is null; -- quick list of what's still to do
alter table public.billing_xero_tasks enable row level security; -- access rules apply
revoke all on public.billing_xero_tasks from anon; -- signed-out visitors see nothing
revoke insert, update, delete on public.billing_xero_tasks from authenticated; -- only the functions below write it
drop policy if exists "pay admins see xero to-dos" on public.billing_xero_tasks; -- replace the rule if re-run
create policy "pay admins see xero to-dos" on public.billing_xero_tasks -- who can read the list
  for select to authenticated using (private.is_pay_admin()); -- the owner and Finance admins (it shows pay rates)
drop trigger if exists audit on public.billing_xero_tasks; -- replace the record-keeper if re-run
create trigger audit after insert or update or delete on public.billing_xero_tasks -- after any change,
  for each row execute function private.audit_change(); -- write a line in the audit log

-- ---------------------------------------------------------------------------
-- Dollars per hour from cents, for the to-do wording ("–" when empty).
-- ---------------------------------------------------------------------------
create or replace function private.billing_dollars(p_cents int) -- the cents to show
returns text language sql immutable -- the same answer every time
set search_path = '' -- no hidden schema lookups (safety)
as $$
  select case when p_cents is null then '–' else '$' || to_char(p_cents / 100.0, 'FM999990.00') || '/hr' end; -- for example $33.12/hr
$$;
revoke all on function private.billing_dollars(int) from public, anon, authenticated; -- only used inside the database

-- ---------------------------------------------------------------------------
-- When pay details change, add a Xero to-do saying what changed.
-- Only changes Xero holds too: employment type, agreed hours, the rates.
-- Choosing Xero links alone adds nothing.
-- ---------------------------------------------------------------------------
create or replace function private.billing_note_pay_change() -- runs after billing_staff_pay changes
returns trigger language plpgsql security definer -- runs with the owner's rights so it can add the to-do
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_old public.billing_staff_pay; -- the details before (empty for someone new)
  v_parts text[] := '{}'; -- each change, in words
  v_words constant jsonb := '{"casual": "Casual", "part_time": "Part-time", "full_time": "Full-time"}'; -- employment types in words
begin
  if tg_op = 'UPDATE' then -- an existing person's details changed
    v_old := old; -- keep the old details to compare
  elsif new.school_rate_cents is null and new.tertiary_rate_cents is null and new.admin_rate_cents is null -- someone new with no rates
        and new.guaranteed_weekly_minutes is null then -- and no agreed hours (for example only linked to Xero)
    return new; -- nothing for Xero yet
  end if;
  if v_old.employment is distinct from new.employment then -- employment type changed
    v_parts := v_parts || format('Employment: %s to %s', coalesce(v_words ->> v_old.employment, '–'), v_words ->> new.employment); -- say from what to what
  end if;
  if v_old.guaranteed_weekly_minutes is distinct from new.guaranteed_weekly_minutes then -- agreed hours changed
    v_parts := v_parts || format('Agreed hours: %s to %s a week', -- say from what to what
      coalesce(round(v_old.guaranteed_weekly_minutes / 60.0, 2)::text || ' hr', 'none'), -- the old hours (or none)
      coalesce(round(new.guaranteed_weekly_minutes / 60.0, 2)::text || ' hr', 'none')); -- the new hours (or none)
  end if;
  if v_old.school_rate_cents is distinct from new.school_rate_cents then -- school tutoring rate changed
    v_parts := v_parts || format('School tutoring rate: %s to %s', private.billing_dollars(v_old.school_rate_cents), private.billing_dollars(new.school_rate_cents)); -- from what to what
  end if;
  if v_old.tertiary_rate_cents is distinct from new.tertiary_rate_cents then -- tertiary rate changed
    v_parts := v_parts || format('Tertiary tutoring rate: %s to %s', private.billing_dollars(v_old.tertiary_rate_cents), private.billing_dollars(new.tertiary_rate_cents)); -- from what to what
  end if;
  if v_old.admin_rate_cents is distinct from new.admin_rate_cents then -- admin rate changed
    v_parts := v_parts || format('Admin rate: %s to %s', private.billing_dollars(v_old.admin_rate_cents), private.billing_dollars(new.admin_rate_cents)); -- from what to what
  end if;
  if cardinality(v_parts) = 0 then -- nothing Xero holds changed
    return new; -- no to-do needed
  end if;
  insert into public.billing_xero_tasks (account_id, kind, details) -- add the to-do
  values (new.account_id, 'pay_details', left(array_to_string(v_parts, '; '), 1000)); -- every change on one line
  return new; -- let the change go ahead
end;
$$;
revoke all on function private.billing_note_pay_change() from public, anon, authenticated; -- only the trigger uses it
drop trigger if exists billing_note_pay_change on public.billing_staff_pay; -- replace the trigger if re-run
create trigger billing_note_pay_change after insert or update on public.billing_staff_pay -- after pay details are added or changed
  for each row execute function private.billing_note_pay_change(); -- add a Xero to-do if needed

-- ---------------------------------------------------------------------------
-- When someone is removed from the team, add a Xero to-do to end their
-- employment there too. Reads the staff directory's record; writes only
-- the billing to-do list.
-- ---------------------------------------------------------------------------
create or replace function private.billing_note_departure() -- runs after a "who left" record is added
returns trigger language plpgsql security definer -- runs with the owner's rights so it can add the to-do
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  insert into public.billing_xero_tasks (account_id, kind, details, left_on, departure_id) -- add the to-do
  values (new.account_id, 'left', -- for this person, who left
    format('Left CLG. Last day %s. End their employment in Xero, then pay their final wages and any leave owed in a Xero pay run.', to_char(new.left_on, 'FMDD Mon YYYY')), -- what to do, with their last day
    new.left_on, new.id) -- their last day, and which record it came from
  on conflict (departure_id) do nothing; -- only one to-do for each leaving
  return new; -- let the record be added
end;
$$;
revoke all on function private.billing_note_departure() from public, anon, authenticated; -- only the trigger uses it
drop trigger if exists billing_note_departure on public.staff_departures; -- replace the trigger if re-run
create trigger billing_note_departure after insert on public.staff_departures -- after someone is removed from the team
  for each row execute function private.billing_note_departure(); -- add the Xero to-do

-- ---------------------------------------------------------------------------
-- Tick a Xero to-do off. The owner or Finance, by hand; or the app, once it
-- has made the change in Xero itself (p_how = 'app').
-- ---------------------------------------------------------------------------
create or replace function public.billing_xero_task_done(p_task uuid, p_how text default 'by_hand') -- which to-do, and how it was done
returns void language plpgsql security definer -- runs with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not (private.is_backend() or private.is_pay_admin()) then -- only the owner, Finance, or the app's back end
    raise exception 'Only the owner or a Finance admin can tick off Xero to-dos' using errcode = '42501'; -- plain message for anyone else
  end if;
  if p_how is null or p_how not in ('by_hand', 'app') then -- not one of the two ways
    raise exception 'Choose how it was done' using errcode = '22023'; -- plain message
  end if;
  update public.billing_xero_tasks -- tick it off
  set done_at = now(), done_by = auth.uid(), done_how = p_how -- now, by this person, this way
  where id = p_task and done_at is null; -- only if still to do
end;
$$;
revoke all on function public.billing_xero_task_done(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.billing_xero_task_done(uuid, text) to authenticated, service_role; -- signed-in admins (checked inside) and the back end

-- ---------------------------------------------------------------------------
-- Link several people to their Xero employee records at once (for example
-- everyone whose email matches). Only sets the Xero employee; someone with
-- no pay details yet starts as casual with no rates.
-- p_links is a list like [{"account_id": "...", "xero_employee_id": "..."}].
-- Returns how many were linked.
-- ---------------------------------------------------------------------------
create or replace function public.billing_link_xero_employees(p_links jsonb) -- the people and their Xero ids
returns int language plpgsql security definer -- runs with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  r record; -- one link at a time
  n int := 0; -- how many were linked
begin
  if not private.is_pay_admin() then -- only the owner or Finance
    raise exception 'Only the owner or a Finance admin can link staff to Xero' using errcode = '42501'; -- plain message for anyone else
  end if;
  if jsonb_typeof(p_links) is distinct from 'array' or jsonb_array_length(p_links) > 500 then -- not a list, or far too long
    raise exception 'Send a list of up to 500 people' using errcode = '22023'; -- plain message
  end if;
  for r in -- each link in the list
    select (e ->> 'account_id')::uuid as account_id, left(trim(e ->> 'xero_employee_id'), 100) as xero_id -- the person and their Xero id
    from jsonb_array_elements(p_links) e -- from the list
  loop
    if r.xero_id is null or r.xero_id = '' then -- no Xero id given
      continue; -- skip this one
    end if;
    if not (private.account_has_role(r.account_id, 'tutor') or private.account_has_role(r.account_id, 'admin')) then -- not current staff
      continue; -- skip this one
    end if;
    insert into public.billing_staff_pay (account_id, employment, xero_employee_id) -- add their pay details if they have none
    values (r.account_id, 'casual', r.xero_id) -- casual to start, with the Xero link
    on conflict (account_id) do update set xero_employee_id = excluded.xero_employee_id -- or just set the Xero link
    where public.billing_staff_pay.xero_employee_id is null; -- but never replace a link someone already chose
    if found then -- a row was added or changed
      n := n + 1; -- count it
    end if;
  end loop;
  return n; -- tell the caller how many
end;
$$;
revoke all on function public.billing_link_xero_employees(jsonb) from public, anon; -- not for signed-out visitors
grant execute on function public.billing_link_xero_employees(jsonb) to authenticated; -- signed-in admins (checked inside)
