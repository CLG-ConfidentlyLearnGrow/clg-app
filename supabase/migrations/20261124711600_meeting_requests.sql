-- Summary: booking a meeting with Carla (Carla, 22 Nov 2026).
--
-- From the How We Do Things guide: anyone on staff who needs a meeting with
-- Carla sends a request that says what it is About, the Context, and the
-- Goal, and it is handled like a help desk request: it waits in one list
-- until Carla answers it. Carla agreed (22 Nov 2026) that the person asking
-- suggests 2 or 3 times and how urgent it is, and Carla confirms one.
--
-- What this adds (module: staff, which owns staff records outside pay):
--   * public.meeting_requests: one row per request, from a tutor or admin.
--   * Carla (CLG's owner) can: confirm one of the suggested times, offer a
--     different time (the person then accepts it or cancels), or answer
--     without a meeting, with a note. She marks a meeting as held afterwards.
--   * The person asking can cancel at any time before it is held.
--   * Each step sends an app notice to the other person.
--
-- Safe to run more than once. Run after 20261124711000_quiet_hours_count_from_5am.sql.

-- ---------------------------------------------------------------------------
-- 1. The requests
-- ---------------------------------------------------------------------------
create table if not exists public.meeting_requests ( -- one row per meeting request
  id uuid primary key default gen_random_uuid(), -- the request's id
  requester_id uuid not null references public.accounts (id) on delete cascade, -- who asked (removed with their account)
  about text not null check (char_length(btrim(about)) between 3 and 200), -- what it is about, in a few words
  context text not null check (char_length(btrim(context)) between 2 and 3000), -- the background Carla needs
  goal text not null check (char_length(btrim(goal)) between 2 and 1000), -- what the person wants to come away with
  urgency text not null check (urgency in ('urgent', 'this_week', 'no_rush')), -- how soon it is needed
  length_minutes integer not null default 30 check (length_minutes in (15, 30, 45, 60)), -- how long it needs
  how text not null default 'online' check (how in ('online', 'phone', 'in_person')), -- online, by phone, or in person
  suggested_times timestamptz[] not null check (cardinality(suggested_times) between 2 and 3), -- the 2 or 3 times the person can do
  status text not null default 'waiting' check (status in ('waiting', 'new_time', 'confirmed', 'answered', 'cancelled', 'held')), -- where it is up to
  meeting_at timestamptz, -- the confirmed time (or the different time Carla offered)
  owner_note text check (char_length(owner_note) <= 2000), -- Carla's note (for example the answer, or why a different time)
  cancel_note text check (char_length(cancel_note) <= 1000), -- why it was cancelled, if it was
  handled_by uuid references public.accounts (id) on delete set null, -- who answered it
  handled_at timestamptz, -- when it was first answered
  created_at timestamptz not null default now(), -- when it was sent
  updated_at timestamptz not null default now() -- when it last changed
); -- end of the table
create index if not exists meeting_requests_requester on public.meeting_requests (requester_id, created_at desc); -- finds a person's requests quickly
create index if not exists meeting_requests_open on public.meeting_requests (created_at) where status in ('waiting', 'new_time', 'confirmed'); -- lists open requests quickly
alter table public.meeting_requests enable row level security; -- access rules apply
revoke all on public.meeting_requests from anon; -- signed-out visitors get nothing
revoke insert, update, delete, truncate on public.meeting_requests from authenticated; -- changes only through the functions below
grant select on public.meeting_requests to authenticated; -- reading, limited by the rule below
drop trigger if exists audit on public.meeting_requests; -- replaces the change log trigger if run again
create trigger audit after insert or update or delete on public.meeting_requests -- logs every change
  for each row execute function private.audit_change(); -- in the shared change log
drop policy if exists "see meeting requests" on public.meeting_requests; -- replaces the rule if run again
create policy "see meeting requests" on public.meeting_requests -- who can read a row:
  for select to authenticated -- signed-in people
  using (requester_id = (select auth.uid()) or (select private.is_owner())); -- the person who asked, or CLG's owner

-- ---------------------------------------------------------------------------
-- 2. Helpers: words for a time, and notices
-- ---------------------------------------------------------------------------
-- A time in plain words, Adelaide time, for example "Wed 25 Nov, 10:30 am".
create or replace function private.meeting_time_words(p_at timestamptz) -- takes the moment
returns text language sql stable -- only reads
set search_path = '' -- no hidden schema lookups (safety)
as $$ select to_char(p_at at time zone 'Australia/Adelaide', 'Dy FMDD Mon, FMHH12:MI am') $$; -- the day, date and time in Adelaide
revoke all on function private.meeting_time_words(timestamptz) from public; -- inside use only

-- Tells CLG's owner about a request (every account at owner level).
create or replace function private.meeting_tell_owner(p_title text, p_body text) -- takes the notice title and words
returns void language plpgsql security definer -- writes notices for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_owner uuid; -- each owner account
begin -- start
  for v_owner in -- for each owner:
    select distinct ar.account_id from public.account_roles ar -- people with the admin role
    left join public.admin_profiles ap on ap.account_id = ar.account_id -- and their admin level
    where ar.role = 'admin' and coalesce(ap.level, 'owner') = 'owner' -- at owner level
  loop -- each one:
    perform private.add_notice(v_owner, null, null, 'staff_alert', p_title, p_body, now()); -- a staff notice, now (quiet hours still apply)
  end loop; -- next owner
end; -- end of the code
$$; -- end of the function
revoke all on function private.meeting_tell_owner(text, text) from public; -- inside use only

-- ---------------------------------------------------------------------------
-- 3. Staff send or cancel a request
-- ---------------------------------------------------------------------------
create or replace function public.meeting_request_send( -- sends a meeting request to Carla:
  p_about text, -- what it is about
  p_context text, -- the background
  p_goal text, -- what they want to come away with
  p_urgency text, -- urgent, this_week or no_rush
  p_length integer, -- minutes needed
  p_how text, -- online, phone or in_person
  p_times timestamp[] -- the 2 or 3 times they can do, as Adelaide clock times
)
returns uuid language plpgsql security definer -- writes for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_times timestamptz[]; -- the times as true moments
  v_id uuid; -- the new request
  v_name text; -- the person's name
begin -- start
  if not (private.has_role('tutor') or private.has_role('admin')) then -- not staff:
    raise exception 'Only CLG tutors and admin staff can book a meeting with Carla here.' using errcode = '42501'; -- plain refusal
  end if; -- end of the check
  if char_length(btrim(coalesce(p_about, ''))) < 3 or char_length(btrim(coalesce(p_context, ''))) < 2 or char_length(btrim(coalesce(p_goal, ''))) < 2 then -- missing words
    raise exception 'Please fill in what it is about, the context and your goal.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_urgency is null or p_urgency not in ('urgent', 'this_week', 'no_rush') then raise exception 'Please choose how urgent it is.' using errcode = '22023'; end if; -- urgency must be known
  if p_length is null or p_length not in (15, 30, 45, 60) then raise exception 'Please choose how long the meeting needs.' using errcode = '22023'; end if; -- length must be known
  if p_how is null or p_how not in ('online', 'phone', 'in_person') then raise exception 'Please choose how to meet.' using errcode = '22023'; end if; -- how must be known
  select array_agg(distinct t at time zone 'Australia/Adelaide' order by t at time zone 'Australia/Adelaide') into v_times -- turns each Adelaide clock time into a true moment, without repeats, earliest first
  from unnest(coalesce(p_times, '{}')) as t where t is not null; -- each time given
  if coalesce(cardinality(v_times), 0) < 2 or cardinality(v_times) > 3 then -- not 2 or 3 different times
    raise exception 'Please suggest 2 or 3 different times you can do.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if exists (select 1 from unnest(v_times) as t where t <= now()) then -- a time already past
    raise exception 'Each suggested time needs to be in the future.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.meeting_requests (requester_id, about, context, goal, urgency, length_minutes, how, suggested_times) -- saves the request:
  values (auth.uid(), left(btrim(p_about), 200), left(btrim(p_context), 3000), left(btrim(p_goal), 1000), p_urgency, p_length, p_how, v_times) -- with their words and times
  returning id into v_id; -- keeps its id
  select full_name into v_name from public.accounts where id = auth.uid(); -- their name, for the notice
  perform private.meeting_tell_owner( -- tells Carla:
    case when p_urgency = 'urgent' then 'Urgent meeting request' else 'Meeting request' end, -- the title (urgent ones say so)
    left(coalesce(v_name, 'A staff member') || ' asked for a meeting about "' || btrim(p_about) || '". See Meetings to choose a time.', 1000)); -- who, what and where
  return v_id; -- hands back the new request
end; -- end of the code
$$; -- end of the function
revoke all on function public.meeting_request_send(text, text, text, text, integer, text, timestamp[]) from public, anon; -- not for signed-out visitors
grant execute on function public.meeting_request_send(text, text, text, text, integer, text, timestamp[]) to authenticated; -- signed-in people (the check is inside)

create or replace function public.meeting_request_cancel(p_id uuid, p_note text) -- cancels a request (the person who asked, or the owner)
returns void language plpgsql security definer -- writes for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  r public.meeting_requests; -- the request
begin -- start
  select * into r from public.meeting_requests where id = p_id for update; -- reads it, holding it still
  if r.id is null or not (r.requester_id = auth.uid() or private.is_owner()) then -- not there, or not theirs
    raise exception 'That meeting request could not be found.' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
  if r.status not in ('waiting', 'new_time', 'confirmed') then raise exception 'That meeting request is already closed.' using errcode = '22023'; end if; -- only open ones
  update public.meeting_requests set status = 'cancelled', cancel_note = nullif(left(btrim(coalesce(p_note, '')), 1000), ''), updated_at = now() where id = p_id; -- cancels it, with any note
  if r.requester_id = auth.uid() then -- the person who asked cancelled:
    perform private.meeting_tell_owner('Meeting request cancelled', -- tells Carla
      left(coalesce((select full_name from public.accounts where id = r.requester_id), 'A staff member') || ' cancelled their meeting request about "' || r.about || '".', 1000)); -- who and which
  else -- the owner cancelled:
    perform private.add_notice(r.requester_id, null, null, 'staff_alert', 'Meeting cancelled', -- tells the person who asked
      left('Carla cancelled the meeting about "' || r.about || '".' || coalesce(' Note: ' || nullif(btrim(coalesce(p_note, '')), ''), '') || ' See Meetings.', 1000), now()); -- which, and any note
  end if; -- end of the choice
end; -- end of the code
$$; -- end of the function
revoke all on function public.meeting_request_cancel(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.meeting_request_cancel(uuid, text) to authenticated; -- signed-in people (the check is inside)

create or replace function public.meeting_request_accept_time(p_id uuid) -- the person who asked accepts the different time Carla offered
returns void language plpgsql security definer -- writes for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  r public.meeting_requests; -- the request
begin -- start
  update public.meeting_requests set status = 'confirmed', updated_at = now() -- confirms it
  where id = p_id and requester_id = auth.uid() and status = 'new_time' and meeting_at > now() returning * into r; -- only their own, with a different time offered that is still ahead
  if r.id is null then raise exception 'That time could not be accepted. It may have passed or changed.' using errcode = 'P0002'; end if; -- nothing to accept
  perform private.meeting_tell_owner('Meeting time accepted', -- tells Carla
    left(coalesce((select full_name from public.accounts where id = r.requester_id), 'A staff member') || ' accepted ' || private.meeting_time_words(r.meeting_at) || ' for the meeting about "' || r.about || '".', 1000)); -- who, when and which
end; -- end of the code
$$; -- end of the function
revoke all on function public.meeting_request_accept_time(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.meeting_request_accept_time(uuid) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- 4. Carla (CLG's owner) answers
-- ---------------------------------------------------------------------------
create or replace function public.meeting_request_confirm(p_id uuid, p_at timestamp, p_note text) -- confirms a time (Adelaide clock time); a time they did not suggest is offered to them instead
returns text language plpgsql security definer -- writes for the owner; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  r public.meeting_requests; -- the request
  v_at timestamptz := p_at at time zone 'Australia/Adelaide'; -- the time as a true moment
  v_status text; -- confirmed, or new_time when it is a different time
begin -- start
  if not private.is_owner() then raise exception 'Only Carla (CLG''s owner) answers meeting requests.' using errcode = '42501'; end if; -- owner only
  select * into r from public.meeting_requests where id = p_id for update; -- reads it, holding it still
  if r.id is null then raise exception 'That meeting request could not be found.' using errcode = 'P0002'; end if; -- not there
  if r.status not in ('waiting', 'new_time', 'confirmed') then raise exception 'That meeting request is already closed.' using errcode = '22023'; end if; -- only open ones
  if v_at is null or v_at <= now() then raise exception 'Please choose a time in the future.' using errcode = '22023'; end if; -- the time must be ahead
  v_status := case when v_at = any (r.suggested_times) then 'confirmed' else 'new_time' end; -- one of theirs is confirmed; any other time is offered
  update public.meeting_requests set status = v_status, meeting_at = v_at, owner_note = nullif(left(btrim(coalesce(p_note, '')), 2000), ''), -- the time and note
    handled_by = coalesce(handled_by, auth.uid()), handled_at = coalesce(handled_at, now()), updated_at = now() where id = p_id; -- who answered, and when
  perform private.add_notice(r.requester_id, null, null, 'staff_alert', -- tells the person who asked:
    case when v_status = 'confirmed' then 'Meeting confirmed' else 'Carla offered a different meeting time' end, -- the title
    left(case when v_status = 'confirmed' -- the words:
      then 'Your meeting with Carla about "' || r.about || '" is on ' || private.meeting_time_words(v_at) || '.' -- the confirmed time,
      else 'Carla cannot do your suggested times for "' || r.about || '". She offered ' || private.meeting_time_words(v_at) || '. Open Meetings to accept it or cancel.' end -- or the offered time,
      || coalesce(' Note: ' || nullif(btrim(coalesce(p_note, '')), ''), ''), 1000), now()); -- and any note
  return v_status; -- hands back what happened
end; -- end of the code
$$; -- end of the function
revoke all on function public.meeting_request_confirm(uuid, timestamp, text) from public, anon; -- not for signed-out visitors
grant execute on function public.meeting_request_confirm(uuid, timestamp, text) to authenticated; -- signed-in people (the check is inside)

create or replace function public.meeting_request_answer(p_id uuid, p_note text) -- answers without a meeting (like a help desk reply)
returns void language plpgsql security definer -- writes for the owner; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  r public.meeting_requests; -- the request
begin -- start
  if not private.is_owner() then raise exception 'Only Carla (CLG''s owner) answers meeting requests.' using errcode = '42501'; end if; -- owner only
  if char_length(btrim(coalesce(p_note, ''))) < 2 then raise exception 'Please write your answer.' using errcode = '22023'; end if; -- an answer is needed
  update public.meeting_requests set status = 'answered', meeting_at = null, owner_note = left(btrim(p_note), 2000), -- closes it with the answer
    handled_by = coalesce(handled_by, auth.uid()), handled_at = coalesce(handled_at, now()), updated_at = now() -- who answered, and when
  where id = p_id and status in ('waiting', 'new_time') returning * into r; -- only ones not yet confirmed
  if r.id is null then raise exception 'That meeting request could not be answered. It may be closed or already confirmed.' using errcode = 'P0002'; end if; -- nothing to answer
  perform private.add_notice(r.requester_id, null, null, 'staff_alert', 'Carla answered your meeting request', -- tells the person who asked
    left('Carla answered "' || r.about || '" without needing a meeting: ' || btrim(p_note), 1000), now()); -- which, and the answer
end; -- end of the code
$$; -- end of the function
revoke all on function public.meeting_request_answer(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.meeting_request_answer(uuid, text) to authenticated; -- signed-in people (the check is inside)

create or replace function public.meeting_request_held(p_id uuid) -- marks a confirmed meeting as held
returns void language plpgsql security definer -- writes for the owner; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_owner() then raise exception 'Only Carla (CLG''s owner) answers meeting requests.' using errcode = '42501'; end if; -- owner only
  update public.meeting_requests set status = 'held', updated_at = now() where id = p_id and status = 'confirmed'; -- marks it held
  if not found then raise exception 'Only a confirmed meeting can be marked as held.' using errcode = 'P0002'; end if; -- nothing to mark
end; -- end of the code
$$; -- end of the function
revoke all on function public.meeting_request_held(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.meeting_request_held(uuid) to authenticated; -- signed-in people (the check is inside)

-- The menu number: for the owner, requests waiting for an answer; for anyone
-- else, different times Carla offered that they have not answered yet.
create or replace function public.meeting_requests_to_do() -- no inputs
returns integer language sql stable security definer -- counts for the signed-in person
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the count
  select case when private.is_owner() -- the owner:
    then (select count(*)::integer from public.meeting_requests where status = 'waiting') -- requests waiting
    else (select count(*)::integer from public.meeting_requests where requester_id = auth.uid() and status = 'new_time') end -- anyone else: offered times to answer
$$; -- end of the count
revoke all on function public.meeting_requests_to_do() from public, anon; -- not for signed-out visitors
grant execute on function public.meeting_requests_to_do() to authenticated; -- signed-in people (the count is limited inside)
