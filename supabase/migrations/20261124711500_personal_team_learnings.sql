-- Summary: personal and team learnings (Carla, 22 Nov 2026).
--
-- Carla: "Anyone can add to personal learnings, then team learnings are
-- adapted from personal learnings when approved by either myself or Emma."
-- From the How We Do Things guide: staff note what they learn, and the best
-- lessons are shared with the whole team.
--
-- What this adds (module: staff, which owns staff records outside pay):
--   * public.learnings: each learning is "personal" (written by a tutor or
--     admin staff member, for themselves) or "team" (shared with all staff).
--   * A personal learning is private to the person who wrote it until they
--     choose "Suggest for the team". Then CLG's owner and Operations admins
--     (Carla and Emma) see it.
--   * An approver adapts a suggested learning into a team learning (their
--     own wording, linked to where it came from), or declines it with a
--     note. Team learnings are seen by every tutor and admin.
--
-- Safe to run more than once. Run after 20261124710800_policy_versions_read_again.sql.

-- ---------------------------------------------------------------------------
-- 1. The learnings
-- ---------------------------------------------------------------------------
create table if not exists public.learnings ( -- one row per learning
  id uuid primary key default gen_random_uuid(), -- the learning's id
  kind text not null check (kind in ('personal', 'team')), -- personal or team
  author_id uuid references public.accounts (id) on delete cascade, -- who wrote it (removed with their account)
  title text not null check (char_length(btrim(title)) between 3 and 200), -- a short title
  body text not null check (char_length(btrim(body)) between 2 and 3000), -- the learning itself
  review_status text not null default 'none' check (review_status in ('none', 'suggested', 'adopted', 'declined')), -- for a personal one: not suggested, suggested, made into a team learning, or declined
  suggested_at timestamptz, -- when it was suggested for the team
  review_note text check (char_length(review_note) <= 1000), -- the approver's note (for a decline)
  reviewed_by uuid references public.accounts (id) on delete set null, -- who adopted or declined it
  reviewed_at timestamptz, -- when
  source_id uuid references public.learnings (id) on delete set null, -- for a team one: the personal learning it was adapted from
  created_at timestamptz not null default now(), -- when it was written
  updated_at timestamptz not null default now() -- when it last changed
); -- end of the table
create index if not exists learnings_author on public.learnings (author_id, created_at desc); -- finds a person's learnings quickly
create index if not exists learnings_team on public.learnings (created_at desc) where kind = 'team'; -- lists team learnings quickly
alter table public.learnings enable row level security; -- access rules apply
revoke all on public.learnings from anon; -- signed-out visitors get nothing
revoke insert, update, delete, truncate on public.learnings from authenticated; -- changes only through the functions below
grant select on public.learnings to authenticated; -- reading, limited by the rule below
drop trigger if exists audit on public.learnings; -- replaces the change log trigger if run again
create trigger audit after insert or update or delete on public.learnings -- logs every change
  for each row execute function private.audit_change(); -- in the shared change log
drop policy if exists "see learnings" on public.learnings; -- replaces the rule if run again
create policy "see learnings" on public.learnings -- who can read a row:
  for select to authenticated -- signed-in people
  using ( -- one of:
    (kind = 'team' and ((select private.has_role('tutor')) or (select private.has_role('admin')))) -- team learnings: every tutor and admin,
    or author_id = (select auth.uid()) -- their own personal learnings,
    or (kind = 'personal' and review_status <> 'none' and (select private.is_admin())) -- suggested ones (and their outcome): the owner and Operations admins
  ); -- end of the rule

-- Is the signed-in person staff (a tutor or admin)?
create or replace function private.is_staff() -- no inputs
returns boolean language sql stable security definer -- reads their roles
set search_path = '' -- no hidden schema lookups (safety)
as $$ select private.has_role('tutor') or private.has_role('admin') $$; -- a tutor or an admin
revoke all on function private.is_staff() from public; -- inside use only

