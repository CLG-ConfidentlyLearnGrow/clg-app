-- Summary: tutors say what they did, and what they achieved, in paid time
-- outside sessions, and CLG can check it (Carla, 18 Nov 2026).
--
-- Carla: "tutors must note what they do outside of tutor sessions for that
-- worked time to be logged. There needs to be some way to track they have
-- actually achieved something in this work time, and a way to check what
-- they have achieved."
--
-- What changes on the My pay page when someone logs hours:
--   * They choose what kind of work it was: lesson preparation and planning,
--     making learning materials, training CLG set, other work CLG set,
--     work done in the time of a no-show or late cancel, or (for admin
--     staff) office admin.
--   * As well as "What you did", they write "What you finished or achieved"
--     (for example "Three Year 7 fraction worksheets, saved in Materials").
--     Both are required.
--   * Time during a no-show or late cancel is already paid with that
--     session. Logging it records what was done in that time, picked from
--     their own session, and is never paid a second time.
--
-- What changes for CLG:
--   * The owner or a Finance admin sees the kind of work and what was
--     achieved before approving or declining, as before.
--   * Approving a no-show entry marks it checked without adding pay.
--   * The admin pay section lists all work outside sessions for the last
--     8 weeks, by person, so CLG can see what was achieved.
--
-- Billing module (billing_hour_logs). It reads sessions (scheduling) but
-- never changes them. Edits billing_review_hours and
-- billing_check_guaranteed_hours in place, so other changes stay.
-- Safe to run more than once. Run after 20261116300200_billing_training_pay.sql.

-- ---------------------------------------------------------------------------
-- 1. New details on each hours entry
-- ---------------------------------------------------------------------------
alter table public.billing_hour_logs add column if not exists work_category text; -- what kind of work (empty on older entries and app-made ones)
alter table public.billing_hour_logs drop constraint if exists billing_hour_logs_work_category_check; -- replaces the rule if run again
alter table public.billing_hour_logs add constraint billing_hour_logs_work_category_check -- the kinds allowed:
  check (work_category is null or work_category in ('preparation', 'materials', 'training', 'set_work', 'no_show_time', 'office_admin')); -- the six kinds
alter table public.billing_hour_logs add column if not exists achieved text; -- what was finished or achieved (empty on older entries)
alter table public.billing_hour_logs drop constraint if exists billing_hour_logs_achieved_check; -- replaces the rule if run again
alter table public.billing_hour_logs add constraint billing_hour_logs_achieved_check -- a sensible length:
  check (achieved is null or char_length(achieved) <= 1000); -- at most 1,000 characters
alter table public.billing_hour_logs add column if not exists session_id uuid references public.sessions (id) on delete set null; -- the session, for time during a no-show or late cancel

-- Each session's no-show time is recorded only once per person (entries
-- that were declined do not count, so a corrected one can be logged).
create unique index if not exists billing_hour_logs_no_show_once -- one entry per session
  on public.billing_hour_logs (session_id) where work_category = 'no_show_time' and status <> 'declined'; -- (only no-show entries still standing)

-- ---------------------------------------------------------------------------
-- 2. Which kinds of work are tutoring work, and which are office admin
-- ---------------------------------------------------------------------------
create or replace function private.billing_category_type(p_category text) -- takes the kind of work
returns text language sql immutable -- the same answer every time
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select case -- choose:
    when p_category = 'office_admin' then 'admin' -- office admin is paid at the admin rate
    when p_category in ('preparation', 'materials', 'training', 'set_work', 'no_show_time') then 'tutoring' -- the rest are tutoring work
  end -- (anything else gives nothing)
$$; -- end of the function
revoke all on function private.billing_category_type(text) from public, anon, authenticated; -- only used inside the database

-- ---------------------------------------------------------------------------
-- 3. Logging hours: the new version asks for the kind of work and what was
--    achieved. The older four-part version is removed so every new entry
--    has both.
-- ---------------------------------------------------------------------------
drop function if exists public.billing_log_my_hours(date, int, text, text); -- removes the older version

create or replace function public.billing_log_my_hours( -- logs the signed-in person's own hours
  p_day date, -- the day worked
  p_minutes int, -- how long, in minutes
  p_note text, -- what they did
  p_category text, -- the kind of work
  p_achieved text, -- what they finished or achieved
  p_session uuid default null -- the session (only for time during a no-show or late cancel)
) -- (end of the inputs)
returns uuid language plpgsql security definer -- gives back the new entry's id; checks who is asking below
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps:
declare -- working values:
  v_type text := private.billing_category_type(p_category); -- tutoring work or office admin
  v_s public.sessions; -- the session, for no-show time
  v uuid; -- the new entry's id
