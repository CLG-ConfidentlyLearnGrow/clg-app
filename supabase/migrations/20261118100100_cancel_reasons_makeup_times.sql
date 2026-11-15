-- Summary: a reason and two make-up times when a session is cancelled (Carla, 16 Nov 2026).
--
-- "When tutors and clients cancel a tutor session, there needs to be a
-- space for a reason (maybe a drop down of sick, away, ...). This also
-- needs to give a space to give two alternative session times for that
-- week."
--
-- What this adds (module: scheduling, which owns sessions):
--   * Every cancelled session now has a reason picked from a short list
--     (sick, away, school or uni event, family matter, clash, other). "Other"
--     needs a few words. The reason is saved on the session.
--   * Whoever cancels one session (the tutor, a parent, a student 16+, or
--     CLG for them) offers two other times in the same week (Monday to
--     Sunday), same length and same place. If no other time works that week
--     they tick a box instead, and CLG's admins are asked to sort it out.
--   * The other side (the family if the tutor cancelled; the tutor if the
--     family cancelled) picks one of the two times, or says neither works
--     and why. Picking one books a make-up session straight away.
--   * CLG's owner and operations admins get a notice at each step: the
--     cancel, the pick or "neither", and if both times pass with no answer.
--   * public.cancel_session now refuses a cancel with no reason, so the
--     rule holds even outside the app's screens.
--
-- Billing is unchanged: the cancelled session gets its credit by the usual
-- rules, and the make-up session is a new session that is billed and paid
-- like any other. Quiet hours apply to every notice (the notice trigger
-- moves them).
--
-- Safe to run more than once. Run after every earlier scheduling file.

-- ---------------------------------------------------------------------------
-- 1. New details on sessions
-- ---------------------------------------------------------------------------

-- Which reason from the list was picked (empty for older cancels).
alter table public.sessions add column if not exists cancel_reason_kind text; -- the reason picked from the list
alter table public.sessions drop constraint if exists sessions_cancel_reason_kind; -- removes the rule first, so this can be run again
alter table public.sessions add constraint sessions_cancel_reason_kind -- only reasons from the list are allowed:
  check (cancel_reason_kind in ('sick', 'away', 'school_event', 'family', 'clash', 'other')); -- sick, away, school or uni event, family matter, clash, other

-- For a make-up session: the cancelled session it makes up for.
alter table public.sessions add column if not exists makeup_for uuid references public.sessions (id) on delete set null; -- empty for ordinary sessions

-- ---------------------------------------------------------------------------
-- 2. The two times offered after a cancel
-- ---------------------------------------------------------------------------

create table if not exists public.session_makeup_offers ( -- one row per cancelled session
  id uuid primary key default gen_random_uuid(), -- the offer's id
  session_id uuid not null unique references public.sessions (id) on delete cascade, -- the cancelled session (one offer each)
  student_id uuid not null references public.students (id) on delete cascade, -- the student (for the access rules)
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade, -- the tutor (for the access rules)
  offered_by uuid references public.accounts (id) on delete set null, -- who cancelled and offered the times
  offered_by_role text not null check (offered_by_role in ('family', 'tutor', 'admin')), -- which side cancelled: family, tutor or CLG
  answer_by text not null check (answer_by in ('family', 'tutor')), -- which side picks: the family or the tutor
  option_1 timestamptz, -- the first time offered (empty if none could be offered)
  option_2 timestamptz, -- the second time offered (empty if none could be offered)
  status text not null default 'waiting' -- where it's up to:
    check (status in ('waiting', 'picked', 'declined', 'expired', 'none_offered')), -- waiting, picked, neither works, ran out, or no times offered
  picked_at timestamptz, -- the time that was picked
  makeup_session_id uuid references public.sessions (id) on delete set null, -- the make-up session that was booked
  answered_by uuid references public.accounts (id) on delete set null, -- who picked (or said neither)
  answered_at timestamptz, -- when
  answer_note text check (char_length(answer_note) <= 500), -- why neither works (needed for "neither")
  created_at timestamptz not null default now(), -- when the times were offered
  check ((option_1 is null) = (option_2 is null)), -- both times, or neither
  check (option_1 is distinct from option_2 or option_1 is null), -- two different times
  check ((status = 'none_offered') = (option_1 is null)) -- "no times offered" exactly when there are no times
); -- end of the table
create index if not exists session_makeup_offers_tutor on public.session_makeup_offers (tutor_id, status); -- quick lookups for a tutor's list
create index if not exists session_makeup_offers_student on public.session_makeup_offers (student_id, status); -- quick lookups for a family's list

