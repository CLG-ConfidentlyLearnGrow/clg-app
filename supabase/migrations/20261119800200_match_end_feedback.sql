-- Summary: feedback when a match ends (Carla, 16 Nov 2026: "whenever a tutor
-- and client are unmatched, they are asked for feedback too, and ... how it
-- has been handled").
--
-- When a tutor and a learner stop working together (for example a change of
-- tutor, or their bookings come to an end with no new ones), the tutor, each
-- parent or carer, and the learner (if they have their own login) are each
-- asked two short questions, plus a comment and a "please contact me" tick:
--   * overall, how did the sessions go? (1 to 5)
--   * how well was the ending handled? (1 to 5)
-- It is asked the day after the match ends and stays open for 3 weeks. It
-- uses the same answers table and admin page as the 1, 2 and 6-week
-- check-ins (stage 0 means "end of match"), so the same privacy rules apply:
-- only full admins read answers, comments go through the concerning-words
-- check (so safety words reach the Child Safety Officer and deputy), and
-- quiet hours are kept. A rating of 1 or 2 on either question, or a request
-- for contact, is flagged for follow-up.
--
-- A match counts as ended when the tutor and learner had at least one session
-- (not counting cancelled ones), no assignment for them is current or still
-- to come, and the last one ended on or after the check-in start date (so
-- matches that ended long ago are not asked).
--
-- The 1, 2 and 6-week check-ins already stop once a match ends: they are only
-- asked while the match has a current assignment.
--
-- Needs 20261119800100_match_check_ins.sql first. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. The answers table: allow the end-of-match stage and its extra question
-- ---------------------------------------------------------------------------

-- The end-of-match question: how well the ending was handled.
alter table public.match_check_ins add column if not exists ending_rating smallint check (ending_rating between 1 and 5); -- 1 (very poorly) to 5 (very well); only for end-of-match feedback

-- Stage 0 now means "end of match", as well as 1, 2 and 6 weeks.
alter table public.match_check_ins drop constraint if exists match_check_ins_stage_check; -- removes the old list of stages
alter table public.match_check_ins add constraint match_check_ins_stage_check check (stage in (0, 1, 2, 6)); -- adds the new list

-- An answer (not skipped) needs a rating; the fit question is only for the
-- 1, 2 and 6-week check-ins, and the ending question only for end-of-match.
alter table public.match_check_ins drop constraint if exists match_check_ins_check; -- removes the old rule (rating and fit always needed)
alter table public.match_check_ins drop constraint if exists match_check_ins_answer_check; -- removes this rule if the file is run again
alter table public.match_check_ins add constraint match_check_ins_answer_check check ( -- the new rule:
  skipped -- a skip needs nothing,
  or (stage = 0 and rating is not null and ending_rating is not null) -- end of match needs both ratings,
  or (stage <> 0 and rating is not null and fit is not null) -- the others need a rating and a fit
); -- end of the rule

-- ---------------------------------------------------------------------------
-- 2. Which matches have ended
-- ---------------------------------------------------------------------------

-- Every match that has ended, with the last day it ran. Only matches that
-- had a session, have no current or future assignment, and ended on or after
-- the day before the check-in start date.
create or replace function private.check_in_ended_matches() -- no inputs
returns table (tutor_id uuid, student_id uuid, ended_on date) -- the tutor, the learner and the last day of the match
language sql stable security definer -- reads assignments and sessions whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select a.tutor_id, a.student_id, max(a.ends_on) -- each tutor and learner, and the last day any of their assignments ran
  from public.tutor_assignments a -- from the assignments
  group by a.tutor_id, a.student_id -- one row per tutor and learner
  having bool_and(a.ends_on is not null and a.ends_on < (now() at time zone 'Australia/Adelaide')::date) -- every assignment has finished (none current, none open-ended, none still to come),
    and max(a.ends_on) >= coalesce((select c.starts_from from public.match_check_in_settings c where c.id), date '2026-11-16') - 1 -- it ended recently enough to ask about,
    and exists ( -- and they actually worked together:
      select 1 from public.sessions s -- a session
      where s.tutor_id = a.tutor_id and s.student_id = a.student_id and s.status <> 'cancelled' -- for this tutor and learner, not cancelled
    ) -- end of the check
$$; -- end of the function
revoke all on function private.check_in_ended_matches() from public; -- only used inside other functions

-- ---------------------------------------------------------------------------
-- 3. The schedule: the 1, 2 and 6-week check-ins, plus end-of-match feedback
-- ---------------------------------------------------------------------------

-- Every check-in and when it opens and closes. The 1, 2 and 6-week ones are
-- as before (only while the match is running). End-of-match feedback (stage
-- 0) opens at 9am Adelaide time the day after the match ends, and stays open
-- for 3 weeks.
create or replace function private.check_in_schedule() -- no inputs
returns table (tutor_id uuid, student_id uuid, stage smallint, opens_at timestamptz, closes_at timestamptz) -- each check-in and its open and close times
language sql stable security definer -- reads the matches whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select m.tutor_id, m.student_id, st.stage, -- the match and the check-in,
    m.first_end + make_interval(days => st.opens_day), -- opens this many days after the first session ended,
    m.first_end + make_interval(days => st.closes_day) -- and closes this many days after it
  from private.check_in_matches() m -- for each new match still running
  cross join (values -- and each check-in:
    (1::smallint, 7, 14), -- 1 week: open from day 7 to day 14,
    (2::smallint, 14, 42), -- 2 weeks: open from day 14 to day 42 (when the 6-week one opens),
    (6::smallint, 42, 56) -- 6 weeks: open from day 42 to day 56
  ) as st (stage, opens_day, closes_day) -- (names for the columns above)
  union all -- and
  select e.tutor_id, e.student_id, 0::smallint, -- each ended match, as stage 0 (end of match),
    ((e.ended_on + 1) + time '09:00') at time zone 'Australia/Adelaide', -- opens at 9am the day after it ended,
    ((e.ended_on + 22) + time '09:00') at time zone 'Australia/Adelaide' -- and closes 3 weeks later
  from private.check_in_ended_matches() e -- from the ended matches
$$; -- end of the function
revoke all on function private.check_in_schedule() from public; -- only used inside other functions

-- ---------------------------------------------------------------------------
-- 4. Answering: the ending question, and the follow-up flag
-- ---------------------------------------------------------------------------

-- The old version had no ending question. It is removed so there is only
-- one way to answer (two versions would confuse the database).
drop function if exists public.answer_check_in(uuid, uuid, smallint, smallint, text, boolean, text, boolean); -- removes the old version

-- Saves the signed-in person's answer to one check-in (or their choice to
-- skip it). Only a check-in waiting for them can be answered. For
-- end-of-match feedback (stage 0) the fit question is not asked and the
-- ending question is. A poor answer is flagged for follow-up.
create or replace function public.answer_check_in( -- the inputs:
  p_tutor uuid, -- the tutor in the match
  p_student uuid, -- the learner in the match
  p_stage smallint, -- which check-in (0 for end of match, or 1, 2 or 6)
  p_rating smallint, -- how it is going (or went), 1 to 5 (ignored when skipping)
  p_fit text, -- 'yes', 'unsure' or 'no' (1, 2 and 6 weeks only; ignored when skipping)
  p_wants_contact boolean, -- whether they would like CLG to contact them
  p_comment text, -- anything else (optional)
  p_skip boolean default false, -- true to skip this check-in
  p_ending_rating smallint default null -- how well the ending was handled, 1 to 5 (end of match only)
) -- end of the inputs
returns uuid -- gives back the new answer's id
language plpgsql security definer -- saves to a table people cannot write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_me uuid := auth.uid(); -- who is answering
  v_kind text; -- the role they answer in
  v_skip boolean := coalesce(p_skip, false); -- whether they are skipping
  v_contact boolean := coalesce(p_wants_contact, false); -- whether they asked to be contacted
  v_end boolean := p_stage = 0; -- whether this is end-of-match feedback
  v_follow text; -- whether it needs follow-up
  v_id uuid; -- the new answer's id
