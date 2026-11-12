-- Scheduling: tell everyone when a session time runs out with no answer,
-- and count the times waiting for each person (Carla, 12 Nov 2026).
--
-- What already happens: when a time is offered, the tutor (and the family,
-- for a time CLG found) get a notice straight away, and for a time CLG
-- found there is a reminder at 48 hr (it stays open 72 hr).
-- This adds:
--   * a notice when the answer time runs out with no answer, to the tutor,
--     the family and CLG's admins, so a new time or tutor can be found;
--   * my_offers_to_answer(), so the tutor and parent dashboards can show
--     how many times are waiting for that person's answer.
-- A job checks every 15 minutes (where pg_cron is available, as on
-- Supabase). Each notice is sent once per booking.
--
-- Safe to run more than once.

-- Remember when the "not answered" notice went, so it goes out only once.
alter table public.bookings add column if not exists not_answered_notice_at timestamptz; -- empty until the notice is sent

-- Send the "not answered in time" notices that are due. Returns how many
-- bookings were handled. Run by the 15-minute job.
create or replace function private.notify_offers_not_answered()
returns integer -- how many bookings got a notice
language plpgsql security definer -- runs with full rights, as a background job
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps below
declare -- working values
  b record; -- one booking at a time
  p record; -- one person to tell
  v_student text; -- the student's name
  v_tutor text; -- the tutor's name
  v_when text; -- e.g. "Mondays at 4:00pm"
  v_done integer := 0; -- how many bookings were handled
begin -- start
  for b in -- each booking that ran out with no answer
    select * from public.bookings x -- every booking
    where x.status = 'requested' -- still waiting for answers
      and x.not_answered_notice_at is null -- nobody told yet
      and x.tutor_reply_by <= now() -- the answer time has run out
      and x.tutor_reply_by > now() - interval '7 days' -- skip old ones from before this update
    for update skip locked -- don't fight another run over the same row
  loop -- one booking at a time
    select full_name into v_student from public.students where id = b.student_id; -- student's name
    select full_name into v_tutor from public.accounts where id = b.tutor_id; -- tutor's name
    v_when := (array['Mondays','Tuesdays','Wednesdays','Thursdays','Fridays','Saturdays','Sundays'])[b.weekday] -- day words
              || ' at ' || lower(trim(to_char(timestamp '2000-01-01' + b.start_time, 'FMHH12:MIam'))); -- time words
    for p in select * from private.session_people(b.student_id, b.tutor_id) loop -- the tutor and the family
      perform private.add_notice(p.account_id, null, b.id, 'booking_declined', 'Session time not answered in time', -- tell each one
        v_student || ' (' || b.subject || '), ' || v_when -- who and when
        || ': not everyone answered in time, so this time has lapsed. CLG will be in touch about another time.', now()); -- what happens next
    end loop; -- everyone told
    perform private.notify_admins('Session time not answered', -- tell CLG's admins
      v_student || ' (' || b.subject || ') with ' || coalesce(v_tutor, 'the tutor') || ', ' || v_when -- who and when
      || ': no answer in time from the ' -- what went wrong
      || case when b.tutor_ok_at is null and b.needs_family_ok and b.family_ok_at is null then 'tutor or the family' -- neither answered
              when b.tutor_ok_at is null then 'tutor' -- the tutor didn't answer
              else 'family' end -- the family didn't answer
      || '. The student is back in Matching.', b.id); -- what to do next
    update public.bookings set not_answered_notice_at = now() where id = b.id; -- mark it told
    v_done := v_done + 1; -- count it
  end loop; -- all bookings done
  return v_done; -- how many bookings were handled
end; -- finish
$$; -- end of the function
revoke all on function private.notify_offers_not_answered() from public; -- only the background job runs it

-- Run it every 15 minutes, where pg_cron is available (Supabase has it).
do $$ -- a one-off block
begin -- start
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then -- the job scheduler is available
    execute 'create extension if not exists pg_cron with schema pg_catalog'; -- turn it on if needed
    execute $job$ select cron.schedule('clg-offers-not-answered', '*/15 * * * *', 'select private.notify_offers_not_answered()') $job$; -- every 15 minutes (re-running replaces the same named job)
  end if; -- done checking
end; -- finish
$$; -- end of the block

-- How many session times are waiting for the viewer's own answer: as the
-- tutor, and as a parent (or adult student) approving a time CLG found.
create or replace function public.my_offers_to_answer()
returns table (as_tutor integer, as_family integer) -- two numbers
language sql stable security definer -- reads only bookings the viewer is part of (checked below)
set search_path = '' -- only fully named tables, for safety
as $$ -- the count
  select -- two numbers side by side
    (select count(*)::integer from public.bookings b -- times waiting for this tutor
     where b.tutor_id = auth.uid() -- the viewer is the tutor
       and b.status = 'requested' and b.tutor_ok_at is null -- not answered yet
       and b.tutor_reply_by > now()), -- still in time
    (select count(*)::integer from public.bookings b -- times waiting for this family
     where (private.is_parent_of(b.student_id) or private.is_student_self(b.student_id)) -- the viewer's own child, or themselves (not every child an admin can see)
       and b.status = 'requested' and b.needs_family_ok and b.family_ok_at is null -- not approved yet
       and b.tutor_reply_by > now()) -- still in time
$$; -- end of the function
revoke all on function public.my_offers_to_answer() from public, anon; -- not for signed-out visitors
grant execute on function public.my_offers_to_answer() to authenticated; -- signed-in people only (each sees their own)
