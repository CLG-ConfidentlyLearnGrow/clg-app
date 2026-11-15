-- Summary: moving a student's booked sessions to a new tutor (scheduling
-- module, Carla 15 Nov 2026).
--
-- Until now, the only way to give a student a new tutor was to cancel their
-- sessions and book again. That loses the link between a session and the
-- invoice it was paid on, so pre-paid sessions looked unpaid. Now a matching
-- admin (owner, operations or support) can move a student's upcoming sessions
-- in one subject from one tutor to another, from a chosen date:
--   * the same sessions are kept (same times, places, Teams links and
--     invoice lines), only the tutor changes, so paid sessions stay paid;
--   * a weekly booking that has already started is split: the old tutor's
--     part ends before the change date, and a new booking with the new
--     tutor carries on to the same end date (marked as continuing the old
--     one, so "next term" offers and reports treat it as the same booking);
--   * a booking request still waiting for the old tutor goes to the new
--     tutor to accept instead;
--   * the new tutor is matched with the student (so they can read the notes),
--     and the old tutor's match for that subject ends;
--   * the new tutor and the family get a notice; the old tutor gets a plain
--     "moved to another tutor" notice unless the admin unticks it (for
--     example, when a child safety concern is being looked into);
--   * the usual matching rules apply: the new tutor must hold in-date checks
--     for the student's state, teach the subject at the student's level, be
--     free at those times, teach at the library (for library sessions), stay
--     within their most hours per week, and not be blocked from the student.
-- Each change is recorded in tutor_changes (who, what, when and a short
-- reason) for matching admins.
--
-- This module only writes scheduling tables and the tutor matches (as
-- confirming a booking already does). It never writes billing, Teams or
-- child safety tables. Needs 20261117400100_safety_quiet_steps.sql (for the
-- latest pairing check). Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The record of each change
-- ---------------------------------------------------------------------------

-- One row each time an admin moves a student's sessions to a new tutor.
create table if not exists public.tutor_changes ( -- the list of tutor changes
  id uuid primary key default gen_random_uuid(), -- the change's id
  student_id uuid not null references public.students (id) on delete cascade, -- the student
  from_tutor uuid references public.accounts (id) on delete set null, -- the tutor the sessions were with
  to_tutor uuid references public.accounts (id) on delete set null, -- the tutor they moved to
  subject text not null check (char_length(subject) between 1 and 100), -- the subject
  from_date date not null, -- the first date that moved
  sessions_moved integer not null default 0 check (sessions_moved >= 0), -- how many sessions moved
  bookings_moved integer not null default 0 check (bookings_moved >= 0), -- how many weekly bookings moved or were split
  reason text not null check (char_length(reason) between 2 and 500), -- a short reason, e.g. "Tutor leaving CLG"
  told_old_tutor boolean not null default true, -- whether the old tutor was sent a notice
  changed_by uuid references public.accounts (id) on delete set null, -- the admin who made the change
  changed_at timestamptz not null default now() -- when
); -- end of the table
create index if not exists tutor_changes_student on public.tutor_changes (student_id, changed_at desc); -- finds a student's changes quickly
alter table public.tutor_changes enable row level security; -- turns on access rules
revoke all on public.tutor_changes from anon, authenticated; -- nobody changes it directly (only the function below writes it)
grant select on public.tutor_changes to authenticated; -- signed-in people may read, but only rows the rule below allows
drop policy if exists "matching admins read tutor changes" on public.tutor_changes; -- removes the old rule if the file is run again
create policy "matching admins read tutor changes" on public.tutor_changes -- the reading rule:
  for select to authenticated using (private.is_front_desk() and private.has_aal2()); -- only matching admins, with two-step sign-in
drop trigger if exists audit on public.tutor_changes; -- removes the old audit trigger if the file is run again
create trigger audit after insert or update or delete on public.tutor_changes -- records every change in the audit log
  for each row execute function private.audit_change(); -- using the shared audit step

-- ---------------------------------------------------------------------------
-- Which sessions would move
-- ---------------------------------------------------------------------------

