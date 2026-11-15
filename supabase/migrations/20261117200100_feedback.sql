-- Summary: feedback from everyone (Carla, 15 Nov 2026).
--
-- One easy "Feedback" button for anyone signed in (parents, students,
-- tutors, staff). They pick what it's about, grouped three ways:
--   * the app (booking, progress, billing ...),
--   * CLG's service (tutoring sessions, matching, communication ...),
--   * a person at CLG (a tutor or staff member),
-- then whether it's praise, an idea or a worry, an optional 1 to 5 rating,
-- and a comment. Admins see an overview grouped by area: what's going well,
-- what needs work, and how that is changing.
--
-- Privacy:
--   * feedback about a person is seen ONLY by the Child Safety Officer
--     (Carla), or by the deputy (Lauren) when it's about Carla. The person
--     it's about never sees it. Other admins never see it;
--   * other feedback is seen by full admins (owner and operations), with
--     two-step sign-in;
--   * the person who gave it sees what they sent and where it's up to, but
--     not the admins' private notes;
--   * the activity log holds ids only.
-- Child safety worries belong on the Child safety page, and the form says so.
--
-- Needs 20261113700100_child_safety_concerns.sql (the officer and deputy),
-- 20261117100100_safety_concern_about_worker.sql (who can be named) and
-- 20261114100100_safety_watch_words.sql (the concerning-words check).
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The areas feedback can be about
-- ---------------------------------------------------------------------------

-- Each area, in one of three groups. Areas are hidden, never deleted, so old feedback keeps its area.
create table if not exists public.feedback_areas ( -- one row per area
  id text primary key check (id ~ '^[a-z_]{2,40}$'), -- a short fixed name, e.g. "app_billing"
  grp text not null check (grp in ('app', 'service', 'people')), -- the group: the app, CLG's service, or a person
  label text not null check (char_length(label) between 2 and 80), -- the name people see
  sort smallint not null default 100, -- where it sits in the list (smaller first)
  active boolean not null default true -- whether it can be picked for new feedback
); -- end of the table
alter table public.feedback_areas enable row level security; -- turns on access rules
revoke all on public.feedback_areas from anon, authenticated; -- changed only through the owner's function below
grant select on public.feedback_areas to authenticated; -- signed-in people may read the list
drop policy if exists "signed-in people read areas" on public.feedback_areas; -- removes the old rule if the file is run again
create policy "signed-in people read areas" on public.feedback_areas for select to authenticated using (true); -- everyone signed in can see the areas (they're not private)

-- The starting areas. Existing ones are left as they are, so the owner's changes are kept.
insert into public.feedback_areas (id, grp, label, sort) values -- the list:
  ('app_booking', 'app', 'Booking and sessions in the app', 10), -- booking and session screens
  ('app_progress', 'app', 'Progress and reports', 20), -- progress, summaries and reports
  ('app_billing', 'app', 'Billing and payments', 30), -- invoices and payments
  ('app_materials', 'app', 'Learning materials', 40), -- the materials library
  ('app_notices', 'app', 'Notices and emails', 50), -- notices and emails from the app
  ('app_ease', 'app', 'How easy the app is to use', 60), -- ease of use in general
  ('app_other', 'app', 'Something else in the app', 90), -- anything else in the app
  ('service_tutoring', 'service', 'Tutoring sessions', 10), -- the sessions themselves
  ('service_matching', 'service', 'Being matched with a tutor', 20), -- matching
  ('service_scheduling', 'service', 'Session times and availability', 30), -- scheduling
  ('service_communication', 'service', 'Communication from CLG', 40), -- how CLG keeps in touch
  ('service_value', 'service', 'Prices and value', 50), -- prices
  ('service_other_support', 'service', 'Other support (not tutoring)', 60), -- other kinds of support
  ('service_other', 'service', 'Something else about CLG', 90), -- anything else about CLG
  ('people_person', 'people', 'A person at CLG', 10) -- feedback about one person
on conflict (id) do nothing; -- already there: leaves it alone

-- ---------------------------------------------------------------------------
-- The feedback itself
-- ---------------------------------------------------------------------------

create table if not exists public.feedback ( -- one row per piece of feedback
  id uuid primary key default gen_random_uuid(), -- its id
  given_by uuid references public.accounts (id) on delete set null, -- who gave it (empty if their account is later deleted)
  given_by_name text not null check (char_length(given_by_name) between 1 and 200), -- their name, copied so the record stays complete
  given_by_roles text not null default '' check (char_length(given_by_roles) <= 100), -- their roles at the time, e.g. "parent"
  area_id text not null references public.feedback_areas (id), -- what it's about
  about_account uuid references public.accounts (id) on delete set null, -- the person it's about (only for "A person at CLG")
  about_name text check (char_length(about_name) <= 200), -- their name, copied
  reader_id uuid references public.accounts (id) on delete set null, -- for feedback about a person: the ONE person who can read it
  kind text not null check (kind in ('praise', 'idea', 'worry')), -- praise (going well), an idea, or a worry (needs work)
  rating smallint check (rating between 1 and 5), -- an optional 1 to 5 rating
  comment text not null check (char_length(comment) between 3 and 4000), -- what they said
  status text not null default 'new' check (status in ('new', 'read', 'acting', 'done')), -- not read yet, read, being acted on, done
  admin_note text check (char_length(admin_note) <= 4000), -- the admins' private note on what was done (the giver can't see it)
  created_at timestamptz not null default now(), -- when it was given
  updated_at timestamptz not null default now() -- when it last changed
); -- end of the table
create index if not exists feedback_area_time on public.feedback (area_id, created_at desc); -- groups by area quickly
create index if not exists feedback_given_by on public.feedback (given_by); -- finds a person's own feedback quickly
create index if not exists feedback_reader on public.feedback (reader_id) where reader_id is not null; -- finds feedback about people quickly
alter table public.feedback enable row level security; -- turns on access rules
revoke all on public.feedback from anon, authenticated; -- no direct changes: everything goes through the functions below
grant select on public.feedback to authenticated; -- signed-in people may read, but only the rows the rules below allow

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- True when the signed-in person can read a piece of feedback:
--   * about a person: they're its one reader, with two-step sign-in;
--   * otherwise: a full admin (owner or operations), with two-step sign-in.
create or replace function private.can_read_feedback(p_about uuid, p_reader uuid) -- takes who it's about and its reader
returns boolean -- gives back yes or no
language sql stable security definer -- uses the admin checks
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select private.has_aal2() -- two-step sign-in used,
    and case -- and:
      when p_about is not null then p_reader = auth.uid() -- about a person: only its reader,
      else private.is_admin() -- otherwise: full admins.
    end -- end of the choice
