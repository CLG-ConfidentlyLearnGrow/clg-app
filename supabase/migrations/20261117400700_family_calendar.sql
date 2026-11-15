-- Summary: a private calendar link for parents and students (Carla,
-- 15 Nov 2026): "Student and parent profiles should also get a similar
-- calendar entry as tutors do."
--
-- Works like the tutors' link (20261113200100_tutor_calendar.sql):
--   1. Each parent or student (with their own login) can make one secret
--      link. Only a scrambled copy (hash) is stored. They can make a new one
--      (the old one stops) or turn it off.
--   2. The feed holds only their own family's sessions: a parent's linked
--      children, and a student's own sessions. Each entry has the child's
--      first name, the subject, the tutor's first name, the time and the
--      place (library name and address, or Online). No Teams links (they
--      stay in the app, Carla 15 Nov 2026), no surnames, no notes, no money.
--   3. Calendar apps can't sign in, so the secret in the link is the only
--      key. The link stops working by itself if the person no longer has
--      the parent or student role; a child unlinked from a parent drops out
--      of the parent's feed straight away.
--
-- Also: the tutors' feed now leaves out sessions while the tutor's checks
-- for that student have lapsed, to match their Sessions list (Carla,
-- 16 Nov 2026, 20261117300100_hide_sessions_lapsed_checks.sql).
--
-- Belongs to the scheduling module (it only reads sessions). Safe to run
-- more than once.

-- ---------------------------------------------------------------------------
-- 1. The table: one calendar link per parent or student account
-- ---------------------------------------------------------------------------

-- One row per family member who has made a calendar link.
create table if not exists public.family_calendar_links ( -- the table, made only if it isn't there yet
  account_id uuid primary key references public.accounts (id) on delete cascade, -- the person (the link goes if their account goes)
  link_hash text not null unique, -- the scrambled copy of the link's secret (never the secret itself)
  created_at timestamptz not null default now(), -- when this link was made (a new link resets it)
  last_used_at timestamptz -- when a calendar app last read the link (blank until it does)
); -- end of the table

alter table public.family_calendar_links enable row level security; -- Turns on the access rules for this table.
revoke all on public.family_calendar_links from anon, authenticated; -- Takes away every direct permission: changes go only through the functions below.
grant select (account_id, created_at, last_used_at) on public.family_calendar_links to authenticated; -- Signed-in people may read these columns only (never the hash); the rule below narrows it to their own row.

drop policy if exists "person sees own family calendar link" on public.family_calendar_links; -- Removes the rule if it's there, so this file can be run again.
create policy "person sees own family calendar link" on public.family_calendar_links -- The read rule:
  for select to authenticated -- for reading, by signed-in people,
  using (account_id = auth.uid()); -- only their own row.

-- Keep a record of links being made, replaced or turned off (not of each
-- time a calendar app reads it, which would fill the record).
drop trigger if exists audit on public.family_calendar_links; -- Removes the record-keeper if it's there, so this file can be run again.
create trigger audit after insert or delete or update of link_hash on public.family_calendar_links -- Adds it back: after a link is made, removed or replaced,
  for each row execute function private.audit_change(); -- writes a line in the audit log.

-- ---------------------------------------------------------------------------
-- 2. Who may have a family calendar link
-- ---------------------------------------------------------------------------

-- Whether an account is a parent, or a student with their own login.
create or replace function private.can_have_family_calendar(p_account uuid) -- Takes the account.
returns boolean language sql stable security definer -- Gives back yes or no; runs with the owner's rights to read roles.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the steps:
  select exists ( -- Yes if there is:
    select 1 from public.account_roles r -- a role
    where r.account_id = p_account and r.role in ('parent', 'student') -- of parent or student for this account.
  ) -- End of the check.
$$; -- end of the function.
revoke execute on function private.can_have_family_calendar(uuid) from public; -- Nobody calls it directly; only the functions below use it.

-- ---------------------------------------------------------------------------
-- 3. Making a new link, and turning it off (parents and students)
-- ---------------------------------------------------------------------------

-- A parent or student makes a new calendar link. Any earlier link stops
-- working. Gives back the secret once; the app shows it as a web address.
create or replace function public.reset_family_calendar_link() -- No inputs: always for the signed-in person.
returns text language plpgsql security definer -- Gives back the secret; runs with the owner's rights so it can write the table.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the steps:
declare -- working values:
  v_token text; -- The new secret.
begin -- start of the steps.
  if auth.uid() is null or not private.can_have_family_calendar(auth.uid()) then -- Not signed in, or not a parent or student:
    raise exception 'Only parents and students can make a family calendar link' using errcode = '42501'; -- refuses, in plain words.
  end if; -- End of the check.
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''); -- 64 random hex characters from Postgres's secure random source.
  insert into public.family_calendar_links (account_id, link_hash) -- Saves the link for this person:
  values (auth.uid(), private.calendar_link_hash(v_token)) -- the person and the scrambled secret,
  on conflict (account_id) do update -- or, if they already had one, replaces it:
    set link_hash = excluded.link_hash, -- the new scrambled secret (the old link stops working),
        created_at = now(), -- made now,
        last_used_at = null; -- not yet read by a calendar app.
  return v_token; -- Hands back the secret, this one time.