alter table public.session_makeup_offers enable row level security; -- access rules apply to this table
revoke all on public.session_makeup_offers from anon; -- signed-out visitors see nothing
revoke insert, update, delete, truncate on public.session_makeup_offers from authenticated; -- changes only through the functions below

drop trigger if exists audit on public.session_makeup_offers; -- replaces the audit trigger if this is run again
create trigger audit after insert or update or delete on public.session_makeup_offers -- every change is written to the audit log
  for each row execute function private.audit_change(); -- (the shared audit step)

-- Who can read an offer: CLG's front desk, the tutor (while their checks
-- for this student are in date), the student's parents, and the student.
drop policy if exists "see own make-up offers" on public.session_makeup_offers; -- removes the old rule first, so this can be run again
create policy "see own make-up offers" on public.session_makeup_offers for select to authenticated -- who can read offers:
  using ( -- (the rule)
    private.is_front_desk() -- CLG's owner, operations and support admins,
    or (tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2() -- the tutor with two-step sign-in,
        and private.tutor_cleared_for_student(tutor_id, student_id)) -- while their checks for this student are in date,
    or private.is_parent_of(student_id) -- the student's parents,
    or private.is_student_self(student_id) -- or the student themselves.
  ); -- end of the rule

-- ---------------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------------

-- The words shown for each reason.
create or replace function private.cancel_reason_label(p_kind text) -- takes the reason's short name
returns text -- hands back the words to show
language sql immutable -- the same name always gives the same words
set search_path = '' -- only fully named things, for safety
as $$ -- the lookup
  select case p_kind -- by the reason:
    when 'sick' then 'Sick or unwell' -- sick
    when 'away' then 'Away or travelling' -- away
    when 'school_event' then 'School or uni event' -- school or uni event
    when 'family' then 'Family matter' -- family matter
    when 'clash' then 'Clashes with something else' -- clash
    when 'other' then 'Other' -- other
  end -- (anything else gives nothing)
$$; -- end of the function

-- Checks one make-up time for a cancelled session. Hands back a plain
-- message saying what's wrong, or nothing when the time is fine.
-- p_notice is how far ahead it must be (2 hr when offering, so the other
-- side has time to answer; any future time when picking).
create or replace function private.makeup_time_problem( -- takes:
  p_session public.sessions, -- the cancelled session,
  p_at timestamptz, -- the time to check,
  p_notice interval -- and how far ahead of now it must be
) -- (end of the inputs)
returns text -- hands back a message, or nothing if fine
language plpgsql stable security definer -- reads every session (to check clashes) whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the checks
declare -- working values:
  v_tz text; -- the student's time zone (Adelaide for South Australia)
  v_local timestamp; -- the time on the student's clock
  v_length interval; -- how long the session is
begin -- start
  select private.state_timezone(st.state) into v_tz -- finds the student's time zone
  from public.students st where st.id = p_session.student_id; -- from the student's state
  v_tz := coalesce(v_tz, 'Australia/Adelaide'); -- Adelaide if the state is missing
  v_local := p_at at time zone v_tz; -- the time on the student's clock
  v_length := p_session.ends_at - p_session.starts_at; -- the session's length (the make-up is the same length)

  if extract(minute from v_local)::integer % 15 <> 0 or extract(second from v_local) <> 0 then -- not on a quarter hour:
    return 'Sessions start on the hour, or at 15, 30 or 45 minutes past.'; -- plain message
  end if; -- (end of that check)
  if p_at < now() + p_notice then -- too soon (or already passed):
    return case when p_notice > interval '0' -- the message depends on the rule:
      then private.when_text(p_at) || ' is too soon. New times must be at least 2 hours from now.' -- when offering
      else private.when_text(p_at) || ' has already passed.' end; -- when picking
  end if; -- (end of that check)
  if date_trunc('week', v_local) <> date_trunc('week', p_session.starts_at at time zone v_tz) then -- a different Monday-to-Sunday week:
    return private.when_text(p_at) || ' isn''t in the same week as the cancelled session (Monday to Sunday).'; -- plain message
  end if; -- (end of that check)
  if p_at = p_session.starts_at then -- the same time as the cancelled one:
    return 'Please choose a time other than the cancelled one.'; -- plain message
  end if; -- (end of that check)
  if exists ( -- another session already at that time:
    select 1 from public.sessions x -- any session
    where x.id <> p_session.id -- other than the cancelled one,
      and x.status = 'scheduled' -- still going ahead,
      and (x.tutor_id = p_session.tutor_id or x.student_id = p_session.student_id) -- for the same tutor or the same student,
      and x.starts_at < p_at + v_length and x.ends_at > p_at -- overlapping the new time
  ) then -- (end of the condition)
    return 'There''s already a session at ' || private.when_text(p_at) || '. Please choose another time.'; -- plain message
  end if; -- (end of that check)
  if exists ( -- the tutor or the student is away that day:
    select 1 from public.away_dates a -- any away dates
    where (a.tutor_id = p_session.tutor_id or a.student_id = p_session.student_id) -- for the same tutor or student,
      and v_local::date between a.from_date and a.to_date -- covering that day
  ) then -- (end of the condition)
    return 'Someone is marked as away on ' || trim(to_char(v_local, 'Dy FMDD Mon')) || '. Please choose another day.'; -- plain message
  end if; -- (end of that check)
  return null; -- all fine
