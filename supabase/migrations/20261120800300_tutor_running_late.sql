-- Summary: a tutor can tell the family and CLG they are running late, and
-- CLG keeps a record of late starts to review (Carla, 18 Nov 2026).
--
-- Carla: "How does it work if a tutor is going to be late? There needs to
-- be some kind of ... consequence ... especially if it is a regular
-- occurrence. And they should not be paid for their time they were not
-- working."
--
-- How it works:
--   * From 3 hours before a session until 30 minutes after it starts, the
--     tutor can press "Running late" on their Sessions page, choose about
--     how late they will be, and say why.
--   * The family (parents and a learner with their own login) get an app
--     notice and an email straight away: "[Tutor] is running about 10
--     minutes late". The reason is only for CLG, so it is not sent to the
--     family. The owner and operations admins get an app notice too.
--   * If the tutor signs on more than 5 minutes after the start, the app
--     records the late start by itself, whether or not they gave notice.
--   * Every late start (or notice) is one line on the new Tutor lateness
--     page for the owner and operations admins, with how many late starts
--     each tutor has had in the last 90 days. An admin marks each line
--     reviewed with a private note (for example "Talked with the tutor").
--   * Tutors can see their own lines, so the record is open and fair.
--   * Pay is unchanged: session pay already starts from the later of the
--     sign-on time and the booked start (see 20261027200300_scheduling_sign_on.sql).
--
-- Scheduling module (sessions, session_notices and the new session_lateness
-- tables). Safe to run more than once.
-- Run after 20261119910100_help_chat.sql.

-- ---------------------------------------------------------------------------
-- 1. The lateness record: one line per session
-- ---------------------------------------------------------------------------
create table if not exists public.session_lateness ( -- one row for each late session
  id uuid primary key default gen_random_uuid(), -- the line's id
  session_id uuid not null unique references public.sessions (id) on delete cascade, -- the session (one line each)
  tutor_id uuid not null references public.accounts (id) on delete cascade, -- the tutor
  told_at timestamptz, -- when the tutor last said they were running late (empty if they did not)
  told_minutes integer check (told_minutes is null or told_minutes between 5 and 90), -- about how late they said they would be
  told_reason text check (told_reason is null or char_length(told_reason) <= 300), -- why, for CLG only
  told_count integer not null default 0 check (told_count between 0 and 3), -- how many times they sent a notice for this session
  told_before_start boolean, -- whether the first notice was sent before the session started
  signed_on_late_minutes integer check (signed_on_late_minutes is null or signed_on_late_minutes >= 0), -- how many minutes after the start they signed on (if more than 5)
  review_status text not null default 'open' check (review_status in ('open', 'reviewed')), -- waiting for an admin, or reviewed
  review_note text check (review_note is null or char_length(review_note) <= 1000), -- the admin's private note
  reviewed_by uuid references public.accounts (id) on delete set null, -- who reviewed it
  reviewed_at timestamptz, -- when it was reviewed
  created_at timestamptz not null default now() -- when the line was made
); -- (end of the table)
create index if not exists session_lateness_tutor on public.session_lateness (tutor_id, created_at desc); -- quick look-ups by tutor
create index if not exists session_lateness_open on public.session_lateness (created_at) where review_status = 'open'; -- quick list of lines to review

alter table public.session_lateness enable row level security; -- access rules apply
revoke all on public.session_lateness from anon; -- signed-out visitors see nothing
revoke insert, update, delete, truncate on public.session_lateness from authenticated; -- only the functions below write it
drop policy if exists "own lateness, admins all" on public.session_lateness; -- replaces the rule if run again
create policy "own lateness, admins all" on public.session_lateness -- who can read the lines
  for select to authenticated using (tutor_id = auth.uid() or private.is_admin()); -- the tutor sees their own; owner and operations admins see all

drop trigger if exists audit on public.session_lateness; -- replaces the record-keeper if run again
create trigger audit after insert or update or delete on public.session_lateness -- after any change,
  for each row execute function private.audit_change(); -- writes a line in the audit log

