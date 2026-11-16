-- Summary: check-ins after a new match (Carla, 16 Nov 2026: "Yes, all of these").
--
-- When a tutor and a learner start working together, the app asks how it is
-- going three times: 1 week, 2 weeks and 6 weeks after their first session.
-- Each person is asked on their own:
--   * the tutor;
--   * each parent or carer linked to the learner;
--   * the learner, if they have their own login (16 and over, or an adult
--     learner).
-- Each check-in is four short questions: how it is going (1 to 5), whether it
-- is a good fit (yes, not sure, no), whether they would like CLG to contact
-- them, and an optional comment. They can also skip one.
--
-- A poor answer (rated 1 or 2, "not a good fit", or asking CLG to make
-- contact) is flagged for follow-up. Full admins (owner and operations, with
-- two-step sign-in) see every answer and mark each flag as followed up.
--
-- Privacy:
--   * nobody but full admins can read the answers. The tutor never sees what
--     the family said, and the family never sees what the tutor said, so
--     both can be honest;
--   * comments go through the concerning-words check like other writing;
--   * the activity log holds ids only.
--
-- Quiet hours: a check-in only appears outside quiet hours (9pm to 5am) in
-- the person's own local time. Check-ins are shown in the app only (Carla
-- chose app notices only on 2 Nov 2026, so no emails are sent).
--
-- Only matches whose first session is on or after the start date below get
-- check-ins, so families who have had the same tutor for years are not asked.
--
-- Needs 20261113200100_quiet_hours.sql (quiet hours in each person's time
-- zone) and 20261114100100_safety_watch_words.sql (the concerning-words
-- check, optional). Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. The setting: from which date new matches get check-ins
-- ---------------------------------------------------------------------------

-- One row holding the date check-ins started. Matches whose first session is before it are not asked.
create table if not exists public.match_check_in_settings ( -- one row only
  id boolean primary key default true check (id), -- always "true", so there can only be one row
  starts_from date not null default date '2026-11-16', -- first sessions on or after this date (Adelaide time) get check-ins
  updated_at timestamptz not null default now() -- when it last changed
); -- end of the table
insert into public.match_check_in_settings (id) values (true) on conflict (id) do nothing; -- adds the one row (leaves it alone if it is already there)
alter table public.match_check_in_settings enable row level security; -- turns on access rules
revoke all on public.match_check_in_settings from anon, authenticated; -- nobody changes it directly
grant select on public.match_check_in_settings to authenticated; -- signed-in people may read it
drop policy if exists "full admins read check-in settings" on public.match_check_in_settings; -- removes the old rule if the file is run again
create policy "full admins read check-in settings" on public.match_check_in_settings for select to authenticated using (private.is_admin()); -- only full admins read it

-- ---------------------------------------------------------------------------
-- 2. The answers
-- ---------------------------------------------------------------------------

