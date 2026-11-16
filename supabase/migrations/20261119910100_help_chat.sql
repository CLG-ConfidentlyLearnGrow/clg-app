-- Summary: the help chat (Carla, 16 Nov 2026). Families, students with their
-- own login, tutors and staff can ask CLG a question in the app and talk it
-- through in one place, instead of by phone, text or email. CLG's admins can
-- also start a chat with a family or a person, for example to ask for a
-- missing detail. The matching page's "Ask the family" notice links families
-- to /help/new?student=...&item=..., which opens a chat about that item.
--
-- Privacy (children's data):
--   * a chat is read only by the people in it (its "members") and by the
--     admins who answer that kind of question (the "help desk");
--   * help desk: owner, operations and support admins answer general chats;
--     billing chats go to owner, operations and finance admins; staff pay
--     chats go to owner, operations and finance admins (support admins do
--     not handle money);
--   * a chat about a student can only be started by that student's parent,
--     the student themselves, or one of their tutors, and a member only keeps
--     reading it while they are still connected to that student. Brothers
--     and sisters never see each other's chats (sibling privacy);
--   * admins choose exactly which parents are in a chat they start, so a
--     separated parent is never added without the admin deciding to;
--   * every message is checked for concerning words (/safety/flags);
--   * emails say only "you have a new message", never what it says, and wait
--     until quiet hours end (9pm to 5am in the person's own time);
--   * the activity log holds ids only;
--   * chats are deleted 2 years after their last message, and straight away
--     when the student they are about is erased.
--
-- Module: help_chat. Tables: help_chats, help_chat_members, help_messages,
-- help_chat_reads, help_chat_emails. It reads (never writes) other modules'
-- tables. Needs 20261114100100_safety_watch_words.sql (the concerning-words
-- check) and 20261113200100_quiet_hours.sql (quiet hours). Safe to run more
-- than once.

-- ---------------------------------------------------------------------------
-- 1. The tables
-- ---------------------------------------------------------------------------

-- One row per chat (a question and its answers).
create table if not exists public.help_chats ( -- the chats table
  id uuid primary key default gen_random_uuid(), -- the chat's id
  started_by uuid references public.accounts (id) on delete set null, -- who started it (empty if their account is later deleted)
  started_by_name text not null check (char_length(started_by_name) between 1 and 200), -- their name, copied so the record stays complete
  started_by_clg boolean not null default false, -- true when a CLG admin started it (for example "Ask the family")
  topic text not null check (topic in ('missing_info', 'sessions', 'matching', 'billing', 'pay', 'app', 'other')), -- what kind of question it is (decides which admins answer it)
  subject text not null check (char_length(subject) between 3 and 120), -- a short title for the chat
  student_id uuid references public.students (id) on delete cascade, -- the student it is about, if any (deleted with the student)
  missing_item text check (missing_item in ('year_level', 'school', 'session_places', 'booking_length')), -- the missing detail it is about, if any
  status text not null default 'waiting_on_clg' check (status in ('waiting_on_clg', 'waiting_on_you', 'closed')), -- whose turn it is, or closed
  assigned_to uuid references public.accounts (id) on delete set null, -- the admin looking after it, if any
  created_at timestamptz not null default now(), -- when it was started
  last_message_at timestamptz not null default now(), -- when the latest message was written
  closed_at timestamptz -- when it was closed, if it is closed
); -- end of the table
create index if not exists help_chats_status on public.help_chats (status, last_message_at); -- finds chats waiting for CLG quickly
create index if not exists help_chats_student on public.help_chats (student_id) where student_id is not null; -- finds a student's chats quickly
alter table public.help_chats enable row level security; -- turns on access rules
revoke all on public.help_chats from anon, authenticated; -- no direct changes: everything goes through the functions below
grant select on public.help_chats to authenticated; -- signed-in people may read, but only the rows the rules below allow

-- The people in each chat (apart from the help desk admins, who see every chat they answer).
create table if not exists public.help_chat_members ( -- the members table
  chat_id uuid not null references public.help_chats (id) on delete cascade, -- the chat (removed with it)
  account_id uuid not null references public.accounts (id) on delete cascade, -- the person (removed if their account is deleted)
  added_at timestamptz not null default now(), -- when they were added
  primary key (chat_id, account_id) -- each person is in a chat once
); -- end of the table
create index if not exists help_chat_members_account on public.help_chat_members (account_id); -- finds a person's chats quickly
alter table public.help_chat_members enable row level security; -- turns on access rules
revoke all on public.help_chat_members from anon, authenticated; -- no direct changes
grant select on public.help_chat_members to authenticated; -- read, within the rules below

-- One row per message.
create table if not exists public.help_messages ( -- the messages table
  id uuid primary key default gen_random_uuid(), -- the message's id
  chat_id uuid not null references public.help_chats (id) on delete cascade, -- the chat it belongs to (removed with it)
  author_id uuid references public.accounts (id) on delete set null, -- who wrote it (empty if their account is later deleted)
  author_name text not null check (char_length(author_name) between 1 and 200), -- their name, copied so the record stays complete
  from_clg boolean not null default false, -- true when a CLG admin wrote it on CLG's behalf
  student_id uuid references public.students (id) on delete cascade, -- the chat's student, copied so the concerning-words check knows who it is about
  body text not null check (char_length(body) between 1 and 4000), -- what they wrote
  created_at timestamptz not null default now() -- when it was written
); -- end of the table
create index if not exists help_messages_chat on public.help_messages (chat_id, created_at); -- lists a chat's messages in order quickly
create index if not exists help_messages_author_time on public.help_messages (author_id, created_at); -- counts a person's messages for the daily limit quickly
alter table public.help_messages enable row level security; -- turns on access rules
revoke all on public.help_messages from anon, authenticated; -- no direct changes
grant select on public.help_messages to authenticated; -- read, within the rules below
alter table public.help_messages alter column created_at set default clock_timestamp(); -- the exact moment of writing, so messages and "read" marks made close together stay in the right order

-- When each person last read each chat (for the "new" marks and numbers).
create table if not exists public.help_chat_reads ( -- the reads table
  chat_id uuid not null references public.help_chats (id) on delete cascade, -- the chat (removed with it)
  account_id uuid not null references public.accounts (id) on delete cascade, -- the reader (removed with their account)
  last_read_at timestamptz not null default now(), -- when they last opened it
  primary key (chat_id, account_id) -- one row per person per chat
); -- end of the table
alter table public.help_chat_reads enable row level security; -- turns on access rules
revoke all on public.help_chat_reads from anon, authenticated; -- no direct changes
grant select on public.help_chat_reads to authenticated; -- read, within the rule below (their own rows only)

-- Emails waiting to tell someone they have a new message (no message words).
create table if not exists public.help_chat_emails ( -- the email queue
  id uuid primary key default gen_random_uuid(), -- the row's id
  chat_id uuid not null references public.help_chats (id) on delete cascade, -- the chat (removed with it)
  account_id uuid not null references public.accounts (id) on delete cascade, -- who to email
  send_after timestamptz not null, -- the earliest it may go (after quiet hours, and a few minutes' wait)
  email_id uuid, -- the id of the email being sent
  emailed_at timestamptz, -- when it was handed to the sender (or skipped because they had already read it)
  created_at timestamptz not null default now() -- when it was queued
); -- end of the table
create index if not exists help_chat_emails_unsent on public.help_chat_emails (send_after) where emailed_at is null; -- finds emails still to send quickly
create unique index if not exists help_chat_emails_one_waiting on public.help_chat_emails (chat_id, account_id) where emailed_at is null; -- at most one waiting email per person per chat
alter table public.help_chat_emails enable row level security; -- turns on access rules (with no rules, nobody signed in can read it)
revoke all on public.help_chat_emails from anon, authenticated; -- only the database and the email sender use it
alter table public.help_chat_emails alter column created_at set default clock_timestamp(); -- the exact moment it was queued (compared with "read" marks)

-- ---------------------------------------------------------------------------
-- 2. Who can read what
-- ---------------------------------------------------------------------------

-- True when the signed-in admin answers this kind of chat (two-step sign-in
-- is already part of every admin level check).
create or replace function private.is_help_desk(p_topic text) -- takes the chat's topic
returns boolean -- gives back yes or no
language sql stable security definer -- uses the admin level checks
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select case -- depends on the topic:
    when p_topic in ('billing', 'pay') then private.is_finance_admin() -- money questions: owner, operations and finance admins
    else private.is_front_desk() -- everything else: owner, operations and support admins
  end -- end of the choice
$$; -- end of the function
revoke all on function private.is_help_desk(text) from public; -- not for everyone by default
grant execute on function private.is_help_desk(text) to authenticated; -- the access rules run as the signed-in person

-- True when the signed-in person is in this chat and, for a chat about a
-- student, is still that student's parent, the student, or one of their
-- tutors (so someone who is no longer connected stops seeing it).
create or replace function private.is_help_member(p_chat uuid) -- takes the chat
returns boolean -- gives back yes or no
language sql stable security definer -- reads the members table whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- is there a row:
    select 1 from public.help_chat_members m -- in the members,
    join public.help_chats c on c.id = m.chat_id -- with its chat,
    where m.chat_id = p_chat and m.account_id = auth.uid() -- for this chat and this person,
      and (c.student_id is null -- and the chat is not about a student,
        or private.is_parent_of(c.student_id) -- or they are the student's parent,
        or private.is_student_self(c.student_id) -- or the student,
        or private.is_tutor_of(c.student_id)) -- or one of the student's tutors
  ) -- end of the check
$$; -- end of the function
revoke all on function private.is_help_member(uuid) from public; -- not for everyone by default
grant execute on function private.is_help_member(uuid) to authenticated; -- the access rules run as the signed-in person

-- True when the signed-in person answers this chat for CLG (a help desk
-- admin for its topic who is not one of its members).
create or replace function private.is_help_desk_for(p_chat uuid) -- takes the chat
returns boolean -- gives back yes or no
language sql stable security definer -- reads the chat whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select coalesce((select private.is_help_desk(c.topic) from public.help_chats c where c.id = p_chat), false) -- a help desk admin for its topic (no if there is no such chat)
$$; -- end of the function
revoke all on function private.is_help_desk_for(uuid) from public; -- not for everyone by default
grant execute on function private.is_help_desk_for(uuid) to authenticated; -- the access rules run as the signed-in person

-- True when the signed-in person can read this chat at all.
create or replace function private.can_read_help_chat(p_chat uuid) -- takes the chat
returns boolean -- gives back yes or no
language sql stable security definer -- uses the two checks above
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select private.is_help_member(p_chat) or private.is_help_desk_for(p_chat) -- a member, or a help desk admin for it
$$; -- end of the function
revoke all on function private.can_read_help_chat(uuid) from public; -- not for everyone by default
grant execute on function private.can_read_help_chat(uuid) to authenticated; -- the access rules run as the signed-in person

-- Chats: members and the help desk read them.
drop policy if exists "members and help desk read chats" on public.help_chats; -- removes the old rule if the file is run again
create policy "members and help desk read chats" on public.help_chats -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (private.is_help_desk(topic) or private.is_help_member(id)); -- help desk for its topic, or a member

-- Messages: the same people as the chat.
drop policy if exists "members and help desk read messages" on public.help_messages; -- removes the old rule if the file is run again
create policy "members and help desk read messages" on public.help_messages -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (private.can_read_help_chat(chat_id)); -- whoever can read the chat

-- Members: a person sees their own membership rows; the help desk sees who is in each chat.
drop policy if exists "own rows and help desk read members" on public.help_chat_members; -- removes the old rule if the file is run again
create policy "own rows and help desk read members" on public.help_chat_members -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (account_id = auth.uid() or private.is_help_desk_for(chat_id)); -- their own row, or a help desk admin for the chat

-- Reads: only a person's own.
drop policy if exists "own reads" on public.help_chat_reads; -- removes the old rule if the file is run again
create policy "own reads" on public.help_chat_reads -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (account_id = auth.uid()); -- only their own rows

-- ---------------------------------------------------------------------------
-- 3. Helpers used by the functions below
-- ---------------------------------------------------------------------------

-- True when the chat has a message the signed-in person has not read yet
-- (written by someone else after they last opened it).
create or replace function private.help_chat_unread(p_chat uuid) -- takes the chat
returns boolean -- gives back yes or no
language sql stable security definer -- reads the messages and reads tables
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- is there a message:
    select 1 from public.help_messages m -- in the messages,
    where m.chat_id = p_chat -- of this chat,
      and m.author_id is distinct from auth.uid() -- written by someone else,
      and m.created_at > coalesce((select r.last_read_at from public.help_chat_reads r where r.chat_id = p_chat and r.account_id = auth.uid()), '-infinity'::timestamptz) -- after they last read it
  ) -- end of the check
$$; -- end of the function
revoke all on function private.help_chat_unread(uuid) from public; -- not for everyone by default
grant execute on function private.help_chat_unread(uuid) to authenticated; -- used by the list and the to-do numbers

-- Notes that the signed-in person has read a chat up to now.
create or replace function private.help_note_read(p_chat uuid) -- takes the chat
returns void -- gives nothing back
language sql security definer -- writes a table people cannot write directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the change
  insert into public.help_chat_reads (chat_id, account_id, last_read_at) -- adds a row:
  values (p_chat, auth.uid(), clock_timestamp()) -- this chat, this person, this exact moment
  on conflict (chat_id, account_id) do update set last_read_at = excluded.last_read_at -- or moves their existing row to now
$$; -- end of the function
revoke all on function private.help_note_read(uuid) from public; -- for the database's own use only

-- Queues "you have a new message" emails after a message is written. CLG's
-- messages go to every member except the writer. A member's message goes to
-- the admin looking after the chat, or, if nobody is yet, to every owner and
-- operations admin. One waiting email per person per chat is enough, so a
-- busy chat does not send a pile of emails. Each email waits 5 minutes (in
-- case they read it in the app first) and until quiet hours end.
create or replace function private.help_queue_emails(p_chat uuid, p_author uuid, p_from_clg boolean) -- takes the chat, the writer and whether CLG wrote it
returns void -- gives nothing back
language sql security definer -- writes the email queue
set search_path = '' -- only fully named tables, for safety
as $$ -- the change
  insert into public.help_chat_emails (chat_id, account_id, send_after) -- adds an email row:
  select p_chat, who.account_id, private.outside_quiet_hours_for(who.account_id, now() + interval '5 minutes') -- for each person below, 5 minutes from now or after their quiet hours
  from ( -- the people to tell:
    select m.account_id from public.help_chat_members m -- the members,
    where p_from_clg and m.chat_id = p_chat -- when CLG wrote it, for this chat
    union -- and
    select c.assigned_to from public.help_chats c -- the admin looking after it,
    where not p_from_clg and c.id = p_chat and c.assigned_to is not null -- when a member wrote it and someone is looking after it
    union -- and
    select ap.account_id from public.admin_profiles ap -- the owner and operations admins,
    join public.account_roles r on r.account_id = ap.account_id and r.role = 'admin' -- who still have the admin role,
    join public.help_chats c on c.id = p_chat -- (with the chat)
    where not p_from_clg and c.assigned_to is null and ap.level::text in ('owner', 'operations') -- when a member wrote it and nobody is looking after it yet
  ) who -- end of the people
  where who.account_id is not null and who.account_id is distinct from p_author -- never the writer
  on conflict (chat_id, account_id) where emailed_at is null -- when they already have one waiting for this chat:
  do update set created_at = clock_timestamp() -- keeps that one email, but marks it as about this newer message (so reading an older message does not cancel it)
$$; -- end of the function
revoke all on function private.help_queue_emails(uuid, uuid, boolean) from public; -- for the database's own use only

-- The help chat's daily limits, so a mistake or misuse cannot flood CLG.
create or replace function private.help_check_limits(p_new_chat boolean) -- takes whether this is a new chat
returns void -- gives nothing back (refuses with a plain message when over a limit)
language plpgsql stable security definer -- counts rows people cannot all read
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if p_new_chat and (select count(*) from public.help_chats where started_by = auth.uid() and created_at > now() - interval '1 day') >= 20 then -- 20 new chats in a day already
    raise exception 'You have started a lot of chats today. Please add to one of your open chats, or try again tomorrow.' using errcode = '54000'; -- plain message, "too many" code
  end if; -- end of the check
  if (select count(*) from public.help_messages where author_id = auth.uid() and created_at > now() - interval '1 day') >= 300 then -- 300 messages in a day already
    raise exception 'You have sent a lot of messages today. Please try again tomorrow, or contact CLG directly.' using errcode = '54000'; -- plain message, "too many" code
  end if; -- end of the check
end; -- ends the code
$$; -- end of the function
revoke all on function private.help_check_limits(boolean) from public; -- for the database's own use only

-- Checks the topic, subject, message and missing item, with plain messages.
create or replace function private.help_check_fields(p_topic text, p_subject text, p_body text, p_item text) -- takes what was typed and chosen
returns void -- gives nothing back (refuses with a plain message when something is wrong)
language plpgsql immutable -- only looks at what it is given
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if coalesce(p_topic, '') not in ('missing_info', 'sessions', 'matching', 'billing', 'pay', 'app', 'other') then -- no topic chosen
    raise exception 'Please choose what your question is about.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_subject, ''))) < 3 then -- no subject
    raise exception 'Please give your chat a short title (at least 3 letters).' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_body, ''))) < 1 then -- nothing written
    raise exception 'Please write your message.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_item is not null and p_item not in ('year_level', 'school', 'session_places', 'booking_length') then -- an unknown missing item
    raise exception 'That missing detail is not one CLG asks about.' using errcode = '22023'; -- plain message
  end if; -- end of the check
