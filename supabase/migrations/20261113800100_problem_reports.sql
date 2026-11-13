-- Problem reports (module: problem_reports). Carla, 12 Nov 2026.
--
-- "Need to make a spot where anyone can outline any problems with the app
-- ... it might be better if a particular person/s are required to check
-- this over - this also needs a place where a screenshot or multiple
-- screenshots can be provided as supporting evidence."
--
-- Anyone signed in can report a problem with the app: what went wrong, what
-- they were trying to do, and up to 6 screenshots. Screenshots sit in a
-- private file store ("problem-screenshots"), in a folder named with the
-- reporter's own account id.
--
-- Reports are checked by people, never fixed automatically. Who checks them
-- is the reviewer list the owner chooses. The owner always sees reports;
-- anyone else on the list must hold the admin role and use two-step login
-- (screenshots may show children's details). Reviewers move each report
-- through: New, Being checked, Approved to fix, Fixed, or Closed (no change).
--
-- Reporters see their own reports, where each is up to, and any reply. They
-- never see reviewers' private notes.
--
-- Keeping records small: screenshots are deleted 90 days after a report is
-- fixed or closed, and the report itself 2 years after that. The app's daily
-- job does the deleting, because files can only be deleted through the file
-- store itself.
--
-- This module writes only its own tables. See docs/features/problem-reports.md.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The private file store for screenshots: pictures only, up to 1 MB each
-- (the app shrinks screenshots before sending them).
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) -- adds the file store
values ( -- with these settings:
  'problem-screenshots', 'problem-screenshots', false, 1048576, -- its id and name, private, 1 MB per file
  array['image/jpeg', 'image/png', 'image/webp'] -- JPG, PNG and WebP pictures only
) -- end of the settings
on conflict (id) do nothing; -- leaves it alone if it's already there (so this file can run twice)

-- ---------------------------------------------------------------------------
-- The reviewer list: who checks problem reports (besides the owner).
-- ---------------------------------------------------------------------------
create table if not exists public.problem_reviewers ( -- one row per reviewer
  account_id uuid primary key references public.accounts (id) on delete cascade, -- the reviewer (gone if their account is deleted)
  added_by uuid references public.accounts (id) on delete set null, -- who put them on the list
  added_at timestamptz not null default now() -- when they were added
); -- end of problem_reviewers
alter table public.problem_reviewers enable row level security; -- turns on access rules for the list
revoke all on public.problem_reviewers from anon; -- people who aren't signed in get nothing
revoke insert, update, delete, truncate on public.problem_reviewers from authenticated; -- changes only go through the owner's functions below

-- ---------------------------------------------------------------------------
-- The reports themselves.
-- ---------------------------------------------------------------------------
create table if not exists public.problem_reports ( -- one row per report
  id uuid primary key default gen_random_uuid(), -- its id
  reported_by uuid references public.accounts (id) on delete set null, -- who reported it (empty if their account is later deleted)
  reporter_name text not null check (char_length(reporter_name) <= 200), -- their name when they reported it, so reviewers know who to reply to
  what_happened text not null check (char_length(what_happened) between 10 and 4000), -- what went wrong, in their words
  trying_to text check (char_length(trying_to) <= 1000), -- what they were trying to do (optional)
  page text check (char_length(page) <= 300), -- the page they were on, filled in by the app (optional)
  device text check (char_length(device) <= 400), -- their browser and device, filled in by the app (optional)
  status text not null default 'new' -- where the report is up to:
    check (status in ('new', 'checking', 'approved', 'fixed', 'closed')), -- new, being checked, approved to fix, fixed, closed with no change
  priority text not null default 'normal' -- how soon it needs attention:
    check (priority in ('urgent', 'normal', 'low')), -- urgent (e.g. privacy or money), normal, or low
  reply text check (char_length(reply) <= 2000), -- a reply the reporter can see (optional)
  replied_at timestamptz, -- when the reply was last changed
  reviewer_notes text check (char_length(reviewer_notes) <= 4000), -- private notes only reviewers see (optional)
  -- The fix written for the developer, with no names or personal details.
  -- Only this text (and the page, with ids taken out) goes to GitHub.
  fix_summary text check (char_length(fix_summary) <= 4000), -- (optional)
  github_issue_url text check (github_issue_url ~ '^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/issues/[0-9]+$'), -- the GitHub issue made from it, if any
  reviewed_by uuid references public.accounts (id) on delete set null, -- the reviewer who last changed it
  created_at timestamptz not null default now(), -- when it was reported
  updated_at timestamptz not null default now(), -- when a reviewer last changed it
  closed_at timestamptz -- when it was marked fixed or closed (empty while open)
); -- end of problem_reports
create index if not exists problem_reports_queue on public.problem_reports (status, created_at desc); -- quick queue: by status, newest first
create index if not exists problem_reports_reporter on public.problem_reports (reported_by, created_at desc); -- quick "your reports" list
alter table public.problem_reports enable row level security; -- turns on access rules for reports
revoke all on public.problem_reports from anon; -- people who aren't signed in get nothing
revoke insert, update, delete, truncate on public.problem_reports from authenticated; -- changes only go through the functions below

