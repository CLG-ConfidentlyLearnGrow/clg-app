-- Summary: "What's new" pop-up for each dashboard (Carla, 15 Nov 2026).
--
-- After an app update, each person sees a short pop-up listing only what was
-- added, updated or removed in their own part of the app. Someone with more
-- than one role (say admin and tutor) sees the admin changes on the admin
-- dashboard and the tutor changes on the tutor dashboard, each once.
--
-- How it works:
--   * full admins (owner and operations, with two-step sign-in) write an
--     update: a title plus a list of changes, each marked New, Updated or
--     Removed and tagged with the dashboards it applies to;
--   * they publish it now, or choose a day for it to start showing (so the
--     30 Nov 2026 welcome for trial families can be written ahead);
--   * once published, the changes can't be edited (people may have read
--     them). To fix one, take the update back to a draft, fix it and publish
--     again, and everyone sees it fresh;
--   * each person's dashboard remembers when they last closed the pop-up, so
--     it only shows updates they haven't seen. Updates from before they got
--     a role are skipped, so new families aren't greeted by old news.
--
-- Privacy: updates hold no personal details. The only thing kept about a
-- person is the time they last closed the pop-up on each dashboard, which is
-- deleted with their account. Parents and students can't see admin or tutor
-- changes; the database enforces that.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The updates
-- ---------------------------------------------------------------------------

-- One row per update (a group of changes released together).
create table if not exists public.whats_new_notes ( -- one row per update
  id uuid primary key default gen_random_uuid(), -- its id
  title text not null check (char_length(title) between 2 and 120), -- a short heading, e.g. "Booking is quicker"
  status text not null default 'draft' check (status in ('draft', 'published')), -- still being written, or out
  show_from timestamptz, -- when it starts showing (set when it's published)
  created_by uuid references public.accounts (id) on delete set null, -- the admin who started it
  published_by uuid references public.accounts (id) on delete set null, -- the admin who published it
  created_at timestamptz not null default now(), -- when it was started
  updated_at timestamptz not null default now(), -- when it last changed
  check (status = 'draft' or show_from is not null) -- a published update always has a start time
); -- end of the table
create index if not exists whats_new_notes_live on public.whats_new_notes (show_from desc) where status = 'published'; -- finds the newest published updates quickly
alter table public.whats_new_notes enable row level security; -- turns on access rules
revoke all on public.whats_new_notes from anon, authenticated; -- no direct changes: everything goes through the functions below
grant select on public.whats_new_notes to authenticated; -- signed-in people may read, but only the rows the rules below allow

-- One row per change inside an update.
create table if not exists public.whats_new_items ( -- one row per change
  id uuid primary key default gen_random_uuid(), -- its id
  note_id uuid not null references public.whats_new_notes (id) on delete cascade, -- the update it belongs to (removed with it)
  kind text not null check (kind in ('added', 'updated', 'removed')), -- New, Updated or Removed
  roles public.app_role[] not null check (cardinality(roles) between 1 and 4), -- the dashboards it applies to (at least one)
  body text not null check (char_length(body) between 3 and 500), -- what changed, in a sentence or two
  sort smallint not null default 100, -- where it sits in the list (smaller first)
  created_at timestamptz not null default now() -- when it was written
); -- end of the table
create index if not exists whats_new_items_note on public.whats_new_items (note_id, sort); -- finds an update's changes quickly
alter table public.whats_new_items enable row level security; -- turns on access rules
revoke all on public.whats_new_items from anon, authenticated; -- no direct changes: everything goes through the functions below
grant select on public.whats_new_items to authenticated; -- signed-in people may read, but only the rows the rules below allow

-- When each person last closed the pop-up, per dashboard.
create table if not exists public.whats_new_seen ( -- one row per person per dashboard
  account_id uuid not null references public.accounts (id) on delete cascade, -- the person (removed with their account)
  role public.app_role not null, -- which dashboard
  seen_up_to timestamptz not null default now(), -- when they last closed it there
  primary key (account_id, role) -- one row each
); -- end of the table
alter table public.whats_new_seen enable row level security; -- turns on access rules
revoke all on public.whats_new_seen from anon, authenticated; -- changed only through whats_new_mark_seen()
grant select on public.whats_new_seen to authenticated; -- people may read their own (rule below)

-- ---------------------------------------------------------------------------
-- Helpers (they read past the access rules, so the rules don't loop)
-- ---------------------------------------------------------------------------

-- True when an update is out: published, and its start time has passed.
create or replace function private.whats_new_note_live(p_note uuid) -- takes the update
returns boolean -- gives back yes or no
language sql stable security definer -- reads the update directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- is there
    select 1 from public.whats_new_notes n -- an update
    where n.id = p_note and n.status = 'published' and n.show_from <= now() -- with this id that is out?
  ) -- end of the check
$$; -- end of the function
revoke all on function private.whats_new_note_live(uuid) from public; -- not for everyone by default
grant execute on function private.whats_new_note_live(uuid) to authenticated; -- the access rules run as the signed-in person, so they need it

-- True when the signed-in person holds at least one of the given roles.
create or replace function private.holds_any_role(p_roles public.app_role[]) -- takes a list of roles
returns boolean -- gives back yes or no
language sql stable security definer -- reads the roles list directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- is there
    select 1 from public.account_roles r -- a role
    where r.account_id = auth.uid() and r.role = any(p_roles) -- held by this person that is in the list?
  ) -- end of the check
