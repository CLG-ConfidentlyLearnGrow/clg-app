-- Summary: a make-up time is only booked once everyone involved has agreed (Carla, 16 Nov 2026).
--
-- "A session which has been altered needs to be confirmed by the other or
-- all parties before being confirmed."
--
-- How make-up times work (20261118100100): whoever cancels offers two
-- times, and the other side picks one. When a tutor or family offers the
-- times themselves, their offer is their agreement and the pick is the
-- other side's, so both have agreed and the session is booked. Two gaps are
-- closed here:
--   * CLG staff can no longer pick a time on someone's behalf. Only the
--     tutor, or the family (a parent, or the student with their own login),
--     can pick.
--   * When CLG staff cancel and offer the times (for CLG, or for the tutor
--     or family after a phone call), neither side has agreed yet. Then one
--     side picks, the other side confirms, and only then is the make-up
--     booked. Until then it shows as "waiting for confirmation". If they
--     can't do it they say why, and CLG is told.
-- One parent (or the student 16+) answers for the family, as with every
-- other booking approval.
--
-- Needs 20261118100100_cancel_reasons_makeup_times.sql first. Safe to run
-- more than once.

-- ---------------------------------------------------------------------------
-- 1. Offers made by CLG staff need both sides
-- ---------------------------------------------------------------------------
alter table public.session_makeup_offers add column if not exists needs_both boolean not null default false; -- true when CLG offered the times, so both sides must agree
alter table public.session_makeup_offers drop constraint if exists session_makeup_offers_status_check; -- removes the old list of stages, so it can be replaced
alter table public.session_makeup_offers add constraint session_makeup_offers_status_check check ( -- the stages an offer can be at:
  status in ('waiting', 'confirming', 'picked', 'declined', 'expired', 'none_offered') -- now with "confirming": picked by one side, waiting for the other
); -- end of the rule