-- ---------------------------------------------------------------------------
-- Screenshots attached to a report.
-- ---------------------------------------------------------------------------
create table if not exists public.problem_report_screenshots ( -- one row per screenshot
  id uuid primary key default gen_random_uuid(), -- its id
  report_id uuid not null references public.problem_reports (id) on delete cascade, -- the report it belongs to (goes with it)
  file_path text not null unique -- where it's kept: the reporter's folder and a random name
    check (file_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f-]{36}\.(jpg|png|webp)$'), -- (only names the app makes)
  file_type text not null check (file_type in ('image/jpeg', 'image/png', 'image/webp')), -- the picture type
  added_at timestamptz not null default now() -- when it was added
); -- end of problem_report_screenshots
create index if not exists problem_report_screenshots_report on public.problem_report_screenshots (report_id); -- quick list of a report's screenshots
alter table public.problem_report_screenshots enable row level security; -- turns on access rules for screenshots
revoke all on public.problem_report_screenshots from anon; -- people who aren't signed in get nothing
revoke insert, update, delete, truncate on public.problem_report_screenshots from authenticated; -- changes only go through the functions below

-- Screenshot files waiting to be removed from the file store by the daily job.
create table if not exists public.problem_screenshot_removals ( -- one row per file to remove
  file_path text primary key, -- the file's path
  queued_at timestamptz not null default now() -- when it was queued
); -- end of problem_screenshot_removals
alter table public.problem_screenshot_removals enable row level security; -- turns on access rules (with no rules, nobody signed in can see it)
revoke all on public.problem_screenshot_removals from anon, authenticated; -- only the server's own role uses it

-- Every change to reports, screenshots and the reviewer list is logged.
drop trigger if exists audit on public.problem_reports; -- removes the old trigger (so this file can run twice)
create trigger audit after insert or update or delete on public.problem_reports -- logs each change to a report
  for each row execute function private.audit_change(); -- using the shared change log
drop trigger if exists audit on public.problem_report_screenshots; -- removes the old trigger
create trigger audit after insert or update or delete on public.problem_report_screenshots -- logs each change to a screenshot record
  for each row execute function private.audit_change(); -- using the shared change log
drop trigger if exists audit on public.problem_reviewers; -- removes the old trigger
create trigger audit after insert or update or delete on public.problem_reviewers -- logs who is added to or removed from the list
  for each row execute function private.audit_change(); -- using the shared change log

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- True if the signed-in person may check problem reports: the owner, or an
-- admin (with two-step login) on the reviewer list.
create or replace function private.is_problem_reviewer() -- no inputs: it asks about the signed-in person
returns boolean language sql stable security definer -- reads the list with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
  select private.is_owner() -- the owner always can,
      or (private.is_any_admin() -- or any admin (this also checks two-step login)
          and exists (select 1 from public.problem_reviewers r where r.account_id = auth.uid())) -- who is on the list
