-- Summary: child safety concern flag (Carla, 12 Nov 2026).
--
-- Anyone signed in (tutor, parent, student or admin) can raise a concern
-- about a child. The app tells them to call 000 first in an emergency, then
-- the child protection line for the child's state, and then to tell CLG
-- here. Each concern goes to ONE person, chosen by the person raising it:
--   * the Child Safety Officer (Carla), or
--   * the deputy (Lauren), for example when the concern is about Carla.
--
-- Records are confidential:
--   * only the person it was sent to can read it and its notes, and only
--     after two-step sign-in. Other admins, even the owner, can't read it
--     unless it was sent to them;
--   * the person who raised it can see what they sent and where it's up to,
--     but not the follow-up notes;
--   * nothing about the concern goes into the general activity log (only
--     the concern's id), and the alert email holds no names or details;
--   * the records are kept when a student or account is deleted (names are
--     copied onto the record), because child safety records must be kept
--     for decades (see docs/features/child-safety-concerns.md).
--
-- Needs 20261111700100_to_do_counts.sql and 20261029700100_email_sender.sql.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- Where a concern is up to. Made only if it doesn't exist yet, so the file can run twice.
do $$ -- a small block of code
begin -- starts the block
  if to_regtype('public.safety_concern_status') is null then -- the type isn't there yet
    create type public.safety_concern_status as enum ('new', 'in_progress', 'closed'); -- new (not opened), being dealt with, finished
  end if; -- end of the check
  if to_regtype('public.safety_contact_role') is null then -- the second type isn't there yet
    create type public.safety_contact_role as enum ('officer', 'deputy'); -- the Child Safety Officer, or their deputy
  end if; -- end of the check
end; -- ends the block
$$; -- end of the code

-- ---------------------------------------------------------------------------
-- Who receives concerns: the Child Safety Officer and the deputy
-- ---------------------------------------------------------------------------

-- One row only. The owner sets who holds each job (Carla and Lauren today).
create table if not exists public.child_safety_contacts ( -- the one settings row
  id boolean primary key default true check (id), -- always "true", so there can only be one row
  officer_id uuid references public.accounts (id) on delete set null, -- the Child Safety Officer's account
  deputy_id uuid references public.accounts (id) on delete set null, -- the deputy's account (optional)
  updated_by uuid references public.accounts (id) on delete set null, -- who last changed it
  updated_at timestamptz not null default now(), -- when it was last changed
  constraint child_safety_contacts_two_people check (officer_id is null or deputy_id is null or officer_id <> deputy_id) -- the officer and deputy must be different people
); -- end of the table
alter table public.child_safety_contacts enable row level security; -- turns on access rules (no rule below, so nobody reads it directly)
revoke all on public.child_safety_contacts from anon, authenticated; -- read and changed only through the functions below

-- Makes the row, with the owner as the Child Safety Officer when there is exactly one owner (Carla).
insert into public.child_safety_contacts (id, officer_id) -- adds the settings row
select true, (select account_id from public.admin_profiles where level = 'owner' limit 1) -- the owner as officer
where (select count(*) from public.admin_profiles where level = 'owner') = 1 -- only when there's exactly one owner
on conflict (id) do nothing; -- already there: leaves it alone
insert into public.child_safety_contacts (id) values (true) on conflict (id) do nothing; -- makes an empty row if there was no single owner

-- ---------------------------------------------------------------------------
-- The concerns and their follow-up notes
-- ---------------------------------------------------------------------------

create table if not exists public.safety_concerns ( -- one row per concern raised
  id uuid primary key default gen_random_uuid(), -- the concern's id
  raised_by uuid references public.accounts (id) on delete set null, -- who raised it (empty if their account is later deleted)
  raised_by_name text not null check (char_length(raised_by_name) between 1 and 200), -- their name, copied so the record stays complete
  raised_by_roles text not null default '' check (char_length(raised_by_roles) <= 100), -- their roles at the time, e.g. "tutor"
  raised_by_contact text check (char_length(raised_by_contact) <= 300), -- their email and phone at the time, so the officer can follow up
  student_id uuid references public.students (id) on delete set null, -- the child, if they're a CLG student (empty if not, or if later deleted)
  child_name text not null check (char_length(child_name) between 1 and 200), -- the child's name, copied (or typed if not a CLG student)
  child_state public.au_state not null, -- the state the child lives in (decides which reporting line applies)
  sent_to public.safety_contact_role not null, -- whether it was sent to the officer or the deputy
  recipient_id uuid references public.accounts (id) on delete set null, -- the person it went to (the only person who can read it)
  immediate_danger boolean not null, -- whether they said a child is in immediate danger
  called_000 boolean not null default false, -- whether they said they had called 000
  reported_to_line text not null check (reported_to_line in ('yes', 'no', 'not_sure')), -- whether they had reported to the state's child protection line
  line_reference text check (char_length(line_reference) <= 100), -- the reference number the line gave them, if any
  happened_on date check (happened_on is null or happened_on > date '1900-01-01'), -- when it happened or was noticed, if known
  what_happened text not null check (char_length(what_happened) between 10 and 8000), -- what they saw, heard or were told
  status public.safety_concern_status not null default 'new', -- where it's up to
  email_id uuid, -- the id of the alert email being sent (empty when none is waiting)
  emailed_at timestamptz, -- when the alert email was handed over to send
  created_at timestamptz not null default now(), -- when it was raised
  updated_at timestamptz not null default now(), -- when it last changed
  closed_at timestamptz -- when it was closed, if it has been
); -- end of the table
create index if not exists safety_concerns_recipient on public.safety_concerns (recipient_id, status); -- finds a person's concerns quickly
create index if not exists safety_concerns_raised_by on public.safety_concerns (raised_by); -- finds the concerns a person raised quickly
create index if not exists safety_concerns_unsent on public.safety_concerns (created_at) where emailed_at is null; -- finds alerts still to email quickly
alter table public.safety_concerns enable row level security; -- turns on access rules
revoke all on public.safety_concerns from anon, authenticated; -- no direct changes: everything goes through the functions below
grant select on public.safety_concerns to authenticated; -- signed-in people may read, but only the rows the rule below allows

-- Follow-up notes: what the officer or deputy did (e.g. "Phoned CARL, reference 123").
create table if not exists public.safety_concern_notes ( -- one row per note
  id uuid primary key default gen_random_uuid(), -- the note's id
  concern_id uuid not null references public.safety_concerns (id) on delete cascade, -- which concern it belongs to
  author_id uuid references public.accounts (id) on delete set null, -- who wrote it
  author_name text not null check (char_length(author_name) between 1 and 200), -- their name, copied so the record stays complete
  note text not null check (char_length(note) between 2 and 4000), -- the note itself
  created_at timestamptz not null default now() -- when it was written
); -- end of the table
create index if not exists safety_concern_notes_concern on public.safety_concern_notes (concern_id, created_at); -- finds a concern's notes in order
alter table public.safety_concern_notes enable row level security; -- turns on access rules
revoke all on public.safety_concern_notes from anon, authenticated; -- notes are added only through the function below, and never edited
grant select on public.safety_concern_notes to authenticated; -- signed-in people may read, but only the rows the rule below allows

-- ---------------------------------------------------------------------------
-- Access rules (who can read what)
-- ---------------------------------------------------------------------------

-- Concerns: the person it was sent to (after two-step sign-in), and the person who raised it.
drop policy if exists "recipient or raiser reads concern" on public.safety_concerns; -- removes the old rule if the file is run again
create policy "recipient or raiser reads concern" on public.safety_concerns -- the reading rule
  for select to authenticated -- for signed-in people reading
  using ( -- a row is visible when:
    (recipient_id = auth.uid() and private.has_aal2()) -- it was sent to them and they used two-step sign-in,
    or raised_by = auth.uid() -- or they raised it.
  ); -- end of the rule

-- Notes: only the person the concern was sent to (after two-step sign-in). Not the person who raised it.
drop policy if exists "recipient reads notes" on public.safety_concern_notes; -- removes the old rule if the file is run again
create policy "recipient reads notes" on public.safety_concern_notes -- the reading rule
  for select to authenticated -- for signed-in people reading
  using ( -- a note is visible when:
    private.has_aal2() -- they used two-step sign-in,
    and exists (select 1 from public.safety_concerns c where c.id = concern_id and c.recipient_id = auth.uid()) -- and its concern was sent to them.
  ); -- end of the rule

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- The account that holds a job (officer or deputy), or nothing if nobody does.
create or replace function private.safety_contact(p_role public.safety_contact_role) -- takes the job
returns uuid -- gives back an account id
language sql stable security definer -- reads the settings row, which people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the lookup
  select case p_role when 'officer' then officer_id else deputy_id end -- the officer's or deputy's account
  from public.child_safety_contacts -- from the settings row
  where id -- (the one row)
$$; -- end of the function
revoke all on function private.safety_contact(public.safety_contact_role) from public; -- for the database's own use only

-- True when the account works for CLG (has the admin or tutor role), so it can hold a child safety job.
create or replace function private.is_staff_account(p_account uuid) -- takes an account
returns boolean -- gives back yes or no
language sql stable security definer -- reads roles for any account
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists (select 1 from public.account_roles where account_id = p_account and role in ('admin', 'tutor')) -- an admin or tutor role
$$; -- end of the function
revoke all on function private.is_staff_account(uuid) from public; -- for the database's own use only

-- ---------------------------------------------------------------------------
-- Who receives concerns: reading and setting
-- ---------------------------------------------------------------------------

-- Everyone signed in can see WHO receives concerns (names only), so the form can name them.
create or replace function public.child_safety_contacts_list() -- no inputs
returns table (role public.safety_contact_role, account_id uuid, full_name text) -- each job, who holds it, and their name
language sql stable security definer -- reads the settings row and names, which people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select 'officer'::public.safety_contact_role, a.id, a.full_name -- the officer
  from public.child_safety_contacts c join public.accounts a on a.id = c.officer_id -- from the settings row and their account
  where c.id and auth.uid() is not null -- only for signed-in people
  union all -- and
  select 'deputy'::public.safety_contact_role, a.id, a.full_name -- the deputy
  from public.child_safety_contacts c join public.accounts a on a.id = c.deputy_id -- from the settings row and their account
  where c.id and auth.uid() is not null -- only for signed-in people
$$; -- end of the function
revoke all on function public.child_safety_contacts_list() from public, anon; -- not for signed-out visitors
grant execute on function public.child_safety_contacts_list() to authenticated; -- signed-in people

-- The people the owner can choose from: everyone with the admin or tutor role.
create or replace function public.child_safety_contact_choices() -- no inputs
returns table (account_id uuid, full_name text) -- each staff member and their name
language sql stable security definer -- reads roles and names for everyone
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select a.id, a.full_name -- the account and name
  from public.accounts a -- from every account
  where private.is_owner() -- only the owner gets the list
    and private.is_staff_account(a.id) -- staff only
  order by a.full_name -- in name order
$$; -- end of the function
revoke all on function public.child_safety_contact_choices() from public, anon; -- not for signed-out visitors
grant execute on function public.child_safety_contact_choices() to authenticated; -- signed-in people can ask (only the owner gets names)

-- The owner names the Child Safety Officer and the deputy. Concerns already
-- raised stay with the person they were sent to, so a change here never
-- opens old concerns to someone new.
create or replace function public.set_child_safety_contacts(p_officer uuid, p_deputy uuid) -- takes the officer and the deputy (deputy optional)
returns void -- gives nothing back
language plpgsql security definer -- changes the settings row, which people can't change directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if not private.is_owner() then -- not the owner (with two-step sign-in)
    raise exception 'Only the owner can choose who receives child safety concerns.' using errcode = '42501'; -- plain message, "not allowed" code
  end if; -- end of the check
  if p_officer is null then -- no officer chosen
    raise exception 'Please choose a Child Safety Officer.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_officer = p_deputy then -- the same person twice
    raise exception 'The deputy must be a different person from the Child Safety Officer.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if not private.is_staff_account(p_officer) or (p_deputy is not null and not private.is_staff_account(p_deputy)) then -- someone who doesn't work for CLG
    raise exception 'Both people must be CLG staff (admin or tutor).' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.child_safety_contacts -- saves the choice
  set officer_id = p_officer, -- the officer
      deputy_id = p_deputy, -- the deputy
      updated_by = auth.uid(), -- who changed it
      updated_at = now() -- when
  where id; -- the one row
  perform private.log_event('set_child_safety_contacts', 'child_safety_contacts', null, -- records the change in the activity log
    jsonb_build_object('officer_id', p_officer, 'deputy_id', p_deputy)); -- with the two account ids (no concern details)
end; -- ends the code
$$; -- end of the function
revoke all on function public.set_child_safety_contacts(uuid, uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.set_child_safety_contacts(uuid, uuid) to authenticated; -- signed-in people can try (the owner check is inside)

-- ---------------------------------------------------------------------------
-- Raising a concern
-- ---------------------------------------------------------------------------

-- Saves a new concern and sends it to the officer or the deputy. When the
-- child is a CLG student, the person must be able to see that student
-- (their own child, their own student, themselves, or any student for an
-- admin); the name and state then come from the student record. Otherwise
-- the person types the child's name and picks the state.
create or replace function public.raise_safety_concern( -- the inputs:
  p_student uuid, -- the CLG student it's about (or empty)
  p_child_name text, -- the child's name, when not a CLG student
  p_child_state public.au_state, -- the child's state, when not a CLG student
  p_send_to public.safety_contact_role, -- officer or deputy
  p_immediate_danger boolean, -- whether a child is in immediate danger
  p_called_000 boolean, -- whether they called 000
  p_reported_to_line text, -- yes, no or not_sure
  p_line_reference text, -- the line's reference number (optional)
  p_happened_on date, -- when it happened (optional)
  p_what_happened text -- what happened
) -- end of the inputs
returns uuid -- gives back the new concern's id
language plpgsql security definer -- saves to a table people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_me uuid := auth.uid(); -- who is raising it
  v_name text; -- the child's name
  v_state public.au_state; -- the child's state
  v_recipient uuid; -- who it goes to
  v_id uuid; -- the new concern's id
begin -- starts the code
  if v_me is null then -- nobody signed in
    raise exception 'Please sign in to raise a concern.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if (select count(*) from public.safety_concerns where raised_by = v_me and created_at > now() - interval '1 day') >= 20 then -- 20 in a day already
    raise exception 'You have raised a lot of concerns today. Please phone CLG directly.' using errcode = '54000'; -- plain message, "too many" code
  end if; -- end of the check
  if p_student is not null then -- a CLG student was chosen
    if not private.can_view_student(p_student) then -- they can't see that student
      raise exception 'Please choose one of the children listed, or "Someone not listed".' using errcode = '42501'; -- plain message
    end if; -- end of the check
    select full_name, state into v_name, v_state from public.students where id = p_student; -- the student's name and state
  else -- not a CLG student
    v_name := nullif(btrim(coalesce(p_child_name, '')), ''); -- the typed name, trimmed
    v_state := p_child_state; -- the chosen state
    if v_name is null then -- no name
      raise exception 'Please give the child''s name, or a description if you don''t know it.' using errcode = '22023'; -- plain message
    end if; -- end of the check
    if v_state is null then -- no state
      raise exception 'Please choose the state the child lives in.' using errcode = '22023'; -- plain message
    end if; -- end of the check
  end if; -- end of the choice
  if p_send_to is null then -- nobody chosen to send to
    raise exception 'Please choose who to send this to.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_recipient := private.safety_contact(p_send_to); -- the person who holds that job
  if v_recipient is null then -- nobody holds it
    raise exception 'CLG hasn''t named a % yet. Please phone CLG directly.', -- plain message
      case p_send_to when 'officer' then 'Child Safety Officer' else 'deputy Child Safety Officer' end -- naming the job
      using errcode = '22023'; -- "bad value" code
  end if; -- end of the check
  if p_immediate_danger is null then -- the danger question wasn't answered
    raise exception 'Please say whether a child is in immediate danger.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if coalesce(p_reported_to_line, '') not in ('yes', 'no', 'not_sure') then -- the reporting-line question wasn't answered
    raise exception 'Please say whether you have reported this to the child protection line.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_what_happened, ''))) < 10 then -- too little written
    raise exception 'Please describe what happened (at least a sentence).' using errcode = '22023'; -- plain message
  end if; -- end of the check

  insert into public.safety_concerns ( -- saves the concern:
    raised_by, raised_by_name, raised_by_roles, raised_by_contact, -- who raised it,
    student_id, child_name, child_state, -- the child,
    sent_to, recipient_id, -- who it goes to,
    immediate_danger, called_000, reported_to_line, line_reference, happened_on, what_happened -- and their answers
  ) -- end of the column list
  select v_me, -- the person raising it,
    coalesce(nullif(a.full_name, ''), 'Unknown'), -- their name,
    coalesce((select string_agg(r.role::text, ', ' order by r.role) from public.account_roles r where r.account_id = v_me), ''), -- their roles,
    nullif(concat_ws(', ', ap.email, ap.phone), ''), -- their email and phone,
    p_student, left(v_name, 200), v_state, -- the child,
    p_send_to, v_recipient, -- the job and person it goes to,
    p_immediate_danger, coalesce(p_called_000, false), p_reported_to_line, -- danger, 000 and reporting-line answers,
    nullif(left(btrim(coalesce(p_line_reference, '')), 100), ''), -- the reference number (if any),
    p_happened_on, -- when it happened (if given),
    left(btrim(p_what_happened), 8000) -- and what happened.
  from public.accounts a -- from their account
  left join public.account_private ap on ap.account_id = a.id -- with their contact details
  where a.id = v_me -- (their own account)
  returning id into v_id; -- keeps the new id
  if v_id is null then -- nothing saved (no account row)
    raise exception 'We couldn''t save that. Please phone CLG directly.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  perform private.log_event('raise_safety_concern', 'safety_concerns', v_id::text, '{}'); -- notes in the activity log that a concern was raised (id only, no details)
  return v_id; -- hands back the new id
end; -- ends the code
$$; -- end of the function
revoke all on function public.raise_safety_concern(uuid, text, public.au_state, public.safety_contact_role, boolean, boolean, text, text, date, text) from public, anon; -- not for signed-out visitors
grant execute on function public.raise_safety_concern(uuid, text, public.au_state, public.safety_contact_role, boolean, boolean, text, text, date, text) to authenticated; -- signed-in people

-- ---------------------------------------------------------------------------
-- Dealing with a concern (the person it was sent to only)
-- ---------------------------------------------------------------------------

-- Finds a concern the current person received, or stops with a plain message.
create or replace function private.my_received_concern(p_id uuid) -- takes the concern's id
returns public.safety_concerns -- gives back the concern
language plpgsql stable security definer -- reads the concern
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_row public.safety_concerns; -- the concern
begin -- starts the code
  select * into v_row from public.safety_concerns where id = p_id and recipient_id = auth.uid(); -- the concern, if it was sent to them
  if v_row.id is null or not private.has_aal2() then -- not theirs, or no two-step sign-in
    raise exception 'Only the person this concern was sent to can do that (with two-step sign-in).' using errcode = '42501'; -- plain message
  end if; -- end of the check
  return v_row; -- hands back the concern
end; -- ends the code
$$; -- end of the function
revoke all on function private.my_received_concern(uuid) from public; -- for the database's own use only

-- Moves a concern to "being dealt with" or "closed" (or back to new).
create or replace function public.safety_concern_set_status(p_id uuid, p_status public.safety_concern_status) -- takes the concern and its new stage
returns void -- gives nothing back
language plpgsql security definer -- changes a table people can't change directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  perform private.my_received_concern(p_id); -- checks it was sent to them (stops otherwise)
  if p_status is null then -- no stage given
    raise exception 'Please choose where this concern is up to.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.safety_concerns -- saves the stage
  set status = p_status, -- the new stage
      closed_at = case when p_status = 'closed' then now() else null end, -- when it was closed (cleared if reopened)
      updated_at = now() -- when it changed
  where id = p_id; -- this concern
  perform private.log_event('safety_concern_status', 'safety_concerns', p_id::text, jsonb_build_object('status', p_status)); -- notes the change (id and stage only)
end; -- ends the code
$$; -- end of the function
revoke all on function public.safety_concern_set_status(uuid, public.safety_concern_status) from public, anon; -- not for signed-out visitors
grant execute on function public.safety_concern_set_status(uuid, public.safety_concern_status) to authenticated; -- signed-in people can try (the check is inside)

-- Adds a follow-up note. Notes can't be edited or deleted, so the record stays complete.
create or replace function public.safety_concern_add_note(p_id uuid, p_note text) -- takes the concern and the note
returns void -- gives nothing back
language plpgsql security definer -- writes to a table people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  perform private.my_received_concern(p_id); -- checks it was sent to them (stops otherwise)
  if char_length(btrim(coalesce(p_note, ''))) < 2 then -- nothing written
    raise exception 'Please write the note first.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.safety_concern_notes (concern_id, author_id, author_name, note) -- saves the note:
  select p_id, a.id, a.full_name, left(btrim(p_note), 4000) -- the concern, who wrote it, their name, and the note
  from public.accounts a where a.id = auth.uid(); -- from their account
  update public.safety_concerns -- marks the concern as being dealt with
  set status = case when status = 'new' then 'in_progress'::public.safety_concern_status else status end, -- a new concern moves on; others keep their stage
      updated_at = now() -- when it changed
  where id = p_id; -- this concern
  perform private.log_event('safety_concern_note', 'safety_concerns', p_id::text, '{}'); -- notes that a note was added (id only)
end; -- ends the code
$$; -- end of the function
revoke all on function public.safety_concern_add_note(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.safety_concern_add_note(uuid, text) to authenticated; -- signed-in people can try (the check is inside)

-- Passes a concern to the other contact (officer to deputy, or deputy to
-- officer), for example when it turns out to be about the person who got it,
-- or they're away. After this, only the new person can read it.
create or replace function public.safety_concern_pass_on(p_id uuid, p_reason text) -- takes the concern and why
returns void -- gives nothing back
language plpgsql security definer -- changes a table people can't change directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_row public.safety_concerns; -- the concern
  v_to_role public.safety_contact_role; -- the job it's going to
  v_to uuid; -- the person it's going to
begin -- starts the code
  v_row := private.my_received_concern(p_id); -- checks it was sent to them (stops otherwise)
  if char_length(btrim(coalesce(p_reason, ''))) < 2 then -- no reason given
    raise exception 'Please say why you are passing this on.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_to_role := case when v_row.sent_to = 'officer' then 'deputy' else 'officer' end; -- the other job
  v_to := private.safety_contact(v_to_role); -- who holds it
  if v_to is null or v_to = auth.uid() then -- nobody else to pass it to
    raise exception 'There is nobody else to pass this to. The owner can name a deputy first.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.safety_concern_notes (concern_id, author_id, author_name, note) -- records the hand-over as a note:
  select p_id, a.id, a.full_name, -- the concern, who passed it on and their name,
    left('Passed to the ' || case v_to_role when 'officer' then 'Child Safety Officer' else 'deputy' end || '. Reason: ' || btrim(p_reason), 4000) -- and the reason
  from public.accounts a where a.id = auth.uid(); -- from their account
  update public.safety_concerns -- moves the concern
  set sent_to = v_to_role, -- to the other job
      recipient_id = v_to, -- and the person who holds it
      status = 'new', -- so it shows as new for them
      email_id = null, emailed_at = null, -- and they get an alert email
      updated_at = now() -- when it changed
  where id = p_id; -- this concern
  perform private.log_event('safety_concern_pass_on', 'safety_concerns', p_id::text, '{}'); -- notes the hand-over (id only)
end; -- ends the code
$$; -- end of the function
revoke all on function public.safety_concern_pass_on(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.safety_concern_pass_on(uuid, text) to authenticated; -- signed-in people can try (the check is inside)

-- If the person a concern was sent to has their account deleted, the
-- concern moves to the other contact instead of becoming unreadable.
create or replace function private.safety_concern_find_new_recipient() -- runs on a change to a concern
returns trigger -- a trigger function
language plpgsql security definer -- reads the settings row
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if new.recipient_id is null and old.recipient_id is not null then -- their account was just deleted
    select a.id into new.recipient_id -- picks a new recipient:
    from public.child_safety_contacts c -- from the settings row
    join public.accounts a on a.id in (c.officer_id, c.deputy_id) -- the officer and deputy who still have accounts
    where c.id and a.id <> old.recipient_id -- not the deleted person
    order by (a.id = c.officer_id) desc -- the officer first
    limit 1; -- just one
    if new.recipient_id is not null then -- someone was found
      new.sent_to := case when new.recipient_id = (select officer_id from public.child_safety_contacts where id) then 'officer' else 'deputy' end; -- their job
      new.status := 'new'; -- shows as new for them
      new.email_id := null; -- clears the old email
      new.emailed_at := null; -- so they get an alert email
    end if; -- end of the check
  end if; -- end of the check
  return new; -- carries on with the change
end; -- ends the code
$$; -- end of the function
revoke all on function private.safety_concern_find_new_recipient() from public; -- for the database's own use only
drop trigger if exists find_new_recipient on public.safety_concerns; -- removes the old trigger if the file is run again
create trigger find_new_recipient before update of recipient_id on public.safety_concerns -- before the recipient changes
  for each row execute function private.safety_concern_find_new_recipient(); -- runs the check above

-- ---------------------------------------------------------------------------
-- Alert emails (no names or details, only "open the app")
-- ---------------------------------------------------------------------------

-- Any alert waiting to be emailed? (Sent straight away, even in quiet hours: child safety can't wait.)
create or replace function private.safety_concern_emails_waiting() -- no inputs
returns boolean -- gives back yes or no
language sql stable security definer -- reads concerns
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- is there one:
    select 1 from public.safety_concerns -- a concern
    where emailed_at is null and recipient_id is not null -- not yet emailed, with someone to email
      and created_at > now() - interval '30 days' -- and raised in the last 30 days
  ) -- end of the check
$$; -- end of the function
revoke all on function private.safety_concern_emails_waiting() from public; -- for the database's own use only

-- Hands waiting alerts to the email sender and marks them sent.
create or replace function public.safety_concern_emails_claim(p_limit integer default 50) -- takes how many at most
returns table (id uuid, email text, first_name text, subject text, body text, link text, button text, footer text) -- one email per concern
language plpgsql security definer -- reads and marks concerns
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  return query -- hands back:
  with due as ( -- the concerns to email:
    select c.id from public.safety_concerns c -- each concern
    where c.emailed_at is null and c.recipient_id is not null -- not yet emailed, with someone to email
      and c.created_at > now() - interval '30 days' -- raised in the last 30 days
    order by c.created_at -- oldest first
    limit least(greatest(p_limit, 1), 100) -- at most the number asked for (1 to 100)
    for update skip locked -- so two senders never take the same one
  ), marked as ( -- marks them sent:
    update public.safety_concerns c -- each concern taken
    set email_id = gen_random_uuid(), emailed_at = now() -- gets a new email id and the time
    from due where c.id = due.id -- (only the ones taken)
    returning c.email_id, c.recipient_id, c.sent_to, c.immediate_danger, c.created_at -- what the email needs
  ) -- end of the steps
  select m.email_id, -- the email's id
    ap.email, -- who it goes to
    private.first_name(a.full_name), -- their first name
    case when m.immediate_danger then 'Urgent: a child safety concern was sent to you' else 'A child safety concern was sent to you' end, -- the subject
    'Someone raised a child safety concern in the CLG app on ' -- the message: when,
      || to_char(m.created_at at time zone 'Australia/Adelaide', 'FMDy FMDD FMMon, FMHH12:MI am') || ' (Adelaide time)' -- the time in words,
      || ' and sent it to you as ' || case m.sent_to when 'officer' then 'Child Safety Officer' else 'deputy Child Safety Officer' end || '.' -- and in which job,
      || case when m.immediate_danger then E'\n\nThey said a child may be in immediate danger. Please read it now.' else '' end -- urgent ones say so,
      || E'\n\nTo keep it confidential, the details are only in the app. You''ll need two-step sign-in to open it.', -- and why there are no details
    '/safety/concerns'::text, -- the page the button opens
    'Read the concern'::text, -- the button's words
    'You get this email because CLG has named you as a child safety contact. These emails can''t be turned off.'::text -- the small print
  from marked m -- from the concerns taken
  join public.accounts a on a.id = m.recipient_id -- with the recipient's name
  join public.account_private ap on ap.account_id = m.recipient_id; -- and email
end; -- ends the code
$$; -- end of the function
revoke all on function public.safety_concern_emails_claim(integer) from public, anon, authenticated; -- the server only
grant execute on function public.safety_concern_emails_claim(integer) to service_role; -- the email sender

-- Puts alerts back if sending failed (only ones taken in the last hour).
create or replace function public.safety_concern_emails_release(p_ids uuid[]) -- takes the email ids
returns void -- gives nothing back
language sql security definer -- changes concerns
set search_path = '' -- only fully named tables, for safety
as $$ -- the change
  update public.safety_concerns set email_id = null, emailed_at = null -- clears the email marks
  where email_id = any (p_ids) and emailed_at > now() - interval '1 hour' -- for those emails, taken in the last hour
$$; -- end of the function
revoke all on function public.safety_concern_emails_release(uuid[]) from public, anon, authenticated; -- the server only
grant execute on function public.safety_concern_emails_release(uuid[]) to service_role; -- the email sender

-- Wakes the email sender for concern alerts too. The shared check is
-- extended rather than copied, so changes other modules made to it are kept.
do $$ -- a small block of code
declare -- the working values:
  v_def text; -- the shared check's code
begin -- starts the block
  if to_regprocedure('private.emails_waiting()') is null then -- the shared check isn't there
    return; -- nothing to do
  end if; -- end of the check
  v_def := pg_catalog.pg_get_functiondef('private.emails_waiting()'::regprocedure); -- reads its current code
  if strpos(v_def, 'private.safety_concern_emails_waiting()') = 0 then -- not added yet
    v_def := regexp_replace(v_def, '\s*\$function\$\s*$', E'\n  or private.safety_concern_emails_waiting()\n$function$\n'); -- adds "or a concern alert is waiting" at the end
    execute v_def; -- saves the new code
  end if; -- end of the check
end; -- ends the block
$$; -- end of the code

-- ---------------------------------------------------------------------------
-- To-do number: "Child safety 1" in the top bar for the person who has new
-- concerns. to_do_counts is edited in place, so other changes to it stay.
-- ---------------------------------------------------------------------------
do $$ -- a small block of code
declare -- the working values:
  v_def text; -- the to-do function's code
begin -- starts the block
  v_def := pg_get_functiondef('public.to_do_counts()'::regprocedure); -- reads the current code
  v_def := replace(v_def, chr(13), ''); -- line endings from pasting on Windows
  if strpos(v_def, 'section := ''concerns''') > 0 then -- already added
    return; -- nothing to do
  end if; -- end of the check
  if strpos(v_def, E'  -- Billing (owner, operations and finance).\n') = 0 then -- the place to add it has changed
    raise exception 'to_do_counts has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- end of the check
  v_def := replace(v_def, -- adds the child safety number just before the billing numbers:
    E'  -- Billing (owner, operations and finance).\n', -- the place to add it
    E'  -- Child safety: new concerns sent to this person, not yet opened.\n' -- a comment saying what it is
    || E'  area := ''safety''; section := ''concerns'';\n' -- the area and section names
    || E'  n := (select count(*) from public.safety_concerns where recipient_id = v_me and status = ''new'');\n' -- the count (row level security also applies)
    || E'  return next;\n\n' -- hands back the row
    || E'  -- Billing (owner, operations and finance).\n'); -- and puts back the billing comment
  execute v_def; -- saves the new code
end; -- ends the block
$$; -- end of the code
