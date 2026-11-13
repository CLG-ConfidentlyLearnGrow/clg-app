-- Summary: a private calendar link for each tutor (Carla, 12 Nov 2026).
--
-- Tutors asked to see their weekly bookings in their own calendar (Google,
-- Outlook or Apple). Each tutor can make one secret calendar link. Their
-- calendar app checks the link every few hours and shows their sessions.
--
-- How it stays private:
--   1. The link holds a long random secret (64 characters). Only a scrambled
--      copy (hash) is stored, so even someone who could read this table
--      couldn't rebuild a working link.
--   2. The link shows only that tutor's own sessions, with the least detail
--      needed to turn up: the student's first name, the subject, the time,
--      the place (library name and address, or "Online" with the Teams
--      link). No surnames, family contacts, home addresses, notes or money.
--   3. The tutor can make a new link at any time (the old one stops working
--      straight away) or turn the link off.
--   4. The link stops working by itself if the person is no longer a tutor
--      or their tutor profile is switched off.
--
-- Calendar apps can't sign in, so the feed function is open to "not signed
-- in" callers; the secret in the link is the only key. That is why it shows
-- so little. The weekly calendar page in the app uses the normal signed-in
-- list (public.list_sessions) and isn't changed here.
--
-- This belongs to the scheduling module (it only reads sessions). Safe to
-- run more than once.

-- ---------------------------------------------------------------------------
-- 1. The table: one calendar link per tutor
-- ---------------------------------------------------------------------------

-- One row per tutor who has made a calendar link.
create table if not exists public.tutor_calendar_links ( -- the table, made only if it isn't there yet
  tutor_id uuid primary key references public.tutor_profiles (account_id) on delete cascade, -- the tutor (the link goes if the tutor profile goes)
  link_hash text not null unique, -- the scrambled copy of the link's secret (never the secret itself)
  created_at timestamptz not null default now(), -- when this link was made (a new link resets it)
  last_used_at timestamptz -- when a calendar app last read the link (blank until it does)
); -- end of the table

alter table public.tutor_calendar_links enable row level security; -- Turns on the access rules for this table.
revoke all on public.tutor_calendar_links from anon, authenticated; -- Takes away every direct permission: changes go only through the functions below.
grant select (tutor_id, created_at, last_used_at) on public.tutor_calendar_links to authenticated; -- Signed-in people may read these columns only (never the hash), and the rule below narrows it to their own row.

drop policy if exists "tutor sees own calendar link" on public.tutor_calendar_links; -- Removes the rule if it's there, so this file can be run again.
create policy "tutor sees own calendar link" on public.tutor_calendar_links -- The read rule:
  for select to authenticated -- for reading, by signed-in people,
  using (tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2()); -- only their own row, only as a tutor, only after two-step sign-in.

-- Keep a record of links being made, replaced or turned off (not of each
-- time a calendar app reads it, which would fill the record).
drop trigger if exists audit on public.tutor_calendar_links; -- Removes the record-keeper if it's there, so this file can be run again.
create trigger audit after insert or delete or update of link_hash on public.tutor_calendar_links -- Adds it back: after a link is made, removed or replaced,
  for each row execute function private.audit_change(); -- writes a line in the audit log.

-- ---------------------------------------------------------------------------
-- 2. Scrambling the secret
-- ---------------------------------------------------------------------------

-- Turns a link's secret into its scrambled copy (SHA-256, as hex text).
create or replace function private.calendar_link_hash(p_token text) -- Takes the secret.
returns text language sql immutable -- Gives back text; the same secret always gives the same copy.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ select encode(pg_catalog.sha256(pg_catalog.convert_to(coalesce(p_token, ''), 'UTF8')), 'hex') $$; -- Scrambles the secret (blank if none) and writes it as hex.
revoke execute on function private.calendar_link_hash(text) from public; -- Nobody calls it directly; only the functions below use it.

-- ---------------------------------------------------------------------------
-- 3. Making a new link, and turning it off (tutors)
-- ---------------------------------------------------------------------------