end; -- finish
$$; -- end of the function
revoke all on function private.makeup_time_problem(public.sessions, timestamptz, interval) from public; -- only used by the functions below

-- The people on one side of a session: the tutor ('tutor'), or the
-- student's parents and the student's own login ('family').
create or replace function private.makeup_side(p_student uuid, p_tutor uuid, p_side text) -- takes the student, tutor and side
returns setof uuid -- hands back the accounts
language sql stable security definer -- reads the links whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select p.account_id -- each person's account
  from private.session_people(p_student, p_tutor) p -- everyone who hears about this student's sessions
  where p.is_tutor = (p_side = 'tutor') -- on the side asked for
$$; -- end of the function
revoke all on function private.makeup_side(uuid, uuid, text) from public; -- only used by the functions below

-- ---------------------------------------------------------------------------
-- 4. A reason is needed to cancel (edits cancel_session in place)
-- ---------------------------------------------------------------------------
-- Only the new check is added, so other changes to cancel_session (such as
-- support admins being allowed to use it) are kept.
do $$ -- (a block of steps)
declare -- working values:
  v_def text; -- the function's current code
  v_find text := E'  if v_s.status <> ''scheduled'' then\n'; -- the line the new check goes before
begin -- start
  v_def := replace(pg_get_functiondef('public.cancel_session(uuid, text, text)'::regprocedure), chr(13), ''); -- reads its code (without Windows line endings from pasting)
  if strpos(v_def, 'Please give a reason for cancelling') > 0 then -- already done:
    return; -- nothing to change
  end if; -- (end of that check)
  if strpos(v_def, v_find) = 0 then -- the line isn't there any more:
    raise exception 'public.cancel_session has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- (end of that check)
  execute replace(v_def, v_find, -- saves the code with the new check added:
    E'  if nullif(btrim(coalesce(p_reason, '''')), '''') is null then\n' -- if no reason was given,
    || E'    raise exception ''Please give a reason for cancelling'' using errcode = ''22023'';\n' -- refuse with a plain message
    || E'  end if;\n' -- (end of the new check)
    || v_find); -- then the line it goes before
end; -- finish
$$; -- (end of the block)

-- ---------------------------------------------------------------------------
-- 5. Cancel one session with a reason and two make-up times
-- ---------------------------------------------------------------------------
-- Dates and times are on the student's clock (Adelaide for South Australia).
-- Either give both times, or set p_no_times when nothing else works that
-- week. Hands back the offer's id.
create or replace function public.cancel_session_with_times( -- takes:
  p_session uuid, -- the session to cancel,
  p_reason text, -- the reason's short name (sick, away, school_event, family, clash, other),
  p_note text default null, -- a few words (needed for "other"),
  p_date_1 date default null, -- the first new date,
  p_time_1 time default null, -- the first new start time,
  p_date_2 date default null, -- the second new date,
  p_time_2 time default null, -- the second new start time,
  p_no_times boolean default false, -- true when no other time works this week,
  p_for text default null -- for CLG staff: who asked (family, tutor or admin)
) -- (end of the inputs)
returns uuid -- hands back the offer's id
language plpgsql security definer -- checks who may cancel itself (below)
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_s public.sessions; -- the session
  v_role text; -- who is cancelling: family, tutor or admin
  v_tz text; -- the student's time zone
  v_t1 timestamptz; -- the first new time
  v_t2 timestamptz; -- the second new time
  v_problem text; -- what's wrong with a time, if anything
  v_note text; -- the cleaned-up note
  v_answer text; -- which side picks: family or tutor
  v_offer uuid; -- the new offer's id
  v_student text; -- the student's name
  v_tutor text; -- the tutor's name
  v_who text; -- who cancelled, in words