$$;
revoke execute on function private.is_problem_reviewer() from public; -- not for everyone by default
grant execute on function private.is_problem_reviewer() to authenticated, service_role; -- signed-in people and the server can ask

-- The account a screenshot file belongs to, from its folder name (null if
-- the name isn't an account folder).
create or replace function private.problem_folder_account(p_name text) -- takes a file path
returns uuid language sql immutable -- the answer only depends on the path
set search_path = '' -- no hidden schema lookups (safety)
as $$
  select case when split_part(p_name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -- if the first folder looks like an id
              then split_part(p_name, '/', 1)::uuid end -- gives it back as an id (otherwise null)
$$;

-- True if a screenshot file is attached to a report.
create or replace function private.problem_file_in_use(p_name text) -- takes a file path
returns boolean language sql stable security definer -- reads screenshots with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$ select exists (select 1 from public.problem_report_screenshots where file_path = p_name) $$; -- yes if any screenshot uses it
revoke execute on function private.problem_file_in_use(text) from public; -- not for everyone by default
grant execute on function private.problem_file_in_use(text) to authenticated, service_role; -- the file rules below need it

-- ---------------------------------------------------------------------------
-- Access rules
-- ---------------------------------------------------------------------------
drop policy if exists "reviewers see the reviewer list" on public.problem_reviewers; -- removes the old rule (so this file can run twice)
create policy "reviewers see the reviewer list" on public.problem_reviewers -- reviewers can see who else checks reports
  for select to authenticated using (private.is_problem_reviewer()); -- only reviewers

drop policy if exists "reviewers see problem reports" on public.problem_reports; -- removes the old rule
create policy "reviewers see problem reports" on public.problem_reports -- reviewers see every report, with private notes
  for select to authenticated using (private.is_problem_reviewer()); -- reporters use my_problem_reports() instead, which leaves the notes out

drop policy if exists "reviewers see screenshots" on public.problem_report_screenshots; -- removes the old rule
create policy "reviewers see screenshots" on public.problem_report_screenshots -- reviewers see every screenshot record
  for select to authenticated using (private.is_problem_reviewer()); -- only reviewers

-- Files: anyone signed in can upload into their own folder only.
drop policy if exists "problem screenshots: upload" on storage.objects; -- removes the old rule
create policy "problem screenshots: upload" on storage.objects -- uploading a screenshot
  for insert to authenticated -- for signed-in people
  with check ( -- allowed only when:
    bucket_id = 'problem-screenshots' -- it's this file store,
    and private.problem_folder_account(name) = auth.uid() -- and the folder is their own
  ); -- end of the rule
-- Reviewers open any screenshot; reporters open their own.
drop policy if exists "problem screenshots: open" on storage.objects; -- removes the old rule
create policy "problem screenshots: open" on storage.objects -- opening a screenshot
  for select to authenticated -- for signed-in people
  using ( -- allowed only when:
    bucket_id = 'problem-screenshots' -- it's this file store,
    and (private.problem_folder_account(name) = auth.uid() or private.is_problem_reviewer()) -- and it's their own, or they're a reviewer
  ); -- end of the rule
-- Reporters can remove their own file only if it isn't attached to a report
-- (an upload left behind when sending failed half way).
drop policy if exists "problem screenshots: remove unattached" on storage.objects; -- removes the old rule
create policy "problem screenshots: remove unattached" on storage.objects -- removing a screenshot file
  for delete to authenticated -- for signed-in people
  using ( -- allowed only when:
    bucket_id = 'problem-screenshots' -- it's this file store,
    and private.problem_folder_account(name) = auth.uid() -- the folder is their own,
    and not private.problem_file_in_use(name) -- and no report uses it
  ); -- end of the rule

-- ---------------------------------------------------------------------------
-- Sending a report (anyone signed in).
-- ---------------------------------------------------------------------------
create or replace function public.problem_report_submit( -- saves a new report with its screenshots
  p_what_happened text, -- what went wrong
  p_trying_to text, -- what they were trying to do (may be blank)
  p_page text, -- the page they were on (may be blank)
  p_device text, -- their browser and device (may be blank)
  p_screenshots jsonb -- a list of {"path": ..., "type": ...} for files already uploaded (may be empty)
) returns uuid language plpgsql security definer -- gives back the new report's id; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_me uuid := auth.uid(); -- the signed-in person
  v_what text := btrim(coalesce(p_what_happened, '')); -- what went wrong, without spaces at either end
  v_shots jsonb := coalesce(p_screenshots, '[]'::jsonb); -- the screenshot list (empty if none given)
  v_name text; -- the reporter's name
  v_id uuid; -- the new report's id
  v_shot jsonb; -- one screenshot from the list
  v_path text; -- that screenshot's path
  v_type text; -- that screenshot's picture type
begin
  if v_me is null then -- nobody signed in
    raise exception 'Please sign in to report a problem.' using errcode = '42501'; -- refuses
  end if;
  if char_length(v_what) < 10 then -- too short to be useful
    raise exception 'Please say what went wrong in a sentence or two.' using errcode = '23514'; -- asks for more
  end if;
  if char_length(v_what) > 4000 then -- too long
    raise exception 'Please keep "What went wrong" under 4,000 characters.' using errcode = '23514'; -- asks for less
  end if;
  if jsonb_typeof(v_shots) <> 'array' then -- the list isn't a list
    raise exception 'The screenshots didn''t come through. Please try again.' using errcode = '23514'; -- plain message
  end if;
  if jsonb_array_length(v_shots) > 6 then -- too many screenshots
    raise exception 'Please attach no more than 6 screenshots.' using errcode = '23514'; -- says the limit
  end if;
  -- Stops one person filling the queue by accident (or on purpose).
  if (select count(*) from public.problem_reports r -- counts their reports
      where r.reported_by = v_me and r.created_at > now() - interval '1 day') >= 10 then -- in the last 24 hours
    raise exception 'You''ve sent 10 reports today. Please try again tomorrow, or contact CLG directly.' using errcode = '23514'; -- says why
  end if;

  select a.full_name into v_name from public.accounts a where a.id = v_me; -- reads their name

  insert into public.problem_reports (reported_by, reporter_name, what_happened, trying_to, page, device) -- saves the report
  values ( -- with:
    v_me, -- the reporter,
    coalesce(left(v_name, 200), 'Unknown'), -- their name (cut to 200 characters),
    v_what, -- what went wrong,
    nullif(left(btrim(coalesce(p_trying_to, '')), 1000), ''), -- what they were trying to do (or nothing),
    nullif(left(btrim(coalesce(p_page, '')), 300), ''), -- the page (or nothing),
    nullif(left(btrim(coalesce(p_device, '')), 400), '') -- the device (or nothing)
  ) returning id into v_id; -- keeps the new id

  for v_shot in select value from jsonb_array_elements(v_shots) loop -- for each screenshot given
    v_path := v_shot ->> 'path'; -- its path
    v_type := v_shot ->> 'type'; -- its picture type
    if private.problem_folder_account(v_path) is distinct from v_me then -- not in their own folder
      raise exception 'That screenshot isn''t yours.' using errcode = '42501'; -- refuses
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'problem-screenshots' and o.name = v_path) then -- the file isn't there
      raise exception 'A screenshot didn''t upload. Please try again.' using errcode = '23514'; -- asks to try again
    end if;
    insert into public.problem_report_screenshots (report_id, file_path, file_type) -- attaches it to the report
    values (v_id, v_path, v_type); -- (the table's own checks refuse odd names and types)
  end loop; -- end of the screenshots

  return v_id; -- gives back the new report's id
end;
$$;
revoke execute on function public.problem_report_submit(text, text, text, text, jsonb) from public, anon; -- not for people who aren't signed in
grant execute on function public.problem_report_submit(text, text, text, text, jsonb) to authenticated; -- anyone signed in can send a report

-- ---------------------------------------------------------------------------
-- A reporter's own reports: where each is up to and any reply, without
-- reviewers' private notes.
-- ---------------------------------------------------------------------------
create or replace function public.my_problem_reports() -- no inputs: it lists the signed-in person's reports
returns table ( -- gives back one row per report:
  id uuid, -- its id
  created_at timestamptz, -- when it was sent
  what_happened text, -- what they wrote
  status text, -- where it's up to
  reply text, -- the reply (if any)
  replied_at timestamptz, -- when the reply was written
  screenshots integer -- how many screenshots it has
) language sql stable security definer -- reads with the owner's rights, but only their own rows (below)
set search_path = '' -- no hidden schema lookups (safety)
as $$
  select r.id, r.created_at, r.what_happened, r.status, r.reply, r.replied_at, -- the safe columns
         (select count(*)::integer from public.problem_report_screenshots s where s.report_id = r.id) -- and the screenshot count
  from public.problem_reports r -- from the reports
  where r.reported_by = auth.uid() -- only their own
  order by r.created_at desc -- newest first
  limit 50 -- the latest 50
$$;
revoke execute on function public.my_problem_reports() from public, anon; -- not for people who aren't signed in
grant execute on function public.my_problem_reports() to authenticated; -- anyone signed in can see their own

-- ---------------------------------------------------------------------------
-- Reviewers: change a report's status, priority, reply and notes.
-- ---------------------------------------------------------------------------
create or replace function public.problem_report_update( -- saves a reviewer's changes to one report
  p_id uuid, -- the report
  p_status text, -- its new status
  p_priority text, -- its priority
  p_reply text, -- the reply the reporter sees (may be blank)
  p_notes text, -- private reviewer notes (may be blank)
  p_fix_summary text -- the fix for the developer, with no personal details (may be blank)
) returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_old public.problem_reports; -- the report as it was
  v_reply text := nullif(btrim(coalesce(p_reply, '')), ''); -- the reply, tidied (blank means none)
begin
  if not private.is_problem_reviewer() then -- not a reviewer
    raise exception 'Only the people on the reviewer list can change problem reports.' using errcode = '42501'; -- refuses
  end if;
  if p_status is null or p_status not in ('new', 'checking', 'approved', 'fixed', 'closed') then -- an unknown status
    raise exception 'Choose a status.' using errcode = '23514'; -- asks for one
  end if;
  if p_priority is null or p_priority not in ('urgent', 'normal', 'low') then -- an unknown priority
    raise exception 'Choose a priority.' using errcode = '23514'; -- asks for one
  end if;
  select * into v_old from public.problem_reports where id = p_id for update; -- reads the report (and holds it while changing)
  if v_old.id is null then -- no such report
    raise exception 'That report wasn''t found.' using errcode = '23514'; -- says so
  end if;
  update public.problem_reports set -- saves the changes:
    status = p_status, -- the status,
    priority = p_priority, -- the priority,
    reply = v_reply, -- the reply,
    replied_at = case when v_reply is distinct from v_old.reply then (case when v_reply is null then null else now() end) else replied_at end, -- stamps the reply time when it changes
    reviewer_notes = nullif(btrim(coalesce(p_notes, '')), ''), -- the private notes,
    fix_summary = nullif(btrim(coalesce(p_fix_summary, '')), ''), -- the fix summary,
    reviewed_by = auth.uid(), -- who changed it,
    updated_at = now(), -- when,
    closed_at = case when p_status in ('fixed', 'closed') then coalesce(v_old.closed_at, now()) else null end -- when it was fixed or closed (cleared if reopened)
  where id = p_id; -- this report only
end;
$$;
revoke execute on function public.problem_report_update(uuid, text, text, text, text, text) from public, anon; -- not for people who aren't signed in
grant execute on function public.problem_report_update(uuid, text, text, text, text, text) to authenticated; -- the function checks who is a reviewer

-- The owner records the GitHub issue the app made from an approved report.
create or replace function public.problem_report_github_saved(p_id uuid, p_url text) -- takes the report and the issue's address
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not private.is_owner() then -- not the owner
    raise exception 'Only the owner can send reports to GitHub.' using errcode = '42501'; -- refuses
  end if;
  update public.problem_reports set -- saves:
    github_issue_url = p_url, -- the issue's address (the table checks it's a GitHub issue),
    reviewed_by = auth.uid(), -- who sent it,
    updated_at = now() -- and when
  where id = p_id; -- this report only
end;
$$;
revoke execute on function public.problem_report_github_saved(uuid, text) from public, anon; -- not for people who aren't signed in
grant execute on function public.problem_report_github_saved(uuid, text) to authenticated; -- the function checks for the owner

-- The owner deletes a report (for example, one with details that shouldn't
-- have been shared). Its screenshots go with it.
create or replace function public.problem_report_delete(p_id uuid) -- takes the report
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not private.is_owner() then -- not the owner
    raise exception 'Only the owner can delete problem reports.' using errcode = '42501'; -- refuses
  end if;
  delete from public.problem_reports where id = p_id; -- deletes it (screenshots follow, and their files are queued for removal)
end;
$$;
revoke execute on function public.problem_report_delete(uuid) from public, anon; -- not for people who aren't signed in
grant execute on function public.problem_report_delete(uuid) to authenticated; -- the function checks for the owner

-- ---------------------------------------------------------------------------
-- The owner chooses the reviewer list.
-- ---------------------------------------------------------------------------

-- Every admin, and whether they're on the list (for the owner's settings).
create or replace function public.problem_reviewer_choices() -- no inputs
returns table (account_id uuid, full_name text, level text, on_list boolean) -- each admin: id, name, level, on the list or not
language sql stable security definer -- reads accounts with the owner's rights, but only for the owner (below)
set search_path = '' -- no hidden schema lookups (safety)
as $$
  select a.id, a.full_name, ap.level::text, -- the admin's id, name and level
         exists (select 1 from public.problem_reviewers r where r.account_id = a.id) -- whether they're on the list
  from public.accounts a -- from accounts
  join public.account_roles ar on ar.account_id = a.id and ar.role::text = 'admin' -- who hold the admin role
  left join public.admin_profiles ap on ap.account_id = a.id -- with their level
  where private.is_owner() -- only the owner gets any rows
  order by a.full_name -- in name order
