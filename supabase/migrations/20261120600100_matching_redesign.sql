-- Scheduling: the cleaner Matching page (Carla, 16 Nov 2026, ideas 1 to 3).
--
-- What this adds for the Matching page:
--   1. Back-dating: admins can say when a student really started waiting
--      (for students who were on CLG's waitlist before the app).
--   2. Missing information: which students still need a year level,
--      school, session places or "How long to book", for the ready check.
--   3. "Ask the family": tells the family in the app and by email what is
--      missing, with a link to fill it in and a link to the help chat.
--   4. Offers waiting: whether each offer waits for the tutor or the family.
--   5. Response times: how long each tutor, and families, take to answer.
--
-- Changes private.matching_rows and private.emails_waiting in place, so
-- other changes to them are kept. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. Back-dating when a student started waiting
-- ---------------------------------------------------------------------------

-- The date an admin gave for when a student started waiting for a subject.
create table if not exists public.matching_waiting_since ( -- makes the "waiting since" table (once)
  student_id uuid not null references public.students (id) on delete cascade, -- the student (removed with them)
  subject text not null check (char_length(subject) between 1 and 100), -- the subject
  since timestamptz not null, -- when they started waiting
  set_by uuid references public.accounts (id) on delete set null, -- the admin who set it
  set_at timestamptz not null default now() -- when it was set
); -- end of the table
create unique index if not exists matching_waiting_since_one on public.matching_waiting_since (student_id, lower(subject)); -- one date per student and subject
alter table public.matching_waiting_since enable row level security; -- access rules apply
revoke all on public.matching_waiting_since from anon; -- signed-out visitors see nothing
drop policy if exists "front desk reads waiting dates" on public.matching_waiting_since; -- replace the rule if re-run
create policy "front desk reads waiting dates" on public.matching_waiting_since -- only CLG's front desk admins can read it
  for select to authenticated using (private.is_front_desk()); -- (changes go through set_waiting_since)

-- Front desk admins set (or clear, with no date) when a student started waiting.
create or replace function public.set_waiting_since(p_student uuid, p_subject text, p_since date) -- makes or updates the back-dating function
returns void -- nothing back
language plpgsql security definer -- writes after checking who is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  if not private.is_front_desk() then -- only owner, operations and support admins
    raise exception 'Only CLG admins can change this' using errcode = '42501'; -- plain message
  end if; -- checked who
  if not exists (select 1 from public.student_subjects ss where ss.student_id = p_student and lower(ss.subject) = lower(trim(p_subject))) then -- the subject must be one they asked for
    raise exception 'This student has not asked for that subject' using errcode = '22023'; -- plain message
  end if; -- checked the subject
  if p_since is null then -- no date: clear it
    delete from public.matching_waiting_since where student_id = p_student and lower(subject) = lower(trim(p_subject)); -- remove the date
    return; -- done
  end if; -- (clearing done)
  if p_since > (now() at time zone 'Australia/Adelaide')::date or p_since < date '2015-01-01' then -- must be a sensible past date
    raise exception 'Please choose a date between 2015 and today' using errcode = '22023'; -- plain message
  end if; -- checked the date
  insert into public.matching_waiting_since (student_id, subject, since, set_by) -- save it:
  values (p_student, trim(p_subject), (p_since::timestamp at time zone 'Australia/Adelaide'), auth.uid()) -- the start of that day in Adelaide
  on conflict (student_id, lower(subject)) do update set since = excluded.since, set_by = excluded.set_by, set_at = now(); -- or replace the old date
end; -- finish
$$; -- end of the function
revoke all on function public.set_waiting_since(uuid, text, date) from public, anon; -- not for signed-out visitors
grant execute on function public.set_waiting_since(uuid, text, date) to authenticated; -- signed-in (the function checks for admins)

-- Use the back-dated time in the Matching queue (the earlier of the two).
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's current text
  v_new text; -- the changed text
begin -- start
  v_def := replace(pg_get_functiondef('private.matching_rows()'::regprocedure), chr(13), ''); -- current text, without Windows line ends
  if position('matching_waiting_since' in v_def) = 0 then -- not changed yet
    v_new := replace(v_def, 'when w.id is not null then w.created_at', 'when w.id is not null then least(w.created_at, ws.since)'); -- waitlist: the earlier date
    v_new := replace(v_new, 'else greatest(ss.added_at, past.finished)', 'else least(greatest(ss.added_at, past.finished), ws.since)'); -- needs a tutor: the earlier date
    v_new := replace(v_new, 'left join public.student_places sp on sp.student_id = ss.student_id', -- add the back-dated time
      'left join public.student_places sp on sp.student_id = ss.student_id' || chr(10) -- (the line the new join goes after)
      || '  left join public.matching_waiting_since ws on ws.student_id = ss.student_id and lower(ws.subject) = lower(ss.subject)'); -- (joined by student and subject)
    if (length(v_new) - length(replace(v_new, 'ws.since', ''))) / length('ws.since') <> 2 or position('matching_waiting_since ws' in v_new) = 0 then -- expect all three changes
      raise exception 'matching_rows has changed since this was written; please ask for help'; -- stop rather than half-change it
    end if; -- checked
    execute v_new; -- save the changed function
  end if; -- done
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 2. Missing information for the ready check
-- ---------------------------------------------------------------------------

-- For the given students, each thing still missing before an offer, with
-- when the family was last asked. Items: year_level, school,
-- session_places, booking_length.
create or replace function public.matching_missing(p_students uuid[]) -- makes or updates the missing details check
returns table (student_id uuid, item text, last_asked timestamptz) -- each missing item and the last ask
language plpgsql stable security definer -- reads student details for front desk admins only
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  if not private.is_front_desk() then -- only owner, operations and support admins
    raise exception 'Only CLG admins can see this' using errcode = '42501'; -- plain message
  end if; -- checked who
  return query -- hand back:
  with m as ( -- every missing item:
    select s.id as sid, 'year_level'::text as it from public.students s where s.id = any (p_students) and s.year_level is null -- no year level
    union all -- adds the next check
    select s.id, 'school' from public.students s where s.id = any (p_students) and nullif(trim(coalesce(s.school, '')), '') is null -- no school
    union all -- adds the next check
    select s.id, 'session_places' from public.students s -- no places:
    left join public.student_places sp on sp.student_id = s.id -- (their places, if any)
    where s.id = any (p_students) -- one of these students
      and (sp.student_id is null or not (sp.online or coalesce(cardinality(sp.library_ids), 0) > 0 or sp.travel_km is not null)) -- nothing chosen
    union all -- adds the next check
    select s.id, 'booking_length' from public.students s -- "How long to book" not answered:
    left join public.student_places sp on sp.student_id = s.id -- (their answers, if any)
    where s.id = any (p_students) -- one of these students
      and (sp.book_until is null or sp.include_school_holidays is null or sp.include_public_holidays is null) -- any answer missing
  ) -- end of the items
  select m.sid, m.it, -- the student and item
    (select max(a.asked_at) from public.matching_family_asks a where a.student_id = m.sid and a.item = m.it) -- when the family was last asked
  from m; -- every one
end; -- finish
$$; -- end of the function

-- ---------------------------------------------------------------------------
-- 3. "Ask the family"
-- ---------------------------------------------------------------------------

-- One row per person asked, so the app notice and the email go out once.
create table if not exists public.matching_family_asks ( -- makes the family asks table (once)
  id uuid primary key default gen_random_uuid(), -- the ask's id
  student_id uuid not null references public.students (id) on delete cascade, -- the student (removed with them)
  item text not null check (item in ('year_level', 'school', 'session_places', 'booking_length')), -- what is missing
  account_id uuid not null references public.accounts (id) on delete cascade, -- the parent or adult student asked
  asked_by uuid references public.accounts (id) on delete set null, -- the admin who asked
  asked_at timestamptz not null default now(), -- when
  email_id uuid, -- the email's id once taken by the sender
  emailed_at timestamptz -- when it was emailed
); -- end of the table
create index if not exists matching_family_asks_student on public.matching_family_asks (student_id, item, asked_at); -- quick look-up by student and item
create index if not exists matching_family_asks_to_email on public.matching_family_asks (asked_at) where emailed_at is null; -- quick look-up of emails to send
alter table public.matching_family_asks enable row level security; -- access rules apply
revoke all on public.matching_family_asks from anon; -- signed-out visitors see nothing
drop policy if exists "front desk reads family asks" on public.matching_family_asks; -- replace the rule if re-run
create policy "front desk reads family asks" on public.matching_family_asks -- only CLG's front desk admins can read them
  for select to authenticated using (private.is_front_desk()); -- (asks are made through ask_family)

-- The plain words for each item.
create or replace function private.missing_item_label(p_item text) -- makes or updates the plain name for each detail
returns text -- e.g. "School"
language sql immutable -- always the same answer
set search_path = '' -- only fully named things, for safety
as $$ -- the words
  select case p_item -- by item:
    when 'year_level' then 'year level' -- year level
    when 'school' then 'school' -- school
    when 'session_places' then 'session places' -- session places
    when 'booking_length' then 'how long to book' -- how long to book
    else p_item end -- anything else as it is
$$; -- end of the function

-- The page in the app where the family fills each item in.
create or replace function private.missing_item_link(p_item text) -- makes or updates the link for each detail
returns text -- an app address
language sql immutable -- always the same answer
set search_path = '' -- only fully named things, for safety
as $$ -- the address
  select case p_item -- by item:
    when 'session_places' then '/schedule?as=parent&section=child-places' -- preferred times and places
    when 'booking_length' then '/schedule?as=parent&section=booking-length' -- how long to book
    else '/dashboard/parent?section=children' end -- year level and school: the child's details
$$; -- end of the function

-- Front desk admins ask the family to add a missing item. Tells each parent
-- (and the student, if they have their own login) in the app, and the email
-- goes out on the next send. Returns how many people were asked.
create or replace function public.ask_family(p_student uuid, p_item text) -- makes or updates the "Ask the family" function
returns integer -- how many people were asked
language plpgsql security definer -- writes asks and notices after checking who is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values
  v_child text; -- the student's first name
  v_count integer := 0; -- how many were asked
  p record; -- one person to ask
begin -- start
  if not private.is_front_desk() then -- only owner, operations and support admins
    raise exception 'Only CLG admins can ask families for information' using errcode = '42501'; -- plain message
  end if; -- checked who
  if p_item not in ('year_level', 'school', 'session_places', 'booking_length') then -- must be a known item
    raise exception 'Please choose what to ask the family for' using errcode = '22023'; -- plain message
  end if; -- checked the item
  if exists (select 1 from public.matching_family_asks a where a.student_id = p_student and a.item = p_item and a.asked_at > now() - interval '24 hours') then -- once a day at most
    raise exception 'The family was already asked about this in the last 24 hours' using errcode = '22023'; -- plain message
  end if; -- checked the timing
  select private.first_name(s.full_name) into v_child from public.students s where s.id = p_student; -- the child's first name
  if v_child is null then -- no such student
    raise exception 'Student not found' using errcode = '22023'; -- plain message
  end if; -- checked the student
  for p in select x.account_id from private.session_people(p_student, null) x where not x.is_tutor and x.account_id is not null loop -- each parent, and the student's own login
    insert into public.matching_family_asks (student_id, item, account_id, asked_by) values (p_student, p_item, p.account_id, auth.uid()); -- record the ask (for the email)
    perform private.add_notice(p.account_id, null, null, 'request_update', 'Please add ' || v_child || '''s ' || private.missing_item_label(p_item), -- the app notice's title
      'CLG needs ' || v_child || '''s ' || private.missing_item_label(p_item) || ' to find the right tutor and times. ' -- why
      || 'Please add it in the app. Need help with this? Ask CLG in the help chat.', now()); -- what to do, and where to get help
    v_count := v_count + 1; -- count them
  end loop; -- everyone asked
  if v_count = 0 then -- nobody to ask
    raise exception 'This student has no parent or own login to ask yet' using errcode = '22023'; -- plain message
  end if; -- checked
  return v_count; -- how many were asked
end; -- finish
$$; -- end of the function
revoke all on function public.ask_family(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.ask_family(uuid, text) to authenticated; -- signed-in (the function checks for admins)

-- Whether any "ask the family" emails are waiting (outside quiet hours).
create or replace function private.family_ask_emails_waiting() -- makes or updates the "any ask emails waiting" check
returns boolean -- yes or no
language sql stable security definer -- reads the asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- any ask:
    select 1 from public.matching_family_asks a -- each ask
    where a.emailed_at is null -- not yet emailed
      and a.asked_at > now() - interval '3 days' -- asked in the last 3 days
      and private.outside_quiet_hours(a.asked_at) <= now() -- and not in quiet hours
  ) -- end of the check
$$; -- end of the function
revoke all on function private.family_ask_emails_waiting() from public; -- used by the email sender only

-- The email sender collects waiting "ask the family" emails and marks them sent.
create or replace function public.family_ask_emails_claim(p_limit integer default 50) -- makes or updates the ask email pick-up
returns table (id uuid, email text, first_name text, subject text, body text, link text, button text, footer text) -- one email per ask
language plpgsql security definer -- reads and marks asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  return query -- hand back:
  with due as ( -- the asks to email:
    select a.id from public.matching_family_asks a -- each ask
    where a.emailed_at is null -- not yet emailed
      and a.asked_at > now() - interval '3 days' -- asked in the last 3 days
      and private.outside_quiet_hours(a.asked_at) <= now() -- not in quiet hours
    order by a.asked_at -- oldest first
    limit least(greatest(p_limit, 1), 100) -- at most the number asked for (1 to 100)
    for update skip locked -- so two senders never take the same one
  ), marked as ( -- marks them sent:
    update public.matching_family_asks a -- each ask taken
    set email_id = gen_random_uuid(), emailed_at = now() -- a new email id and the time
    from due where a.id = due.id -- (only the ones taken)
    returning a.email_id, a.account_id, a.student_id, a.item -- what the email needs
  ) -- end of the steps
  select m.email_id, -- the email's id
    ap.email, -- who it goes to
    private.first_name(acc.full_name), -- their first name
    'Please add ' || private.first_name(s.full_name) || '''s ' || private.missing_item_label(m.item), -- the subject
    'CLG needs ' || private.first_name(s.full_name) || '''s ' || private.missing_item_label(m.item) -- the message: what is needed,
      || ' to find the right tutor and session times. Please add it in the CLG app.' -- why, and what to do,
      || E'\n\nNeed help with this? Ask CLG in the help chat in the app.', -- and where to get help
    private.missing_item_link(m.item), -- the page the button opens
    'Add it now'::text, -- the button's words
    'You are receiving this because CLG is arranging tutoring for your family.'::text -- the small print
  from marked m -- each ask taken
  join public.account_private ap on ap.account_id = m.account_id -- their email
  join public.accounts acc on acc.id = m.account_id -- their name
  join public.students s on s.id = m.student_id; -- the child's name
end; -- finish
$$; -- end of the function
revoke all on function public.family_ask_emails_claim(integer) from public, anon, authenticated; -- the server only
grant execute on function public.family_ask_emails_claim(integer) to service_role; -- the email sender

-- Puts emails back if sending failed (only ones taken in the last hour).
create or replace function public.family_ask_emails_release(p_ids uuid[]) -- makes or updates the ask email hand-back
returns void -- nothing back
language sql security definer -- changes asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the change
  update public.matching_family_asks set email_id = null, emailed_at = null -- mark as not sent
  where email_id = any (p_ids) and emailed_at > now() - interval '1 hour' -- for these emails, taken in the last hour
$$; -- end of the function
revoke all on function public.family_ask_emails_release(uuid[]) from public, anon, authenticated; -- the server only
grant execute on function public.family_ask_emails_release(uuid[]) to service_role; -- the email sender

-- Wake the email sender for these emails too.
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's current text
begin -- start
  v_def := replace(pg_get_functiondef('private.emails_waiting()'::regprocedure), chr(13), ''); -- current text, without Windows line ends
  if position('family_ask_emails_waiting' in v_def) = 0 then -- not changed yet
    if position('private.emergency_emails_waiting()' in v_def) = 0 then -- the expected start is missing
      raise exception 'emails_waiting has changed since this was written; please ask for help'; -- stop rather than guess
    end if; -- checked
    execute replace(v_def, 'private.emergency_emails_waiting()', 'private.emergency_emails_waiting() or private.family_ask_emails_waiting()'); -- add this check and save
  end if; -- done
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 4. Offers waiting: for the tutor or for the family
-- ---------------------------------------------------------------------------

-- For each student subject with an offer waiting, who it waits for:
-- 'tutor', 'family' or 'both'.
create or replace function public.matching_offer_waits() -- makes or updates the "who an offer waits for" list
returns table (student_id uuid, subject text, waiting_on text, since timestamptz) -- each waiting offer
language plpgsql stable security definer -- reads bookings for front desk admins only
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  if not private.is_front_desk() then -- only owner, operations and support admins
    raise exception 'Only CLG admins can see this' using errcode = '42501'; -- plain message
  end if; -- checked who
  return query -- hand back:
  select distinct on (b.student_id, lower(b.subject)) -- the newest offer for each student and subject
    b.student_id, b.subject, -- who and what
    case when b.tutor_ok_at is null and b.needs_family_ok and b.family_ok_at is null then 'both' -- neither has answered
         when b.tutor_ok_at is null then 'tutor' -- the tutor has not answered
         else 'family' end, -- the family has not answered
    b.requested_at -- when it was offered
  from public.bookings b -- every booking
  where b.status = 'requested' and b.tutor_reply_by > now() and b.last_date >= current_date -- waiting and still in time
  order by b.student_id, lower(b.subject), b.requested_at desc; -- newest first within each
end; -- finish
$$; -- end of the function
revoke all on function public.matching_offer_waits() from public, anon; -- not for signed-out visitors
grant execute on function public.matching_offer_waits() to authenticated; -- signed-in (the function checks for admins)
revoke all on function public.matching_missing(uuid[]) from public, anon; -- not for signed-out visitors
grant execute on function public.matching_missing(uuid[]) to authenticated; -- signed-in (the function checks for admins)

-- ---------------------------------------------------------------------------
-- 5. Response times
-- ---------------------------------------------------------------------------

-- When a booking was declined, so answer times count declines too.
alter table public.bookings add column if not exists declined_at timestamptz; -- empty until declined

-- Stamp the time whenever a booking becomes declined.
create or replace function private.stamp_declined_at() -- makes or updates the decline time stamp
returns trigger -- runs before each change
language plpgsql -- simple steps
set search_path = '' -- only fully named things, for safety
as $$ -- the steps
begin -- start
  if new.status = 'declined' and old.status is distinct from 'declined' and new.declined_at is null then -- just declined
    new.declined_at := now(); -- note when
  end if; -- done
  return new; -- keep the change
end; -- finish
$$; -- end of the function
drop trigger if exists stamp_declined_at on public.bookings; -- replace the trigger if re-run
create trigger stamp_declined_at before update on public.bookings -- before each change to a booking
  for each row execute function private.stamp_declined_at(); -- stamp the decline time

-- Average time to answer offers over the last p_days days: one row per
-- tutor, and one row for families together (tutor_id empty).
create or replace function public.matching_response_times(p_days integer default 180) -- makes or updates the response times report
returns table (who text, tutor_id uuid, tutor_name text, answered integer, avg_hours numeric, not_answered integer) -- one row each
language plpgsql stable security definer -- reads bookings for front desk admins only
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  if not private.is_front_desk() then -- only owner, operations and support admins
    raise exception 'Only CLG admins can see this' using errcode = '42501'; -- plain message
  end if; -- checked who
  return query -- hand back:
  with b as ( -- the offers in the period:
    select x.*, -- each booking
      coalesce(x.tutor_ok_at, case when x.declined_by_role = 'tutor' then x.declined_at end) as tutor_answer, -- when the tutor answered
      coalesce(x.family_ok_at, case when x.declined_by_role = 'family' then x.declined_at end) as family_answer, -- when the family answered
      (x.status = 'requested' and x.tutor_reply_by <= now()) as lapsed -- whether time ran out
    from public.bookings x -- every booking
    where x.requested_at > now() - make_interval(days => least(greatest(coalesce(p_days, 180), 7), 730)) -- in the period (7 to 730 days)
  ) -- end of the offers
  select 'tutor'::text, b.tutor_id, a.full_name, -- each tutor
    count(b.tutor_answer)::integer, -- how many they answered
    round((avg(extract(epoch from b.tutor_answer - b.requested_at)) / 3600)::numeric, 1), -- average hours to answer
    count(*) filter (where b.lapsed and b.tutor_ok_at is null)::integer -- how many ran out unanswered
  from b join public.accounts a on a.id = b.tutor_id -- with their name
  group by b.tutor_id, a.full_name -- one row per tutor
  union all -- adds the families row
  select 'family'::text, null::uuid, 'Families'::text, -- families together
    count(b.family_answer)::integer, -- how many they answered
    round((avg(extract(epoch from b.family_answer - b.requested_at)) / 3600)::numeric, 1), -- average hours to answer
    count(*) filter (where b.lapsed and b.family_ok_at is null)::integer -- how many ran out unanswered
  from b where b.needs_family_ok -- only offers the family had to approve
  having count(*) > 0; -- only when there were some
end; -- finish
$$; -- end of the function
revoke all on function public.matching_response_times(integer) from public, anon; -- not for signed-out visitors
grant execute on function public.matching_response_times(integer) to authenticated; -- signed-in (the function checks for admins)