begin -- start
  select * into v_s from public.sessions where id = p_session for update; -- finds the session and holds it while this runs
  v_role := case when v_s.id is null then null -- no session: nobody,
                 else private.cancel_role(v_s.student_id, v_s.tutor_id, p_for) end; -- otherwise works out who is cancelling (refuses others)
  if v_role is null then -- not found, or not theirs to cancel:
    raise exception 'Session not found' using errcode = 'P0002'; -- plain message
  end if; -- (end of that check)

  -- The reason.
  if private.cancel_reason_label(p_reason) is null then -- no reason picked from the list:
    raise exception 'Please choose a reason for cancelling' using errcode = '22023'; -- plain message
  end if; -- (end of that check)
  v_note := nullif(left(btrim(coalesce(p_note, '')), 300), ''); -- the note, trimmed (or nothing)
  if p_reason = 'other' and v_note is null then -- "Other" with no words:
    raise exception 'Please say why you are cancelling' using errcode = '22023'; -- plain message
  end if; -- (end of that check)

  -- The two new times (unless nothing else works this week).
  if not coalesce(p_no_times, false) then -- times are being offered:
    if p_date_1 is null or p_time_1 is null or p_date_2 is null or p_time_2 is null then -- one is missing:
      raise exception 'Please give two other times this week, or tick that no other time works' using errcode = '22023'; -- plain message
    end if; -- (end of that check)
    select coalesce(private.state_timezone(st.state), 'Australia/Adelaide') into v_tz -- the student's time zone
    from public.students st where st.id = v_s.student_id; -- from the student's state
    v_t1 := (p_date_1 + p_time_1) at time zone v_tz; -- the first time, on the student's clock
    v_t2 := (p_date_2 + p_time_2) at time zone v_tz; -- the second time, on the student's clock
    if v_t1 = v_t2 then -- the same time twice:
      raise exception 'Please give two different times' using errcode = '22023'; -- plain message
    end if; -- (end of that check)
    v_problem := coalesce( -- the first problem found, if any:
      private.makeup_time_problem(v_s, v_t1, interval '2 hours'), -- with the first time,
      private.makeup_time_problem(v_s, v_t2, interval '2 hours')); -- or with the second
    if v_problem is not null then -- a problem:
      raise exception '%', v_problem using errcode = '22023'; -- shows it in plain words
    end if; -- (end of that check)
  end if; -- (end of the times)

  -- Save the offer first, so the "cancelled" notices can mention the times.
  v_answer := case when v_role = 'family' then 'tutor' else 'family' end; -- the family cancelled: the tutor picks; otherwise the family picks
  insert into public.session_makeup_offers ( -- saves the offer:
    session_id, student_id, tutor_id, offered_by, offered_by_role, answer_by, option_1, option_2, status -- (the details)
  ) values ( -- (their values)
    v_s.id, v_s.student_id, v_s.tutor_id, auth.uid(), v_role, v_answer, v_t1, v_t2, -- the session, people, side and times,
    case when v_t1 is null then 'none_offered' else 'waiting' end -- waiting for a pick, or no times offered
  ) returning id into v_offer; -- keeps its id

  -- Cancel it (the usual checks, credits and notices), with the reason in words.
  perform public.cancel_session( -- cancels the session:
    v_s.id, -- this session,
    private.cancel_reason_label(p_reason) || coalesce(': ' || v_note, ''), -- the reason in words, plus the note,
    p_for); -- and who asked (CLG staff only)
  update public.sessions set cancel_reason_kind = p_reason where id = v_s.id; -- remembers which reason was picked (for reports)

  -- Tell CLG's owner and operations admins.
  select full_name into v_student from public.students where id = v_s.student_id; -- the student's name
  select full_name into v_tutor from public.accounts where id = v_s.tutor_id; -- the tutor's name
  v_who := case v_role -- who cancelled, in words:
    when 'tutor' then coalesce(v_tutor, 'The tutor') -- the tutor,
    when 'family' then split_part(coalesce(v_student, 'The student'), ' ', 1) || '''s family' -- the family,
    else 'CLG' end; -- or CLG
  perform private.notify_admins('Session cancelled', -- a notice to admins:
    v_who || ' cancelled ' || v_s.subject || ' for ' || coalesce(v_student, 'a student') -- who cancelled what, for whom,
    || ' with ' || coalesce(v_tutor, 'the tutor') || ', ' || private.when_text(v_s.starts_at) || '.' -- with whom and when,
    || ' Reason: ' || private.cancel_reason_label(p_reason) || coalesce(' (' || v_note || ')', '') || '.' -- the reason,
    || case when v_t1 is null -- then either:
         then ' No other time works this week: please arrange a make-up session.' -- no times: CLG to sort it,
         else ' Make-up times offered: ' || private.when_text(v_t1) || ' or ' || private.when_text(v_t2) -- or the two times,
              || '. Waiting for ' || case when v_answer = 'tutor' then 'the tutor' else 'the family' end || ' to pick.' end, -- and who is picking
    v_s.booking_id); -- linked to the booking
  return v_offer; -- hands back the offer's id
end; -- finish
$$; -- end of the function
revoke all on function public.cancel_session_with_times(uuid, text, text, date, time, date, time, boolean, text) from public, anon; -- not for signed-out visitors
grant execute on function public.cancel_session_with_times(uuid, text, text, date, time, date, time, boolean, text) to authenticated; -- signed-in people (the checks above decide)

-- ---------------------------------------------------------------------------
-- 6. The other side picks a time, or says neither works
-- ---------------------------------------------------------------------------
-- p_choice is 1 or 2 for a time, or 0 for "neither works" (needs a note).
-- Picking a time books the make-up session. Hands back its id (or nothing
-- for "neither").
create or replace function public.answer_makeup_times(p_offer uuid, p_choice integer, p_note text default null) -- takes the offer, the choice and a note
returns uuid -- hands back the make-up session's id
language plpgsql security definer -- checks who may answer itself (below)
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_o public.session_makeup_offers; -- the offer
  v_s public.sessions; -- the cancelled session
  v_ok boolean; -- whether this person may answer
  v_at timestamptz; -- the picked time
  v_problem text; -- what's wrong with the time, if anything
  v_new uuid; -- the make-up session's id
  v_family uuid; -- the student's family
  v_note text; -- the cleaned-up note
  v_student text; -- the student's name
  v_tutor text; -- the tutor's name
  v_place text; -- where the session is, in words
  v_who text; -- who answered, in words
  p uuid; -- one person to tell
begin -- start
  select * into v_o from public.session_makeup_offers where id = p_offer for update; -- finds the offer and holds it while this runs
  select * into v_s from public.sessions where id = v_o.session_id; -- the cancelled session
  v_ok := case v_o.answer_by -- may this person answer?
    when 'tutor' then (v_o.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2() -- the tutor with two-step sign-in,
                       and private.tutor_cleared_for_student(v_o.tutor_id, v_o.student_id)) -- with checks in date for this student,
                      or private.is_front_desk() -- or CLG's front desk for them;
    when 'family' then private.can_book_for(v_o.student_id) -- the family (or CLG's front desk for them)
    else false end; -- (nobody else)
  if v_o.id is null or not coalesce(v_ok, false) then -- not found, or not theirs to answer:
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

  v_note := nullif(left(btrim(coalesce(p_note, '')), 500), ''); -- the note, trimmed (or nothing)
  select full_name into v_student from public.students where id = v_o.student_id; -- the student's name
  select full_name into v_tutor from public.accounts where id = v_o.tutor_id; -- the tutor's name
  v_who := case when v_o.answer_by = 'tutor' then coalesce(v_tutor, 'The tutor') -- the tutor answered,
                else split_part(coalesce(v_student, 'The student'), ' ', 1) || '''s family' end; -- or the family

  if p_choice = 0 then -- neither works:
    if v_note is null then -- with no reason:
      raise exception 'Please say why neither time works' using errcode = '22023'; -- plain message
    end if; -- (end of that check)
    update public.session_makeup_offers -- records the answer:
    set status = 'declined', answered_by = auth.uid(), answered_at = now(), answer_note = v_note -- neither, by whom, when, why
    where id = v_o.id; -- on this offer
    for p in select * from private.makeup_side(v_o.student_id, v_o.tutor_id, -- tells the side that offered the times:
               case when v_o.answer_by = 'tutor' then 'family' else 'tutor' end) loop -- (the other side from whoever answered)
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

  -- A time was picked: check it again (things may have changed since).
  v_at := case when p_choice = 1 then v_o.option_1 else v_o.option_2 end; -- the picked time
  v_problem := private.makeup_time_problem(v_s, v_at, interval '0'); -- any problem with it now
  if v_problem is not null then -- a problem:
    raise exception '% You can pick the other time, or say neither works.', v_problem using errcode = '22023'; -- plain message with what to do
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
    v_s.delivery, v_s.library_id, v_at, v_at + (v_s.ends_at - v_s.starts_at), v_s.id -- same place and length, at the new time
  ) returning id into v_new; -- keeps its id
  update public.session_makeup_offers -- records the answer:
  set status = 'picked', picked_at = v_at, makeup_session_id = v_new, -- picked, which time, which session,
      answered_by = auth.uid(), answered_at = now(), answer_note = v_note -- by whom, when, and any note
  where id = v_o.id; -- on this offer

  v_place := case v_s.delivery when 'online' then 'online' when 'home' then 'at home' -- where, in words:
             else coalesce((select l.name from public.libraries l where l.id = v_s.library_id), 'at the library') end; -- online, at home, or the library
  for p in select account_id from private.session_people(v_s.student_id, v_s.tutor_id) -- tells everyone involved:
           where account_id is distinct from auth.uid() loop -- except whoever picked
    perform private.add_notice(p, v_new, v_s.booking_id, 'booking_confirmed', 'Make-up session booked', -- a notice to each:
      coalesce(v_student, 'The student') || ': ' || v_s.subject || ' with ' || coalesce(v_tutor, 'the tutor') -- who and what,
      || ', ' || private.when_text(v_at) || ', ' || v_place || '.', now()); -- when and where
  end loop; -- next person
  perform private.notify_admins('Make-up session booked', -- a notice to admins:
    v_who || ' picked ' || private.when_text(v_at) || ' for ' || coalesce(v_student, 'a student') || ' (' || v_s.subject -- who picked when, for what,
    || ' with ' || coalesce(v_tutor, 'the tutor') || '), making up for ' || private.when_text(v_s.starts_at) || '.', -- with whom, for which session
    v_s.booking_id); -- linked to the booking
  return v_new; -- hands back the make-up session's id