-- One row for each person's answer to one check-in (or their choice to skip it).
create table if not exists public.match_check_ins ( -- one row per answer
  id uuid primary key default gen_random_uuid(), -- its id
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade, -- the tutor in the match
  student_id uuid not null references public.students (id) on delete cascade, -- the learner in the match (answers go when the learner's record is deleted)
  stage smallint not null check (stage in (1, 2, 6)), -- which check-in: 1 week, 2 weeks or 6 weeks after the first session
  respondent_id uuid references public.accounts (id) on delete set null, -- who answered (empty if their account is later deleted)
  respondent_kind text not null check (respondent_kind in ('tutor', 'parent', 'student')), -- whether they answered as the tutor, a parent or the learner
  respondent_name text not null check (char_length(respondent_name) between 1 and 200), -- their name, copied so the record stays complete
  tutor_name text not null check (char_length(tutor_name) between 1 and 200), -- the tutor's name, copied
  student_name text not null check (char_length(student_name) between 1 and 200), -- the learner's name, copied
  skipped boolean not null default false, -- true when they chose to skip this check-in
  rating smallint check (rating between 1 and 5), -- how it is going, 1 (not well at all) to 5 (very well); empty when skipped
  fit text check (fit in ('yes', 'unsure', 'no')), -- whether it is a good fit; empty when skipped
  wants_contact boolean not null default false, -- true when they asked CLG to contact them
  comment text check (char_length(comment) <= 2000), -- anything else they want to say (optional)
  follow_up text not null default 'none' check (follow_up in ('none', 'open', 'done')), -- no follow-up needed, waiting for follow-up, or followed up
  follow_up_note text check (char_length(follow_up_note) <= 2000), -- the admins' private note on what was done
  followed_up_by uuid references public.accounts (id) on delete set null, -- which admin marked it followed up
  followed_up_at timestamptz, -- when it was marked followed up
  created_at timestamptz not null default now(), -- when they answered
  check (skipped or (rating is not null and fit is not null)), -- an answer (not skipped) must have a rating and a fit
  unique (tutor_id, student_id, stage, respondent_id) -- each person answers each check-in once
); -- end of the table
create index if not exists match_check_ins_follow_up on public.match_check_ins (follow_up, created_at desc); -- finds flagged answers quickly
create index if not exists match_check_ins_pair on public.match_check_ins (tutor_id, student_id, stage); -- finds a match's answers quickly
alter table public.match_check_ins enable row level security; -- turns on access rules
revoke all on public.match_check_ins from anon, authenticated; -- no direct changes: everything goes through the functions below
grant select on public.match_check_ins to authenticated; -- signed-in people may read, but only the rows the rule below allows
drop policy if exists "full admins read check-ins" on public.match_check_ins; -- removes the old rule if the file is run again
create policy "full admins read check-ins" on public.match_check_ins -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (private.is_admin()); -- only full admins (owner and operations, with two-step sign-in); the tutor and the family never read answers

-- ---------------------------------------------------------------------------
-- 3. Helpers: which matches are new, and when each check-in is due
-- ---------------------------------------------------------------------------

-- Every new match still running, with the end of its first session. A match
-- is a tutor and a learner with a current assignment. It is "new" when their
-- first session (not counting cancelled ones) started on or after the start
-- date in the setting.
create or replace function private.check_in_matches() -- no inputs
returns table (tutor_id uuid, student_id uuid, first_end timestamptz) -- the tutor, the learner, and when their first session ended
language sql stable security definer -- reads sessions and assignments whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  with firsts as ( -- the first session for each tutor and learner:
    select distinct on (s.tutor_id, s.student_id) -- one row per tutor and learner,
      s.tutor_id, s.student_id, s.starts_at, s.ends_at -- with that session's start and end,
    from public.sessions s -- from all sessions,
    where s.status <> 'cancelled' -- leaving out cancelled ones,
    order by s.tutor_id, s.student_id, s.starts_at -- earliest first, so the first one is kept
  ) -- end of the first sessions
  select f.tutor_id, f.student_id, f.ends_at -- the tutor, the learner and when the first session ended
  from firsts f -- from the first sessions
  where (f.starts_at at time zone 'Australia/Adelaide')::date -- the first session's date in Adelaide
        >= coalesce((select c.starts_from from public.match_check_in_settings c where c.id), date '2026-11-16') -- is on or after the start date,
    and exists ( -- and the match is still running:
      select 1 from public.tutor_assignments a -- an assignment
      where a.tutor_id = f.tutor_id and a.student_id = f.student_id -- for this tutor and learner
        and private.assignment_is_current(a.starts_on, a.ends_on) -- that is current today
    ) -- end of the check
$$; -- end of the function
revoke all on function private.check_in_matches() from public; -- only used inside other functions

-- The three check-ins for every new match: when each opens and closes. Each
-- stays open until the next one opens, and the last one stays open for 2
-- weeks, so people who only open the app now and then still see it.
create or replace function private.check_in_schedule() -- no inputs
returns table (tutor_id uuid, student_id uuid, stage smallint, opens_at timestamptz, closes_at timestamptz) -- each check-in and its open and close times
language sql stable security definer -- reads the matches whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select m.tutor_id, m.student_id, st.stage, -- the match and the check-in,
    m.first_end + make_interval(days => st.opens_day), -- opens this many days after the first session ended,
    m.first_end + make_interval(days => st.closes_day) -- and closes this many days after it
  from private.check_in_matches() m -- for each new match
  cross join (values -- and each check-in:
    (1::smallint, 7, 14), -- 1 week: open from day 7 to day 14,
    (2::smallint, 14, 42), -- 2 weeks: open from day 14 to day 42 (when the 6-week one opens),
    (6::smallint, 42, 56) -- 6 weeks: open from day 42 to day 56
  ) as st (stage, opens_day, closes_day) -- (names for the columns above)
$$; -- end of the function
revoke all on function private.check_in_schedule() from public; -- only used inside other functions

-- When a check-in may be shown to a person: the time it opens, moved out of
-- quiet hours in that person's own local time.
create or replace function private.check_in_due_at(p_account uuid, p_opens timestamptz) -- takes the person and when the check-in opens
returns timestamptz -- the moment it may be shown to them
language sql stable security definer -- reads their details and the quiet hours setting whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the value
  select private.outside_quiet_hours_for(p_account, p_opens) -- quiet hours in their own time zone
$$; -- end of the function
revoke all on function private.check_in_due_at(uuid, timestamptz) from public; -- only used inside other functions

-- Every check-in waiting for the signed-in person right now, in any role:
-- open, past quiet hours for them, and not yet answered or skipped by them.
create or replace function private.my_due_check_ins() -- no inputs: it is for the signed-in person
returns table (tutor_id uuid, student_id uuid, stage smallint, respondent_kind text) -- each check-in and the role they answer it in
language sql stable security definer -- reads matches, links and answers whoever asks, but only for the signed-in person
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  with me as (select auth.uid() as id), -- who is signed in
  mine as ( -- the check-ins this person is asked, in each role:
    select c.tutor_id, c.student_id, c.stage, c.opens_at, c.closes_at, 'tutor'::text as kind -- as the tutor:
    from private.check_in_schedule() c, me where c.tutor_id = me.id -- their own matches
    union all -- and
    select c.tutor_id, c.student_id, c.stage, c.opens_at, c.closes_at, 'parent' -- as a parent or carer:
    from private.check_in_schedule() c, me -- each check-in
    where exists (select 1 from public.parent_student_links l where l.student_id = c.student_id and l.parent_id = me.id and l.verified_at is not null) -- for a child they are confirmed as linked to
    union all -- and
    select c.tutor_id, c.student_id, c.stage, c.opens_at, c.closes_at, 'student' -- as the learner:
    from private.check_in_schedule() c, me -- each check-in
    where exists (select 1 from public.students s where s.id = c.student_id and s.account_id = me.id) -- for their own learning (only learners with their own login)
  ) -- end of the list
  select m.tutor_id, m.student_id, m.stage, m.kind -- the check-in and the role
  from mine m, me -- from the list
  where (m.kind = 'tutor' or m.tutor_id <> me.id) -- (a tutor is never asked as a family member about their own match; that cannot happen, but this keeps it safe)
    and private.check_in_due_at(me.id, m.opens_at) <= now() -- it is open for them (after quiet hours),
    and now() < m.closes_at -- it has not closed yet,
    and not exists ( -- and they have not answered or skipped it:
      select 1 from public.match_check_ins a -- an answer
      where a.tutor_id = m.tutor_id and a.student_id = m.student_id and a.stage = m.stage and a.respondent_id = me.id -- by them, for this check-in
    ) -- end of the check
$$; -- end of the function
revoke all on function private.my_due_check_ins() from public; -- only used inside other functions

-- ---------------------------------------------------------------------------
-- 4. What people see and do
-- ---------------------------------------------------------------------------

-- The check-ins waiting for the signed-in person on one dashboard: the tutor
-- dashboard shows tutor check-ins, the parent dashboard parent ones, and the
-- student dashboard the learner's own. Gives first names only, for the
-- question wording.
create or replace function public.my_check_ins(p_as text) -- takes the dashboard: 'tutor', 'parent' or 'student'
returns table (tutor_id uuid, student_id uuid, stage smallint, respondent_kind text, tutor_first_name text, student_first_name text) -- each check-in and the names for the question
language sql stable security definer -- reads names past the access rules, but only for the person's own check-ins
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select d.tutor_id, d.student_id, d.stage, d.respondent_kind, -- the check-in,
    coalesce(nullif(split_part(btrim(t.full_name), ' ', 1), ''), 'your tutor'), -- the tutor's first name,
    coalesce(nullif(split_part(btrim(s.full_name), ' ', 1), ''), 'your learner') -- and the learner's first name
  from private.my_due_check_ins() d -- from the person's waiting check-ins
  join public.accounts t on t.id = d.tutor_id -- with the tutor's account
  join public.students s on s.id = d.student_id -- and the learner's record
  where d.respondent_kind = p_as -- only the ones for this dashboard
  order by d.stage, s.full_name -- earliest check-in first, then by learner
$$; -- end of the function
revoke all on function public.my_check_ins(text) from public, anon; -- not for signed-out visitors
grant execute on function public.my_check_ins(text) to authenticated; -- signed-in people

-- Saves the signed-in person's answer to one check-in (or their choice to
-- skip it). Only a check-in that is waiting for them can be answered. A poor
-- answer is flagged for follow-up.
create or replace function public.answer_check_in( -- the inputs:
  p_tutor uuid, -- the tutor in the match
  p_student uuid, -- the learner in the match
  p_stage smallint, -- which check-in (1, 2 or 6)
  p_rating smallint, -- how it is going, 1 to 5 (ignored when skipping)
  p_fit text, -- 'yes', 'unsure' or 'no' (ignored when skipping)
  p_wants_contact boolean, -- whether they would like CLG to contact them
  p_comment text, -- anything else (optional)
  p_skip boolean default false -- true to skip this check-in
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
      raise exception 'Please choose how it is going, from 1 to 5.' using errcode = '22023'; -- plain message
    end if; -- end of the check
    if coalesce(p_fit, '') not in ('yes', 'unsure', 'no') then -- no fit answer
      raise exception 'Please choose yes, not sure or no.' using errcode = '22023'; -- plain message
    end if; -- end of the check
  end if; -- end of the answer checks
  if char_length(coalesce(p_comment, '')) > 2000 then -- a very long comment
    raise exception 'Please keep your comment under 2000 characters.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_follow := case -- whether CLG should follow up:
    when v_contact then 'open' -- they asked CLG to contact them (even when skipping the questions),
    when not v_skip and (p_rating <= 2 or p_fit = 'no') then 'open' -- or a poor rating, or not a good fit,
    else 'none' -- otherwise nothing needed
  end; -- end of the choice
  insert into public.match_check_ins ( -- saves the answer:
    tutor_id, student_id, stage, -- which check-in,
    respondent_id, respondent_kind, respondent_name, tutor_name, student_name, -- who answered and the names,
    skipped, rating, fit, wants_contact, comment, follow_up -- and what they said
  ) -- end of the column list
  select p_tutor, p_student, p_stage, -- the check-in,
    v_me, v_kind, -- who answered and in which role,
    coalesce(nullif(btrim(me.full_name), ''), 'Unknown'), -- their name,
    coalesce(nullif(btrim(t.full_name), ''), 'Unknown'), -- the tutor's name,
    coalesce(nullif(btrim(s.full_name), ''), 'Unknown'), -- the learner's name,
    v_skip, -- whether they skipped,
    case when v_skip then null else p_rating end, -- the rating (none when skipped),
    case when v_skip then null else p_fit end, -- the fit (none when skipped),
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
revoke all on function public.answer_check_in(uuid, uuid, smallint, smallint, text, boolean, text, boolean) from public, anon; -- not for signed-out visitors
grant execute on function public.answer_check_in(uuid, uuid, smallint, smallint, text, boolean, text, boolean) to authenticated; -- signed-in people can try (the checks are inside)

-- ---------------------------------------------------------------------------
-- 5. Following up (full admins)
-- ---------------------------------------------------------------------------

-- Marks a flagged answer as followed up (or opens it again), with a private
-- note on what was done. Full admins only.
create or replace function public.check_in_follow_up(p_id uuid, p_done boolean, p_note text) -- takes the answer, whether it is done, and the note
returns void -- gives nothing back
language plpgsql security definer -- changes a table people cannot change directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if not private.is_admin() then -- not a full admin with two-step sign-in
    raise exception 'Only the owner and operations admins can follow up check-ins (with two-step sign-in).' using errcode = '42501'; -- plain message
  end if; -- end of the check
  update public.match_check_ins -- saves the change
  set follow_up = case when coalesce(p_done, true) then 'done' else 'open' end, -- followed up, or waiting again
      follow_up_note = nullif(left(btrim(coalesce(p_note, '')), 2000), ''), -- the note (empty clears it)
      followed_up_by = case when coalesce(p_done, true) then auth.uid() else null end, -- who did it (cleared when opened again)
      followed_up_at = case when coalesce(p_done, true) then now() else null end -- when (cleared when opened again)
  where id = p_id; -- this answer
  if not found then -- no such answer
    raise exception 'That check-in answer could not be found.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  perform private.log_event('check_in_follow_up', 'match_check_ins', p_id::text, jsonb_build_object('done', coalesce(p_done, true))); -- notes the change (id only)
end; -- ends the code
$$; -- end of the function
revoke all on function public.check_in_follow_up(uuid, boolean, text) from public, anon; -- not for signed-out visitors
grant execute on function public.check_in_follow_up(uuid, boolean, text) to authenticated; -- signed-in people can try (the admin check is inside)

-- Every new match's check-ins that have opened so far, for the admin
-- overview: who is in the match, when each check-in opened, whether it has
-- closed, how many people were asked, and how many answered or skipped. Full
-- admins only (anyone else gets nothing).
create or replace function public.check_in_overview() -- no inputs
returns table ( -- what it gives back:
  tutor_id uuid, student_id uuid, tutor_name text, student_name text, -- the match and names,
  stage smallint, opens_at timestamptz, closes_at timestamptz, is_closed boolean, -- the check-in, when it is open, and whether it has closed,
  asked integer, answered integer, skipped integer -- how many people were asked, answered and skipped
) -- end of the list
language sql stable security definer -- reads matches and links past the access rules
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select c.tutor_id, c.student_id, -- the match,
    coalesce(nullif(btrim(t.full_name), ''), 'Unknown'), -- the tutor's name,
    coalesce(nullif(btrim(s.full_name), ''), 'Unknown'), -- the learner's name,
    c.stage, c.opens_at, c.closes_at, c.closes_at <= now(), -- the check-in, its times, and whether it has closed,
    (1 -- the tutor,
      + (select count(*) from public.parent_student_links l where l.student_id = c.student_id and l.verified_at is not null) -- plus each confirmed parent or carer,
      + (case when s.account_id is not null then 1 else 0 end))::integer, -- plus the learner if they have their own login
    (select count(*) from public.match_check_ins a where a.tutor_id = c.tutor_id and a.student_id = c.student_id and a.stage = c.stage and not a.skipped)::integer, -- how many answered
    (select count(*) from public.match_check_ins a where a.tutor_id = c.tutor_id and a.student_id = c.student_id and a.stage = c.stage and a.skipped)::integer -- how many skipped
  from private.check_in_schedule() c -- every new match's check-ins
  join public.accounts t on t.id = c.tutor_id -- with the tutor's account
  join public.students s on s.id = c.student_id -- and the learner's record
  where private.is_admin() -- only for full admins,
    and c.opens_at <= now() -- and only check-ins that have opened
  order by c.opens_at desc, s.full_name, c.stage -- the latest first
$$; -- end of the function
revoke all on function public.check_in_overview() from public, anon; -- not for signed-out visitors
grant execute on function public.check_in_overview() to authenticated; -- signed-in people can try (the admin check is inside)

-- ---------------------------------------------------------------------------
-- 6. Concerning words: check-in comments are checked like other writing
-- ---------------------------------------------------------------------------
do $$ -- a small block of code
begin -- starts the block
  if to_regprocedure('private.scan_watch_words()') is null then -- the concerning-words check is not there
    return; -- nothing to do
  end if; -- end of the check
  drop trigger if exists watch_words_scan on public.match_check_ins; -- removes the old check if the file is run again
  create trigger watch_words_scan after insert or update of comment on public.match_check_ins -- after a new answer or a change to its comment,
    for each row execute function private.scan_watch_words('comment'); -- checks the comment
end; -- ends the block
$$; -- end of the code