$$; -- end of the function
revoke all on function private.can_read_feedback(uuid, uuid) from public; -- not for everyone by default
grant execute on function private.can_read_feedback(uuid, uuid) to authenticated; -- the access rule runs as the signed-in person, so it needs it

-- ---------------------------------------------------------------------------
-- Access rules
-- ---------------------------------------------------------------------------

-- Admins (or the one reader, for feedback about a person) read feedback. The
-- person who gave it reads their own through my_feedback() instead, which
-- leaves out the admins' note.
drop policy if exists "reviewers read feedback" on public.feedback; -- removes the old rule if the file is run again
create policy "reviewers read feedback" on public.feedback -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (private.can_read_feedback(about_account, reader_id)); -- only the people allowed (see the helper above)

-- A safety net that must also pass: the person feedback is about never sees it.
drop policy if exists "person named never reads feedback" on public.feedback; -- removes the old rule if the file is run again
create policy "person named never reads feedback" on public.feedback -- the blocking rule
  as restrictive -- must pass as well as the rule above
  for select to authenticated -- for signed-in people reading
  using (about_account is distinct from auth.uid()); -- never the person it's about

-- ---------------------------------------------------------------------------
-- Giving feedback
-- ---------------------------------------------------------------------------

-- Saves feedback. For "A person at CLG", the person must be someone the giver
-- can name (the same list as the child safety form), and the feedback goes to
-- the Child Safety Officer, or to the deputy when it's about the officer.
create or replace function public.give_feedback( -- the inputs:
  p_area text, -- what it's about
  p_kind text, -- praise, idea or worry
  p_rating smallint, -- 1 to 5 (optional)
  p_comment text, -- what they want to say
  p_about uuid default null -- the person it's about (only for "A person at CLG")
) -- end of the inputs
returns uuid -- gives back the new feedback's id
language plpgsql security definer -- saves to a table people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_me uuid := auth.uid(); -- who is giving it
  v_grp text; -- the area's group
  v_reader uuid; -- for feedback about a person: who reads it
  v_id uuid; -- the new feedback's id