end; -- finish
$$; -- end of the function
revoke all on function public.answer_makeup_times(uuid, integer, text) from public, anon; -- not for signed-out visitors
grant execute on function public.answer_makeup_times(uuid, integer, text) to authenticated; -- signed-in people (the checks above decide)

-- ---------------------------------------------------------------------------
-- 7. The list for the Sessions page
-- ---------------------------------------------------------------------------
-- Offers the viewer can see: open ones, and answered ones from the last
-- 30 days. "waiting" offers whose times have both passed show as expired.
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
         case when o.status = 'waiting' and greatest(o.option_1, o.option_2) <= now() then 'expired' else o.status end, -- where it's up to (passed counts as expired),
         o.picked_at, o.answer_note, o.created_at -- the picked time, note and when offered
  from public.session_makeup_offers o -- the offers
  join public.sessions x on x.id = o.session_id -- with their cancelled session
  join public.students st on st.id = o.student_id -- the student
  join public.accounts a on a.id = o.tutor_id -- the tutor
  left join public.libraries l on l.id = x.library_id -- and the library, if any
  where (o.status = 'waiting' or o.created_at > now() - interval '30 days') -- open, or recent
    and (private.is_front_desk() -- CLG's front desk sees all,
         or (o.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2() -- the tutor sees their own,
             and private.tutor_cleared_for_student(o.tutor_id, o.student_id)) -- while their checks are in date,
         or private.is_parent_of(o.student_id) -- parents see their children's,
         or private.is_student_self(o.student_id)) -- and students their own
  order by o.created_at desc -- newest first
