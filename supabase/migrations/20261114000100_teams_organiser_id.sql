-- Summary: Teams links need the organiser account's Microsoft "Object ID".
-- Carla, 12 Nov 2026.
--
-- The first real test failed with "The userId in request URL is not a valid
-- GUID": when the app makes meetings on its own (not signed in as a person),
-- Microsoft only accepts the account's Object ID (a long code like
-- 1a2b3c4d-...), not its email. This file:
--   1. adds organiser_id (the Object ID) to the Teams settings,
--   2. lets admins save it with the other settings,
--   3. makes the job use it, and only run once it is filled in,
--   4. lets sessions that failed in the test be tried again.
-- The email stays too, so admins can see which account it is.
--
-- Teams links module only. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. The Object ID column
-- ---------------------------------------------------------------------------
alter table public.teams_settings add column if not exists organiser_id uuid; -- The organiser's Microsoft Object ID (empty until an admin enters it).

-- ---------------------------------------------------------------------------
-- 2. Saving the settings (now with the Object ID)
-- ---------------------------------------------------------------------------
-- Saves on/off, the organiser email and Object ID, and days ahead. Admins only.
create or replace function public.save_teams_settings(p_enabled boolean, p_organiser text, p_days_ahead int, p_organiser_id text) -- The new version takes the Object ID as well.
returns void language plpgsql security definer -- Returns nothing; runs as the table owner so it can save.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$
declare
  v_email text := nullif(lower(btrim(coalesce(p_organiser, ''))), ''); -- The email, tidied (empty means none).
  v_id_text text := nullif(lower(btrim(coalesce(p_organiser_id, ''))), ''); -- The Object ID as typed, tidied (empty means none).
  v_id uuid; -- The Object ID once checked.
begin
  if not private.is_admin() then -- Only admins (with two-step login) may change settings.
    raise exception 'Only CLG admins can change the Teams settings.' using errcode = '42501'; -- Plain refusal.
  end if; -- End of the admin check.
  if v_id_text is not null then -- If an Object ID was given:
    if v_id_text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then -- it must look like one,
      raise exception 'The Object ID should look like 1a2b3c4d-1a2b-1a2b-1a2b-1a2b3c4d5e6f. Copy it from portal.azure.com > Users > the account.' using errcode = '22023'; -- or we explain where to find it.
    end if; -- End of the shape check.
    v_id := v_id_text::uuid; -- Keeps it as an ID.
  end if; -- End of the Object ID check.
  if p_enabled and (v_email is null or v_id is null) then -- Switching on needs both the email and the Object ID.
    raise exception 'Enter the Microsoft 365 email and its Object ID before switching Teams links on.' using errcode = '22023'; -- Plain message.
  end if; -- End of that check.
  if v_email is not null and v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then -- The email must look like an email.
    raise exception 'That doesn''t look like an email address.' using errcode = '22023'; -- Plain message.
  end if; -- End of the email check.
  if p_days_ahead is null or p_days_ahead not between 1 and 28 then -- Days ahead must be 1 to 28.
    raise exception 'Days ahead must be between 1 and 28.' using errcode = '22023'; -- Plain message.
  end if; -- End of the days check.
  update public.teams_settings -- Saves the one settings row:
     set enabled = coalesce(p_enabled, false), organiser_email = v_email, -- on or off, the email,
         organiser_id = v_id, days_ahead = p_days_ahead, updated_by = auth.uid() -- the Object ID, days ahead, and who changed it.
   where id; -- (the only row)
end;
$$;
revoke all on function public.save_teams_settings(boolean, text, int, text) from public, anon; -- Nobody by default...
grant execute on function public.save_teams_settings(boolean, text, int, text) to authenticated; -- ...signed-in people may call it (it checks for admins itself).
drop function if exists public.save_teams_settings(boolean, text, int); -- Removes the old version without the Object ID, so it can't switch links on without one.

-- ---------------------------------------------------------------------------
-- 3. The job uses the Object ID
-- ---------------------------------------------------------------------------
-- Starts a run only when switched on with an Object ID, and not if one started in the last p_gap.
create or replace function public.teams_start_run(p_gap interval default interval '5 minutes') -- Same inputs as before.
returns boolean language plpgsql security definer -- Says whether to go ahead; runs as the table owner.
set search_path = '' -- Full names only.
as $$
declare
  v_started boolean; -- True when this run may go ahead.