$$; -- end of the function
revoke all on function private.holds_any_role(public.app_role[]) from public; -- not for everyone by default
grant execute on function private.holds_any_role(public.app_role[]) to authenticated; -- the access rules need it

-- True when the signed-in person can see at least one change in an update.
create or replace function private.whats_new_note_for_me(p_note uuid) -- takes the update
returns boolean -- gives back yes or no
language sql stable security definer -- reads the changes directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select private.whats_new_note_live(p_note) -- the update is out,
    and exists ( -- and there is
      select 1 from public.whats_new_items i -- a change in it
      where i.note_id = p_note and private.holds_any_role(i.roles) -- for one of their dashboards
    ) -- end of the check
$$; -- end of the function
revoke all on function private.whats_new_note_for_me(uuid) from public; -- not for everyone by default
grant execute on function private.whats_new_note_for_me(uuid) to authenticated; -- the access rules need it

-- ---------------------------------------------------------------------------
-- Access rules
-- ---------------------------------------------------------------------------

-- Full admins see every update, drafts included. Everyone else sees an update
-- only once it's out and has a change for one of their dashboards.
drop policy if exists "read updates" on public.whats_new_notes; -- removes the old rule if the file is run again
create policy "read updates" on public.whats_new_notes -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (private.is_admin() or private.whats_new_note_for_me(id)); -- full admins, or people it's for

-- Full admins see every change. Everyone else sees only changes that are out
-- and tagged with one of their dashboards (a parent never sees admin changes).
drop policy if exists "read changes" on public.whats_new_items; -- removes the old rule if the file is run again
create policy "read changes" on public.whats_new_items -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (private.is_admin() or (private.whats_new_note_live(note_id) and private.holds_any_role(roles))); -- full admins, or people it's for once it's out

-- People see only their own "last closed" times.
drop policy if exists "read own seen times" on public.whats_new_seen; -- removes the old rule if the file is run again
create policy "read own seen times" on public.whats_new_seen -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (account_id = auth.uid()); -- only their own rows

-- ---------------------------------------------------------------------------
-- Reading updates (everyone)
-- ---------------------------------------------------------------------------