$$; -- end of the function
revoke all on function public.list_makeup_offers() from public, anon; -- not for signed-out visitors
grant execute on function public.list_makeup_offers() to authenticated; -- signed-in people (each sees their own)

-- ---------------------------------------------------------------------------
-- 8. The "cancelled" notice mentions the times offered
-- ---------------------------------------------------------------------------
-- Replaces the notice sent when a future session is cancelled. Everyone
-- else involved still hears about it. Now the notice also lists the two
-- times offered, and the side that picks is asked to choose one.
create or replace function private.notice_on_cancel() -- a trigger function (no inputs)
returns trigger -- hands back the row
language plpgsql security definer -- reads names and links whoever cancels
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_student text; -- the student's name
  v_tutor text; -- the tutor's name
  v_offer public.session_makeup_offers; -- the make-up offer, if any
  v_extra text := ''; -- the sentence about make-up times
  v_asked boolean; -- whether this person is asked to pick
  p record; -- one person to tell
begin -- start
  if not (old.status = 'scheduled' and new.status = 'cancelled' and new.starts_at > now()) then -- not a future session being cancelled:
    return new; -- nothing to send
  end if; -- (end of that check)
  select full_name into v_student from public.students where id = new.student_id; -- the student's name
  select full_name into v_tutor from public.accounts where id = new.tutor_id; -- the tutor's name
  select * into v_offer from public.session_makeup_offers where session_id = new.id; -- the make-up offer, if any
  if v_offer.status = 'none_offered' then -- no other time works this week:
    v_extra := ' No other time works this week, so CLG will be in touch about a make-up session.'; -- says CLG will help
  elsif v_offer.status = 'waiting' then -- two times offered:
    v_extra := ' Make-up times offered: ' || private.when_text(v_offer.option_1) || ' or ' || private.when_text(v_offer.option_2) || '.'; -- lists them
  end if; -- (end of the sentence)
  for p in -- for each person:
    select * from private.session_people(new.student_id, new.tutor_id) -- everyone involved
    where account_id is distinct from new.cancelled_by -- except whoever cancelled
  loop -- (each one)
    v_asked := v_offer.status = 'waiting' and (v_offer.answer_by = 'tutor') = p.is_tutor; -- on the side that picks?
    perform private.add_notice(p.account_id, new.id, new.booking_id, 'session_cancelled', -- a notice:
      case when coalesce(v_asked, false) then 'Session cancelled: please pick a make-up time' else 'Session cancelled' end, -- the title,
      v_student || ': ' || new.subject || ' with ' || v_tutor || ', ' || private.when_text(new.starts_at) -- which session,
      || ', is cancelled' || coalesce(' (' || new.cancel_reason || ')', '') || '.' || v_extra -- cancelled, why, and the times,
      || case when coalesce(v_asked, false) then ' Please pick one, or say neither works, under Sessions.' else '' end, -- and what to do
      now()); -- straight away (quiet hours still apply)
  end loop; -- next person
  return new; -- carries on
