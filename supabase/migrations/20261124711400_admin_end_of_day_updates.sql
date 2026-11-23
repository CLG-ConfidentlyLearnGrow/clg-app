-- Summary: end-of-day updates from admin staff (Carla, 22 Nov 2026).
--
-- Carla: "Updates should be sent every day admin work is done. What they
-- did, what went well, what didn't go well (in dot point form...)".
--
-- What this adds (module: staff, which owns staff records outside pay):
--   * public.admin_day_updates: one update per admin staff member per day,
--     with three dot point lists: what they did, what went well, and what
--     did not go well.
--   * Admin staff write and correct their own updates for today or the last
--     7 days. They see their own; CLG's owner sees everyone's and marks them
--     as read.
--   * public.my_missing_day_updates(): the days in the last 7 (not today)
--     on which the person logged office admin hours but sent no update, so
--     the menu can show a number and the page a reminder.
--   * public.day_updates_unread_count(): for the owner, how many updates
--     from the last 30 days are not yet read (the menu number).
--
-- Safe to run more than once. Run after 20261124710800_policy_versions_read_again.sql.

-- ---------------------------------------------------------------------------
-- 1. The updates
-- ---------------------------------------------------------------------------
create table if not exists public.admin_day_updates ( -- one row per person per day
  id uuid primary key default gen_random_uuid(), -- the update's id
  account_id uuid not null references public.accounts (id) on delete cascade, -- who sent it (removed with their account)
  work_date date not null, -- the day it is about
  did text not null check (char_length(btrim(did)) between 2 and 3000), -- what they did (dot points, one per line)
  went_well text check (char_length(went_well) <= 2000), -- what went well (dot points)
  not_well text check (char_length(not_well) <= 2000), -- what did not go well (dot points)
  owner_read_at timestamptz, -- when the owner read it (cleared when it is changed)
  created_at timestamptz not null default now(), -- when it was sent
  updated_at timestamptz not null default now(), -- when it last changed
  unique (account_id, work_date) -- one update per person per day
); -- end of the table
create index if not exists admin_day_updates_date on public.admin_day_updates (work_date desc); -- lists the newest days quickly
alter table public.admin_day_updates enable row level security; -- access rules apply
revoke all on public.admin_day_updates from anon; -- signed-out visitors get nothing
revoke insert, update, delete, truncate on public.admin_day_updates from authenticated; -- changes only through the functions below
grant select on public.admin_day_updates to authenticated; -- reading, limited by the rule below
drop trigger if exists audit on public.admin_day_updates; -- replaces the change log trigger if run again
create trigger audit after insert or update or delete on public.admin_day_updates -- logs every change
  for each row execute function private.audit_change(); -- in the shared change log
drop policy if exists "see own or owner" on public.admin_day_updates; -- replaces the rule if run again
create policy "see own or owner" on public.admin_day_updates -- who can read a row:
  for select to authenticated -- signed-in people
  using (account_id = (select auth.uid()) or (select private.is_owner())); -- the person who sent it, and CLG's owner

-- ---------------------------------------------------------------------------
-- 2. Sending and correcting an update (admin staff)
-- ---------------------------------------------------------------------------
create or replace function public.admin_day_update_save( -- sends or corrects the person's update for a day:
  p_date date, -- the day it is about
  p_did text, -- what they did
  p_went_well text, -- what went well
  p_not_well text -- what did not go well
)
returns uuid language plpgsql security definer -- writes the updates for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_today date := (now() at time zone 'Australia/Adelaide')::date; -- today in Adelaide
  v_id uuid; -- the update's id
