-- Teams links module.
--
-- For each scheduled online session starting in the next few days, the app
-- makes a Microsoft Teams meeting under one CLG Microsoft 365 account (the
-- "organiser") and puts its join link on the session. When a session is
-- cancelled, or has finished, the meeting is deleted so the link stops
-- working: a CLG link can't be reused for contact outside booked times.
--
-- This module owns teams_settings and teams_meetings. It only READS the
-- scheduling module's sessions table, and fills sessions.meeting_url through
-- scheduling's public.set_session_meeting_url.
--
-- The talking to Microsoft happens on the server (src/lib/teams). These
-- functions hand out work and record the results; only the server may call
-- them. Admins can read the tables to see what happened.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Settings: one row.
-- ---------------------------------------------------------------------------
create table if not exists public.teams_settings (
  id boolean primary key default true check (id),
  -- Off until CLG has finished the Microsoft 365 setup.
  enabled boolean not null default false,
  -- The CLG Microsoft 365 account that owns every meeting (an email address).
  organiser_email text check (organiser_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  -- How many days ahead links are made. Short, so a cancelled session
  -- rarely has a meeting to delete.
  days_ahead int not null default 7 check (days_ahead between 1 and 28),
  -- When the last background run started (so page visits don't start
  -- runs over the top of each other).
  last_run_at timestamptz,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.accounts (id) on delete set null
);
insert into public.teams_settings (id) values (true) on conflict do nothing;

-- ---------------------------------------------------------------------------
-- One row per session that has (or had) a Teams meeting.
--   making   : the server is creating it now
--   made     : it exists in Teams and the link is on the session
--   failed   : Microsoft said no; tried again on the next run, up to 5 times
--   removing : the server is deleting it now
--   removed  : deleted in Teams; the link no longer works
-- ---------------------------------------------------------------------------
create table if not exists public.teams_meetings (
  id uuid primary key default gen_random_uuid(),
  -- Kept as null if the session row is ever deleted, so the meeting can
  -- still be deleted in Teams.
  session_id uuid unique references public.sessions (id) on delete set null,
  status text not null default 'making'
    check (status in ('making', 'made', 'failed', 'removing', 'removed')),
  -- Microsoft's id for the meeting, and the account it was made under
  -- (needed to delete it, even if the organiser setting changes later).
  graph_meeting_id text check (char_length(graph_meeting_id) <= 1000),
  organiser_email text,
  join_url text check (char_length(join_url) <= 2000),
  attempts int not null default 0,
  last_error text check (char_length(last_error) <= 1000),
  claimed_at timestamptz,
  made_at timestamptz,
  removed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists teams_meetings_status on public.teams_meetings (status);

alter table public.teams_settings enable row level security;
alter table public.teams_meetings enable row level security;
revoke all on public.teams_settings, public.teams_meetings from anon;
-- Changes only through the functions below (settings: save_teams_settings).
revoke insert, update, delete, truncate on public.teams_settings, public.teams_meetings from authenticated;

drop policy if exists "admins see Teams settings" on public.teams_settings;
create policy "admins see Teams settings" on public.teams_settings
  for select to authenticated using (private.is_admin());
drop policy if exists "admins see Teams meetings" on public.teams_meetings;
create policy "admins see Teams meetings" on public.teams_meetings
  for select to authenticated using (private.is_admin());

drop trigger if exists audit on public.teams_settings;
create trigger audit after insert or update or delete on public.teams_settings
  for each row execute function private.audit_change();
drop trigger if exists touch on public.teams_settings;
create trigger touch before update on public.teams_settings
  for each row execute function private.touch_updated_at();
drop trigger if exists touch on public.teams_meetings;
create trigger touch before update on public.teams_meetings
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Admin: settings
-- ---------------------------------------------------------------------------
create or replace function public.save_teams_settings(p_enabled boolean, p_organiser text, p_days_ahead int)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_email text := nullif(lower(btrim(coalesce(p_organiser, ''))), '');
begin
  if not private.is_admin() then
    raise exception 'Only CLG admins can change the Teams settings.' using errcode = '42501';
  end if;
  if p_enabled and v_email is null then
    raise exception 'Enter the Microsoft 365 email address that will own the meetings before switching Teams links on.'
      using errcode = '22023';
  end if;
  if v_email is not null and v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'That doesn''t look like an email address.' using errcode = '22023';
  end if;
  if p_days_ahead is null or p_days_ahead not between 1 and 28 then
    raise exception 'Days ahead must be between 1 and 28.' using errcode = '22023';
  end if;
  update public.teams_settings
     set enabled = coalesce(p_enabled, false), organiser_email = v_email,
         days_ahead = p_days_ahead, updated_by = auth.uid()
   where id;
end;
$$;
revoke all on function public.save_teams_settings(boolean, text, int) from public, anon;
grant execute on function public.save_teams_settings(boolean, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- Server: start a run. Returns false if one started less than p_gap ago,
-- so a busy page can ask often without causing a crowd of runs.
-- ---------------------------------------------------------------------------
create or replace function public.teams_start_run(p_gap interval default interval '5 minutes')
returns boolean language plpgsql security definer
set search_path = ''
as $$
declare
  v_started boolean;
begin
  if not private.is_backend() then
    raise exception 'Only the server can run the Teams links job.' using errcode = '42501';
  end if;
  update public.teams_settings
     set last_run_at = now()
   where id and enabled and organiser_email is not null
     and (last_run_at is null or last_run_at < now() - p_gap)
  returning true into v_started;
  return coalesce(v_started, false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Server: sessions that need a meeting. Marks each one 'making' so a second
-- run at the same moment can't make a second meeting. A run that died part
-- way is picked up again after 10 minutes. A session that already has a link
-- (pasted in by an admin) is left alone.
-- ---------------------------------------------------------------------------
create or replace function public.teams_claim_sessions(p_limit int default 20)
returns table (meeting_id uuid, session_id uuid, organiser_email text, subject text,
               starts_at timestamptz, ends_at timestamptz)
language plpgsql security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_settings public.teams_settings;
begin
  if not private.is_backend() then
    raise exception 'Only the server can run the Teams links job.' using errcode = '42501';
  end if;
  select * into v_settings from public.teams_settings where id;
  if not v_settings.enabled or v_settings.organiser_email is null then
    return;
  end if;

  return query
  with picked as (
    select x.id, x.subject, x.starts_at, x.ends_at
    from public.sessions x
    left join public.teams_meetings m on m.session_id = x.id
    where x.status = 'scheduled'
      and x.delivery = 'online'
      and x.meeting_url is null
      and x.ends_at > now()
      and x.starts_at < now() + make_interval(days => v_settings.days_ahead)
      and (m.id is null
           or (m.status = 'failed' and m.attempts < 5)
           or (m.status = 'making' and m.claimed_at < now() - interval '10 minutes'))
    order by x.starts_at
    limit greatest(coalesce(p_limit, 20), 1)
    for update of x skip locked
  ),
  claimed as (
    insert into public.teams_meetings as t (session_id, status, organiser_email, attempts, claimed_at)
    select p.id, 'making', v_settings.organiser_email, 1, now() from picked p
    on conflict on constraint teams_meetings_session_id_key do update
      set status = 'making', organiser_email = excluded.organiser_email,
          attempts = t.attempts + 1, claimed_at = now()
    returning t.id, t.session_id, t.organiser_email
  )
  select c.id, c.session_id, c.organiser_email,
         -- Kept free of names: Microsoft only needs a title.
         'CLG session: ' || p.subject, p.starts_at, p.ends_at
  from claimed c join picked p on p.id = c.session_id;
end;
$$;

-- Server: the meeting was made. The link goes on the session only if the
-- session is still scheduled and has no other link; otherwise the meeting
-- is queued for deletion straight away.
create or replace function public.teams_record_made(p_meeting uuid, p_graph_id text, p_join_url text)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_session uuid;
  v_still_wanted boolean;
begin
  if not private.is_backend() then
    raise exception 'Only the server can run the Teams links job.' using errcode = '42501';
  end if;
  update public.teams_meetings
     set status = 'made', graph_meeting_id = p_graph_id, join_url = p_join_url,
         made_at = now(), last_error = null
   where id = p_meeting
   returning session_id into v_session;

  select x.status = 'scheduled' and x.delivery = 'online' and x.meeting_url is null
    into v_still_wanted
    from public.sessions x where x.id = v_session;
  if coalesce(v_still_wanted, false) then
    perform public.set_session_meeting_url(v_session, p_join_url);
  end if;
end;
$$;

create or replace function public.teams_record_failed(p_meeting uuid, p_error text)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_backend() then
    raise exception 'Only the server can run the Teams links job.' using errcode = '42501';
  end if;
  update public.teams_meetings
     set status = case status when 'removing' then 'made' else 'failed' end,
         last_error = left(p_error, 1000)
   where id = p_meeting;
end;
$$;

-- ---------------------------------------------------------------------------
-- Server: meetings to delete. A meeting goes when its session is cancelled,
-- moved off online, deleted, given a different link, or finished more than
-- an hour ago.
-- ---------------------------------------------------------------------------
create or replace function public.teams_claim_removals(p_limit int default 50)
returns table (meeting_id uuid, graph_meeting_id text, organiser_email text)
language plpgsql security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not private.is_backend() then
    raise exception 'Only the server can run the Teams links job.' using errcode = '42501';
  end if;
  return query
  with picked as (
    select m.id
    from public.teams_meetings m
    left join public.sessions x on x.id = m.session_id
    where (m.status = 'made' or (m.status = 'removing' and m.claimed_at < now() - interval '10 minutes'))
      and (x.id is null
           or x.status <> 'scheduled'
           or x.delivery <> 'online'
           or x.meeting_url is distinct from m.join_url
           or x.ends_at < now() - interval '1 hour')
    order by m.made_at
    limit greatest(coalesce(p_limit, 50), 1)
    for update of m skip locked
  )
  update public.teams_meetings t
     set status = 'removing', claimed_at = now()
    from picked p
   where t.id = p.id
  returning t.id, t.graph_meeting_id, t.organiser_email;
end;
$$;

-- Server: the meeting is gone from Teams. Take its link off the session
-- (only if it is still this meeting's link).
create or replace function public.teams_record_removed(p_meeting uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_session uuid;
  v_url text;
begin
  if not private.is_backend() then
    raise exception 'Only the server can run the Teams links job.' using errcode = '42501';
  end if;
  update public.teams_meetings
     set status = 'removed', removed_at = now(), last_error = null
   where id = p_meeting
   returning session_id, join_url into v_session, v_url;
  if v_session is not null and exists (
    select 1 from public.sessions where id = v_session and meeting_url = v_url
  ) then
    perform public.set_session_meeting_url(v_session, null);
  end if;
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.teams_start_run(interval)',
    'public.teams_claim_sessions(int)',
    'public.teams_record_made(uuid, text, text)',
    'public.teams_record_failed(uuid, text)',
    'public.teams_claim_removals(int)',
    'public.teams_record_removed(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;
