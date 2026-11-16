-- Scheduling: an offer nobody approved in 3 days is "closed for now"
-- (Carla, 16 Nov 2026).
--
-- Carla's rule for offers: a notice when the offer is sent, a reminder at
-- 48 hours to whoever hasn't answered, and after 3 days a message to the
-- family and the tutor saying the offer is closed for now. The notice when
-- sent and the 48-hour reminder already happen (20261103000400). This only
-- changes the words of the last message, so it matches the Student Success
-- Coordinator Handbook (v1.3) and the Client Terms (v1.2). Nothing else
-- about when or to whom it is sent changes.
--
-- Safe to run more than once.

-- Send the "closed for now" notices that are due. Returns how many
-- bookings were handled. Run by the 15-minute job (clg-offers-not-answered).
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
      perform private.add_notice(p.account_id, null, b.id, 'booking_declined', 'Session offer closed for now', -- tell each one
        v_student || ' (' || b.subject || '), ' || v_when -- who and when
        || ': this offer wasn''t approved by everyone within 3 days, so it has closed for now. CLG will be in touch about another time.', now()); -- what happens next
    end loop; -- everyone told
    perform private.notify_admins('Session offer closed for now', -- tell CLG's admins
      v_student || ' (' || b.subject || ') with ' || coalesce(v_tutor, 'the tutor') || ', ' || v_when -- who and when
      || ': no answer in time from the ' -- what went wrong
      || case when b.tutor_ok_at is null and b.needs_family_ok and b.family_ok_at is null then 'tutor or the family' -- neither answered
              when b.tutor_ok_at is null then 'tutor' -- the tutor didn't answer
              else 'family' end -- the family didn't answer
      || '. The offer has closed for now and the student is back in Matching. Contact whoever didn''t answer, then send a new offer.', b.id); -- what to do next
    update public.bookings set not_answered_notice_at = now() where id = b.id; -- mark it told
    v_done := v_done + 1; -- count it
  end loop; -- all bookings done
  return v_done; -- how many bookings were handled
end; -- finish
$$; -- end of the function
revoke all on function private.notify_offers_not_answered() from public; -- only the background job runs it
