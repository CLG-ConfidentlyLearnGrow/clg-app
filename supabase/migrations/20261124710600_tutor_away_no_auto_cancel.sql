-- Summary: tutor away dates no longer cancel sessions on their own (Carla,
-- 22 Nov 2026, from her notes on Emma's Job Proposal: "Should stop
-- cancelling automatically so Emma can offer alternatives or cancel").
--
-- Before: 2 hours after a tutor entered away dates, every booked session on
-- those dates was cancelled and the families were told.
-- Now (module: scheduling, which owns sessions and away dates):
--   * The 2 hours stay, so a tutor can still remove a mistake quietly.
--   * After the 2 hours, nothing is cancelled. CLG's owner and Operations
--     admins get one notice listing the sessions that fall on those dates.
--   * Sessions > Away dates shows admins a "Sessions during tutor away
--     dates" list. For each one an admin either arranges another time or
--     tutor with the family (changing the session takes it off the list), or
--     presses "Cancel session", which cancels it with full credit and tells
--     the family, as the old automatic cancel did.
--   * A family's or student's own away dates still cancel straight away,
--     as before.
--   * New weekly bookings still skip all away dates, as before.
--
-- Safe to run more than once. Run after every earlier scheduling file.

-- ---------------------------------------------------------------------------
-- 1. Applying an away entry: tutors' entries tell admins instead of cancelling
-- ---------------------------------------------------------------------------
create or replace function private.apply_away_entry(p_id uuid) -- one away entry
returns integer -- how many sessions were cancelled (always 0 for a tutor's entry now)
language plpgsql security definer -- changes sessions for them
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_a public.away_dates; -- the away entry
  v_count integer; -- how many sessions it affects
  v_tutor text; -- the tutor's name
  v_list text; -- the sessions affected, as text for the notice
begin -- start
  select * into v_a from public.away_dates where id = p_id for update; -- reads the entry and holds it
  if v_a.id is null or v_a.applied_at is not null then -- gone, or already applied:
    return 0; -- nothing to do
  end if; -- end of the check
  update public.away_dates set applied_at = now() where id = p_id; -- marks it applied, so it runs only once

  -- A student's own away dates: their sessions are cancelled straight away, as before.
  if v_a.student_id is not null then -- for a student's entry:
    with c as ( -- cancels their booked sessions on those dates:
      update public.sessions x -- the sessions
      set status = 'cancelled', cancelled_at = v_a.created_at, cancelled_by = v_a.created_by, -- cancelled from when the dates were entered (full credit for early notice),
          cancelled_by_role = 'family', cancel_reason_kind = 'away', -- by the family, because they are away,
          cancel_reason = left(coalesce('Away: ' || nullif(trim(v_a.reason), ''), 'Away'), 500) -- with the reason they gave
      from public.students s -- (with the student, for their time zone)
      where s.id = x.student_id -- matched to the session's student
        and x.status = 'scheduled' -- only sessions still booked
        and x.starts_at > now() -- only ones still to come
        and x.student_id = v_a.student_id -- only this student's
        and (x.starts_at at time zone private.state_timezone(s.state))::date between v_a.from_date and v_a.to_date -- only on the away dates (local time)
      returning x.id -- each one cancelled
    )
    select count(*) into v_count from c; -- how many
    return v_count; -- hands it back
  end if; -- end of the student part

  -- A tutor's away dates: nothing is cancelled; the admins are told which sessions need sorting out.
  select count(*), string_agg(s.full_name || ' ' || private.when_text(x.starts_at), '; ' order by x.starts_at) -- how many, and each student and time,
    into v_count, v_list -- kept for the notice
  from public.sessions x join public.students s on s.id = x.student_id -- from the sessions, with their students
  where x.status = 'scheduled' and x.starts_at > now() and x.tutor_id = v_a.tutor_id -- this tutor's booked sessions still to come
    and (x.starts_at at time zone private.state_timezone(s.state))::date between v_a.from_date and v_a.to_date; -- on the away dates (local time)
  if v_count > 0 then -- if any are affected:
    select full_name into v_tutor from public.accounts where id = v_a.tutor_id; -- the tutor's name
    perform private.notify_admins('Tutor away: ' || coalesce(v_tutor, 'a tutor'), -- tells the owner and Operations admins:
      coalesce(v_tutor, 'A tutor') || ' is away ' || to_char(v_a.from_date, 'FMDD Mon') -- who is away and from when,
      || case when v_a.to_date <> v_a.from_date then ' to ' || to_char(v_a.to_date, 'FMDD Mon') else '' end -- to when,
      || '. ' || v_count || ' booked session' || case when v_count = 1 then ' falls' else 's fall' end || ' on these dates: ' || v_list || '. ' -- which sessions,
      || 'Nothing has been cancelled. Offer each family another time or tutor, or cancel the session, under Sessions > Away dates.' -- what to do,
      || coalesce(' The tutor can offer instead: ' || nullif(trim(v_a.tutor_offer), '') || '.', '')); -- and what the tutor offered (if anything)
  end if; -- end of the notice
  return 0; -- nothing was cancelled
end; -- end of the code
$$; -- end of the function
revoke all on function private.apply_away_entry(uuid) from public; -- inside use only

-- ---------------------------------------------------------------------------
-- 2. The sessions that fall on a tutor's away dates (for admins)
-- ---------------------------------------------------------------------------
create or replace function private.tutor_away_entry_for(p_session uuid) -- one session
returns uuid -- the tutor away entry it falls in (none if it does not)
language sql stable security definer -- reads sessions and away dates
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select a.id -- the away entry
  from public.sessions x -- from the session
  join public.students s on s.id = x.student_id -- with its student (for their time zone)
  join public.away_dates a on a.tutor_id = x.tutor_id -- and the tutor's away entries
  where x.id = p_session -- this session
    and x.status = 'scheduled' and x.starts_at > now() -- still booked and still to come
    and a.applied_at is not null -- the tutor's 2 hours to fix a mistake are over
    and (x.starts_at at time zone private.state_timezone(s.state))::date between a.from_date and a.to_date -- on the away dates (local time)
  order by a.created_at -- the earliest entry first
  limit 1; -- just one
$$; -- end of the function
revoke all on function private.tutor_away_entry_for(uuid) from public; -- inside use only

create or replace function public.tutor_away_sessions() -- no inputs
returns table ( -- one row per session to sort out:
  session_id uuid, starts_at timestamptz, ends_at timestamptz, -- the session and its time,
  student_name text, tutor_name text, subject text, -- who and what,
  away_from date, away_to date, reason text, tutor_offer text -- the away dates, the reason and the tutor's offer
)
language plpgsql stable security definer -- reads sessions and away dates for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG admins can see this list' using errcode = '42501'; -- plain message for anyone else
  end if; -- end of the check
  return query -- hands back:
    select x.id, x.starts_at, x.ends_at, s.full_name, t.full_name, x.subject, -- each session, its time, student, tutor and subject,
           a.from_date, a.to_date, a.reason, a.tutor_offer -- and the away entry it falls in
    from public.sessions x -- from the sessions
    join public.students s on s.id = x.student_id -- with their students
    join public.accounts t on t.id = x.tutor_id -- and tutors
    join public.away_dates a on a.id = private.tutor_away_entry_for(x.id) -- and the away entry (only sessions in one)
    where x.status = 'scheduled' and x.starts_at > now() -- still booked and still to come
    order by x.starts_at; -- soonest first
end; -- end of the code
$$; -- end of the function
revoke all on function public.tutor_away_sessions() from public, anon; -- not for signed-out visitors
grant execute on function public.tutor_away_sessions() to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- 3. An admin cancels one of those sessions (full credit; the family is told)
-- ---------------------------------------------------------------------------
create or replace function public.cancel_for_tutor_away(p_session uuid) -- the session
returns void -- nothing to hand back
language plpgsql security definer -- changes the session for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_away uuid; -- the away entry the session falls in
  v_a public.away_dates; -- that entry
  v_s public.sessions; -- the session
  v_tutor text; -- the tutor's name
  v_student text; -- the student's first name
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG admins can cancel a session for tutor away dates' using errcode = '42501'; -- plain message for anyone else
  end if; -- end of the check
  v_away := private.tutor_away_entry_for(p_session); -- the away entry it falls in
  if v_away is null then -- not in one (or no longer booked):
    raise exception 'That session is no longer booked during the tutor''s away dates' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select * into v_a from public.away_dates where id = v_away; -- reads the entry
  update public.sessions -- cancels the session:
  set status = 'cancelled', cancelled_at = v_a.created_at, cancelled_by = auth.uid(), -- from when the dates were entered (full credit), by this admin,
      cancelled_by_role = 'tutor', cancel_reason_kind = 'away', -- for the tutor, because they are away,
      cancel_reason = 'Your tutor is not available that day. You can ask for another time or tutor under Sessions > Requests.' -- the reason the family sees
  where id = p_session and status = 'scheduled' -- this session, if still booked
  returning * into v_s; -- keeps it for the notice
  if v_s.id is null then -- someone else changed it first:
    raise exception 'That session is no longer booked' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select full_name into v_tutor from public.accounts where id = v_s.tutor_id; -- the tutor's name
  select split_part(full_name, ' ', 1) into v_student from public.students where id = v_s.student_id; -- the student's first name
  perform private.add_notice(p.account_id, null, null, 'tutor_away', 'Your tutor is away', -- tells the family:
    'We are sorry: ' || coalesce(v_tutor, 'your tutor') || ' is not available for ' || coalesce(v_student, 'your child') || '''s session (' -- who is away,
    || private.when_text(v_s.starts_at) || '), so it is cancelled and you will not be charged.' -- which session, and that there is no charge,
    || coalesce(' ' || split_part(v_tutor, ' ', 1) || ' can offer instead: ' || nullif(trim(v_a.tutor_offer), '') || '.', '') -- what the tutor offered (if anything),
    || ' If you would like another time or a different tutor, please ask under Sessions > Requests.', -- and how to ask for another time
    now()) -- now
  from private.session_people(v_s.student_id, v_s.tutor_id) p -- to the people linked to the session
  where not p.is_tutor; -- except the tutor
end; -- end of the code
$$; -- end of the function
revoke all on function public.cancel_for_tutor_away(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.cancel_for_tutor_away(uuid) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- 4. A number on Sessions > Away dates for admins while any are waiting
-- ---------------------------------------------------------------------------
grant execute on function private.tutor_away_entry_for(uuid) to authenticated, service_role; -- to_do_counts runs as the caller, so it needs this
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's code
  v_old text := E'  if v_admin then\n    area := ''sessions''; section := ''libraries'';\n'; -- the line the new count goes before
begin -- start
  if to_regprocedure('public.to_do_counts()') is null then return; end if; -- not there: nothing to do
  v_def := replace(pg_get_functiondef('public.to_do_counts()'::regprocedure), chr(13), ''); -- reads its current code (without Windows line endings)
  if strpos(v_def, 'tutor_away_entry_for') > 0 then return; end if; -- already added: nothing to do
  if strpos(v_def, v_old) = 0 then -- the place to add it has changed:
    raise exception 'to_do_counts has changed since this update was written. Ask for an updated file.'; -- stops, so nothing half-changes
  end if; -- end of the check
  v_def := replace(v_def, v_old, -- adds the away count before the libraries count:
    E'  if v_admin then\n' -- for owner and Operations admins:
    || E'    area := ''sessions''; section := ''away'';\n' -- the Away dates sub-tab,
    || E'    n := (select count(*) from public.sessions x where x.status = ''scheduled'' and x.starts_at > now() and private.tutor_away_entry_for(x.id) is not null); -- sessions on a tutor''s away dates\n'
    || E'    return next;\n' -- hands back the count,
    || E'  end if;\n' -- end of the admin part,
    || v_old); -- then the libraries count as before
  execute v_def; -- saves the changed function
end; -- finish
$$; -- end of the block