-- The changes for one of the signed-in person's dashboards, newest update
-- first. With p_unseen_only, only updates they haven't closed yet, and none
-- from before they got that role (that's the pop-up). Without it, every
-- update for that dashboard (that's the "What's new" page). Runs as the
-- signed-in person, so the access rules above still apply.
create or replace function public.whats_new_for_me(p_role public.app_role, p_unseen_only boolean default true) -- takes the dashboard and which updates
returns table (note_id uuid, title text, show_from timestamptz, item_id uuid, kind text, body text) -- one row per change
language sql stable security invoker -- runs as the signed-in person (the access rules apply)
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select n.id, n.title, n.show_from, i.id, i.kind, i.body -- the update and the change
  from public.whats_new_notes n -- from the updates
  join public.whats_new_items i on i.note_id = n.id -- with their changes
  join public.account_roles r on r.account_id = auth.uid() and r.role = p_role -- only if they hold this role (and when they got it)
  left join public.whats_new_seen s on s.account_id = auth.uid() and s.role = p_role -- when they last closed the pop-up here (if ever)
  where n.status = 'published' -- published updates,
    and n.show_from <= now() -- that have started showing,
    and p_role = any(i.roles) -- changes for this dashboard,
    and (not coalesce(p_unseen_only, true) -- and, for the pop-up only:
      or (n.show_from > r.granted_at -- released after they got the role,
        and n.show_from > coalesce(s.seen_up_to, '-infinity'::timestamptz))) -- and not yet seen
  order by n.show_from desc, i.sort, i.created_at -- newest update first, changes in order
  limit 300 -- plenty for a page
$$; -- end of the function
revoke all on function public.whats_new_for_me(public.app_role, boolean) from public, anon; -- not for signed-out visitors
grant execute on function public.whats_new_for_me(public.app_role, boolean) to authenticated; -- signed-in people

-- Notes that the signed-in person has closed the pop-up on one dashboard.
create or replace function public.whats_new_mark_seen(p_role public.app_role) -- takes the dashboard
returns void -- gives nothing back
language plpgsql security definer -- writes to a table people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if auth.uid() is null or not private.has_role(p_role) then -- not signed in, or not their dashboard
    raise exception 'You can only close updates for your own dashboards.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  insert into public.whats_new_seen (account_id, role, seen_up_to) -- saves the time,
  values (auth.uid(), p_role, now()) -- for this person and dashboard,
  on conflict (account_id, role) do update set seen_up_to = excluded.seen_up_to; -- or moves it on if they've closed it before
end; -- ends the code
$$; -- end of the function
revoke all on function public.whats_new_mark_seen(public.app_role) from public, anon; -- not for signed-out visitors
grant execute on function public.whats_new_mark_seen(public.app_role) to authenticated; -- signed-in people

-- ---------------------------------------------------------------------------
-- Writing updates (full admins: owner and operations, two-step sign-in)
-- ---------------------------------------------------------------------------

-- Stops with a plain message unless the signed-in person is a full admin.
create or replace function private.whats_new_require_admin() -- no inputs
returns void -- gives nothing back
language plpgsql stable security definer -- uses the admin check
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if not private.is_admin() then -- not owner or operations with two-step sign-in
    raise exception 'Only the owner and operations admins can write "What''s new" updates (with two-step sign-in).' using errcode = '42501'; -- plain message
  end if; -- end of the check
end; -- ends the code
$$; -- end of the function
revoke all on function private.whats_new_require_admin() from public; -- not for everyone by default
grant execute on function private.whats_new_require_admin() to authenticated; -- the functions below run it

-- Stops with a plain message unless the update exists and is still a draft.
create or replace function private.whats_new_require_draft(p_note uuid) -- takes the update
returns void -- gives nothing back
language plpgsql stable security definer -- reads the update directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_status text; -- the update's status
begin -- starts the code
  select status into v_status from public.whats_new_notes where id = p_note; -- finds it
  if v_status is null then -- not there
    raise exception 'That update can''t be found. It may have been deleted.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if v_status <> 'draft' then -- already out
    raise exception 'This update is published. Take it back to a draft to change it.' using errcode = '22023'; -- plain message
  end if; -- end of the check
end; -- ends the code
$$; -- end of the function
revoke all on function private.whats_new_require_draft(uuid) from public; -- not for everyone by default
grant execute on function private.whats_new_require_draft(uuid) to authenticated; -- the functions below run it

-- Starts a new draft update (no id given), or renames a draft.
create or replace function public.whats_new_save_note(p_id uuid, p_title text) -- takes the update (empty for a new one) and its title
returns uuid -- gives back the update's id
language plpgsql security definer -- writes to a table people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_id uuid := p_id; -- the update's id
begin -- starts the code
  perform private.whats_new_require_admin(); -- full admins only
  if char_length(btrim(coalesce(p_title, ''))) < 2 then -- no title
    raise exception 'Please give the update a short title.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if v_id is null then -- a new update:
    insert into public.whats_new_notes (title, created_by) -- adds it,
    values (left(btrim(p_title), 120), auth.uid()) -- with its title and who started it,
    returning id into v_id; -- and keeps its id
  else -- renaming one:
    perform private.whats_new_require_draft(v_id); -- only while it's a draft
    update public.whats_new_notes set title = left(btrim(p_title), 120), updated_at = now() where id = v_id; -- saves the new title
  end if; -- end of the choice
  return v_id; -- hands back the id
end; -- ends the code
$$; -- end of the function
revoke all on function public.whats_new_save_note(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.whats_new_save_note(uuid, text) to authenticated; -- signed-in people can try (the admin check is inside)

-- Adds a change to a draft update (no id given), or edits one.
create or replace function public.whats_new_save_item( -- the inputs:
  p_note uuid, -- the update it belongs to
  p_id uuid, -- the change (empty for a new one)
  p_kind text, -- added, updated or removed
  p_roles text[], -- the dashboards it applies to
  p_body text, -- what changed
  p_sort smallint default null -- where it sits (optional)
) -- end of the inputs
returns uuid -- gives back the change's id
language plpgsql security definer -- writes to a table people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_id uuid := p_id; -- the change's id
  v_roles public.app_role[]; -- the dashboards, checked
begin -- starts the code
  perform private.whats_new_require_admin(); -- full admins only
  perform private.whats_new_require_draft(p_note); -- only while the update is a draft
  if coalesce(p_kind, '') not in ('added', 'updated', 'removed') then -- no kind chosen
    raise exception 'Please choose New, Updated or Removed.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if exists (select 1 from unnest(coalesce(p_roles, '{}')) r where r not in ('admin', 'tutor', 'parent', 'student')) then -- a dashboard that doesn't exist
    raise exception 'Please choose dashboards from the list.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select array_agg(distinct r::public.app_role) into v_roles from unnest(coalesce(p_roles, '{}')) r; -- the chosen dashboards, each once
  if coalesce(cardinality(v_roles), 0) = 0 then -- none chosen
    raise exception 'Please choose at least one dashboard this change is for.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_body, ''))) < 3 then -- nothing written
    raise exception 'Please say what changed.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if char_length(btrim(p_body)) > 500 then -- too long for a pop-up
    raise exception 'Please keep each change under 500 characters. Short is better in a pop-up.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if v_id is null then -- a new change:
    insert into public.whats_new_items (note_id, kind, roles, body, sort) -- adds it,
    values (p_note, p_kind, v_roles, btrim(p_body), -- with its details,
      coalesce(p_sort, (select coalesce(max(sort), 0) + 10 from public.whats_new_items where note_id = p_note))) -- at the end of the list unless a place is given
    returning id into v_id; -- and keeps its id
  else -- editing one:
    update public.whats_new_items -- saves the change,
    set kind = p_kind, roles = v_roles, body = btrim(p_body), sort = coalesce(p_sort, sort) -- with its new details,
    where id = v_id and note_id = p_note; -- only if it belongs to this update
    if not found then -- it doesn't
      raise exception 'That change can''t be found in this update.' using errcode = '22023'; -- plain message
    end if; -- end of the check
  end if; -- end of the choice
  update public.whats_new_notes set updated_at = now() where id = p_note; -- notes the update changed
  return v_id; -- hands back the id
end; -- ends the code
$$; -- end of the function
revoke all on function public.whats_new_save_item(uuid, uuid, text, text[], text, smallint) from public, anon; -- not for signed-out visitors
grant execute on function public.whats_new_save_item(uuid, uuid, text, text[], text, smallint) to authenticated; -- signed-in people can try (the admin check is inside)

-- Removes a change from a draft update.
create or replace function public.whats_new_delete_item(p_id uuid) -- takes the change
returns void -- gives nothing back
language plpgsql security definer -- writes to a table people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_note uuid; -- the update it's in
begin -- starts the code
  perform private.whats_new_require_admin(); -- full admins only
  select note_id into v_note from public.whats_new_items where id = p_id; -- finds its update
  if v_note is null then -- not there
    raise exception 'That change can''t be found. It may already be removed.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  perform private.whats_new_require_draft(v_note); -- only while the update is a draft
  delete from public.whats_new_items where id = p_id; -- removes it
  update public.whats_new_notes set updated_at = now() where id = v_note; -- notes the update changed
end; -- ends the code
$$; -- end of the function
revoke all on function public.whats_new_delete_item(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.whats_new_delete_item(uuid) to authenticated; -- signed-in people can try (the admin check is inside)

-- Deletes a draft update and its changes (published ones must be taken back first).
create or replace function public.whats_new_delete_note(p_id uuid) -- takes the update
returns void -- gives nothing back
language plpgsql security definer -- writes to a table people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  perform private.whats_new_require_admin(); -- full admins only
  perform private.whats_new_require_draft(p_id); -- only drafts
  delete from public.whats_new_notes where id = p_id; -- removes it (its changes go with it)
  perform private.log_event('whats_new_delete', 'whats_new_notes', p_id::text, '{}'); -- notes it in the activity log
end; -- ends the code
$$; -- end of the function
revoke all on function public.whats_new_delete_note(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.whats_new_delete_note(uuid) to authenticated; -- signed-in people can try (the admin check is inside)

-- Publishes a draft. With no day given (or today, or a past day) it shows
-- straight away; with a later day it starts showing at the start of that day,
-- Adelaide time.
create or replace function public.whats_new_publish(p_id uuid, p_show_on date default null) -- takes the update and the optional start day
returns timestamptz -- gives back when it starts showing
language plpgsql security definer -- writes to a table people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_from timestamptz; -- when it starts showing
begin -- starts the code
  perform private.whats_new_require_admin(); -- full admins only
  perform private.whats_new_require_draft(p_id); -- only drafts
  if not exists (select 1 from public.whats_new_items where note_id = p_id) then -- nothing in it
    raise exception 'Please add at least one change before publishing.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_from := greatest(now(), coalesce((p_show_on::timestamp at time zone 'Australia/Adelaide'), now())); -- the start of that day in Adelaide, but never earlier than now
  if v_from > now() + interval '1 year' then -- too far ahead (probably a typo)
    raise exception 'Please choose a day within the next year.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.whats_new_notes -- publishes it:
  set status = 'published', show_from = v_from, published_by = auth.uid(), updated_at = now() -- out, from that time, by this admin
  where id = p_id; -- this update
  perform private.log_event('whats_new_publish', 'whats_new_notes', p_id::text, jsonb_build_object('show_from', v_from)); -- notes it in the activity log
  return v_from; -- hands back the start time
end; -- ends the code
$$; -- end of the function
revoke all on function public.whats_new_publish(uuid, date) from public, anon; -- not for signed-out visitors
grant execute on function public.whats_new_publish(uuid, date) to authenticated; -- signed-in people can try (the admin check is inside)

-- Takes a published update back to a draft, so it stops showing and can be fixed.
create or replace function public.whats_new_unpublish(p_id uuid) -- takes the update
returns void -- gives nothing back
language plpgsql security definer -- writes to a table people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  perform private.whats_new_require_admin(); -- full admins only
  update public.whats_new_notes -- takes it back:
  set status = 'draft', show_from = null, updated_at = now() -- a draft again, with no start time
  where id = p_id and status = 'published'; -- only if it's published
  if not found then -- it wasn't
    raise exception 'That update isn''t published.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  perform private.log_event('whats_new_unpublish', 'whats_new_notes', p_id::text, '{}'); -- notes it in the activity log
end; -- ends the code
$$; -- end of the function
revoke all on function public.whats_new_unpublish(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.whats_new_unpublish(uuid) to authenticated; -- signed-in people can try (the admin check is inside)