-- Marks an offer as needing both sides when CLG staff make it. (Anyone at
-- CLG's front desk who cancels does so as CLG, even for a tutor or family.)
create or replace function private.makeup_needs_both() -- a trigger function (no inputs)
returns trigger -- hands back the row to save
language plpgsql security definer -- reads the person's admin level
set search_path = '' -- only fully named things, for safety
as $$ -- the steps
begin -- start
  new.needs_both := private.is_front_desk(); -- CLG staff offered the times: both sides must agree
  return new; -- saves the row
end; -- finish
$$; -- end of the function
revoke all on function private.makeup_needs_both() from public; -- only run by the trigger below
drop trigger if exists needs_both on public.session_makeup_offers; -- replaces the trigger if this is run again
create trigger needs_both before insert on public.session_makeup_offers -- before a new offer is saved:
  for each row execute function private.makeup_needs_both(); -- work out whether both sides must agree

-- ---------------------------------------------------------------------------
-- 2. Helpers
-- ---------------------------------------------------------------------------

-- Whether the signed-in person is on this side of the session themselves
-- (not CLG staff acting for them): the tutor, or the family.
create or replace function private.is_makeup_side(p_student uuid, p_tutor uuid, p_side text) -- takes the student, tutor and side
returns boolean -- yes or no
language sql stable security definer -- reads the links whoever asks
set search_path = '' -- only fully named things, for safety
as $$ -- the check
  select case p_side -- by side:
    when 'tutor' then p_tutor = auth.uid() and private.has_role('tutor') and private.has_aal2() -- the tutor with two-step sign-in,
                      and private.tutor_cleared_for_student(p_tutor, p_student) -- while their checks for this student are in date
    when 'family' then private.can_manage_student(p_student) or private.is_student_self(p_student) -- a parent who manages the student, or the student
    else false end -- (no other side)
$$; -- end of the function
revoke all on function private.is_makeup_side(uuid, uuid, text) from public; -- only used by the functions below

-- Books the make-up session for an offer at its picked time, after the
-- last checks, and tells everyone. Hands back the new session's id.
create or replace function private.book_makeup(p_offer uuid) -- takes the offer
returns uuid -- hands back the make-up session's id
language plpgsql security definer -- writes sessions (callers check who may)
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_o public.session_makeup_offers; -- the offer
  v_s public.sessions; -- the cancelled session
  v_problem text; -- what's wrong with the time, if anything
  v_family uuid; -- the student's family
  v_new uuid; -- the make-up session's id
  v_student text; -- the student's name
  v_tutor text; -- the tutor's name
  v_place text; -- where, in words
  p uuid; -- one person to tell
begin -- start
  select * into v_o from public.session_makeup_offers where id = p_offer; -- the offer
  select * into v_s from public.sessions where id = v_o.session_id; -- the cancelled session
  v_problem := private.makeup_time_problem(v_s, v_o.picked_at, interval '0'); -- any problem with the time now
  if v_problem is not null then -- a problem:
    raise exception '% Please say it doesn''t work, and CLG will help.', v_problem using errcode = '22023'; -- plain message with what to do
  end if; -- (end of that check)
  select coalesce(v_s.family_id, st.family_id) into v_family from public.students st where st.id = v_s.student_id; -- the student's family
  if private.family_paused(v_family) then -- payments overdue:
    raise exception 'Bookings are paused while a payment is overdue. Please contact CLG.' using errcode = '23514'; -- plain message
  end if; -- (end of that check)
  if not private.tutor_cleared_for_student(v_s.tutor_id, v_s.student_id) then -- the tutor's checks have lapsed:
    raise exception 'The tutor can''t take sessions right now. CLG will be in touch.' using errcode = '23514'; -- plain message
  end if; -- (end of that check)
  insert into public.sessions ( -- books the make-up session:
    booking_id, student_id, tutor_id, family_id, subject, level_kind, -- same booking, student, tutor, family, subject and level,
    delivery, library_id, starts_at, ends_at, makeup_for -- same place, the new time, and the session it makes up for
  ) values ( -- (their values)
    v_s.booking_id, v_s.student_id, v_s.tutor_id, v_s.family_id, v_s.subject, v_s.level_kind, -- copied from the cancelled session,
    v_s.delivery, v_s.library_id, v_o.picked_at, v_o.picked_at + (v_s.ends_at - v_s.starts_at), v_s.id -- same place and length, at the picked time
  ) returning id into v_new; -- keeps its id
  update public.session_makeup_offers set status = 'picked', makeup_session_id = v_new where id = v_o.id; -- records it as booked

  select full_name into v_student from public.students where id = v_s.student_id; -- the student's name
  select full_name into v_tutor from public.accounts where id = v_s.tutor_id; -- the tutor's name
  v_place := case v_s.delivery when 'online' then 'online' when 'home' then 'at home' -- where, in words:
             else coalesce((select l.name from public.libraries l where l.id = v_s.library_id), 'at the library') end; -- online, at home, or the library
  for p in select account_id from private.session_people(v_s.student_id, v_s.tutor_id) -- tells everyone involved:
           where account_id is distinct from auth.uid() loop -- except whoever made the last choice
    perform private.add_notice(p, v_new, v_s.booking_id, 'booking_confirmed', 'Make-up session booked', -- a notice to each:
      coalesce(v_student, 'The student') || ': ' || v_s.subject || ' with ' || coalesce(v_tutor, 'the tutor') -- who and what,
      || ', ' || private.when_text(v_o.picked_at) || ', ' || v_place || '.', now()); -- when and where
  end loop; -- next person
  perform private.notify_admins('Make-up session booked', -- a notice to admins:
    coalesce(v_student, 'A student') || ' (' || v_s.subject || ' with ' || coalesce(v_tutor, 'the tutor') || ') now has ' -- for whom,
    || private.when_text(v_o.picked_at) || ', making up for ' || private.when_text(v_s.starts_at) || '. Everyone has agreed.', -- the new time and which session
    v_s.booking_id); -- linked to the booking
  return v_new; -- hands back the make-up session's id
end; -- finish
$$; -- end of the function
revoke all on function private.book_makeup(uuid) from public; -- only used by the functions below

-- ---------------------------------------------------------------------------
-- 3. Picking a time (replaces the earlier version)
-- ---------------------------------------------------------------------------
-- p_choice is 1 or 2 for a time, or 0 for "neither works" (needs a note).
-- Only the picking side itself can answer (not CLG staff for them). If CLG
-- offered the times, the other side must then confirm before it's booked.
create or replace function public.answer_makeup_times(p_offer uuid, p_choice integer, p_note text default null) -- takes the offer, the choice and a note
returns uuid -- hands back the make-up session's id (nothing if not booked yet)
language plpgsql security definer -- checks who may answer itself (below)
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_o public.session_makeup_offers; -- the offer
  v_s public.sessions; -- the cancelled session
  v_at timestamptz; -- the picked time
  v_problem text; -- what's wrong with the time, if anything
  v_note text; -- the cleaned-up note
  v_student text; -- the student's name
  v_tutor text; -- the tutor's name
  v_who text; -- who answered, in words
  v_other text; -- the other side: family or tutor
  p uuid; -- one person to tell
begin -- start
  select * into v_o from public.session_makeup_offers where id = p_offer for update; -- finds the offer and holds it while this runs
  if v_o.id is null or not private.is_makeup_side(v_o.student_id, v_o.tutor_id, v_o.answer_by) then -- not found, or not this person's to pick:
    raise exception 'Make-up times not found' using errcode = 'P0002'; -- plain message
  end if; -- (end of that check)
  if v_o.status <> 'waiting' then -- already answered (or nothing to pick):
    raise exception 'This has already been answered' using errcode = '22023'; -- plain message
  end if; -- (end of that check)
  if greatest(v_o.option_1, v_o.option_2) <= now() then -- both times have passed:
    raise exception 'Both times have passed. CLG will be in touch about a make-up session.' using errcode = '22023'; -- plain message
  end if; -- (end of that check)
  if p_choice not in (0, 1, 2) or p_choice is null then -- not a choice on offer:
    raise exception 'Please pick one of the two times, or say neither works' using errcode = '22023'; -- plain message
  end if; -- (end of that check)

  select * into v_s from public.sessions where id = v_o.session_id; -- the cancelled session
  v_note := nullif(left(btrim(coalesce(p_note, '')), 500), ''); -- the note, trimmed (or nothing)
  select full_name into v_student from public.students where id = v_o.student_id; -- the student's name
  select full_name into v_tutor from public.accounts where id = v_o.tutor_id; -- the tutor's name
  v_who := case when v_o.answer_by = 'tutor' then coalesce(v_tutor, 'The tutor') -- the tutor answered,
                else split_part(coalesce(v_student, 'The student'), ' ', 1) || '''s family' end; -- or the family
  v_other := case when v_o.answer_by = 'tutor' then 'family' else 'tutor' end; -- the other side

  if p_choice = 0 then -- neither works:
    if v_note is null then -- with no reason:
      raise exception 'Please say why neither time works' using errcode = '22023'; -- plain message
    end if; -- (end of that check)
    update public.session_makeup_offers -- records the answer:
    set status = 'declined', answered_by = auth.uid(), answered_at = now(), answer_note = v_note -- neither, by whom, when, why
    where id = v_o.id; -- on this offer
    for p in select * from private.makeup_side(v_o.student_id, v_o.tutor_id, v_other) loop -- tells the other side:
      perform private.add_notice(p, null, v_s.booking_id, 'booking_declined', 'Make-up times not suitable', -- a notice to each of them:
        v_who || ' can''t do either make-up time for ' || coalesce(v_student, 'the student') || ' (' || v_s.subject || ')' -- who can't, for what,
        || ' (' || v_note || '). CLG will be in touch to arrange another time.', now()); -- why, and what happens next
    end loop; -- next person
    perform private.notify_admins('Make-up times not suitable', -- a notice to admins:
      v_who || ' can''t do either make-up time for ' || coalesce(v_student, 'a student') || ' (' || v_s.subject -- who can't, for what,
      || ' with ' || coalesce(v_tutor, 'the tutor') || ', cancelled from ' || private.when_text(v_s.starts_at) || ').' -- with whom, which session,
      || ' Reason: ' || v_note || '. Please arrange a make-up session.', v_s.booking_id); -- why, and what to do
    return null; -- no session booked
  end if; -- (end of "neither")

  v_at := case when p_choice = 1 then v_o.option_1 else v_o.option_2 end; -- the picked time
  v_problem := private.makeup_time_problem(v_s, v_at, interval '0'); -- any problem with it now
  if v_problem is not null then -- a problem:
    raise exception '% You can pick the other time, or say neither works.', v_problem using errcode = '22023'; -- plain message with what to do
  end if; -- (end of that check)
  update public.session_makeup_offers -- records the pick:
  set picked_at = v_at, answered_by = auth.uid(), answered_at = now(), answer_note = v_note, -- which time, by whom, when, any note,
      status = case when v_o.needs_both then 'confirming' else status end -- CLG offered it: now waiting for the other side
  where id = v_o.id; -- on this offer

  if not v_o.needs_both then -- the other side offered these times themselves, so both have agreed:
    return private.book_makeup(v_o.id); -- books it and tells everyone
  end if; -- (end of the agreed case)

  -- CLG offered the times: ask the other side to confirm before booking.
  for p in select * from private.makeup_side(v_o.student_id, v_o.tutor_id, v_other) loop -- tells the other side:
    perform private.add_notice(p, null, v_s.booking_id, 'booking_requested', 'Please confirm a make-up time', -- a notice to each of them:
      v_who || ' picked ' || private.when_text(v_at) || ' to make up ' || coalesce(v_student, 'the student') || '''s ' -- who picked when,
      || v_s.subject || ' session from ' || private.when_text(v_s.starts_at) || '. Please confirm it, or say it doesn''t work, under Sessions.', -- for which session, and what to do
      now()); -- straight away (quiet hours still apply)
  end loop; -- next person
  perform private.notify_admins('Make-up time picked', -- a notice to admins:
    v_who || ' picked ' || private.when_text(v_at) || ' for ' || coalesce(v_student, 'a student') || ' (' || v_s.subject -- who picked when, for what,
    || '). Waiting for ' || case when v_other = 'tutor' then 'the tutor' else 'the family' end || ' to confirm.', v_s.booking_id); -- who must confirm
  return null; -- not booked yet