begin
  if not private.is_backend() then -- Only the server may run the job.
    raise exception 'Only the server can run the Teams links job.' using errcode = '42501'; -- Plain refusal.
  end if; -- End of the server check.
  update public.teams_settings -- Marks the run as started:
     set last_run_at = now() -- now,
   where id and enabled and organiser_id is not null -- only when switched on with an Object ID,
     and (last_run_at is null or last_run_at < now() - p_gap) -- and not if another run started very recently.
  returning true into v_started; -- Notes whether the row was updated.
  return coalesce(v_started, false); -- Go ahead, or not.
end;
$$;

-- Hands out sessions that need a meeting, marking each 'making' (as before),
-- but with the organiser's Object ID, which Microsoft needs in its address.
-- The teams_meetings.organiser_email column now holds that Object ID: it is
-- what deleting the meeting later needs.
create or replace function public.teams_claim_sessions(p_limit int default 20) -- Same inputs as before.
returns table (meeting_id uuid, session_id uuid, organiser_email text, subject text,
               starts_at timestamptz, ends_at timestamptz) -- Same outputs as before (organiser_email = the Object ID).
language plpgsql security definer -- Runs as the table owner.
set search_path = '' -- Full names only.
as $$
#variable_conflict use_column
declare
  v_settings public.teams_settings; -- The settings row.
  v_organiser text; -- The Object ID, as text for Microsoft's address.
begin
  if not private.is_backend() then -- Only the server may run the job.
    raise exception 'Only the server can run the Teams links job.' using errcode = '42501'; -- Plain refusal.
  end if; -- End of the server check.
  select * into v_settings from public.teams_settings where id; -- Reads the settings.
  if not v_settings.enabled or v_settings.organiser_id is null then -- Switched off, or no Object ID yet:
    return; -- nothing to hand out.
  end if; -- End of that check.
  v_organiser := v_settings.organiser_id::text; -- The Object ID as text.

  return query -- Hands out:
  with picked as ( -- the sessions that need a meeting:
    select x.id, x.subject, x.starts_at, x.ends_at -- each session's id, subject and times,
    from public.sessions x -- from the scheduling module's sessions (read only),
    left join public.teams_meetings m on m.session_id = x.id -- with any meeting already tried,
    where x.status = 'scheduled' -- still booked,
      and x.delivery = 'online' -- online,
      and x.meeting_url is null -- with no link yet (a pasted link is left alone),
      and x.ends_at > now() -- not over,
      and x.starts_at < now() + make_interval(days => v_settings.days_ahead) -- starting within the days-ahead window,
      and (m.id is null -- never tried,
           or (m.status = 'failed' and m.attempts < 5) -- or failed fewer than 5 times,
           or (m.status = 'making' and m.claimed_at < now() - interval '10 minutes')) -- or stuck from a run that died.
    order by x.starts_at -- soonest first,
    limit greatest(coalesce(p_limit, 20), 1) -- a few at a time,
    for update of x skip locked -- and not ones another run is handling.
  ),
  claimed as ( -- Marks each one 'making':
    insert into public.teams_meetings as t (session_id, status, organiser_email, attempts, claimed_at) -- a new row,
    select p.id, 'making', v_organiser, 1, now() from picked p -- for each picked session, with the Object ID,
    on conflict on constraint teams_meetings_session_id_key do update -- or, if tried before,
      set status = 'making', organiser_email = excluded.organiser_email, -- marks it 'making' with the Object ID,
          attempts = t.attempts + 1, claimed_at = now() -- and counts the attempt.
    returning t.id, t.session_id, t.organiser_email -- Gives back the meeting row, session and Object ID.
  )
  select c.id, c.session_id, c.organiser_email, -- Each meeting row, session and Object ID,
         'CLG session: ' || p.subject, p.starts_at, p.ends_at -- with a title free of names, and the times.
  from claimed c join picked p on p.id = c.session_id; -- (matching each claim to its session)
end;
$$;

-- Only the server may run the job (same as before; repeated so a re-run keeps it so).
revoke all on function public.teams_start_run(interval) from public, anon, authenticated; -- Nobody signed in...
grant execute on function public.teams_start_run(interval) to service_role; -- ...only the server.
revoke all on function public.teams_claim_sessions(int) from public, anon, authenticated; -- Nobody signed in...
grant execute on function public.teams_claim_sessions(int) to service_role; -- ...only the server.

-- ---------------------------------------------------------------------------
-- 4. Try the sessions that failed in the test again
-- ---------------------------------------------------------------------------
update public.teams_meetings -- Sessions that failed (for example because of the email):
   set attempts = 0, last_error = null -- get a fresh set of 5 tries,
 where status = 'failed'; -- (only failed ones).