$$;
revoke execute on function public.problem_reviewer_choices() from public, anon; -- not for people who aren't signed in
grant execute on function public.problem_reviewer_choices() to authenticated; -- the function checks for the owner

-- Adds an admin to the reviewer list.
create or replace function public.problem_reviewer_add(p_account uuid) -- takes the admin's account
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not private.is_owner() then -- not the owner
    raise exception 'Only the owner can choose who checks problem reports.' using errcode = '42501'; -- refuses
  end if;
  if not exists (select 1 from public.account_roles r where r.account_id = p_account and r.role::text = 'admin') then -- not an admin
    raise exception 'Only admins can check problem reports, because screenshots may show children''s details.' using errcode = '23514'; -- explains why
  end if;
  insert into public.problem_reviewers (account_id, added_by) values (p_account, auth.uid()) -- adds them
  on conflict (account_id) do nothing; -- (already on the list is fine)
end;
$$;
revoke execute on function public.problem_reviewer_add(uuid) from public, anon; -- not for people who aren't signed in
grant execute on function public.problem_reviewer_add(uuid) to authenticated; -- the function checks for the owner

-- Takes someone off the reviewer list.
create or replace function public.problem_reviewer_remove(p_account uuid) -- takes the reviewer's account
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not private.is_owner() then -- not the owner
    raise exception 'Only the owner can choose who checks problem reports.' using errcode = '42501'; -- refuses
  end if;
  delete from public.problem_reviewers where account_id = p_account; -- removes them (nothing happens if they weren't on it)
end;
$$;
revoke execute on function public.problem_reviewer_remove(uuid) from public, anon; -- not for people who aren't signed in
grant execute on function public.problem_reviewer_remove(uuid) to authenticated; -- the function checks for the owner

-- ---------------------------------------------------------------------------
-- Removing files and old reports.
-- ---------------------------------------------------------------------------

-- When a screenshot record goes, its file is queued for the daily job.
create or replace function private.queue_problem_screenshot_removal() -- runs after a screenshot record is deleted
returns trigger language plpgsql security definer -- writes the queue with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  insert into public.problem_screenshot_removals (file_path) values (old.file_path) on conflict do nothing; -- queues the file (once)
  return old; -- carries on with the delete
end;
$$;
drop trigger if exists remove_file on public.problem_report_screenshots; -- removes the old trigger (so this file can run twice)
create trigger remove_file after delete on public.problem_report_screenshots -- after each screenshot record is deleted
  for each row execute function private.queue_problem_screenshot_removal(); -- queues its file

-- The daily tidy-up (server only): screenshots 90 days after a report is
-- fixed or closed, reports 2 years after that, and files left behind by a
-- report that never finished sending (over a day old).
create or replace function public.problem_reports_tidy() -- no inputs
returns integer language plpgsql security definer -- gives back how many records were removed
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_shots integer; -- screenshots removed
  v_reports integer; -- reports removed
begin
  delete from public.problem_report_screenshots s -- removes screenshot records
  using public.problem_reports r -- (looking at their reports)
  where s.report_id = r.id and r.closed_at < now() - interval '90 days'; -- of reports fixed or closed over 90 days ago
  get diagnostics v_shots = row_count; -- counts them

  delete from public.problem_reports where closed_at < now() - interval '2 years'; -- removes reports fixed or closed over 2 years ago
  get diagnostics v_reports = row_count; -- counts them

  insert into public.problem_screenshot_removals (file_path) -- queues leftover files:
  select o.name from storage.objects o -- files in the store
  where o.bucket_id = 'problem-screenshots' -- in this file store
    and o.created_at < now() - interval '1 day' -- over a day old
    and not exists (select 1 from public.problem_report_screenshots s where s.file_path = o.name) -- not attached to any report
  on conflict do nothing; -- (already queued is fine)

  return v_shots + v_reports; -- gives back how many records were removed
end;
$$;
revoke execute on function public.problem_reports_tidy() from public, anon, authenticated; -- nobody signed in can run it
grant execute on function public.problem_reports_tidy() to service_role; -- only the server's daily job

-- The files waiting to be removed (server only).
create or replace function public.problem_screenshots_to_remove() -- no inputs
returns text[] language sql stable security definer -- gives back a list of paths
set search_path = '' -- no hidden schema lookups (safety)
as $$ select coalesce(array_agg(file_path order by queued_at), '{}') from (select file_path, queued_at from public.problem_screenshot_removals order by queued_at limit 500) q $$; -- the oldest 500 paths
revoke execute on function public.problem_screenshots_to_remove() from public, anon, authenticated; -- nobody signed in can run it
grant execute on function public.problem_screenshots_to_remove() to service_role; -- only the server's daily job

-- Marks files as removed (server only).
create or replace function public.problem_screenshots_removed(p_paths text[]) -- takes the paths that were removed
returns void language sql security definer -- gives back nothing
set search_path = '' -- no hidden schema lookups (safety)
as $$ delete from public.problem_screenshot_removals where file_path = any (p_paths) $$; -- clears them from the queue
revoke execute on function public.problem_screenshots_removed(text[]) from public, anon, authenticated; -- nobody signed in can run it
grant execute on function public.problem_screenshots_removed(text[]) to service_role; -- only the server's daily job