end; -- finish
$$; -- end of the function
revoke all on function public.answer_makeup_times(uuid, integer, text) from public, anon; -- not for signed-out visitors
grant execute on function public.answer_makeup_times(uuid, integer, text) to authenticated; -- signed-in people (the checks above decide)

-- ---------------------------------------------------------------------------
-- 4. The other side confirms the picked time (when CLG offered the times)
-- ---------------------------------------------------------------------------
-- p_ok true books the make-up; false needs a note saying why it doesn't work.
create or replace function public.confirm_makeup_time(p_offer uuid, p_ok boolean, p_note text default null) -- takes the offer, yes or no, and a note
returns uuid -- hands back the make-up session's id (nothing if not booked)
language plpgsql security definer -- checks who may confirm itself (below)
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_o public.session_makeup_offers; -- the offer
  v_s public.sessions; -- the cancelled session
  v_other text; -- the side confirming: family or tutor
  v_note text; -- the cleaned-up note
  v_student text; -- the student's name
  v_who text; -- who said no, in words
  p uuid; -- one person to tell
begin -- start
  select * into v_o from public.session_makeup_offers where id = p_offer for update; -- finds the offer and holds it while this runs
  v_other := case when v_o.answer_by = 'tutor' then 'family' else 'tutor' end; -- the side that confirms is the one that didn't pick
  if v_o.id is null or not private.is_makeup_side(v_o.student_id, v_o.tutor_id, v_other) then -- not found, or not this person's to confirm:
    raise exception 'Make-up time not found' using errcode = 'P0002'; -- plain message
  end if; -- (end of that check)
  if v_o.status <> 'confirming' then -- nothing waiting for confirmation:
    raise exception 'This has already been answered' using errcode = '22023'; -- plain message
  end if; -- (end of that check)
  if v_o.picked_at <= now() then -- the time has passed:
    raise exception 'That time has passed. CLG will be in touch about a make-up session.' using errcode = '22023'; -- plain message
  end if; -- (end of that check)
  if coalesce(p_ok, false) then -- yes:
    return private.book_makeup(v_o.id); -- books it and tells everyone
  end if; -- (end of yes)

  v_note := nullif(left(btrim(coalesce(p_note, '')), 500), ''); -- the note, trimmed (or nothing)
  if v_note is null then -- no reason:
    raise exception 'Please say why that time doesn''t work' using errcode = '22023'; -- plain message
  end if; -- (end of that check)
  update public.session_makeup_offers -- records the answer:
  set status = 'declined', answer_note = v_note -- doesn't work, and why
  where id = v_o.id; -- on this offer
  select * into v_s from public.sessions where id = v_o.session_id; -- the cancelled session
  select full_name into v_student from public.students where id = v_o.student_id; -- the student's name
  v_who := case when v_other = 'tutor' then coalesce((select full_name from public.accounts where id = v_o.tutor_id), 'The tutor') -- the tutor said no,
                else split_part(coalesce(v_student, 'The student'), ' ', 1) || '''s family' end; -- or the family
  for p in select * from private.makeup_side(v_o.student_id, v_o.tutor_id, v_o.answer_by) loop -- tells the side that picked:
    perform private.add_notice(p, null, v_s.booking_id, 'booking_declined', 'Make-up time not suitable', -- a notice to each of them:
      v_who || ' can''t do ' || private.when_text(v_o.picked_at) || ' (' || v_note || '). CLG will be in touch to arrange another time.', now()); -- who can't, why, what next
  end loop; -- next person
  perform private.notify_admins('Make-up time not suitable', -- a notice to admins:
    v_who || ' can''t do ' || private.when_text(v_o.picked_at) || ' for ' || coalesce(v_student, 'a student') || ' (' || v_s.subject -- who can't, for what,
    || '). Reason: ' || v_note || '. Please arrange a make-up session.', v_s.booking_id); -- why, and what to do
  return null; -- not booked
end; -- finish
$$; -- end of the function
revoke all on function public.confirm_makeup_time(uuid, boolean, text) from public, anon; -- not for signed-out visitors
grant execute on function public.confirm_makeup_time(uuid, boolean, text) to authenticated; -- signed-in people (the checks above decide)

-- ---------------------------------------------------------------------------
-- 5. Times that run out, and the list (replace the earlier versions)
-- ---------------------------------------------------------------------------
-- An offer runs out when both times pass with no pick, or the picked time
-- passes before the other side confirms. CLG's admins are told.
create or replace function private.expire_makeup_offers() -- no inputs
returns integer -- how many offers ran out
language plpgsql security definer -- runs with full rights, as a background job
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  o record; -- one offer at a time
  v_count integer := 0; -- how many
begin -- start
  for o in -- for each offer that ran out:
    update public.session_makeup_offers m set status = 'expired' -- marks it as run out
    where (m.status = 'waiting' and greatest(m.option_1, m.option_2) <= now()) -- waiting, both times passed,
       or (m.status = 'confirming' and m.picked_at <= now()) -- or picked but not confirmed before the time
    returning m.session_id -- (keeps the session)
  loop -- (each one)
    perform private.notify_admins('Make-up time not picked', -- a notice to admins:
      'No make-up time was agreed for ' || coalesce(st.full_name, 'a student') || ' (' || x.subject -- for whom and what,
      || ', cancelled from ' || private.when_text(x.starts_at) || '). Please arrange a make-up session.', x.booking_id) -- which session, what to do
    from public.sessions x join public.students st on st.id = x.student_id -- (the session and student)
    where x.id = o.session_id; -- for this offer
    v_count := v_count + 1; -- counts it
  end loop; -- next offer
  return v_count; -- how many
end; -- finish
$$; -- end of the function
revoke all on function private.expire_makeup_offers() from public; -- only the background job runs it

-- The list for the Sessions page: the same columns as before. A picked
-- time that passed before it was confirmed also shows as expired.
create or replace function public.list_makeup_offers() -- no inputs
returns table ( -- one row per offer:
  id uuid, session_id uuid, student_id uuid, tutor_id uuid, -- the offer, session, student and tutor,
  student_name text, tutor_name text, subject text, -- names and subject,
  cancelled_starts_at timestamptz, minutes integer, -- the cancelled time and length,
  delivery public.session_delivery, library_name text, -- where,
  reason text, offered_by_role text, answer_by text, -- the reason, who cancelled, who picks,
  option_1 timestamptz, option_2 timestamptz, -- the two times,
  status text, picked_at timestamptz, answer_note text, created_at timestamptz -- where it's up to
) -- (end of the columns)
language sql stable security definer -- checks who sees what itself (below)
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select o.id, o.session_id, o.student_id, o.tutor_id, -- the ids,
         case when private.is_front_desk() or private.is_parent_of(o.student_id) or private.is_student_self(o.student_id) -- CLG and the family see
              then st.full_name else split_part(st.full_name, ' ', 1) end, -- the full name; the tutor sees the first name only,
         a.full_name, x.subject, -- the tutor's name and the subject,
         x.starts_at, (extract(epoch from x.ends_at - x.starts_at) / 60)::integer, -- the cancelled time and its length in minutes,
         x.delivery, l.name, -- where,
         x.cancel_reason, o.offered_by_role, o.answer_by, -- the reason, who cancelled, who picks,
         o.option_1, o.option_2, -- the two times,
         case when o.status = 'waiting' and greatest(o.option_1, o.option_2) <= now() then 'expired' -- both times passed with no pick,
              when o.status = 'confirming' and o.picked_at <= now() then 'expired' -- the picked time passed before it was confirmed,
              else o.status end, -- otherwise where it's up to,
         o.picked_at, o.answer_note, o.created_at -- the picked time, note and when offered
  from public.session_makeup_offers o -- the offers
  join public.sessions x on x.id = o.session_id -- with their cancelled session
  join public.students st on st.id = o.student_id -- the student
  join public.accounts a on a.id = o.tutor_id -- the tutor
  left join public.libraries l on l.id = x.library_id -- and the library, if any
  where (o.status in ('waiting', 'confirming') or o.created_at > now() - interval '30 days') -- open, or recent
    and (private.is_front_desk() -- CLG's front desk sees all,
         or (o.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2() -- the tutor sees their own,
             and private.tutor_cleared_for_student(o.tutor_id, o.student_id)) -- while their checks are in date,
         or private.is_parent_of(o.student_id) -- parents see their children's,
         or private.is_student_self(o.student_id)) -- and students their own
  order by o.created_at desc -- newest first
$$; -- end of the function
revoke all on function public.list_makeup_offers() from public, anon; -- not for signed-out visitors
grant execute on function public.list_makeup_offers() to authenticated; -- signed-in people (each sees their own)