begin -- start
  if not private.has_role('admin') then -- only admin staff send these
    raise exception 'Only CLG admin staff send end-of-day updates.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if p_date is null or p_date > v_today or p_date < v_today - 7 then -- a day outside the last week
    raise exception 'Please choose today or a day in the last 7 days.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_did, ''))) < 2 then -- nothing about what they did
    raise exception 'Please write what you did, one dot point per line.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.admin_day_updates (account_id, work_date, did, went_well, not_well) -- adds it:
  values (auth.uid(), p_date, left(btrim(p_did), 3000), nullif(left(btrim(coalesce(p_went_well, '')), 2000), ''), nullif(left(btrim(coalesce(p_not_well, '')), 2000), '')) -- for them, that day, with the three lists
  on conflict (account_id, work_date) do update set -- or, if they already sent one that day:
    did = excluded.did, went_well = excluded.went_well, not_well = excluded.not_well, -- replaces the three lists,
    updated_at = now(), owner_read_at = null -- and the owner reads it again
  returning id into v_id; -- keeps its id
  return v_id; -- hands back the update's id
end; -- end of the code
$$; -- end of the function
revoke all on function public.admin_day_update_save(date, text, text, text) from public, anon; -- not for signed-out visitors
grant execute on function public.admin_day_update_save(date, text, text, text) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- 3. The owner marks updates as read
-- ---------------------------------------------------------------------------
create or replace function public.admin_day_updates_mark_read(p_ids uuid[]) -- takes the updates read
returns integer language plpgsql security definer -- writes the updates for the owner; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_count integer; -- how many were marked
begin -- start
  if not private.is_owner() then -- only CLG's owner
    raise exception 'Only CLG''s owner can mark updates as read.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  update public.admin_day_updates set owner_read_at = now() where id = any (coalesce(p_ids, '{}')) and owner_read_at is null; -- marks each one read
  get diagnostics v_count = row_count; -- counts them
  return v_count; -- hands back how many
end; -- end of the code
$$; -- end of the function
revoke all on function public.admin_day_updates_mark_read(uuid[]) from public, anon; -- not for signed-out visitors
grant execute on function public.admin_day_updates_mark_read(uuid[]) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- 4. The numbers for the menu
-- ---------------------------------------------------------------------------
-- The days in the last 7 (not today) on which the signed-in admin logged
-- office admin hours but sent no update.
create or replace function public.my_missing_day_updates() -- no inputs: it is about the signed-in person
returns setof date language sql stable security definer -- reads their hours and updates for them
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the list
  select distinct h.work_date -- each day
  from public.billing_hour_logs h -- from their logged hours
  where h.account_id = auth.uid() and private.has_role('admin') -- their own, if they are admin staff,
    and h.work_type = 'admin' and h.source = 'staff' and h.status <> 'declined' -- office admin hours they logged (not declined),
    and h.work_date between (now() at time zone 'Australia/Adelaide')::date - 7 and (now() at time zone 'Australia/Adelaide')::date - 1 -- in the last 7 days (not today),
    and not exists (select 1 from public.admin_day_updates u where u.account_id = h.account_id and u.work_date = h.work_date) -- with no update that day
  order by h.work_date; -- oldest first
$$; -- end of the function
revoke all on function public.my_missing_day_updates() from public, anon; -- not for signed-out visitors
grant execute on function public.my_missing_day_updates() to authenticated; -- signed-in people (only their own)

-- For the owner: how many updates from the last 30 days are not yet read.
create or replace function public.day_updates_unread_count() -- no inputs
returns integer language sql stable security definer -- counts for the owner
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the number
  select case when private.is_owner() then ( -- only for the owner:
    select count(*)::integer from public.admin_day_updates u -- the updates
    where u.owner_read_at is null and u.account_id <> auth.uid() -- not yet read, and not their own
      and u.work_date >= (now() at time zone 'Australia/Adelaide')::date - 30 -- from the last 30 days
  ) else 0 end; -- anyone else: none
$$; -- end of the function
revoke all on function public.day_updates_unread_count() from public, anon; -- not for signed-out visitors
grant execute on function public.day_updates_unread_count() to authenticated; -- signed-in people (the check is inside)