begin -- starts the code
  if v_me is null then -- nobody signed in
    raise exception 'Please sign in to give feedback.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if (select count(*) from public.feedback where given_by = v_me and created_at > now() - interval '1 day') >= 30 then -- 30 in a day already
    raise exception 'Thanks for all your feedback today! Please try again tomorrow, or contact CLG directly.' using errcode = '54000'; -- plain message, "too many" code
  end if; -- end of the check
  select grp into v_grp from public.feedback_areas where id = p_area and active; -- the area's group (only areas that can be picked)
  if v_grp is null then -- no such area
    raise exception 'Please choose what your feedback is about.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if coalesce(p_kind, '') not in ('praise', 'idea', 'worry') then -- no kind chosen
    raise exception 'Please choose praise, an idea or a worry.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_rating is not null and p_rating not between 1 and 5 then -- a rating out of range
    raise exception 'Ratings go from 1 to 5.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_comment, ''))) < 3 then -- nothing written
    raise exception 'Please write a few words.' using errcode = '22023'; -- plain message
  end if; -- end of the check

  if v_grp = 'people' then -- feedback about a person:
    if p_about is null then -- nobody chosen
      raise exception 'Please choose who this feedback is about.' using errcode = '22023'; -- plain message
    end if; -- end of the check
    if p_about = v_me then -- themselves
      raise exception 'You can''t give feedback about yourself here.' using errcode = '22023'; -- plain message
    end if; -- end of the check
    if not exists (select 1 from public.safety_concern_people_choices() c where c.account_id = p_about) then -- someone not on their list
      raise exception 'Please choose someone from the list.' using errcode = '42501'; -- plain message
    end if; -- end of the check
    v_reader := private.safety_contact('officer'); -- usually the Child Safety Officer reads it
    if v_reader is null or v_reader = p_about then -- no officer, or it's about the officer:
      v_reader := private.safety_contact('deputy'); -- the deputy reads it instead
    end if; -- end of the check
    if v_reader is null or v_reader = p_about then -- still nobody suitable
      raise exception 'CLG can''t take feedback about this person in the app yet. Please contact CLG directly.' using errcode = '22023'; -- plain message
    end if; -- end of the check
  elsif p_about is not null then -- a person given for an area that isn't about a person
    raise exception 'To give feedback about a person, choose "A person at CLG".' using errcode = '22023'; -- plain message
  end if; -- end of the choice

  insert into public.feedback ( -- saves the feedback:
    given_by, given_by_name, given_by_roles, -- who gave it,
    area_id, about_account, about_name, reader_id, -- what or who it's about, and who reads it,
    kind, rating, comment -- and what they said
  ) -- end of the column list
  select v_me, -- the giver,
    coalesce(nullif(a.full_name, ''), 'Unknown'), -- their name,
    coalesce((select string_agg(r.role::text, ', ' order by r.role) from public.account_roles r where r.account_id = v_me), ''), -- their roles,
    p_area, p_about, -- the area and the person (if any),
    (select left(b.full_name, 200) from public.accounts b where b.id = p_about), -- the person's name (if any),
    v_reader, -- the one reader (for a person; empty otherwise),
    p_kind, p_rating, left(btrim(p_comment), 4000) -- the kind, rating and comment
  from public.accounts a where a.id = v_me -- from their account
  returning id into v_id; -- keeps the new id
  if v_id is null then -- nothing saved (no account row)
    raise exception 'We couldn''t save that. Please try again.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  perform private.log_event('give_feedback', 'feedback', v_id::text, '{}'); -- notes it in the activity log (id only)
  return v_id; -- hands back the new id
