-- Summary: Teams links no longer go into tutors' own calendars (proposed
-- 15 Nov 2026, for Carla to choose).
--
-- CLG's Teams meetings let everyone with the link straight in (tutors join
-- as guests, so nobody could let a student in from a waiting room). A
-- tutor's Google, Outlook or Apple calendar is only as safe as their own
-- account, so the Teams link, which is the key to a child's live session,
-- now stays inside the app. The calendar entry says to join from the CLG
-- app and links to the Weekly calendar page, which has the Join button.
--
-- This replaces public.calendar_feed (from 20261113200100_tutor_calendar.sql)
-- with the same function minus the meeting_url column. Nothing else changes.
-- Safe to run more than once.

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
    and x.starts_at >= now() - interval '28 days' -- from 4 weeks ago,
    and x.starts_at < now() + interval '183 days' -- to about 6 months ahead,
  order by x.starts_at; -- earliest first.
end; -- end of the steps.
$$; -- end of the function.
revoke all on function public.calendar_feed(text) from public; -- Takes away the default permission first.
grant execute on function public.calendar_feed(text) to anon, authenticated; -- Calendar apps (not signed in) may run it; the secret is the key.