begin -- starts the code
  if v_me is null then -- nobody signed in
    raise exception 'Please sign in to answer the check-in.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  select d.respondent_kind into v_kind -- the role they answer in
  from private.my_due_check_ins() d -- from their waiting check-ins
  where d.tutor_id = p_tutor and d.student_id = p_student and d.stage = p_stage -- this one
  order by case d.respondent_kind when 'tutor' then 1 when 'student' then 2 else 3 end -- (if somehow more than one, the closest role first)
  limit 1; -- just one
  if v_kind is null then -- not waiting for them (already answered, closed, or not theirs)
    raise exception 'This check-in is not waiting for you. It may already be answered or closed.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if not v_skip then -- a real answer:
    if p_rating is null or p_rating not between 1 and 5 then -- no rating, or out of range
      raise exception 'Please choose how it went, from 1 to 5.' using errcode = '22023'; -- plain message
    end if; -- end of the check
    if v_end and (p_ending_rating is null or p_ending_rating not between 1 and 5) then -- end of match with no ending rating
      raise exception 'Please choose how well the ending was handled, from 1 to 5.' using errcode = '22023'; -- plain message
    end if; -- end of the check
    if not v_end and coalesce(p_fit, '') not in ('yes', 'unsure', 'no') then -- a weekly check-in with no fit answer
      raise exception 'Please choose yes, not sure or no.' using errcode = '22023'; -- plain message
    end if; -- end of the check
  end if; -- end of the answer checks
  if char_length(coalesce(p_comment, '')) > 2000 then -- a very long comment
    raise exception 'Please keep your comment under 2000 characters.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_follow := case -- whether CLG should follow up:
    when v_contact then 'open' -- they asked CLG to contact them (even when skipping the questions),
    when not v_skip and (p_rating <= 2 or (not v_end and p_fit = 'no') or (v_end and p_ending_rating <= 2)) then 'open' -- or a poor rating, not a good fit, or a poorly handled ending,
    else 'none' -- otherwise nothing needed
  end; -- end of the choice
  insert into public.match_check_ins ( -- saves the answer:
    tutor_id, student_id, stage, -- which check-in,
    respondent_id, respondent_kind, respondent_name, tutor_name, student_name, -- who answered and the names,
    skipped, rating, fit, ending_rating, wants_contact, comment, follow_up -- and what they said
  ) -- end of the column list
  select p_tutor, p_student, p_stage, -- the check-in,
    v_me, v_kind, -- who answered and in which role,
    coalesce(nullif(btrim(me.full_name), ''), 'Unknown'), -- their name,
    coalesce(nullif(btrim(t.full_name), ''), 'Unknown'), -- the tutor's name,
    coalesce(nullif(btrim(s.full_name), ''), 'Unknown'), -- the learner's name,
    v_skip, -- whether they skipped,
    case when v_skip then null else p_rating end, -- the rating (none when skipped),
    case when v_skip or v_end then null else p_fit end, -- the fit (none when skipped or at the end of a match),
    case when v_skip or not v_end then null else p_ending_rating end, -- the ending rating (end of match only),
    v_contact, -- whether they asked to be contacted,
    nullif(left(btrim(coalesce(p_comment, '')), 2000), ''), -- the comment (empty becomes none),
    v_follow -- whether it needs follow-up
  from public.accounts me, public.accounts t, public.students s -- from their account, the tutor's account and the learner's record
  where me.id = v_me and t.id = p_tutor and s.id = p_student -- (the right ones)
  returning id into v_id; -- keeps the new id
  if v_id is null then -- nothing saved (a missing record)
    raise exception 'We could not save that. Please try again.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  perform private.log_event('answer_check_in', 'match_check_ins', v_id::text, jsonb_build_object('stage', p_stage, 'follow_up', v_follow)); -- notes it in the activity log (id, stage and flag only)
  return v_id; -- hands back the new id
end; -- ends the code
$$; -- end of the function
revoke all on function public.answer_check_in(uuid, uuid, smallint, smallint, text, boolean, text, boolean, smallint) from public, anon; -- not for signed-out visitors
grant execute on function public.answer_check_in(uuid, uuid, smallint, smallint, text, boolean, text, boolean, smallint) to authenticated; -- signed-in people can try (the checks are inside)