end; -- ends the code
$$; -- end of the function
revoke all on function private.help_check_fields(text, text, text, text) from public; -- for the database's own use only

-- ---------------------------------------------------------------------------
-- 4. Starting a chat (anyone signed in)
-- ---------------------------------------------------------------------------

-- The students the signed-in person may ask about: their own children, themselves
-- (a student with their own login) and, for a tutor, their matched students.
create or replace function public.help_my_students() -- no inputs
returns table (id uuid, full_name text, connection text) -- each student, their name, and how the person is connected
language sql stable security definer -- reads past the access rules, but only connected students
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select s.id, s.full_name, -- the student and their name,
    case -- and how the person is connected:
      when private.is_student_self(s.id) then 'self' -- it is them,
      when private.is_parent_of(s.id) then 'child' -- their child,
      else 'student' -- or a student they tutor
    end -- end of the choice
  from public.students s -- from the students,
  where private.is_student_self(s.id) or private.is_parent_of(s.id) or private.is_tutor_of(s.id) -- only the ones they are connected to
  order by s.full_name -- in name order
$$; -- end of the function
revoke all on function public.help_my_students() from public, anon; -- not for signed-out visitors
grant execute on function public.help_my_students() to authenticated; -- signed-in people

-- Starts a chat with CLG and saves the first message. Gives back the chat's id.
create or replace function public.help_start_chat( -- the inputs:
  p_topic text, -- what it is about
  p_subject text, -- a short title
  p_body text, -- the first message
  p_student uuid default null, -- the student it is about, if any
  p_item text default null -- the missing detail it is about, if any
) -- end of the inputs
returns uuid -- gives back the new chat's id
language plpgsql security definer -- saves to tables people cannot write directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_me uuid := auth.uid(); -- who is starting it
  v_name text; -- their name
  v_chat uuid; -- the new chat's id