-- A tutor makes a new calendar link. Any earlier link stops working. Gives
-- back the secret once; the app shows it as a web address to copy.
create or replace function public.reset_calendar_link() -- No inputs: always for the signed-in tutor.
returns text language plpgsql security definer -- Gives back the secret; runs with the owner's rights so it can write the table.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the steps:
declare -- working values:
  v_token text; -- The new secret.
begin -- start of the steps.
  if not (private.has_role('tutor') and private.has_aal2()) then -- Not a tutor, or not signed in with two steps:
    raise exception 'Only tutors can make a calendar link' using errcode = '42501'; -- refuses, in plain words.
  end if; -- End of the tutor check.
  if not exists (select 1 from public.tutor_profiles where account_id = auth.uid() and active) then -- No tutor profile, or it's switched off:
    raise exception 'Your tutor profile is switched off, so a calendar link can''t be made' using errcode = '42501'; -- refuses, in plain words.
  end if; -- End of the profile check.
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''); -- 64 random hex characters from Postgres's secure random source.
  insert into public.tutor_calendar_links (tutor_id, link_hash) -- Saves the link for this tutor:
  values (auth.uid(), private.calendar_link_hash(v_token)) -- the tutor and the scrambled secret,
  on conflict (tutor_id) do update -- or, if they already had one, replaces it:
    set link_hash = excluded.link_hash, -- the new scrambled secret (the old link stops working),
        created_at = now(), -- made now,
        last_used_at = null; -- not yet read by a calendar app.
  return v_token; -- Hands back the secret, this one time.
end; -- end of the steps.
$$; -- end of the function.
revoke all on function public.reset_calendar_link() from public, anon; -- Nobody else may run it.
grant execute on function public.reset_calendar_link() to authenticated; -- Signed-in people may (the checks inside allow only tutors).

-- A tutor turns their calendar link off. Their calendar app stops getting
-- updates (sessions already copied stay until the app removes them).
create or replace function public.remove_calendar_link() -- No inputs: always for the signed-in tutor.
returns void language plpgsql security definer -- Gives back nothing; runs with the owner's rights so it can delete the row.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the steps:
begin -- start of the steps.
  if not (private.has_role('tutor') and private.has_aal2()) then -- Not a tutor, or not signed in with two steps:
    raise exception 'Only tutors can turn off a calendar link' using errcode = '42501'; -- refuses, in plain words.
  end if; -- End of the tutor check.
  delete from public.tutor_calendar_links where tutor_id = auth.uid(); -- Removes their link (if any).
end; -- end of the steps.
$$; -- end of the function.
revoke all on function public.remove_calendar_link() from public, anon; -- Nobody else may run it.
grant execute on function public.remove_calendar_link() to authenticated; -- Signed-in people may (the check inside allows only tutors).

-- ---------------------------------------------------------------------------
-- 4. The feed itself (read by calendar apps, which can't sign in)
-- ---------------------------------------------------------------------------

-- Gives back one tutor's sessions for their calendar app, from 4 weeks ago
-- to 6 months ahead, when given that tutor's secret. A wrong, old or badly
-- shaped secret gives back nothing (never an error, so it gives no hints).
-- Cancelled sessions are included so calendar apps can remove them.
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
  meeting_url text, -- the Teams link (online sessions that aren't cancelled),
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
         case when x.delivery = 'online' and x.status <> 'cancelled' then x.meeting_url end, -- the Teams link (online, not cancelled),
         coalesce(v_zone, 'Australia/Adelaide') -- and the tutor's time zone (Adelaide if not set).
  from public.sessions x -- From the sessions,
  join public.students s on s.id = x.student_id -- with each session's student (for the first name),
  left join public.libraries lib on lib.id = x.library_id -- and its library (if any),
  where x.tutor_id = v_tutor -- only this tutor's sessions,
    and x.starts_at >= now() - interval '28 days' -- from 4 weeks ago,
    and x.starts_at < now() + interval '183 days' -- to about 6 months ahead,
  order by x.starts_at; -- earliest first.
end; -- end of the steps.
$$; -- end of the function.
revoke all on function public.calendar_feed(text) from public; -- Takes away the default permission first.
grant execute on function public.calendar_feed(text) to anon, authenticated; -- Calendar apps (not signed in) may run it; the secret is the key.