end; -- ends the code
$$; -- end of the function
revoke all on function public.give_feedback(text, text, smallint, text, uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.give_feedback(text, text, smallint, text, uuid) to authenticated; -- signed-in people

-- The feedback the signed-in person gave, without the admins' private note.
create or replace function public.my_feedback() -- no inputs
returns table (id uuid, area_label text, about_name text, kind text, rating smallint, comment text, status text, created_at timestamptz) -- what they can see
language sql stable security definer -- reads past the access rules, but only their own rows
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select f.id, a.label, f.about_name, f.kind, f.rating, f.comment, f.status, f.created_at -- the parts they can see
  from public.feedback f join public.feedback_areas a on a.id = f.area_id -- with the area's name
  where f.given_by = auth.uid() -- only their own
  order by f.created_at desc -- newest first
  limit 50 -- the latest 50
$$; -- end of the function
revoke all on function public.my_feedback() from public, anon; -- not for signed-out visitors
grant execute on function public.my_feedback() to authenticated; -- signed-in people

-- ---------------------------------------------------------------------------
-- Dealing with feedback (the people who can read it)
-- ---------------------------------------------------------------------------

-- Changes where feedback is up to, and saves the private note on what was done.
create or replace function public.feedback_update(p_id uuid, p_status text, p_note text) -- takes the feedback, its stage and the note
returns void -- gives nothing back
language plpgsql security definer -- changes a table people can't change directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_row public.feedback; -- the feedback
begin -- starts the code
  select * into v_row from public.feedback where id = p_id; -- finds it
  if v_row.id is null or not private.can_read_feedback(v_row.about_account, v_row.reader_id) or v_row.about_account = auth.uid() then -- not one they can deal with
    raise exception 'Only the people who can read this feedback can update it (with two-step sign-in).' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if coalesce(p_status, '') not in ('new', 'read', 'acting', 'done') then -- no stage chosen
    raise exception 'Please choose where this is up to.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.feedback -- saves the change
  set status = p_status, -- the new stage
      admin_note = nullif(left(btrim(coalesce(p_note, '')), 4000), ''), -- the note (empty clears it)
      updated_at = now() -- when it changed
  where id = p_id; -- this feedback
  perform private.log_event('feedback_update', 'feedback', p_id::text, jsonb_build_object('status', p_status)); -- notes the change (id and stage only)
end; -- ends the code
$$; -- end of the function
revoke all on function public.feedback_update(uuid, text, text) from public, anon; -- not for signed-out visitors
grant execute on function public.feedback_update(uuid, text, text) to authenticated; -- signed-in people can try (the check is inside)

-- The owner adds an area, renames one, or hides one from new feedback.
create or replace function public.set_feedback_area(p_id text, p_grp text, p_label text, p_active boolean) -- takes the area's short name, group, label and whether it can be picked
returns void -- gives nothing back
language plpgsql security definer -- changes a table people can't change directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if not private.is_owner() then -- not the owner (with two-step sign-in)
    raise exception 'Only the owner can change the feedback areas.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if coalesce(p_grp, '') not in ('app', 'service') then -- a group that can't be added to ("A person at CLG" is fixed)
    raise exception 'Please choose "The app" or "CLG''s service".' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_label, ''))) < 2 then -- no name
    raise exception 'Please give the area a name.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if coalesce(p_id, '') !~ '^[a-z_]{2,40}$' then -- a bad short name
    raise exception 'The short name can only use small letters and underscores.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.feedback_areas (id, grp, label, active) -- adds the area,
  values (p_id, p_grp, left(btrim(p_label), 80), coalesce(p_active, true)) -- with its details,
  on conflict (id) do update set label = excluded.label, active = excluded.active -- or renames / hides it if it's there
  where public.feedback_areas.grp <> 'people'; -- ("A person at CLG" can't be changed)
  perform private.log_event('set_feedback_area', 'feedback_areas', p_id, '{}'); -- notes the change
end; -- ends the code
$$; -- end of the function
revoke all on function public.set_feedback_area(text, text, text, boolean) from public, anon; -- not for signed-out visitors
grant execute on function public.set_feedback_area(text, text, text, boolean) to authenticated; -- signed-in people can try (the owner check is inside)

-- ---------------------------------------------------------------------------
-- Concerning words: feedback is checked like other writing, EXCEPT feedback
-- about a person. Flags are seen by both child safety contacts, so checking
-- feedback about one of them would show it to them.
-- ---------------------------------------------------------------------------
do $$ -- a small block of code
begin -- starts the block
  if to_regprocedure('private.scan_watch_words()') is null then -- the check isn't there
    return; -- nothing to do
  end if; -- end of the check
  drop trigger if exists watch_words_scan on public.feedback; -- removes the old check if the file is run again
  create trigger watch_words_scan after insert or update of comment on public.feedback -- after new feedback or an edit to the comment,
    for each row when (new.about_account is null) -- only when it isn't about a person,
    execute function private.scan_watch_words('comment'); -- checks the comment
end; -- ends the block
$$; -- end of the code