begin -- starts the code
  if v_me is null then -- nobody signed in
    raise exception 'Please sign in to use the help chat.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  perform private.help_check_fields(p_topic, p_subject, p_body, p_item); -- checks what was typed
  if p_item is not null and p_student is null then -- a missing detail with no student
    raise exception 'Please choose which child this missing detail is for.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_student is not null and not (private.is_parent_of(p_student) or private.is_student_self(p_student) or private.is_tutor_of(p_student)) then -- a student they are not connected to
    raise exception 'You can only ask about your own children, yourself, or students you tutor.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  perform private.help_check_limits(true); -- checks the daily limits
  select coalesce(nullif(a.full_name, ''), 'Unknown') into v_name from public.accounts a where a.id = v_me; -- their name
  insert into public.help_chats (started_by, started_by_name, topic, subject, student_id, missing_item, status) -- saves the chat:
  values (v_me, coalesce(v_name, 'Unknown'), p_topic, left(btrim(p_subject), 120), p_student, p_item, 'waiting_on_clg') -- with its details, waiting for CLG to reply
  returning id into v_chat; -- keeps the new id
  insert into public.help_chat_members (chat_id, account_id) values (v_chat, v_me); -- they are in their own chat
  insert into public.help_messages (chat_id, author_id, author_name, from_clg, student_id, body) -- saves the first message:
  values (v_chat, v_me, coalesce(v_name, 'Unknown'), false, p_student, left(btrim(p_body), 4000)); -- from them, about the student if any
  perform private.help_note_read(v_chat); -- they have read their own chat
  perform private.help_queue_emails(v_chat, v_me, false); -- tells CLG's admins by email
  perform private.log_event('help_start_chat', 'help_chats', v_chat::text, '{}'); -- notes it in the activity log (id only)
  return v_chat; -- hands back the new id