-- ---------------------------------------------------------------------------
-- 2. Personal learnings: write, change, remove, suggest (any staff member)
-- ---------------------------------------------------------------------------
create or replace function public.learning_save(p_id uuid, p_title text, p_body text) -- adds a personal learning, or changes one of their own
returns uuid language plpgsql security definer -- writes for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_id uuid; -- the learning's id
begin -- start
  if not private.is_staff() then raise exception 'Only CLG tutors and admin staff add learnings.' using errcode = '42501'; end if; -- staff only
  if char_length(btrim(coalesce(p_title, ''))) < 3 or char_length(btrim(coalesce(p_body, ''))) < 2 then -- missing words
    raise exception 'Please give the learning a short title and write what you learned.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_id is null then -- a new one:
    insert into public.learnings (kind, author_id, title, body) values ('personal', auth.uid(), left(btrim(p_title), 200), left(btrim(p_body), 3000)) returning id into v_id; -- adds it, as personal
  else -- a change to one of their own (not once it has been adopted):
    update public.learnings set title = left(btrim(p_title), 200), body = left(btrim(p_body), 3000), updated_at = now() -- the new words
    where id = p_id and author_id = auth.uid() and kind = 'personal' and review_status <> 'adopted' returning id into v_id; -- only their own, still open
    if v_id is null then raise exception 'That learning could not be changed.' using errcode = 'P0002'; end if; -- not theirs, or already adopted
  end if; -- end of the choice
  return v_id; -- hands back its id
end; -- end of the code
$$; -- end of the function
revoke all on function public.learning_save(uuid, text, text) from public, anon; -- not for signed-out visitors
grant execute on function public.learning_save(uuid, text, text) to authenticated; -- signed-in people (the check is inside)

create or replace function public.learning_remove(p_id uuid) -- removes one of their own personal learnings
returns void language plpgsql security definer -- writes for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  delete from public.learnings where id = p_id and author_id = auth.uid() and kind = 'personal'; -- only their own personal ones (a team learning made from it stays)
  if not found then raise exception 'That learning could not be found.' using errcode = 'P0002'; end if; -- not theirs, or not there
