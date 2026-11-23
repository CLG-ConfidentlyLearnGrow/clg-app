-- Summary: staff tell CLG about work outside CLG (Carla, 22 Nov 2026;
-- tutor contract v1.2 to v1.4, clause 6.7).
--
-- Clause 6.7: "While you work for CLG, you must tell CLG, through the CLG
-- App, about any educational support or administrative role you do outside
-- CLG, paid or unpaid. This includes tutoring privately or through another
-- business. Tell CLG before you start the role, and again if it changes or
-- ends."
--
-- What this adds (module: employment contracts, which owns staff contract
-- records):
--   * public.outside_work_reports: one row per outside role a staff member
--     reports: what kind of role, where, a short description, paid or
--     unpaid, and when it starts and ends.
--   * Tutors and admin staff add, change and end their own reports on the
--     My contract page. Only they and CLG's owner can see them (it is
--     employment information, so Operations, Support and Finance admins do
--     not see it).
--   * The owner is told by app notice each time a report is added, changed
--     or ended, and can mark it as seen with a private note.
--
-- Safe to run more than once. Run after 20261124710800_policy_versions_read_again.sql.

-- ---------------------------------------------------------------------------
-- 1. The reports
-- ---------------------------------------------------------------------------
create table if not exists public.outside_work_reports ( -- one row per outside role
  id uuid primary key default gen_random_uuid(), -- the report's id
  account_id uuid not null references public.accounts (id) on delete cascade, -- the staff member (removed with their account)
  kind text not null check (kind in ('tutoring', 'education_support', 'admin', 'other')), -- tutoring, other educational support, admin work, or other
  role_title text not null check (char_length(btrim(role_title)) between 2 and 200), -- the role, in their words (for example "Private maths tutor")
  organisation text check (char_length(organisation) <= 200), -- where (a business or school), or blank for private work
  details text check (char_length(details) <= 1000), -- anything else CLG should know (optional)
  paid boolean not null, -- paid or unpaid
  starts_on date not null, -- when it starts (or started)
  ends_on date, -- when it ends (blank while it carries on)
  owner_seen_at timestamptz, -- when the owner marked it as seen (cleared when it changes)
  owner_note text check (char_length(owner_note) <= 1000), -- the owner's private note
  created_at timestamptz not null default now(), -- when it was first reported
  updated_at timestamptz not null default now(), -- when it last changed
  check (ends_on is null or ends_on >= starts_on) -- it cannot end before it starts
); -- end of the table
create index if not exists outside_work_reports_account on public.outside_work_reports (account_id, starts_on desc); -- finds a person's reports quickly
alter table public.outside_work_reports enable row level security; -- access rules apply
revoke all on public.outside_work_reports from anon; -- signed-out visitors get nothing
revoke insert, update, delete, truncate on public.outside_work_reports from authenticated; -- changes only through the functions below
grant select on public.outside_work_reports to authenticated; -- reading, limited by the rule below
drop trigger if exists audit on public.outside_work_reports; -- replaces the change log trigger if run again
create trigger audit after insert or update or delete on public.outside_work_reports -- logs every change
  for each row execute function private.audit_change(); -- in the shared change log
drop policy if exists "see own or owner" on public.outside_work_reports; -- replaces the rule if run again
create policy "see own or owner" on public.outside_work_reports -- who can read a row:
  for select to authenticated -- signed-in people
  using (account_id = (select auth.uid()) or (select private.is_owner())); -- the staff member themselves, and CLG's owner

-- Tells CLG's owner (only) about a report. The notice names the person but
-- not the details, which are on the Contracts page.
create or replace function private.outside_work_tell_owner(p_account uuid, p_what text) -- takes the staff member and what happened
returns void language plpgsql security definer -- writes notices for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_name text; -- the staff member's name
  v_owner uuid; -- each owner account
begin -- start
  select full_name into v_name from public.accounts where id = p_account; -- their name
  for v_owner in -- for each owner:
    select distinct ar.account_id from public.account_roles ar -- people with the admin role
    left join public.admin_profiles ap on ap.account_id = ar.account_id -- and their admin level
    where ar.role = 'admin' and coalesce(ap.level, 'owner') = 'owner' -- at owner level
  loop -- each one:
    perform private.add_notice(v_owner, null, null, 'staff_alert', -- a staff notice:
      'Work outside CLG ' || p_what, -- the title, for example "Work outside CLG reported",
      coalesce(v_name, 'A staff member') || ' ' || p_what || ' a role outside CLG (contract clause 6.7). See Contracts > Work outside CLG.', -- who, and where to look
      now()); -- now (quiet hours still apply)
  end loop; -- next owner
end; -- end of the code
$$; -- end of the function
revoke all on function private.outside_work_tell_owner(uuid, text) from public; -- inside use only