end; -- ends the code
$$; -- end of the function
revoke all on function public.help_start_chat(text, text, text, uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.help_start_chat(text, text, text, uuid, text) to authenticated; -- signed-in people

-- A help desk admin starts a chat with chosen people, for example the
-- parents of a student who is missing a detail ("Ask the family"). For a
-- chat about a student, every person chosen must be that student's parent,
-- the student, or one of their tutors.
create or replace function public.help_start_chat_with( -- the inputs:
  p_people uuid[], -- who to start it with
  p_topic text, -- what it is about
  p_subject text, -- a short title
  p_body text, -- the first message
  p_student uuid default null, -- the student it is about, if any
  p_item text default null -- the missing detail it is about, if any
) -- end of the inputs
returns uuid -- gives back the new chat's id
language plpgsql security definer -- saves to tables people cannot write directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_me uuid := auth.uid(); -- the admin starting it
  v_name text; -- their name
  v_chat uuid; -- the new chat's id
  v_person uuid; -- one person being added
  v_people uuid[]; -- the people, without repeats or the admin
begin -- starts the code
  perform private.help_check_fields(p_topic, p_subject, p_body, p_item); -- checks what was typed
  if not private.is_help_desk(p_topic) then -- not an admin who answers this kind of chat
    raise exception 'Only CLG admins who handle this kind of question can start a chat with someone (with two-step sign-in).' using errcode = '42501'; -- plain message
  end if; -- end of the check
  select array_agg(distinct x) into v_people from unnest(coalesce(p_people, '{}'::uuid[])) x where x is not null and x <> v_me; -- the people, without repeats, blanks or the admin themselves
  if coalesce(array_length(v_people, 1), 0) = 0 then -- nobody chosen
    raise exception 'Please choose who to start the chat with.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if array_length(v_people, 1) > 10 then -- too many people
    raise exception 'A chat can have up to 10 people.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_item is not null and p_student is null then -- a missing detail with no student
    raise exception 'Please choose which student this missing detail is for.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  foreach v_person in array v_people loop -- for each person chosen:
    if not exists (select 1 from public.accounts a where a.id = v_person) then -- no such account
      raise exception 'One of the people chosen no longer has an account.' using errcode = '22023'; -- plain message
    end if; -- end of the check
    if p_student is not null and not ( -- for a chat about a student, the person must be:
      exists (select 1 from public.parent_student_links l where l.parent_id = v_person and l.student_id = p_student) -- the student's parent,
      or exists (select 1 from public.students s where s.id = p_student and s.account_id = v_person) -- the student,
      or exists (select 1 from public.tutor_assignments t where t.tutor_id = v_person and t.student_id = p_student and (t.ends_on is null or t.ends_on >= current_date)) -- or one of their current tutors
    ) then -- if not:
      raise exception 'Everyone in a chat about a student must be their parent, the student, or one of their tutors.' using errcode = '42501'; -- plain message
    end if; -- end of the check
  end loop; -- next person
  perform private.help_check_limits(true); -- checks the daily limits
  select coalesce(nullif(a.full_name, ''), 'CLG') into v_name from public.accounts a where a.id = v_me; -- the admin's name
  insert into public.help_chats (started_by, started_by_name, started_by_clg, topic, subject, student_id, missing_item, status, assigned_to) -- saves the chat:
  values (v_me, coalesce(v_name, 'CLG'), true, p_topic, left(btrim(p_subject), 120), p_student, p_item, 'waiting_on_you', v_me) -- started by CLG, waiting for the person, looked after by this admin
  returning id into v_chat; -- keeps the new id
  insert into public.help_chat_members (chat_id, account_id) select v_chat, x from unnest(v_people) x; -- adds the people chosen
  insert into public.help_messages (chat_id, author_id, author_name, from_clg, student_id, body) -- saves the first message:
  values (v_chat, v_me, coalesce(v_name, 'CLG'), true, p_student, left(btrim(p_body), 4000)); -- from CLG
  perform private.help_note_read(v_chat); -- the admin has read it
  perform private.help_queue_emails(v_chat, v_me, true); -- tells the people by email
  perform private.log_event('help_start_chat_with', 'help_chats', v_chat::text, jsonb_build_object('people', array_length(v_people, 1))); -- notes it (id and how many people only)
  return v_chat; -- hands back the new id
end; -- ends the code
$$; -- end of the function
revoke all on function public.help_start_chat_with(uuid[], text, text, text, uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.help_start_chat_with(uuid[], text, text, text, uuid, text) to authenticated; -- signed-in people can try (the help desk check is inside)

-- ---------------------------------------------------------------------------
-- 5. Replying, reading, closing and looking after chats
-- ---------------------------------------------------------------------------

-- Adds a message to a chat. A member's reply reopens a closed chat and puts
-- it back with CLG; CLG's reply puts it with the members. The first CLG
-- admin to reply starts looking after it.
create or replace function public.help_reply(p_chat uuid, p_body text) -- takes the chat and the message
returns uuid -- gives back the new message's id
language plpgsql security definer -- saves to tables people cannot write directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_me uuid := auth.uid(); -- who is writing
  v_chat public.help_chats; -- the chat
  v_from_clg boolean; -- whether they write for CLG
  v_name text; -- their name
  v_id uuid; -- the new message's id
begin -- starts the code
  select * into v_chat from public.help_chats where id = p_chat; -- finds the chat
  if v_chat.id is null or v_me is null or not private.can_read_help_chat(p_chat) then -- no such chat, or not theirs to write in
    raise exception 'You can only write in your own chats (CLG admins need two-step sign-in).' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_body, ''))) < 1 then -- nothing written
    raise exception 'Please write your message.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  perform private.help_check_limits(false); -- checks the daily limit
  v_from_clg := not private.is_help_member(p_chat); -- a help desk admin who is not a member writes for CLG
  select coalesce(nullif(a.full_name, ''), 'Unknown') into v_name from public.accounts a where a.id = v_me; -- their name
  insert into public.help_messages (chat_id, author_id, author_name, from_clg, student_id, body) -- saves the message:
  values (p_chat, v_me, coalesce(v_name, 'Unknown'), v_from_clg, v_chat.student_id, left(btrim(p_body), 4000)) -- with who wrote it and the chat's student
  returning id into v_id; -- keeps the new id
  update public.help_chats -- updates the chat:
  set status = case when v_from_clg then 'waiting_on_you' else 'waiting_on_clg' end, -- now it is the other side's turn (this also reopens a closed chat)
      closed_at = null, -- no longer closed
      last_message_at = now(), -- the latest message is now
      assigned_to = case when v_from_clg and assigned_to is null then v_me else assigned_to end -- the first CLG admin to reply looks after it
  where id = p_chat; -- this chat
  perform private.help_note_read(p_chat); -- they have read it up to now
  perform private.help_queue_emails(p_chat, v_me, v_from_clg); -- tells the other side by email
  perform private.log_event('help_reply', 'help_messages', v_id::text, jsonb_build_object('chat', p_chat)); -- notes it (ids only)
  return v_id; -- hands back the new id