end; -- end of the code
$$; -- end of the function
revoke all on function public.learning_remove(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.learning_remove(uuid) to authenticated; -- signed-in people (the check is inside)

create or replace function public.learning_suggest(p_id uuid) -- suggests one of their own for the team
returns void language plpgsql security definer -- writes for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_title text; -- the learning's title
begin -- start
  update public.learnings set review_status = 'suggested', suggested_at = now(), review_note = null, reviewed_by = null, reviewed_at = null -- suggests it (again, if declined before)
  where id = p_id and author_id = auth.uid() and kind = 'personal' and review_status in ('none', 'declined') returning title into v_title; -- only their own, not already suggested or adopted
  if v_title is null then raise exception 'That learning could not be suggested.' using errcode = 'P0002'; end if; -- not theirs, or already suggested
  perform private.notify_admins('Learning suggested for the team', -- tells the owner and Operations admins:
    left(coalesce((select full_name from public.accounts where id = auth.uid()), 'A staff member') || ' suggested "' || v_title || '" for the team learnings. See Learnings > Suggested for the team.', 1000), null); -- who, what and where
end; -- end of the code
$$; -- end of the function
revoke all on function public.learning_suggest(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.learning_suggest(uuid) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- 3. Team learnings: adapt, decline, change, remove (owner and Operations)
-- ---------------------------------------------------------------------------
create or replace function public.learning_adopt(p_source uuid, p_title text, p_body text) -- makes a team learning from a suggested one (or a new one with no source)
returns uuid language plpgsql security definer -- writes for the approver; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_id uuid; -- the team learning's id
  v_author uuid; -- who wrote the suggested one
begin -- start
  if not private.is_admin() then raise exception 'Only CLG''s owner or Operations admins approve team learnings.' using errcode = '42501'; end if; -- approvers only
  if char_length(btrim(coalesce(p_title, ''))) < 3 or char_length(btrim(coalesce(p_body, ''))) < 2 then -- missing words
    raise exception 'Please give the team learning a short title and its wording.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_source is not null then -- adapted from a suggested one:
    update public.learnings set review_status = 'adopted', reviewed_by = auth.uid(), reviewed_at = now() -- marks it adopted
    where id = p_source and kind = 'personal' and review_status = 'suggested' returning author_id into v_author; -- only a suggested personal one
    if not found then raise exception 'That suggestion could not be found.' using errcode = 'P0002'; end if; -- not there, or already answered
  end if; -- end of the source
  insert into public.learnings (kind, author_id, title, body, source_id) values ('team', auth.uid(), left(btrim(p_title), 200), left(btrim(p_body), 3000), p_source) returning id into v_id; -- adds the team learning
  if v_author is not null and v_author <> auth.uid() then -- tells the person who suggested it:
    perform private.add_notice(v_author, null, null, 'staff_alert', 'Your learning is now a team learning', 'Thank you. A learning you suggested has been added to the team learnings, in Learnings.', now()); -- a thank you
  end if; -- end of the thank you
  return v_id; -- hands back its id
end; -- end of the code
$$; -- end of the function
revoke all on function public.learning_adopt(uuid, text, text) from public, anon; -- not for signed-out visitors
grant execute on function public.learning_adopt(uuid, text, text) to authenticated; -- signed-in people (the check is inside)

create or replace function public.learning_decline(p_source uuid, p_note text) -- declines a suggested learning, with a note
returns void language plpgsql security definer -- writes for the approver; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_author uuid; -- who wrote it
begin -- start
  if not private.is_admin() then raise exception 'Only CLG''s owner or Operations admins approve team learnings.' using errcode = '42501'; end if; -- approvers only
  update public.learnings set review_status = 'declined', review_note = nullif(left(btrim(coalesce(p_note, '')), 1000), ''), reviewed_by = auth.uid(), reviewed_at = now() -- declines it, with the note
  where id = p_source and kind = 'personal' and review_status = 'suggested' returning author_id into v_author; -- only a suggested one
  if not found then raise exception 'That suggestion could not be found.' using errcode = 'P0002'; end if; -- not there, or already answered
  perform private.add_notice(v_author, null, null, 'staff_alert', 'About your suggested learning', 'Thank you for suggesting a learning. It stays in your own learnings for now. See the note in Learnings.', now()); -- tells them kindly
end; -- end of the code
$$; -- end of the function
revoke all on function public.learning_decline(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.learning_decline(uuid, text) to authenticated; -- signed-in people (the check is inside)

create or replace function public.team_learning_save(p_id uuid, p_title text, p_body text) -- changes a team learning
returns void language plpgsql security definer -- writes for the approver; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_admin() then raise exception 'Only CLG''s owner or Operations admins change team learnings.' using errcode = '42501'; end if; -- approvers only
  if char_length(btrim(coalesce(p_title, ''))) < 3 or char_length(btrim(coalesce(p_body, ''))) < 2 then -- missing words
    raise exception 'Please give the team learning a short title and its wording.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.learnings set title = left(btrim(p_title), 200), body = left(btrim(p_body), 3000), updated_at = now() where id = p_id and kind = 'team'; -- the new words
  if not found then raise exception 'That team learning could not be found.' using errcode = 'P0002'; end if; -- not there
end; -- end of the code
$$; -- end of the function
revoke all on function public.team_learning_save(uuid, text, text) from public, anon; -- not for signed-out visitors
grant execute on function public.team_learning_save(uuid, text, text) to authenticated; -- signed-in people (the check is inside)

create or replace function public.team_learning_remove(p_id uuid) -- removes a team learning
returns void language plpgsql security definer -- writes for the approver; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_admin() then raise exception 'Only CLG''s owner or Operations admins change team learnings.' using errcode = '42501'; end if; -- approvers only
  delete from public.learnings where id = p_id and kind = 'team'; -- removes it
  if not found then raise exception 'That team learning could not be found.' using errcode = 'P0002'; end if; -- not there
end; -- end of the code
$$; -- end of the function
revoke all on function public.team_learning_remove(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.team_learning_remove(uuid) to authenticated; -- signed-in people (the check is inside)

-- How many suggestions wait for an approver (the menu number; zero for anyone else).
create or replace function public.learnings_waiting_count() -- no inputs
returns integer language sql stable security definer -- counts for approvers
set search_path = '' -- no hidden schema lookups (safety)
as $$ select case when private.is_admin() then (select count(*)::integer from public.learnings where kind = 'personal' and review_status = 'suggested') else 0 end $$; -- the suggestions waiting, or none
revoke all on function public.learnings_waiting_count() from public, anon; -- not for signed-out visitors
grant execute on function public.learnings_waiting_count() to authenticated; -- signed-in people (the check is inside)