-- ---------------------------------------------------------------------------
-- 2. Staff add, change or end their own reports
-- ---------------------------------------------------------------------------
create or replace function public.outside_work_save( -- adds a report, or changes one of the person's own:
  p_id uuid, -- the report to change (blank to add a new one)
  p_kind text, -- the kind of role
  p_role_title text, -- the role
  p_organisation text, -- where (optional)
  p_details text, -- anything else (optional)
  p_paid boolean, -- paid or not
  p_starts_on date, -- when it starts
  p_ends_on date default null -- when it ends (optional)
)
returns uuid language plpgsql security definer -- writes the reports for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_id uuid; -- the report's id
begin -- start
  if not (private.has_role('tutor') or private.has_role('admin')) then -- only staff report outside work
    raise exception 'Only CLG tutors and admin staff report work outside CLG.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if p_kind is null or p_kind not in ('tutoring', 'education_support', 'admin', 'other') then -- an unknown kind
    raise exception 'Please choose the kind of role.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_role_title, ''))) < 2 then -- no role given
    raise exception 'Please say what the role is.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_paid is null or p_starts_on is null then -- paid or start date missing
    raise exception 'Please say whether it is paid and when it starts.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_ends_on is not null and p_ends_on < p_starts_on then -- ends before it starts
    raise exception 'The end date cannot be before the start date.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_id is null then -- a new report:
    insert into public.outside_work_reports (account_id, kind, role_title, organisation, details, paid, starts_on, ends_on) -- adds it:
    values (auth.uid(), p_kind, left(btrim(p_role_title), 200), nullif(left(btrim(coalesce(p_organisation, '')), 200), ''), -- for them, with the kind, role and place,
            nullif(left(btrim(coalesce(p_details, '')), 1000), ''), p_paid, p_starts_on, p_ends_on) -- the details, paid, and dates
    returning id into v_id; -- keeps its id
    perform private.outside_work_tell_owner(auth.uid(), 'reported'); -- tells the owner
  else -- a change to one of their own:
    update public.outside_work_reports set kind = p_kind, role_title = left(btrim(p_role_title), 200), -- the new kind and role,
      organisation = nullif(left(btrim(coalesce(p_organisation, '')), 200), ''), details = nullif(left(btrim(coalesce(p_details, '')), 1000), ''), -- place and details,
      paid = p_paid, starts_on = p_starts_on, ends_on = p_ends_on, updated_at = now(), owner_seen_at = null -- paid, dates, and the owner needs to look again
    where id = p_id and account_id = auth.uid() -- only their own
    returning id into v_id; -- keeps its id
    if v_id is null then raise exception 'That report could not be found.' using errcode = 'P0002'; end if; -- not theirs, or not there
    perform private.outside_work_tell_owner(auth.uid(), 'changed'); -- tells the owner
  end if; -- end of the choice
  return v_id; -- hands back the report's id
end; -- end of the code
$$; -- end of the function
revoke all on function public.outside_work_save(uuid, text, text, text, text, boolean, date, date) from public, anon; -- not for signed-out visitors
grant execute on function public.outside_work_save(uuid, text, text, text, text, boolean, date, date) to authenticated; -- signed-in people (the check is inside)

create or replace function public.outside_work_end(p_id uuid, p_ends_on date) -- ends one of the person's own reports
returns void language plpgsql security definer -- writes the reports for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if p_ends_on is null then raise exception 'Please choose the date it ends.' using errcode = '22023'; end if; -- needs a date
  update public.outside_work_reports set ends_on = greatest(p_ends_on, starts_on), updated_at = now(), owner_seen_at = null -- ends it (never before it started), and the owner looks again
  where id = p_id and account_id = auth.uid(); -- only their own
  if not found then raise exception 'That report could not be found.' using errcode = 'P0002'; end if; -- not theirs, or not there
  perform private.outside_work_tell_owner(auth.uid(), 'ended'); -- tells the owner
end; -- end of the code
$$; -- end of the function
revoke all on function public.outside_work_end(uuid, date) from public, anon; -- not for signed-out visitors
grant execute on function public.outside_work_end(uuid, date) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- 3. The owner marks a report as seen, with a private note
-- ---------------------------------------------------------------------------
create or replace function public.outside_work_mark_seen(p_id uuid, p_note text default null) -- takes the report and a note
returns void language plpgsql security definer -- writes the reports for the owner; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_owner() then -- only CLG's owner
    raise exception 'Only CLG''s owner can mark work outside CLG as seen.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  update public.outside_work_reports set owner_seen_at = now(), owner_note = nullif(left(btrim(coalesce(p_note, '')), 1000), '') where id = p_id; -- marks it seen, with the note
  if not found then raise exception 'That report could not be found.' using errcode = 'P0002'; end if; -- not there
end; -- end of the code
$$; -- end of the function
revoke all on function public.outside_work_mark_seen(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.outside_work_mark_seen(uuid, text) to authenticated; -- signed-in people (the check is inside)