end; -- ends the code
$$; -- end of the function
revoke all on function public.help_reply(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.help_reply(uuid, text) to authenticated; -- signed-in people can try (the check is inside)

-- Notes that the signed-in person has read a chat (when they open it).
create or replace function public.help_mark_read(p_chat uuid) -- takes the chat
returns void -- gives nothing back
language plpgsql security definer -- writes a table people cannot write directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if private.can_read_help_chat(p_chat) then -- only for a chat they can read
    perform private.help_note_read(p_chat); -- notes it as read up to now
  end if; -- end of the check
end; -- ends the code
$$; -- end of the function
revoke all on function public.help_mark_read(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.help_mark_read(uuid) to authenticated; -- signed-in people

-- Closes or reopens a chat, and (help desk only) changes who looks after it.
-- Members can close their own chat ("my question is answered") or reopen it.
create or replace function public.help_update_chat(p_chat uuid, p_status text, p_assign_to uuid default null) -- takes the chat, its new state, and who should look after it
returns void -- gives nothing back
language plpgsql security definer -- changes a table people cannot change directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_chat public.help_chats; -- the chat
  v_desk boolean; -- whether they answer it for CLG
begin -- starts the code
  select * into v_chat from public.help_chats where id = p_chat; -- finds the chat
  if v_chat.id is null or not private.can_read_help_chat(p_chat) then -- no such chat, or not theirs
    raise exception 'You can only change your own chats (CLG admins need two-step sign-in).' using errcode = '42501'; -- plain message
  end if; -- end of the check
  v_desk := private.is_help_desk(v_chat.topic); -- whether they answer this chat for CLG
  if coalesce(p_status, '') not in ('waiting_on_clg', 'waiting_on_you', 'closed') then -- an unknown state
    raise exception 'Please choose where this chat is up to.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if not v_desk and p_status = 'waiting_on_you' then -- a member cannot say it is waiting on themselves
    raise exception 'Please write a reply instead.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_assign_to is not null and not v_desk then -- a member trying to choose who looks after it
    raise exception 'Only CLG admins choose who looks after a chat.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if p_assign_to is not null and not exists ( -- the admin chosen must answer this kind of chat:
    select 1 from public.admin_profiles ap -- an admin
    join public.account_roles r on r.account_id = ap.account_id and r.role = 'admin' -- who still has the admin role,
    where ap.account_id = p_assign_to -- the one chosen,
      and (ap.level::text in ('owner', 'operations') -- owner and operations answer everything,
        or (ap.level::text = 'support' and v_chat.topic not in ('billing', 'pay')) -- support answers everything except money,
        or (ap.level::text = 'finance' and v_chat.topic in ('billing', 'pay'))) -- finance answers money questions
  ) then -- if not:
    raise exception 'Please choose an admin who handles this kind of question.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.help_chats -- saves the change:
  set status = p_status, -- the new state
      closed_at = case when p_status = 'closed' then coalesce(closed_at, now()) else null end, -- when it was closed (cleared when reopened)
      assigned_to = coalesce(p_assign_to, assigned_to) -- who looks after it (unchanged if nobody was chosen)
  where id = p_chat; -- this chat
  perform private.log_event('help_update_chat', 'help_chats', p_chat::text, jsonb_build_object('status', p_status)); -- notes the change (id and state only)
end; -- ends the code
$$; -- end of the function
revoke all on function public.help_update_chat(uuid, text, uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.help_update_chat(uuid, text, uuid) to authenticated; -- signed-in people can try (the checks are inside)

-- The chats the signed-in person can see, newest activity first, with
-- whether each has something new for them. "Desk" lists every chat they
-- answer for CLG; otherwise only chats they are in.
create or replace function public.help_chat_list(p_desk boolean default false) -- takes which list
returns table ( -- each chat:
  id uuid, -- its id
  subject text, -- its title
  topic text, -- what it is about
  status text, -- whose turn it is, or closed
  student_name text, -- the student it is about (if they can see them)
  missing_item text, -- the missing detail (if any)
  started_by_name text, -- who started it
  started_by_clg boolean, -- whether CLG started it
  assigned_name text, -- the admin looking after it (help desk only)
  created_at timestamptz, -- when it was started
  last_message_at timestamptz, -- when the latest message was written
  unread boolean -- whether it has a message they have not read
) -- end of the columns
language sql stable security invoker -- runs as the signed-in person, so the access rules decide what shows
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select c.id, c.subject, c.topic, c.status, -- the chat's details,
    s.full_name, c.missing_item, c.started_by_name, c.started_by_clg, -- the student (if readable), the missing detail and who started it,
    case when p_desk then a.full_name end, -- the admin looking after it (desk list only),
    c.created_at, c.last_message_at, -- the times,
    private.help_chat_unread(c.id) -- and whether there is something new
  from public.help_chats c -- from the chats they can read,
  left join public.students s on s.id = c.student_id -- with the student, where they can read the student,
  left join public.accounts a on a.id = c.assigned_to -- and the admin looking after it, where they can read them
  where case when p_desk then private.is_help_desk(c.topic) else private.is_help_member(c.id) end -- the list asked for
  order by c.last_message_at desc -- latest activity first
  limit 300 -- at most 300
$$; -- end of the function
revoke all on function public.help_chat_list(boolean) from public, anon; -- not for signed-out visitors
grant execute on function public.help_chat_list(boolean) to authenticated; -- signed-in people

-- The admins who can look after a chat of this topic (for the "Looked after
-- by" drop-down). Help desk admins only.
create or replace function public.help_desk_admins(p_topic text) -- takes the topic
returns table (account_id uuid, full_name text) -- each admin and their name
language sql stable security definer -- reads the admin list
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select ap.account_id, a.full_name -- each admin and their name,
  from public.admin_profiles ap -- from the admin levels,
  join public.account_roles r on r.account_id = ap.account_id and r.role = 'admin' -- who still have the admin role,
  join public.accounts a on a.id = ap.account_id -- with their names,
  where private.is_help_desk(p_topic) -- only when the person asking is on the help desk for this topic,
    and (ap.level::text in ('owner', 'operations') -- owner and operations answer everything,
      or (ap.level::text = 'support' and p_topic not in ('billing', 'pay')) -- support answers everything except money,
      or (ap.level::text = 'finance' and p_topic in ('billing', 'pay'))) -- finance answers money questions
  order by a.full_name -- in name order
$$; -- end of the function
revoke all on function public.help_desk_admins(text) from public, anon; -- not for signed-out visitors
grant execute on function public.help_desk_admins(text) to authenticated; -- signed-in people (the help desk check is inside)

-- ---------------------------------------------------------------------------
-- 6. Emails: "you have a new message" (no message words)
-- ---------------------------------------------------------------------------

-- Any help chat email due now? (Used to wake the email sender.)
create or replace function private.help_chat_emails_waiting() -- no inputs
returns boolean -- gives back yes or no
language sql stable security definer -- reads the queue
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- is there one:
    select 1 from public.help_chat_emails -- an email row
    where emailed_at is null and send_after <= now() and created_at > now() - interval '3 days' -- not yet sent, due, and less than 3 days old
  ) -- end of the check
$$; -- end of the function
revoke all on function private.help_chat_emails_waiting() from public; -- for the database's own use only

-- Hands due emails to the sender and marks them sent. Emails for a chat the
-- person has already read since are skipped, and so are emails for someone
-- who can no longer read the chat.
create or replace function public.help_chat_emails_claim(p_limit integer default 50) -- takes how many at most
returns table (id uuid, email text, first_name text, subject text, body text, link text, button text, footer text) -- one email per row
language plpgsql security definer -- reads and marks the queue
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  update public.help_chat_emails e -- first, skips emails no longer needed:
  set emailed_at = now() -- marked as dealt with, with no email id
  where e.emailed_at is null and e.send_after <= now() -- due ones not yet sent,
    and (exists (select 1 from public.help_chat_reads r where r.chat_id = e.chat_id and r.account_id = e.account_id and r.last_read_at >= e.created_at) -- that the person has read since,
      or not ( -- or that the person can no longer read:
        exists (select 1 from public.help_chat_members m where m.chat_id = e.chat_id and m.account_id = e.account_id) -- (a member,
        or exists (select 1 from public.admin_profiles ap join public.account_roles ar on ar.account_id = ap.account_id and ar.role = 'admin' where ap.account_id = e.account_id))); -- or still an admin)
  return query -- then hands back:
  with due as ( -- the emails to send:
    select e.id from public.help_chat_emails e -- each email row
    where e.emailed_at is null and e.send_after <= now() and e.created_at > now() - interval '3 days' -- not yet sent, due, and less than 3 days old
    order by e.send_after -- oldest first
    limit least(greatest(p_limit, 1), 100) -- at most the number asked for (1 to 100)
    for update skip locked -- so two senders never take the same one
  ), marked as ( -- marks them sent:
    update public.help_chat_emails e -- each row taken
    set email_id = gen_random_uuid(), emailed_at = now() -- gets a new email id and the time
    from due where e.id = due.id -- (only the ones taken)
    returning e.email_id, e.account_id, e.chat_id -- what the email needs
  ) -- end of the steps
  select m.email_id, -- the email's id
    ap.email, -- who it goes to
    private.first_name(a.full_name), -- their first name
    'New message in the CLG help chat'::text, -- the subject
    'You have a new message in the CLG help chat.' -- the message
      || E'\n\nTo keep your details private, the message is only in the app. Please sign in to read it and reply.', -- and why there are no details
    '/help/' || m.chat_id::text, -- the page the button opens (the chat)
    'Read the message'::text, -- the button's words
    'You get this email because you have a chat with CLG in the app. CLG does not send these between 9pm and 5am.'::text -- the small print
  from marked m -- from the rows taken
  join public.accounts a on a.id = m.account_id -- with the person's name
  join public.account_private ap on ap.account_id = m.account_id; -- and email
end; -- ends the code
$$; -- end of the function
revoke all on function public.help_chat_emails_claim(integer) from public, anon, authenticated; -- the server only
grant execute on function public.help_chat_emails_claim(integer) to service_role; -- the email sender

-- Puts emails back if sending failed (only ones taken in the last hour).
create or replace function public.help_chat_emails_release(p_ids uuid[]) -- takes the email ids
returns void -- gives nothing back
language sql security definer -- changes the queue
set search_path = '' -- only fully named tables, for safety
as $$ -- the change
  update public.help_chat_emails set email_id = null, emailed_at = null -- clears the email marks
  where email_id = any (p_ids) and emailed_at > now() - interval '1 hour' -- for those emails, taken in the last hour
$$; -- end of the function
revoke all on function public.help_chat_emails_release(uuid[]) from public, anon, authenticated; -- the server only
grant execute on function public.help_chat_emails_release(uuid[]) to service_role; -- the email sender

-- Wakes the email sender for help chat emails too. The shared check is
-- extended rather than copied, so changes other modules made to it are kept.
do $$ -- a small block of code
declare -- the working values:
  v_def text; -- the shared check's code
begin -- starts the block
  if to_regprocedure('private.emails_waiting()') is null then -- the shared check is not there
    return; -- nothing to do
  end if; -- end of the check
  v_def := replace(pg_catalog.pg_get_functiondef('private.emails_waiting()'::regprocedure), chr(13), ''); -- reads its current code (without Windows line endings)
  if strpos(v_def, 'private.help_chat_emails_waiting()') = 0 then -- not added yet
    v_def := regexp_replace(v_def, '\s*\$function\$\s*$', E'\n  or private.help_chat_emails_waiting()\n$function$\n'); -- adds "or a help chat email is waiting" at the end
    execute v_def; -- saves the new code
  end if; -- end of the check
end; -- ends the block
$$; -- end of the code

-- ---------------------------------------------------------------------------
-- 7. Concerning words: every message and chat title is checked
-- ---------------------------------------------------------------------------
do $$ -- a small block of code
begin -- starts the block
  if to_regprocedure('private.scan_watch_words()') is null then -- the check is not there
    return; -- nothing to do
  end if; -- end of the check
  drop trigger if exists watch_words_scan on public.help_messages; -- removes the old check if the file is run again
  create trigger watch_words_scan after insert or update of body on public.help_messages -- after a new message (or a change to one),
    for each row execute function private.scan_watch_words('body'); -- checks what was written
  drop trigger if exists watch_words_scan on public.help_chats; -- removes the old check if the file is run again
  create trigger watch_words_scan after insert or update of subject on public.help_chats -- after a new chat (or a new title),
    for each row execute function private.scan_watch_words('subject'); -- checks the title
end; -- ends the block
$$; -- end of the code

-- ---------------------------------------------------------------------------
-- 8. To-do numbers: chats waiting for CLG (help desk) and new messages
--    (everyone). to_do_counts is edited in place, so other changes stay.
-- ---------------------------------------------------------------------------
do $$ -- a small block of code
declare -- the working values:
  v_def text; -- the to-do function's code
begin -- starts the block
  if to_regprocedure('public.to_do_counts()') is null then -- the to-do numbers are not there
    return; -- nothing to do
  end if; -- end of the check
  v_def := replace(pg_get_functiondef('public.to_do_counts()'::regprocedure), chr(13), ''); -- reads the current code (without Windows line endings)
  if strpos(v_def, 'section := ''help''') > 0 then -- already added
    return; -- nothing to do
  end if; -- end of the check
  if strpos(v_def, E'  -- Billing (owner, operations and finance).\n') = 0 then -- the place to add it has changed
    raise exception 'to_do_counts has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- end of the check
  v_def := replace(v_def, -- adds the help chat numbers just before the billing numbers:
    E'  -- Billing (owner, operations and finance).\n', -- the place to add it
    E'  -- Help chat: chats waiting for a reply from CLG (help desk admins only).\n' -- a comment saying what it is
    || E'  if private.is_front_desk() or private.is_finance_admin() then\n' -- only for admins who answer chats
    || E'    area := ''admin''; section := ''help'';\n' -- the area and section names
    || E'    n := (select count(*) from public.help_chats c where c.status = ''waiting_on_clg'' and private.is_help_desk(c.topic) and not private.is_help_member(c.id));\n' -- chats waiting for CLG that they answer (not their own)
    || E'    return next;\n' -- hands back the row
    || E'  end if;\n\n' -- end of the admin part
    || E'  -- Help chat: chats with a message the person has not read yet (their own chats).\n' -- a comment saying what it is
    || E'  area := ''help''; section := ''unread'';\n' -- the area and section names
    || E'  n := (select count(*) from public.help_chat_members m where m.account_id = v_me and private.is_help_member(m.chat_id) and private.help_chat_unread(m.chat_id));\n' -- their chats with something new
    || E'  return next;\n\n' -- hands back the row
    || E'  -- Billing (owner, operations and finance).\n'); -- and puts back the billing comment
  execute v_def; -- saves the new code
end; -- ends the block
$$; -- end of the code

-- ---------------------------------------------------------------------------
-- 9. Tidying up: chats go 2 years after their last message (the same as
--    other student records), and sent email rows after 30 days.
-- ---------------------------------------------------------------------------
create or replace function private.help_chat_tidy() -- no inputs
returns void -- gives nothing back
language sql security definer -- deletes rows people cannot delete
set search_path = '' -- only fully named tables, for safety
as $$ -- the changes
  delete from public.help_chats where last_message_at < now() - interval '2 years'; -- old chats (their members, messages, reads and emails go with them)
  delete from public.help_chat_emails where emailed_at is not null and emailed_at < now() - interval '30 days'; -- old sent email rows
$$; -- end of the function
revoke all on function private.help_chat_tidy() from public; -- for the database's own use only

-- Runs the tidy-up every night, where the job scheduler (pg_cron) is available. Supabase has it.
do $$ -- a small block of code
begin -- starts the block
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then -- the job scheduler is available
    execute 'create extension if not exists pg_cron with schema pg_catalog'; -- turns it on if needed
    execute $job$ select cron.schedule('clg-help-chat-tidy', '45 17 * * *', 'select private.help_chat_tidy()') $job$; -- every night in the early morning, Adelaide time (re-running replaces the same named job)
  end if; -- end of the check
end; -- ends the block
$$; -- end of the code