begin -- start
  if auth.uid() is null or not private.has_aal2() then -- not signed in with two-step login:
    raise exception 'Please sign in with two-step login to log hours' using errcode = '42501'; -- plain refusal
  end if; -- end of the check
  if v_type is null then -- no kind of work chosen:
    raise exception 'Please choose what kind of work it was' using errcode = '22023'; -- asks for it
  end if; -- end of the check
  if v_type = 'admin' then -- office admin:
    if not private.account_has_role(auth.uid(), 'admin') then -- not admin staff:
      raise exception 'Only CLG admin staff can log office admin hours. Choose a kind of tutoring work instead' using errcode = '42501'; -- plain refusal
    end if; -- end of the check
    if private.billing_pay_rate(auth.uid(), 'admin') is null then -- no admin rate yet:
      raise exception 'CLG has not set an admin pay rate for you yet' using errcode = '42501'; -- says so
    end if; -- end of the check
  else -- tutoring work:
    if not private.account_has_role(auth.uid(), 'tutor') then -- not a tutor:
      raise exception 'Only tutors can log tutoring work' using errcode = '42501'; -- plain refusal
    end if; -- end of the check
    if private.billing_tutoring_kind(auth.uid()) is null then -- no tutoring rate yet:
      raise exception 'CLG has not set a tutoring pay rate for you yet' using errcode = '42501'; -- says so
    end if; -- end of the check
  end if; -- end of the kind checks
  if p_minutes is null or p_minutes < 15 or p_minutes > 720 then -- too short or too long:
    raise exception 'Hours must be between 15 minutes and 12 hours' using errcode = '22023'; -- plain refusal
  end if; -- end of the check
  if p_day is null or p_day > private.billing_today() then -- a day still to come:
    raise exception 'Hours are logged after they are worked' using errcode = '22023'; -- plain refusal
  end if; -- end of the check
  if p_day < private.billing_today() - 60 then -- too long ago:
    raise exception 'Hours more than 60 days ago need to be added by CLG' using errcode = '22023'; -- plain refusal
  end if; -- end of the check
  if char_length(trim(coalesce(p_note, ''))) < 10 then -- no real description:
    raise exception 'Please write what you did (at least a short sentence)' using errcode = '22023'; -- asks for one
  end if; -- end of the check
  if char_length(trim(coalesce(p_achieved, ''))) < 10 then -- nothing about what was achieved:
    raise exception 'Please write what you finished or achieved in this time (at least a short sentence)' using errcode = '22023'; -- asks for it
  end if; -- end of the check

  if p_category = 'no_show_time' then -- time during a no-show or late cancel:
    select * into v_s from public.sessions where id = p_session; -- reads the session
    if not found or v_s.tutor_id <> auth.uid() then -- missing, or not their own:
      raise exception 'Choose one of your own sessions that was a no-show or cancelled late' using errcode = '22023'; -- plain refusal
    end if; -- end of the check
    if not (v_s.status = 'no_show' -- not a no-show,
            or (v_s.status = 'cancelled' and coalesce(v_s.cancelled_by_role, '') <> 'tutor' and v_s.cancelled_at > v_s.starts_at - interval '24 hours')) then -- nor cancelled late (within 24 hours) by the family or CLG:
      raise exception 'That session was not a no-show or a late cancel' using errcode = '22023'; -- plain refusal
    end if; -- end of the check
    if (v_s.starts_at at time zone 'Australia/Adelaide')::date <> p_day then -- a different day from the session:
      raise exception 'Use the day of the session' using errcode = '22023'; -- plain refusal
    end if; -- end of the check
    if p_minutes > round(extract(epoch from v_s.ends_at - v_s.starts_at) / 60)::int then -- longer than the session:
      raise exception 'Time during a no-show cannot be longer than the session' using errcode = '22023'; -- plain refusal
    end if; -- end of the check
  elsif p_session is not null then -- a session given for any other kind of work:
    raise exception 'A session is only chosen for time during a no-show or late cancel' using errcode = '22023'; -- plain refusal
  end if; -- end of the session checks

  insert into public.billing_hour_logs (account_id, work_date, minutes, note, work_type, work_category, achieved, session_id) -- adds the entry
  values (auth.uid(), p_day, p_minutes, left(trim(p_note), 300), v_type, p_category, left(trim(p_achieved), 1000), -- who, when, how long, what they did, the kind and what was achieved
          case when p_category = 'no_show_time' then p_session end) -- and the session, for no-show time
  returning id into v; -- keeps the new id
  return v; -- gives it back
exception when unique_violation then -- the session's no-show time is already logged:
  raise exception 'You have already logged time for that session' using errcode = '22023'; -- plain refusal