-- The ids of a student's upcoming sessions with a tutor in one subject, from
-- a date (in the student's own time zone). Used by the functions below so
-- they all agree on what moves.
create or replace function private.sessions_to_move(p_student uuid, p_tutor uuid, p_subject text, p_from date) -- takes the student, tutor, subject and first date
returns uuid[] -- gives back the session ids, soonest first
language sql stable security definer -- reads the sessions past the access rules
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select coalesce(array_agg(s.id order by s.starts_at), '{}') -- the ids, soonest first (empty if none)
  from public.sessions s -- from the sessions
  join public.students st on st.id = s.student_id -- with the student (for their time zone)
  where s.student_id = p_student and s.tutor_id = p_tutor -- this student and tutor
    and lower(s.subject) = lower(btrim(p_subject)) -- this subject
    and s.status = 'scheduled' and s.starts_at > now() -- still to come
    and (s.starts_at at time zone coalesce(private.state_timezone(st.state), 'Australia/Adelaide'))::date >= p_from -- on or after the change date
$$; -- end of the function
revoke all on function private.sessions_to_move(uuid, uuid, text, date) from public; -- for the database's own use only

-- ---------------------------------------------------------------------------
-- For the "Change tutor" page: the students who have sessions booked
-- ---------------------------------------------------------------------------

-- Each student, tutor and subject with upcoming sessions, with how many are
-- already on an invoice. Optionally just one student, or matching a search.
create or replace function public.tutor_change_pairs(p_student uuid default null, p_search text default null) -- takes an optional student and search words
returns table (student_id uuid, student_name text, tutor_id uuid, tutor_name text, subject text, upcoming_sessions integer, paid_sessions integer, first_session timestamptz, last_session timestamptz, weekly_bookings integer) -- what the page lists
language plpgsql stable security definer -- reads past the access rules, for matching admins only
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if not (private.is_front_desk() and private.has_aal2()) then -- not a matching admin with two-step sign-in
    raise exception 'Only CLG admins who do matching can change a tutor.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  return query -- gives back:
  select s.student_id, st.full_name, s.tutor_id, a.full_name, min(s.subject), -- the student, tutor and subject,
    count(*)::integer, -- how many sessions are booked,
    (count(*) filter (where exists ( -- how many are on a live invoice:
      select 1 from public.billing_invoice_lines l -- an invoice line (billing's table, only read here)
      join public.billing_invoices i on i.id = l.invoice_id -- on an invoice
      where l.session_id = s.id and l.active and i.status <> 'void' -- for this session, not voided
    )))::integer, -- (paid, or sent and waiting)
    min(s.starts_at), max(s.starts_at), -- the first and last of them,
    count(distinct s.booking_id)::integer -- and how many weekly bookings they come from
  from public.sessions s -- from the sessions
  join public.students st on st.id = s.student_id -- with the student's name
  join public.accounts a on a.id = s.tutor_id -- and the tutor's name
  where s.status = 'scheduled' and s.starts_at > now() -- still to come
    and (p_student is null or s.student_id = p_student) -- just this student, if one was chosen
    and (coalesce(btrim(p_search), '') = '' -- and, if search words were given,
         or st.full_name ilike '%' || btrim(p_search) || '%' -- the student's name
         or a.full_name ilike '%' || btrim(p_search) || '%') -- or the tutor's name matches
  group by s.student_id, st.full_name, s.tutor_id, a.full_name, lower(s.subject) -- one row per student, tutor and subject
  order by st.full_name, a.full_name, lower(s.subject) -- by student, then tutor, then subject
  limit 200; -- at most 200 rows
end; -- ends the code
$$; -- end of the function
revoke all on function public.tutor_change_pairs(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.tutor_change_pairs(uuid, text) to authenticated; -- signed-in people can try (the check is inside)

-- The tutors who could take over, with anything that would stop the move:
-- clashing sessions, a library they don't teach at, or going past their
-- most hours. Only tutors who are cleared, teach the subject at the
-- student's level and aren't blocked from the student are listed.
create or replace function public.tutor_change_candidates(p_student uuid, p_from_tutor uuid, p_subject text, p_from date) -- takes the student, current tutor, subject and change date
returns table (tutor_id uuid, full_name text, clashes integer, first_clash timestamptz, missing_library text, booked_minutes integer, added_minutes integer, max_weekly_hours numeric, at_max boolean, teaches_sibling boolean) -- each tutor and what stands in the way
language plpgsql stable security definer -- reads past the access rules, for matching admins only
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_ids uuid[]; -- the sessions that would move
  v_level text; -- the level the student works at in this subject
  v_family uuid; -- the student's family (for siblings)
  v_added integer; -- the weekly minutes of the bookings that would move
begin -- starts the code
  if not (private.is_front_desk() and private.has_aal2()) then -- not a matching admin with two-step sign-in
    raise exception 'Only CLG admins who do matching can change a tutor.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  v_ids := private.sessions_to_move(p_student, p_from_tutor, p_subject, coalesce(p_from, current_date)); -- the sessions that would move
  v_level := private.matching_level(p_student, p_subject); -- the student's level in the subject
  select family_id into v_family from public.students where id = p_student; -- the student's family
  select coalesce(sum(b.minutes), 0)::integer into v_added from public.bookings b -- adds up the weekly minutes
  where b.id in (select x.booking_id from public.sessions x where x.id = any(v_ids)) -- of the bookings those sessions belong to
     or (b.student_id = p_student and b.tutor_id = p_from_tutor and lower(b.subject) = lower(btrim(p_subject)) -- plus requests still waiting for the old tutor
         and b.status = 'requested' and private.booking_is_live(b.status, b.tutor_reply_by) and b.last_date >= coalesce(p_from, current_date)); -- (live, and running past the date)
  return query -- gives back:
  with candidates as ( -- the tutors who could teach this student this subject:
    select t.account_id as tid, a.full_name as tname, w.max_weekly_hours as maxh -- each tutor, their name and most hours
    from public.tutor_profiles t -- from the tutors
    join public.accounts a on a.id = t.account_id -- with their names
    left join public.tutor_work_settings w on w.tutor_id = t.account_id -- and their work settings
    where t.active and t.account_id <> p_from_tutor -- active, and not the current tutor
      and private.tutor_cleared_for_student(t.account_id, p_student) -- holding the checks for the student's state
      and private.tutor_teaches(t.account_id, p_subject, v_level) -- teaching the subject at the student's level
      and not private.blocked_pair(t.account_id, p_student) -- and not blocked from this student
  ), -- end of candidates
  booked as ( -- each tutor's weekly minutes already booked:
    select b.tutor_id as tid, sum(b.minutes)::integer as mins -- the tutor and their minutes
    from public.bookings b -- from the bookings
    where private.booking_is_live(b.status, b.tutor_reply_by) and b.last_date >= current_date -- live and still running
    group by b.tutor_id -- one total per tutor
  ) -- end of booked
  select c.tid, c.tname, -- the tutor and their name,
    (select count(*)::integer from public.sessions m join public.sessions o -- how many moving sessions clash with
       on o.tutor_id = c.tid and o.status = 'scheduled' and o.starts_at < m.ends_at and o.ends_at > m.starts_at -- one of the tutor's booked sessions
     where m.id = any(v_ids)), -- (counting the moving ones)
    (select min(m.starts_at) from public.sessions m join public.sessions o -- the first clash
       on o.tutor_id = c.tid and o.status = 'scheduled' and o.starts_at < m.ends_at and o.ends_at > m.starts_at -- (same test)
     where m.id = any(v_ids)), -- (among the moving ones)
    (select min(l.name) from public.sessions m join public.libraries l on l.id = m.library_id -- a library the moving sessions use
     where m.id = any(v_ids) and m.delivery = 'library' -- (library sessions only)
       and not exists (select 1 from public.tutor_places tp where tp.tutor_id = c.tid and tp.library_id = m.library_id)), -- that the tutor doesn't teach at
    coalesce(bk.mins, 0), v_added, c.maxh, -- minutes booked, minutes added, and their most hours,
    c.maxh is not null and coalesce(bk.mins, 0) + v_added > c.maxh * 60, -- whether this would take them past it,
    exists (select 1 from public.tutor_assignments ta join public.students s2 on s2.id = ta.student_id -- whether they teach a brother or sister:
            where ta.tutor_id = c.tid and v_family is not null and s2.family_id = v_family and s2.id <> p_student -- another child in the family
              and private.assignment_is_current(ta.starts_on, ta.ends_on)) -- with a current match
  from candidates c -- for each candidate
  left join booked bk on bk.tid = c.tid -- with their booked minutes
  order by 3, 9, 10 desc, 2; -- fewest clashes first, then within their hours, then siblings' tutor, then by name
end; -- ends the code
$$; -- end of the function
revoke all on function public.tutor_change_candidates(uuid, uuid, text, date) from public, anon; -- not for signed-out visitors
grant execute on function public.tutor_change_candidates(uuid, uuid, text, date) to authenticated; -- signed-in people can try (the check is inside)

-- ---------------------------------------------------------------------------
-- Making the change
-- ---------------------------------------------------------------------------

-- Moves a student's upcoming sessions in one subject from one tutor to
-- another, from a date. Gives back how many sessions moved.
create or replace function public.change_session_tutor( -- the change itself
  p_student uuid, -- the student
  p_from_tutor uuid, -- the tutor the sessions are with now
  p_subject text, -- the subject
  p_to_tutor uuid, -- the new tutor
  p_from date, -- the first date to move (today or later)
  p_reason text, -- a short reason, kept for admins
  p_tell_old_tutor boolean default true -- whether to send the old tutor a plain notice
) -- end of the inputs
returns integer -- gives back how many sessions moved
language plpgsql security definer -- changes sessions, bookings and matches past the access rules
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_student public.students; -- the student
  v_tz text; -- the student's time zone
  v_level text; -- the student's level in the subject
  v_reason text := btrim(coalesce(p_reason, '')); -- the reason, trimmed
  v_ids uuid[]; -- the sessions that move
  v_requests uuid[]; -- the booking requests that move
  v_subject text; -- the subject, as written on the sessions
  v_library text; -- a library the new tutor doesn't teach at
  v_clash timestamptz; -- the first clashing session
  v_booked integer; -- the new tutor's weekly minutes already booked
  v_added integer; -- the weekly minutes that would move to them
  v_max numeric; -- the new tutor's most hours per week
  v_b public.bookings; -- one booking being moved
  v_new public.bookings; -- the new booking made when one is split
  v_first date; -- the first moved date in a booking
  v_until date; -- the last date the new tutor teaches this student (for the match)
  v_first_at timestamptz; -- when the first moved session starts
  v_moved integer := 0; -- how many sessions moved
  v_bookings integer := 0; -- how many bookings moved or were split
  v_to_name text; -- the new tutor's name
  v_change uuid; -- the change record's id
  p record; -- one person to tell
begin -- starts the code
  -- Who may do this, and the basic answers.
  if not (private.is_front_desk() and private.has_aal2()) then -- not a matching admin with two-step sign-in
    raise exception 'Only CLG admins who do matching can change a tutor.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if char_length(v_reason) < 2 or char_length(v_reason) > 500 then -- no reason, or too long
    raise exception 'Please give a short reason (up to 500 characters), e.g. "Tutor leaving CLG".' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_from is null or p_from < current_date then -- no date, or a past date
    raise exception 'Please choose a change date of today or later.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_to_tutor is null or p_to_tutor = p_from_tutor then -- no new tutor, or the same one
    raise exception 'Please choose a different tutor.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select * into v_student from public.students where id = p_student; -- the student
  if v_student.id is null then -- not found
    raise exception 'Student not found.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_tz := coalesce(private.state_timezone(v_student.state), 'Australia/Adelaide'); -- the student's time zone
  v_level := private.matching_level(p_student, p_subject); -- the student's level in this subject

  -- The new tutor must be allowed to teach this student this subject.
  if not exists (select 1 from public.tutor_profiles where account_id = p_to_tutor and active) then -- not an active tutor
    raise exception 'Please choose an active tutor.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if private.blocked_pair(p_to_tutor, p_student) then -- blocked from this student
    raise exception 'That tutor can''t be matched with this student. Please choose another tutor.' using errcode = '22023'; -- plain message (no reason given)
  end if; -- end of the check
  if not private.tutor_cleared_for_student(p_to_tutor, p_student) then -- missing checks for the student's state
    raise exception 'That tutor doesn''t hold every in-date check needed for this student''s state.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if not private.tutor_teaches(p_to_tutor, p_subject, v_level) then -- doesn't teach the subject at this level
    raise exception 'That tutor doesn''t teach % at this student''s level.', btrim(p_subject) using errcode = '22023'; -- plain message
  end if; -- end of the check

  -- What moves: upcoming sessions from the date, and requests still waiting.
  v_ids := private.sessions_to_move(p_student, p_from_tutor, p_subject, p_from); -- the sessions
  perform 1 from public.sessions where id = any(v_ids) for update; -- holds them so nothing else changes them meanwhile
  select coalesce(array_agg(b.id), '{}') into v_requests from public.bookings b -- the requests:
  where b.student_id = p_student and b.tutor_id = p_from_tutor and lower(b.subject) = lower(btrim(p_subject)) -- for this student, tutor and subject
    and b.status = 'requested' and private.booking_is_live(b.status, b.tutor_reply_by) and b.last_date >= p_from; -- still waiting, and running past the date
  if cardinality(v_ids) = 0 and cardinality(v_requests) = 0 then -- nothing to move
    raise exception 'There are no upcoming sessions with this tutor in that subject from that date.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select coalesce((select subject from public.sessions where id = v_ids[1]), (select subject from public.bookings where id = v_requests[1])) into v_subject; -- the subject as written

  -- The new tutor must teach at the libraries used, be free, and stay within their hours.
  select min(l.name) into v_library from public.sessions s join public.libraries l on l.id = s.library_id -- a library used
  where s.id = any(v_ids) and s.delivery = 'library' -- by a moving library session
    and not exists (select 1 from public.tutor_places tp where tp.tutor_id = p_to_tutor and tp.library_id = s.library_id); -- that the new tutor doesn't teach at
  if v_library is not null then -- one found
    raise exception 'That tutor doesn''t teach at %. Choose another tutor, or change where the sessions are first.', v_library using errcode = '22023'; -- plain message
  end if; -- end of the check
  select min(m.starts_at) into v_clash from public.sessions m join public.sessions o -- the first moving session that clashes
    on o.tutor_id = p_to_tutor and o.status = 'scheduled' and o.starts_at < m.ends_at and o.ends_at > m.starts_at -- with one of the new tutor's sessions
  where m.id = any(v_ids); -- (among the moving ones)
  if v_clash is not null then -- a clash
    raise exception 'That tutor already has a session at the same time on %. Choose another tutor, or move that session first.', private.when_text(v_clash) using errcode = '22023'; -- plain message
  end if; -- end of the check
  select w.max_weekly_hours into v_max from public.tutor_work_settings w where w.tutor_id = p_to_tutor; -- their most hours (if set)
  if v_max is not null then -- a limit is set
    select coalesce(sum(b.minutes), 0)::integer into v_booked from public.bookings b -- their weekly minutes already booked
    where b.tutor_id = p_to_tutor and private.booking_is_live(b.status, b.tutor_reply_by) and b.last_date >= current_date; -- (live and still running)
    select coalesce(sum(b.minutes), 0)::integer into v_added from public.bookings b -- the weekly minutes that would move to them
    where b.id in (select x.booking_id from public.sessions x where x.id = any(v_ids)) or b.id = any(v_requests); -- (bookings of the moving sessions, and requests)
    if v_booked + v_added > v_max * 60 then -- past their limit
      raise exception 'That would take this tutor past their most hours per week (% hr). Choose another tutor, or change their hours first.', v_max using errcode = '22023'; -- plain message
    end if; -- end of the check
  end if; -- end of the hours check

  -- Weekly bookings: move the whole booking if it hasn't started, otherwise split it.
  for v_b in select b.* from public.bookings b -- each booking
    where b.id in (select x.booking_id from public.sessions x where x.id = any(v_ids)) -- that a moving session belongs to
    for update -- held while it changes
  loop -- for each one:
    select min((s.starts_at at time zone v_tz)::date) into v_first from public.sessions s -- the first moving date in this booking
    where s.booking_id = v_b.id and s.id = any(v_ids); -- (moving sessions only)
    if v_first <= v_b.first_date then -- the booking hasn't started yet
      update public.bookings set tutor_id = p_to_tutor where id = v_b.id; -- the whole booking moves to the new tutor
    else -- the booking has already started
      v_new := v_b; -- copies the booking (days, times, place, holidays, end date)
      v_new.id := gen_random_uuid(); -- a new id
      v_new.tutor_id := p_to_tutor; -- with the new tutor
      v_new.first_date := v_first; -- starting at the first moving date
      v_new.status := 'confirmed'; -- already confirmed (the admin arranged it)
      v_new.renews_booking := v_b.id; -- marked as carrying on the old booking
      v_new.requested_by := auth.uid(); -- made by this admin
      v_new.requested_at := now(); -- now
      v_new.tutor_reply_by := now(); -- (nothing to reply to)
      v_new.tutor_ok_at := now(); -- the tutor's yes is the admin's arrangement
      v_new.needs_family_ok := false; -- the family doesn't need to approve again (same times)
      v_new.confirmed_at := now(); -- confirmed now
      v_new.ended_at := null; -- not ended
      v_new.follow_up_sent_at := null; -- no follow-ups sent yet
      v_new.not_answered_notice_at := null; -- no "not answered" notice yet
      v_new.created_at := now(); -- made now
      insert into public.bookings select (v_new).*; -- saves the new booking
      update public.bookings set last_date = v_first - 1 where id = v_b.id; -- the old booking ends the day before
      update public.sessions set booking_id = v_new.id where booking_id = v_b.id and id = any(v_ids); -- the moving sessions now belong to the new booking
    end if; -- end of move or split
    v_until := greatest(v_until, v_b.last_date); -- the new tutor teaches at least until this booking ends
    v_bookings := v_bookings + 1; -- counts it
  end loop; -- end of the bookings

  -- Requests still waiting: the new tutor accepts or declines instead.
  update public.bookings set tutor_id = p_to_tutor, tutor_ok_at = null, tutor_reply_by = now() + interval '48 hours' -- the new tutor, with a fresh 48 hours to answer
  where id = any(v_requests); -- (the waiting requests)
  v_bookings := v_bookings + cardinality(v_requests); -- counts them

  -- The sessions themselves: only the tutor changes (times, places, links and invoices stay).
  update public.sessions set tutor_id = p_to_tutor where id = any(v_ids); -- moves them
  get diagnostics v_moved = row_count; -- how many moved
  delete from public.session_notices -- reminders not yet sent for them (they named the old tutor):
  where session_id = any(v_ids) and kind in ('reminder_first', 'reminder_final') and deliver_at > now(); -- are made again with the new tutor's name on the next run
  select min(starts_at), greatest(v_until, max((starts_at at time zone v_tz)::date)) into v_first_at, v_until -- the first moved session, and the last date taught
  from public.sessions where id = any(v_ids); -- (from the moved sessions)
  v_until := greatest(v_until, (select max(last_date) from public.bookings where id = any(v_requests)), current_date); -- (or the requests' end dates, and at least today)

  -- The matches: the new tutor is matched (so they can read the notes), the old one's match ends.
  if exists (select 1 from public.tutor_assignments a -- the new tutor already has a current match
             where a.tutor_id = p_to_tutor and a.student_id = p_student and lower(a.subject) = lower(v_subject) -- for this student and subject
               and private.assignment_is_current(a.starts_on, a.ends_on)) then -- (current)
    update public.tutor_assignments a set ends_on = greatest(a.ends_on, v_until) -- stretches it to the last date, if it has an end
    where a.tutor_id = p_to_tutor and a.student_id = p_student and lower(a.subject) = lower(v_subject) -- (that match)
      and private.assignment_is_current(a.starts_on, a.ends_on) and a.ends_on is not null and a.ends_on < v_until; -- (only when it ends too soon)
  else -- no match yet
    insert into public.tutor_assignments (tutor_id, student_id, subject, starts_on, ends_on, created_by) -- adds one
    values (p_to_tutor, p_student, v_subject, current_date, v_until, auth.uid()); -- from today until the last date (the usual checks run here)
  end if; -- end of the new tutor's match
  update public.tutor_assignments a set ends_on = greatest(a.starts_on, current_date, p_from - 1) -- the old tutor's match ends the day before the change (or today)
  where a.tutor_id = p_from_tutor and a.student_id = p_student and lower(a.subject) = lower(v_subject) -- for this student and subject
    and private.assignment_is_current(a.starts_on, a.ends_on) -- (current)
    and (a.ends_on is null or a.ends_on > greatest(a.starts_on, current_date, p_from - 1)) -- (only if it would end later)
    and not exists (select 1 from public.sessions s -- and they have no other sessions left after that
                    where s.tutor_id = p_from_tutor and s.student_id = p_student and lower(s.subject) = lower(v_subject) -- (same pair and subject)
                      and s.status = 'scheduled' and (s.starts_at at time zone v_tz)::date > greatest(current_date, p_from - 1)); -- (still to come, after the end)

  -- Tells the people involved (the notices go out as emails too, outside quiet hours).
  select full_name into v_to_name from public.accounts where id = p_to_tutor; -- the new tutor's name
  perform private.add_notice(p_to_tutor, null, null, 'booking_confirmed', 'Sessions added', -- the new tutor:
    split_part(v_student.full_name, ' ', 1) || ' (' || v_subject || '): ' -- the student's first name and subject,
    || case when v_moved > 0 then v_moved || ' upcoming session(s) from ' || private.when_text(v_first_at) || ' are now with you. Please read their notes before the first one.' -- the sessions now theirs,
            else 'a booking request is now with you. Please accept or decline under Sessions within 48 hours.' end, now()); -- or a request to answer
  for p in select * from private.session_people(p_student, p_to_tutor) where not is_tutor loop -- each parent (and the student, with their own login):
    perform private.add_notice(p.account_id, null, null, 'booking_confirmed', 'New tutor', -- a notice:
      v_student.full_name || '''s ' || v_subject || ' sessions' -- the student's sessions in the subject,
      || case when v_first_at is not null then ' from ' || private.when_text(v_first_at) else '' end -- from the first date,
      || ' will be with ' || coalesce(v_to_name, 'a new tutor') || '. Times and places stay the same. Please contact CLG if you have any questions.', now()); -- are with the new tutor
  end loop; -- end of the family
  if p_tell_old_tutor then -- the admin chose to tell the old tutor
    perform private.add_notice(p_from_tutor, null, null, 'session_cancelled', 'Sessions moved', -- a plain notice, with no reason:
      split_part(v_student.full_name, ' ', 1) || '''s ' || v_subject || ' sessions' -- the student's first name and subject,
      || case when v_first_at is not null then ' from ' || private.when_text(v_first_at) else '' end -- from the first date,
      || ' have moved to another CLG tutor. You don''t need to do anything.', now()); -- moved, nothing to do
  end if; -- end of the old tutor's notice

  -- Keeps a record for admins, and notes it in the activity log (ids only).
  insert into public.tutor_changes (student_id, from_tutor, to_tutor, subject, from_date, sessions_moved, bookings_moved, reason, told_old_tutor, changed_by) -- the record:
  values (p_student, p_from_tutor, p_to_tutor, v_subject, p_from, v_moved, v_bookings, v_reason, coalesce(p_tell_old_tutor, true), auth.uid()) -- what moved, why and who
  returning id into v_change; -- keeps its id
  perform private.log_event('tutor_changed', 'tutor_changes', v_change::text, '{}'); -- the activity log entry
  return v_moved; -- how many sessions moved
end; -- ends the code
$$; -- end of the function
revoke all on function public.change_session_tutor(uuid, uuid, text, uuid, date, text, boolean) from public, anon; -- not for signed-out visitors
grant execute on function public.change_session_tutor(uuid, uuid, text, uuid, date, text, boolean) to authenticated; -- signed-in people can try (the check is inside)

-- The last tutor changes for a student (or for everyone), for the page.
create or replace function public.recent_tutor_changes(p_student uuid default null) -- takes an optional student
returns table (id uuid, student_name text, from_tutor_name text, to_tutor_name text, subject text, from_date date, sessions_moved integer, reason text, changed_by_name text, changed_at timestamptz) -- what the page shows
language sql stable security invoker -- runs as the signed-in person, so the reading rule on tutor_changes applies
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select c.id, s.full_name, f.full_name, t.full_name, c.subject, c.from_date, c.sessions_moved, c.reason, b.full_name, c.changed_at -- each change, with names
  from public.tutor_changes c -- from the changes (only rows the reader may see)
  left join public.students s on s.id = c.student_id -- the student's name
  left join public.accounts f on f.id = c.from_tutor -- the old tutor's name
  left join public.accounts t on t.id = c.to_tutor -- the new tutor's name
  left join public.accounts b on b.id = c.changed_by -- the admin's name
  where p_student is null or c.student_id = p_student -- just this student, if one was chosen
  order by c.changed_at desc -- newest first
  limit 20 -- the last 20
$$; -- end of the function
revoke all on function public.recent_tutor_changes(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.recent_tutor_changes(uuid) to authenticated; -- signed-in people (only matching admins get rows)