end; -- end of the steps.
$$; -- end of the function.
revoke all on function public.reset_family_calendar_link() from public, anon; -- Nobody else may run it.
grant execute on function public.reset_family_calendar_link() to authenticated; -- Signed-in people may (the check inside allows only parents and students).

-- A parent or student turns their calendar link off.
create or replace function public.remove_family_calendar_link() -- No inputs: always for the signed-in person.
returns void language plpgsql security definer -- Gives back nothing; runs with the owner's rights so it can delete the row.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the steps:
begin -- start of the steps.
  if auth.uid() is null then -- Not signed in:
    raise exception 'Please sign in first' using errcode = '42501'; -- refuses, in plain words.
  end if; -- End of the check.
  delete from public.family_calendar_links where account_id = auth.uid(); -- Removes their link (if any).
end; -- end of the steps.
$$; -- end of the function.
revoke all on function public.remove_family_calendar_link() from public, anon; -- Nobody else may run it.
grant execute on function public.remove_family_calendar_link() to authenticated; -- Signed-in people may (it only ever removes their own).

-- ---------------------------------------------------------------------------
-- 4. The family feed (read by calendar apps, which can't sign in)
-- ---------------------------------------------------------------------------

-- Gives back a family's sessions for their calendar app, from 4 weeks ago
-- to 6 months ahead, when given the secret: a parent's linked children and
-- a student's own sessions. A wrong, old or badly shaped secret gives back
-- nothing (never an error). Cancelled sessions are included so calendar
-- apps can remove them.
drop function if exists public.family_calendar_feed(text); -- Removes the function if it's there, so its result columns can change on a re-run.
create function public.family_calendar_feed(p_token text) -- Takes the secret from the link.
returns table ( -- Gives back rows with:
  session_id uuid, -- the session's id (so a calendar app updates the same event, not a new one),
  status public.session_status, -- its status (booked, done, cancelled, no-show),
  student_first_name text, -- the student's first name only,
  subject text, -- the subject,
  tutor_first_name text, -- the tutor's first name only,
  delivery public.session_delivery, -- where (online, library, home or school),
  place_name text, -- the library's name (libraries only),
  place_address text, -- the library's address and suburb (libraries only),
  starts_at timestamptz, -- when it starts,
  ends_at timestamptz, -- when it ends,
  time_zone text -- the student's time zone (from their state).
) -- (end of the result columns)
language plpgsql security definer -- Runs with the owner's rights, because the caller isn't signed in.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the steps:
declare -- working values:
  v_account uuid; -- The person the secret belongs to.
begin -- start of the steps.
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then -- No secret, or not the right shape:
    return; -- gives back nothing.
  end if; -- End of the shape check.
  select l.account_id into v_account -- Finds the person:
  from public.family_calendar_links l -- in the family calendar links,
  where l.link_hash = private.calendar_link_hash(p_token); -- whose scrambled secret matches.
  if v_account is null or not private.can_have_family_calendar(v_account) then -- No match, or no longer a parent or student:
    return; -- gives back nothing.
  end if; -- End of the match check.
  update public.family_calendar_links -- Notes that a calendar app read the link:
  set last_used_at = now() -- now,
  where account_id = v_account -- for this person,
    and (last_used_at is null or last_used_at < now() - interval '10 minutes'); -- at most every 10 min, so frequent checks don't keep writing.
  return query -- Gives back their family's sessions:
  select x.id, -- the session's id,
         x.status, -- its status,
         split_part(trim(s.full_name), ' ', 1), -- the student's first name,
         x.subject, -- the subject,
         split_part(trim(a.full_name), ' ', 1), -- the tutor's first name,
         x.delivery, -- where,
         case when x.delivery = 'library' then lib.name end, -- the library's name (libraries only),
         case when x.delivery = 'library' -- the library's address (libraries only):
              then nullif(concat_ws(', ', nullif(trim(lib.address), ''), nullif(trim(lib.suburb), '')), '') end, -- street and suburb, whichever are known,
         x.starts_at, -- when it starts,
         x.ends_at, -- when it ends,
         coalesce(private.state_timezone(s.state), 'Australia/Adelaide') -- the student's time zone (Adelaide if unknown).
  from public.sessions x -- From the sessions,
  join public.students s on s.id = x.student_id -- with each session's student,
  join public.accounts a on a.id = x.tutor_id -- and tutor (for the first name),
  left join public.libraries lib on lib.id = x.library_id -- and library (if any),
  where (exists (select 1 from public.parent_student_links p where p.parent_id = v_account and p.student_id = x.student_id) -- a child linked to this parent,
         or s.account_id = v_account) -- or the student's own sessions,
    and x.starts_at >= now() - interval '28 days' -- from 4 weeks ago,
    and x.starts_at < now() + interval '183 days' -- to about 6 months ahead,
  order by x.starts_at; -- earliest first.
end; -- end of the steps.
$$; -- end of the function.
revoke all on function public.family_calendar_feed(text) from public; -- Takes away the default permission first.
grant execute on function public.family_calendar_feed(text) to anon, authenticated; -- Calendar apps (not signed in) may run it; the secret is the key.

-- ---------------------------------------------------------------------------
-- 5. The tutors' feed: leave out sessions while the tutor's checks lapse
-- ---------------------------------------------------------------------------

-- Gives back one tutor's sessions for their calendar app, from 4 weeks ago
-- to 6 months ahead, when given that tutor's secret. A wrong, old or badly
-- shaped secret gives back nothing (never an error, so it gives no hints).
-- Cancelled sessions are included so calendar apps can remove them.
-- Sessions with a student whose state the tutor's checks don't cover right
-- now are left out, the same as their Sessions list (20261117300100).
drop function if exists public.calendar_feed(text); -- Removes the function if it's there, so its result columns can change on a re-run.
create function public.calendar_feed(p_token text) -- Takes the secret from the link.
returns table ( -- Gives back rows with:
  session_id uuid, -- the session's id (so a calendar app updates the same event, not a new one),
  status public.session_status, -- its status (booked, done, cancelled, no-show),
  student_first_name text, -- the student's first name only,
  subject text, -- the subject,
  delivery public.session_delivery, -- where (online, library, home or school),
  place_name text, -- the library's name (libraries only),
  place_address text, -- the library's address and suburb (libraries only),
  starts_at timestamptz, -- when it starts,
  ends_at timestamptz, -- when it ends,
  time_zone text -- the tutor's own time zone (from the state they work in; Adelaide if not set).
) -- (end of the result columns)
language plpgsql security definer -- Runs with the owner's rights, because the caller isn't signed in.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the steps:
declare -- working values:
  v_tutor uuid; -- The tutor the secret belongs to.
  v_zone text; -- The tutor's time zone.
begin -- start of the steps.
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then -- No secret, or not the right shape:
    return; -- gives back nothing.
  end if; -- End of the shape check.
  select l.tutor_id into v_tutor -- Finds the tutor:
  from public.tutor_calendar_links l -- in the calendar links,
  where l.link_hash = private.calendar_link_hash(p_token); -- whose scrambled secret matches.
  if v_tutor is null then -- No match (wrong or replaced link):
    return; -- gives back nothing.
  end if; -- End of the match check.
  if not exists (select 1 from public.account_roles where account_id = v_tutor and role = 'tutor') -- No longer a tutor,
     or not exists (select 1 from public.tutor_profiles where account_id = v_tutor and active) then -- or the tutor profile is switched off:
    return; -- gives back nothing.
  end if; -- End of the still-a-tutor check.
  update public.tutor_calendar_links -- Notes that a calendar app read the link:
  set last_used_at = now() -- now,
  where tutor_id = v_tutor -- for this tutor,
    and (last_used_at is null or last_used_at < now() - interval '10 minutes'); -- at most every 10 min, so frequent checks don't keep writing.
  select coalesce(private.state_timezone(w.work_state), 'Australia/Adelaide') into v_zone -- The time zone of the state they work in:
  from public.tutor_work_settings w -- from their work settings,
  where w.tutor_id = v_tutor; -- for this tutor.
  return query -- Gives back their sessions:
  select x.id, -- the session's id,
         x.status, -- its status,
         split_part(trim(s.full_name), ' ', 1), -- the student's first name (the first word of their name),
         x.subject, -- the subject,
         x.delivery, -- where,
         case when x.delivery = 'library' then lib.name end, -- the library's name (libraries only),
         case when x.delivery = 'library' -- the library's address (libraries only):
              then nullif(concat_ws(', ', nullif(trim(lib.address), ''), nullif(trim(lib.suburb), '')), '') end, -- street and suburb, whichever are known,
         x.starts_at, -- when it starts,
         x.ends_at, -- when it ends,
         coalesce(v_zone, 'Australia/Adelaide') -- and the tutor's time zone (Adelaide if not set).
  from public.sessions x -- From the sessions,
  join public.students s on s.id = x.student_id -- with each session's student (for the first name),
  left join public.libraries lib on lib.id = x.library_id -- and its library (if any),
  where x.tutor_id = v_tutor -- only this tutor's sessions,
    and private.tutor_cleared_for_student(v_tutor, x.student_id) -- only while their checks are in date for this student (Carla, 16 Nov 2026),
    and x.starts_at >= now() - interval '28 days' -- from 4 weeks ago,
    and x.starts_at < now() + interval '183 days' -- to about 6 months ahead,
  order by x.starts_at; -- earliest first.
end; -- end of the steps.
$$; -- end of the function.
revoke all on function public.calendar_feed(text) from public; -- Takes away the default permission first.
grant execute on function public.calendar_feed(text) to anon, authenticated; -- Calendar apps (not signed in) may run it; the secret is the key.