end; -- finish
$$; -- end of the function

-- ---------------------------------------------------------------------------
-- 9. Times that ran out with no answer
-- ---------------------------------------------------------------------------
-- Marks offers whose two times have both passed, and tells CLG's admins so
-- they can arrange a make-up. Run every 15 minutes. Returns how many.
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
    where m.status = 'waiting' and greatest(m.option_1, m.option_2) <= now() -- still waiting, both times passed
    returning m.session_id -- (keeps the session)
  loop -- (each one)
    perform private.notify_admins('Make-up time not picked', -- a notice to admins:
      'Nobody picked a make-up time for ' || coalesce(st.full_name, 'a student') || ' (' || x.subject -- for whom and what,
      || ', cancelled from ' || private.when_text(x.starts_at) || '). Please arrange a make-up session.', x.booking_id) -- which session, what to do
    from public.sessions x join public.students st on st.id = x.student_id -- (the session and student)
    where x.id = o.session_id; -- for this offer
    v_count := v_count + 1; -- counts it
  end loop; -- next offer
  return v_count; -- how many
end; -- finish
$$; -- end of the function
revoke all on function private.expire_makeup_offers() from public; -- only the background job runs it

do $$ -- a one-off block
begin -- start
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then -- the job scheduler is available (Supabase has it)
    execute 'create extension if not exists pg_cron with schema pg_catalog'; -- turn it on if needed
    execute $job$ select cron.schedule('clg-makeup-times-expire', '*/15 * * * *', 'select private.expire_makeup_offers()') $job$; -- every 15 minutes (re-running replaces the same named job)
  end if; -- done checking
end; -- finish
$$; -- end of the block