end; -- finish
$$; -- end of the function
revoke all on function public.billing_log_my_hours(date, int, text, text, text, uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.billing_log_my_hours(date, int, text, text, text, uuid) to authenticated; -- signed-in people (checked inside)

-- ---------------------------------------------------------------------------
-- 4. Approving a no-show entry marks it checked without adding pay (the
--    session already paid for that time). billing_review_hours is edited in
--    place, so other changes to it stay.
-- ---------------------------------------------------------------------------
do $$ -- a small block of code
declare -- working values:
  v_def text; -- the function's current code
  v_anchor text := E'  end if; -- end of declining\n'; -- the line the new step goes after
  v_new text := E'  if v.work_category = ''no_show_time'' then -- time during a no-show or late cancel (Carla, 18 Nov 2026):\n'
             || E'    update public.billing_hour_logs -- marks the entry checked:\n'
             || E'    set status = ''approved'', review_note = nullif(left(trim(coalesce(p_note, '''')), 300), ''''), -- approved, with any note\n'
             || E'        reviewed_by = auth.uid(), reviewed_at = now() -- who and when (no pay line: the session already paid this time)\n'
             || E'    where id = p_log; -- this entry\n'
             || E'    return; -- finished\n'
             || E'  end if; -- end of the no-show case\n'; -- the new step
begin -- start
  if to_regprocedure('public.billing_review_hours(uuid, boolean, text)') is null then -- the function is not there
    raise exception 'Run 20261116300200_billing_training_pay.sql first.'; -- plain message
  end if; -- end of the check
  v_def := replace(pg_get_functiondef('public.billing_review_hours(uuid, boolean, text)'::regprocedure), chr(13), ''); -- reads its code (without Windows line endings from pasting)
  if strpos(v_def, 'end of the no-show case') > 0 then -- already done:
    return; -- nothing to change
  end if; -- end of the check
  if strpos(v_def, v_anchor) = 0 then -- the code has changed since this was written:
    raise exception 'public.billing_review_hours has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- end of the check
  execute replace(v_def, v_anchor, v_anchor || v_new); -- saves the code with the new step
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 5. Guaranteed hours: no-show entries waiting for approval are not counted
--    as extra hours (the session's pay line already counts that time).
-- ---------------------------------------------------------------------------
do $$ -- a small block of code
declare -- working values:
  v_def text; -- the function's current code
  v_old text := E'and h.status = ''submitted'' and h.source in (''staff'', ''training'')'; -- the condition being extended
begin -- start
  if to_regprocedure('public.billing_check_guaranteed_hours(date)') is null then -- the function is not there
    return; -- nothing to change
  end if; -- end of the check
  v_def := replace(pg_get_functiondef('public.billing_check_guaranteed_hours(date)'::regprocedure), chr(13), ''); -- reads its code (without Windows line endings from pasting)
  if strpos(v_def, 'is distinct from ''no_show_time''') > 0 then -- already done:
    return; -- nothing to change
  end if; -- end of the check
  if strpos(v_def, v_old) = 0 then -- the code has changed since this was written:
    raise exception 'public.billing_check_guaranteed_hours has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- end of the check
  execute replace(v_def, v_old, v_old || E' and h.work_category is distinct from ''no_show_time'''); -- saves the code with the extra condition
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 6. A tutor's own no-show and late-cancel sessions from the last 60 days,
--    for the "which session" choice on the My pay page.
-- ---------------------------------------------------------------------------
create or replace function public.my_no_show_sessions() -- no inputs: it is for the person asking
returns table (id uuid, starts_at timestamptz, ends_at timestamptz, student_first_name text, subject text, status text) -- one row per session
language sql stable security definer -- reads sessions for the person asking only
set search_path = '' -- only fully named tables, for safety
as $$ -- the list:
  select s.id, s.starts_at, s.ends_at, private.first_name(st.full_name), s.subject, s.status::text -- the session's details (learner's first name only)
  from public.sessions s -- from sessions
  join public.students st on st.id = s.student_id -- with the learner
  where s.tutor_id = auth.uid() -- the person's own sessions
    and (s.status = 'no_show' -- that were a no-show,
         or (s.status = 'cancelled' and coalesce(s.cancelled_by_role, '') <> 'tutor' and s.cancelled_at > s.starts_at - interval '24 hours')) -- or cancelled late (within 24 hours) by the family or CLG
    and s.starts_at <= now() -- that were due to start by now
    and s.starts_at >= now() - interval '60 days' -- in the last 60 days
    and not exists (select 1 from public.billing_hour_logs h where h.session_id = s.id and h.work_category = 'no_show_time' and h.status <> 'declined') -- not already logged
  order by s.starts_at desc -- newest first
$$; -- end of the function
revoke all on function public.my_no_show_sessions() from public, anon; -- not for signed-out visitors
grant execute on function public.my_no_show_sessions() to authenticated; -- signed-in people (they only see their own)