-- ---------------------------------------------------------------------------
-- 2. A new kind of session notice: "running_late"
-- ---------------------------------------------------------------------------
do $$ -- a small block of code
begin -- start
  if not exists ( -- the kind is not allowed yet:
    select 1 from pg_constraint -- (looks at the table's rules)
    where conname = 'session_notices_kind_check' -- the rule listing the kinds
      and pg_get_constraintdef(oid) like '%running_late%' -- already includes running_late
  ) then -- so add it:
    alter table public.session_notices drop constraint if exists session_notices_kind_check; -- removes the old list
    alter table public.session_notices add constraint session_notices_kind_check check (kind in ( -- adds the list back:
      'reminder_first', 'reminder_final', -- session reminders
      'booking_requested', 'booking_confirmed', 'booking_declined', -- booking changes
      'session_cancelled', 'renewal_due', 'availability_check', -- cancels, renewals and availability checks
      'offer_follow_up', 'tutor_away', 'request_update', 'staff_alert', 'check_renewal', -- the other kinds already in use
      'running_late' -- and the new one
    )); -- end of the list
  end if; -- end of the check
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 3. Emails to the family when the tutor is running late
-- ---------------------------------------------------------------------------
create table if not exists public.session_lateness_emails ( -- one row per email to send
  id uuid primary key default gen_random_uuid(), -- the row's id
  lateness_id uuid not null references public.session_lateness (id) on delete cascade, -- which late session
  account_id uuid not null references public.accounts (id) on delete cascade, -- who it goes to
  minutes integer not null check (minutes between 5 and 90), -- about how late, as told at the time
  created_at timestamptz not null default now(), -- when it was queued
  email_id uuid, -- the id given to the email when it is sent
  emailed_at timestamptz -- when it was sent (empty while waiting)
); -- (end of the table)
create index if not exists session_lateness_emails_waiting on public.session_lateness_emails (created_at) where emailed_at is null; -- quick list of emails waiting
alter table public.session_lateness_emails enable row level security; -- access rules apply (no rule, so only the database's own functions can read it)
revoke all on public.session_lateness_emails from anon, authenticated; -- nobody signed in reads or writes it directly

-- Whether any running-late email is waiting (wakes the email sender).
create or replace function private.lateness_emails_waiting() -- no inputs
returns boolean -- yes or no
language sql stable security definer -- reads the queue
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- is there one:
    select 1 from public.session_lateness_emails -- an email row
    where emailed_at is null and created_at > now() - interval '2 hours' -- not yet sent, and still useful (less than 2 hours old)
  ) -- end of the check
$$; -- end of the function
revoke all on function private.lateness_emails_waiting() from public; -- for the database's own use only

-- Hands waiting emails to the sender and marks them sent. Emails older than
-- 2 hours are dropped, because the session will be over by then.
create or replace function public.lateness_emails_claim(p_limit integer default 50) -- takes how many at most
returns table (id uuid, email text, first_name text, subject text, body text, link text, button text, footer text) -- one email per row
language plpgsql security definer -- reads and marks the queue
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- start
  update public.session_lateness_emails e set emailed_at = now() -- first, marks old ones as dealt with (no email):
  where e.emailed_at is null and e.created_at <= now() - interval '2 hours'; -- waiting, but more than 2 hours old
  return query -- then hands back:
  with due as ( -- the emails to send:
    select e.id from public.session_lateness_emails e -- each email row
    where e.emailed_at is null -- not yet sent
    order by e.created_at -- oldest first
    limit least(greatest(p_limit, 1), 100) -- at most the number asked for (1 to 100)
    for update skip locked -- so two senders never take the same one
  ), marked as ( -- marks them sent:
    update public.session_lateness_emails e -- each row taken
    set email_id = gen_random_uuid(), emailed_at = now() -- gets a new email id and the time
    from due where e.id = due.id -- (only the ones taken)
    returning e.email_id, e.account_id, e.lateness_id, e.minutes -- what the email needs
  ) -- end of the steps
  select m.email_id, -- the email's id
    ap.email, -- who it goes to
    private.first_name(a.full_name), -- their first name
    'Your tutor is running late'::text, -- the subject
    private.first_name(tu.full_name) || ' is running about ' || m.minutes || ' minutes late for ' -- the message: who and how late,
      || private.first_name(st.full_name) || '''s ' || x.subject || ' session at ' || private.when_text(x.starts_at) || '.' -- for which session,
      || E'\n\nThe tutor has let CLG know. If the session cannot run for its full booked time, CLG will be in touch about the time missed.', -- and what happens next
    '/dashboard'::text, -- the page the button opens
    'Open the CLG app'::text, -- the button's words
    'You get this email because your tutor told CLG they are running late for a session.'::text -- the small print
  from marked m -- from the rows taken
  join public.session_lateness l on l.id = m.lateness_id -- with the late session
  join public.sessions x on x.id = l.session_id -- and the session
  join public.students st on st.id = x.student_id -- and the learner
  join public.accounts tu on tu.id = x.tutor_id -- and the tutor
  join public.accounts a on a.id = m.account_id -- and the person's name
  join public.account_private ap on ap.account_id = m.account_id; -- and email
end; -- finish
$$; -- end of the function
revoke all on function public.lateness_emails_claim(integer) from public, anon, authenticated; -- the server only
grant execute on function public.lateness_emails_claim(integer) to service_role; -- the email sender

-- Puts emails back if sending failed (only ones taken in the last hour).
create or replace function public.lateness_emails_release(p_ids uuid[]) -- takes the email ids
returns void -- gives nothing back
language sql security definer -- changes the queue
set search_path = '' -- only fully named tables, for safety
as $$ -- the change
  update public.session_lateness_emails set email_id = null, emailed_at = null -- clears the email marks
  where email_id = any (p_ids) and emailed_at > now() - interval '1 hour' -- for those emails, taken in the last hour
$$; -- end of the function
revoke all on function public.lateness_emails_release(uuid[]) from public, anon, authenticated; -- the server only
grant execute on function public.lateness_emails_release(uuid[]) to service_role; -- the email sender

-- Wakes the email sender for running-late emails too. The shared check is
-- extended rather than copied, so changes other modules made to it stay.
do $$ -- a small block of code
declare -- working values:
  v_def text; -- the shared check's code
begin -- start
  if to_regprocedure('private.emails_waiting()') is null then -- the shared check is not there
    return; -- nothing to do
  end if; -- end of the check
  v_def := replace(pg_catalog.pg_get_functiondef('private.emails_waiting()'::regprocedure), chr(13), ''); -- reads its current code (without Windows line endings)
  if strpos(v_def, 'private.lateness_emails_waiting()') = 0 then -- not added yet
    v_def := regexp_replace(v_def, '\s*\$function\$\s*$', E'\n  or private.lateness_emails_waiting()\n$function$\n'); -- adds "or a running-late email is waiting" at the end
    execute v_def; -- saves the new code
  end if; -- end of the check
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 4. The tutor says they are running late
-- ---------------------------------------------------------------------------
create or replace function public.tell_running_late(p_session uuid, p_minutes integer, p_reason text) -- the session, about how late, and why
returns void -- gives nothing back
language plpgsql security definer -- writes the record and notices after checking who is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_s public.sessions; -- the session
begin -- start
  select * into v_s from public.sessions where id = p_session; -- reads the session
  if not found or v_s.tutor_id is distinct from auth.uid() then -- missing, or not this tutor's:
    raise exception 'You can only send a running late notice for your own sessions' using errcode = '42501'; -- plain refusal
  end if; -- end of the check
  if v_s.status <> 'scheduled' then -- cancelled or already recorded:
    raise exception 'This session is no longer on' using errcode = '22023'; -- plain refusal
  end if; -- end of the check
  if now() < v_s.starts_at - interval '3 hours' then -- too early:
    raise exception 'A running late notice can be sent from 3 hours before the session. Earlier than that, please contact CLG or change the session time' using errcode = '22023'; -- plain refusal
  end if; -- end of the check
  if now() > v_s.starts_at + interval '30 minutes' then -- too late:
    raise exception 'The session started more than 30 minutes ago. Please contact CLG' using errcode = '22023'; -- plain refusal
  end if; -- end of the check
  if p_minutes is null or p_minutes < 5 or p_minutes > 90 then -- not a sensible number:
    raise exception 'Choose about how late you will be (5 to 90 minutes)' using errcode = '22023'; -- asks for it
  end if; -- end of the check
  if char_length(trim(coalesce(p_reason, ''))) < 3 then -- no reason:
    raise exception 'Please say briefly why you are running late (only CLG sees this)' using errcode = '22023'; -- asks for one
  end if; -- end of the check

  insert into public.session_lateness (session_id, tutor_id, told_at, told_minutes, told_reason, told_count, told_before_start) -- adds the line:
  values (v_s.id, v_s.tutor_id, now(), p_minutes, left(trim(p_reason), 300), 1, now() < v_s.starts_at) -- the session, tutor, time, minutes, reason, first notice, and whether before the start
  on conflict (session_id) do update set -- or, if a line is already there, updates it:
    told_at = now(), -- the latest notice time
    told_minutes = excluded.told_minutes, -- the latest minutes
    told_reason = excluded.told_reason, -- the latest reason
    told_count = public.session_lateness.told_count + 1, -- one more notice
    told_before_start = coalesce(public.session_lateness.told_before_start, excluded.told_before_start), -- keeps whether the first notice was before the start
    review_status = 'open'; -- and needs a look again
exception when check_violation then -- more than three notices for one session:
  raise exception 'You have already sent three running late notices for this session. Please contact CLG' using errcode = '22023'; -- plain refusal
end; -- finish
$$; -- end of the function
revoke all on function public.tell_running_late(uuid, integer, text) from public, anon; -- not for signed-out visitors
grant execute on function public.tell_running_late(uuid, integer, text) to authenticated; -- signed-in people (checked inside)

-- Sends the notices and emails once a notice is saved. Kept in a trigger so
-- it runs only when the line was really saved.
create or replace function private.lateness_tell_family() -- a trigger function (no inputs)
returns trigger -- hands back nothing useful (it runs after the save)
language plpgsql security definer -- writes notices and emails whoever saved the line
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_s public.sessions; -- the session
  v_student text; -- the learner's first name
  v_tutor text; -- the tutor's first name
  v_text text; -- the notice's words
  r record; -- one family member at a time
begin -- start
  if new.told_at is null or (tg_op = 'UPDATE' and new.told_count = old.told_count) then -- not a new notice from the tutor:
    return null; -- nothing to send
  end if; -- end of the check
  select * into v_s from public.sessions where id = new.session_id; -- reads the session
  select private.first_name(full_name) into v_student from public.students where id = v_s.student_id; -- the learner's first name
  select private.first_name(full_name) into v_tutor from public.accounts where id = v_s.tutor_id; -- the tutor's first name
  v_text := v_tutor || ' is running about ' || new.told_minutes || ' minutes late for ' || v_student || '''s ' || v_s.subject || ' session at ' || private.when_text(v_s.starts_at) || '.'; -- the words, for example "Sam is running about 10 minutes late for Ava's Maths session at Tue 18 Nov, 4:00pm."
  for r in select p.account_id from private.session_people(v_s.student_id, v_s.tutor_id) p where not p.is_tutor loop -- each parent, and the learner if they have a login:
    perform private.add_notice(r.account_id, v_s.id, null, 'running_late', 'Your tutor is running late', v_text, now()); -- an app notice now
    insert into public.session_lateness_emails (lateness_id, account_id, minutes) values (new.id, r.account_id, new.told_minutes); -- and an email
  end loop; -- end of the family
  perform private.notify_admins('Tutor running late', v_text || ' Reason: ' || coalesce(new.told_reason, 'not given') || '.'); -- tells the owner and operations admins, with the reason
  return null; -- (nothing to hand back after a save)
end; -- finish
$$; -- end of the function
revoke all on function private.lateness_tell_family() from public; -- only run by the trigger below

drop trigger if exists tell_family on public.session_lateness; -- replaces the trigger if run again
create trigger tell_family after insert or update of told_count on public.session_lateness -- after a new notice is saved:
  for each row execute function private.lateness_tell_family(); -- send the notices and emails

-- ---------------------------------------------------------------------------
-- 5. A late sign-on is recorded by itself
-- ---------------------------------------------------------------------------
create or replace function private.lateness_on_sign_on() -- a trigger function (no inputs)
returns trigger -- hands back nothing useful (it runs after the save)
language plpgsql security definer -- writes the lateness record whoever signs on
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_late integer; -- minutes after the start
begin -- start
  if new.signed_on_at is null or old.signed_on_at is not null then -- not a first sign-on:
    return null; -- nothing to do
  end if; -- end of the check
  v_late := floor(extract(epoch from new.signed_on_at - new.starts_at) / 60)::integer; -- whole minutes after the start
  if v_late > 5 then -- more than 5 minutes late:
    insert into public.session_lateness (session_id, tutor_id, signed_on_late_minutes) -- adds a line:
    values (new.id, new.tutor_id, v_late) -- the session, tutor and minutes late
    on conflict (session_id) do update set signed_on_late_minutes = excluded.signed_on_late_minutes, review_status = 'open'; -- or updates the line made by a notice (and it needs a look)
  else -- on time (or within 5 minutes):
    update public.session_lateness -- a notice line, if any:
    set review_status = 'reviewed', review_note = coalesce(review_note, 'Signed on within 5 minutes of the start.'), reviewed_at = now() -- needs no review
    where session_id = new.id and review_status = 'open'; -- for this session, if still open
  end if; -- end of the choice
  return null; -- (nothing to hand back after a save)
end; -- finish
$$; -- end of the function
revoke all on function private.lateness_on_sign_on() from public; -- only run by the trigger below

drop trigger if exists lateness_on_sign_on on public.sessions; -- replaces the trigger if run again
create trigger lateness_on_sign_on after update of signed_on_at on public.sessions -- after a tutor signs on:
  for each row execute function private.lateness_on_sign_on(); -- record a late start

-- ---------------------------------------------------------------------------
-- 6. Reading and reviewing the record
-- ---------------------------------------------------------------------------
-- Lines from the last p_days days (and every open one), with names. Admins
-- (owner and operations) see everyone's; a tutor sees only their own.
create or replace function public.list_session_lateness(p_days integer default 180) -- how far back to look
returns table ( -- one row per line:
  id uuid, session_id uuid, tutor_id uuid, tutor_name text, student_first_name text, subject text, -- which session and who
  starts_at timestamptz, told_at timestamptz, told_minutes integer, told_reason text, told_count integer, told_before_start boolean, -- the notice
  signed_on_late_minutes integer, review_status text, review_note text, reviewed_at timestamptz, created_at timestamptz, -- the sign-on and the review
  counts_as_late boolean -- whether it counts as a late start (not a notice where the tutor then signed on in time)
) -- (end of the columns it gives back)
language sql stable security definer -- reads names whoever is asking (the rows are limited below)
set search_path = '' -- only fully named tables, for safety
as $$ -- the list:
  select l.id, l.session_id, l.tutor_id, tu.full_name, private.first_name(st.full_name), x.subject, -- which session and who
         x.starts_at, l.told_at, l.told_minutes, l.told_reason, l.told_count, l.told_before_start, -- the notice
         l.signed_on_late_minutes, l.review_status, -- the sign-on and review status
         case when private.is_admin() then l.review_note end, -- the private note (admins only)
         l.reviewed_at, l.created_at, -- when reviewed and made
         (l.signed_on_late_minutes is not null or not (l.review_status = 'reviewed' and l.reviewed_by is null)) -- a late sign-on, or a notice not cleared by an on-time sign-on
  from public.session_lateness l -- the lines
  join public.sessions x on x.id = l.session_id -- with the session
  join public.students st on st.id = x.student_id -- and the learner
  join public.accounts tu on tu.id = l.tutor_id -- and the tutor
  where (private.is_admin() or l.tutor_id = auth.uid()) -- only admins, or the tutor's own
    and (l.review_status = 'open' or x.starts_at >= now() - make_interval(days => least(greatest(coalesce(p_days, 180), 1), 730))) -- open ones, and recent ones
  order by x.starts_at desc -- newest first
$$; -- end of the function
revoke all on function public.list_session_lateness(integer) from public, anon; -- not for signed-out visitors
grant execute on function public.list_session_lateness(integer) to authenticated; -- signed-in people (limited inside)

-- An admin marks a line reviewed, with a private note.
create or replace function public.review_session_lateness(p_id uuid, p_note text) -- the line and the note
returns void -- gives nothing back
language plpgsql security definer -- writes the review after checking who is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  if not private.is_admin() then -- not the owner or an operations admin:
    raise exception 'Only the owner or an operations admin can review lateness' using errcode = '42501'; -- plain refusal
  end if; -- end of the check
  if char_length(trim(coalesce(p_note, ''))) < 3 then -- no note:
    raise exception 'Please write a short note, for example what was discussed with the tutor' using errcode = '22023'; -- asks for one
  end if; -- end of the check
  update public.session_lateness -- marks the line:
  set review_status = 'reviewed', review_note = left(trim(p_note), 1000), reviewed_by = auth.uid(), reviewed_at = now() -- reviewed, with the note, who and when
  where id = p_id; -- this line
  if not found then -- no such line:
    raise exception 'That lateness record was not found' using errcode = '22023'; -- says so
  end if; -- end of the check
end; -- finish
$$; -- end of the function
revoke all on function public.review_session_lateness(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.review_session_lateness(uuid, text) to authenticated; -- signed-in people (checked inside)
