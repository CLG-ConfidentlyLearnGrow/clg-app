-- Summary: confidential flag about a CLG worker (Carla, 15 Nov 2026).
--
-- Builds on the child safety concern form (20261113700100). A person raising
-- a concern can now say it is about someone who works for CLG (a tutor or
-- staff member). The rules Carla set:
--   * the person named can never read the concern, its notes, or that they
--     were named, and nothing changes on their screens;
--   * a concern about the Child Safety Officer (Carla) goes to the deputy
--     (Lauren), and one about the deputy goes to the officer, whoever the
--     person raising it picked;
--   * a concern that names BOTH of them goes to both (until CLG has a lawyer,
--     when these will go to the lawyer instead);
--   * the person handling a concern can choose to share it with the other
--     contact, for example Lauren sharing one particular flag about Carla
--     with Carla. Nothing is shared without that choice;
--   * Lauren's emergency owner access never opens concerns (owners can't
--     read concerns that weren't sent to them; that rule is unchanged).
--
-- Needs 20261113700100_child_safety_concerns.sql. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- New tables: who a concern is about, and extra people who may read it
-- ---------------------------------------------------------------------------

-- One row for each CLG worker a concern names.
create table if not exists public.safety_concern_people ( -- the people a concern is about
  concern_id uuid not null references public.safety_concerns (id) on delete cascade, -- which concern
  account_id uuid references public.accounts (id) on delete set null, -- the worker named (empty if their account is later deleted)
  full_name text not null check (char_length(full_name) between 1 and 200), -- their name, copied so the record stays complete
  created_at timestamptz not null default now(), -- when they were named
  id uuid primary key default gen_random_uuid() -- the row's own id (account_id can become empty, so it can't be the key)
); -- end of the table
create unique index if not exists safety_concern_people_once on public.safety_concern_people (concern_id, account_id); -- each person named at most once per concern
create index if not exists safety_concern_people_account on public.safety_concern_people (account_id); -- finds "concerns naming this person" quickly (for the hiding rule)
alter table public.safety_concern_people enable row level security; -- turns on access rules
revoke all on public.safety_concern_people from anon, authenticated; -- written only through the functions below
grant select on public.safety_concern_people to authenticated; -- signed-in people may read, but only the rows the rule below allows

-- Extra people who may read and handle a concern, besides the person it was sent to.
create table if not exists public.safety_concern_readers ( -- one row per extra reader
  concern_id uuid not null references public.safety_concerns (id) on delete cascade, -- which concern
  account_id uuid not null references public.accounts (id) on delete cascade, -- the extra reader
  reason text not null check (reason in ('names_both', 'shared')), -- why: it names both contacts, or it was shared with them
  added_by uuid references public.accounts (id) on delete set null, -- who shared it (empty when the app added them)
  added_at timestamptz not null default now(), -- when they were added
  email_id uuid, -- the id of the alert email being sent to them (empty when none is waiting)
  emailed_at timestamptz, -- when their alert email was handed over to send
  primary key (concern_id, account_id) -- each person once per concern
); -- end of the table
create index if not exists safety_concern_readers_account on public.safety_concern_readers (account_id); -- finds a person's shared concerns quickly
create index if not exists safety_concern_readers_unsent on public.safety_concern_readers (added_at) where emailed_at is null; -- finds alerts still to email quickly
alter table public.safety_concern_readers enable row level security; -- turns on access rules
revoke all on public.safety_concern_readers from anon, authenticated; -- written only through the functions below
grant select on public.safety_concern_readers to authenticated; -- signed-in people may read, but only the rows the rule below allows

-- ---------------------------------------------------------------------------
-- Helpers (these read past the access rules, so the rules can use them
-- without looping back on themselves)
-- ---------------------------------------------------------------------------

-- True when the signed-in person was added as an extra reader of a concern.
create or replace function private.is_concern_reader(p_concern uuid) -- takes the concern
returns boolean -- gives back yes or no
language sql stable security definer -- reads the readers table directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists (select 1 from public.safety_concern_readers where concern_id = p_concern and account_id = auth.uid()) -- they're on the list
$$; -- end of the function
revoke all on function private.is_concern_reader(uuid) from public; -- not for everyone by default
grant execute on function private.is_concern_reader(uuid) to authenticated; -- the access rules and to-do number run as the signed-in person, so they need it (it only answers about themselves)

-- True when a concern names a given account as the person it is about.
create or replace function private.concern_names(p_concern uuid, p_account uuid) -- takes the concern and the account
returns boolean -- gives back yes or no
language sql stable security definer -- reads the people table directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists (select 1 from public.safety_concern_people where concern_id = p_concern and account_id = p_account) -- they're named
$$; -- end of the function
revoke all on function private.concern_names(uuid, uuid) from public; -- for the database's own use only

-- True when a concern names the signed-in person. The access rules use this
-- one, as it can only answer about the person asking.
create or replace function private.concern_names_me(p_concern uuid) -- takes the concern
returns boolean -- gives back yes or no
language sql stable security definer -- reads the people table directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select private.concern_names(p_concern, auth.uid()) -- asks about the signed-in person only
$$; -- end of the function
revoke all on function private.concern_names_me(uuid) from public; -- not for everyone by default
grant execute on function private.concern_names_me(uuid) to authenticated; -- the access rules run as the signed-in person, so they need it

-- True when the signed-in person handles a concern: it was sent to them, or
-- they were added as a reader, and they used two-step sign-in.
create or replace function private.handles_concern(p_concern uuid) -- takes the concern
returns boolean -- gives back yes or no
language sql stable security definer -- reads the concern directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select private.has_aal2() -- two-step sign-in used,
    and ( -- and either:
      exists (select 1 from public.safety_concerns where id = p_concern and recipient_id = auth.uid()) -- it was sent to them,
      or private.is_concern_reader(p_concern) -- or they're an extra reader.
    ) -- end of the either
$$; -- end of the function
revoke all on function private.handles_concern(uuid) from public; -- not for everyone by default
grant execute on function private.handles_concern(uuid) to authenticated; -- the access rules run as the signed-in person, so they need it (it only answers about themselves)

-- ---------------------------------------------------------------------------
-- Access rules (replacing the ones from 20261113700100)
-- ---------------------------------------------------------------------------

-- Concerns: the person handling it (sent to them or added as a reader, with two-step sign-in), or the person who raised it.
drop policy if exists "recipient or raiser reads concern" on public.safety_concerns; -- removes the old rule
drop policy if exists "handler or raiser reads concern" on public.safety_concerns; -- removes this rule if the file is run again
create policy "handler or raiser reads concern" on public.safety_concerns -- the reading rule
  for select to authenticated -- for signed-in people reading
  using ( -- a row is visible when:
    private.handles_concern(id) -- they handle it,
    or raised_by = auth.uid() -- or they raised it.
  ); -- end of the rule

-- A safety net that every other rule must also pass: the person a concern
-- names never sees it, unless they are one of the people handling it (which
-- only happens when it names both contacts, or the handler chose to share it).
drop policy if exists "named person never reads concern" on public.safety_concerns; -- removes this rule if the file is run again
create policy "named person never reads concern" on public.safety_concerns -- the blocking rule
  as restrictive -- "restrictive" means it must pass as well as the rule above
  for select to authenticated -- for signed-in people reading
  using ( -- a row stays visible only when:
    not private.concern_names_me(id) -- they aren't named in it,
    or private.handles_concern(id) -- or they handle it.
  ); -- end of the rule

-- Notes: only the people handling the concern. Not the person who raised it, and never the person named (unless handling).
drop policy if exists "recipient reads notes" on public.safety_concern_notes; -- removes the old rule
drop policy if exists "handler reads notes" on public.safety_concern_notes; -- removes this rule if the file is run again
create policy "handler reads notes" on public.safety_concern_notes -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (private.handles_concern(concern_id)); -- visible to the people handling its concern

-- Who a concern is about: the people handling it, and the person who raised it. Never the person named, unless handling.
drop policy if exists "handler or raiser reads people" on public.safety_concern_people; -- removes this rule if the file is run again
create policy "handler or raiser reads people" on public.safety_concern_people -- the reading rule
  for select to authenticated -- for signed-in people reading
  using ( -- a row is visible when:
    private.handles_concern(concern_id) -- they handle the concern,
    or ( -- or
      exists (select 1 from public.safety_concerns c where c.id = concern_id and c.raised_by = auth.uid()) -- they raised it
      and not private.concern_names_me(concern_id) -- and they aren't named in it.
    ) -- end of the or
  ); -- end of the rule

-- Extra readers: only the people handling the concern can see who else can read it.
drop policy if exists "handler reads readers" on public.safety_concern_readers; -- removes this rule if the file is run again
create policy "handler reads readers" on public.safety_concern_readers -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (private.handles_concern(concern_id)); -- visible to the people handling the concern

-- ---------------------------------------------------------------------------
-- Who can be named
-- ---------------------------------------------------------------------------

-- The CLG workers the signed-in person can name in a concern (names only):
--   * staff (admins and tutors) can name any current staff member;
--   * families can name CLG's admins, and any tutor who has ever been
--     matched with a child they can see (including past tutors).
-- Nobody can name themselves.
create or replace function public.safety_concern_people_choices() -- no inputs
returns table (account_id uuid, full_name text, job text) -- each worker, their name and a short job label
language sql stable security definer -- reads roles and matches for everyone
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select a.id, a.full_name, -- the worker and their name,
    case when exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'admin') then 'CLG staff' else 'Tutor' end -- and "CLG staff" or "Tutor"
  from public.accounts a -- from every account
  where auth.uid() is not null -- only for signed-in people
    and a.id <> auth.uid() -- never themselves
    and ( -- and one of:
      ( -- the person asking is staff, and this is a current staff member;
        private.is_staff_account(auth.uid()) -- the person asking is staff
        and private.is_staff_account(a.id) -- and this account is staff
      ) -- end of the first case
      or exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'admin') -- or this account is a CLG admin;
      or exists ( -- or this account has tutored a child the person asking can see.
        select 1 from public.tutor_assignments t -- a tutor match
        where t.tutor_id = a.id -- for this account
          and private.can_view_student(t.student_id) -- with a child the person asking can see
      ) -- end of the third case
    ) -- end of the "one of"
  order by a.full_name -- in name order
$$; -- end of the function
revoke all on function public.safety_concern_people_choices() from public, anon; -- not for signed-out visitors
grant execute on function public.safety_concern_people_choices() to authenticated; -- signed-in people

-- ---------------------------------------------------------------------------
-- Raising a concern (now with the people it is about)
-- ---------------------------------------------------------------------------

-- The old version (without "who is it about") is removed, so there is only one.
drop function if exists public.raise_safety_concern(uuid, text, public.au_state, public.safety_contact_role, boolean, boolean, text, text, date, text); -- removes the old version

-- Saves a new concern, works out who it goes to, and records who it names.
-- Everything from the old version is kept; the new parts are p_about and
-- the routing.
create or replace function public.raise_safety_concern( -- the inputs:
  p_student uuid, -- the CLG student it's about (or empty)
  p_child_name text, -- the child's name, when not a CLG student
  p_child_state public.au_state, -- the child's state, when not a CLG student
  p_send_to public.safety_contact_role, -- officer or deputy (the person's own pick; changed if it names that person)
  p_immediate_danger boolean, -- whether a child is in immediate danger
  p_called_000 boolean, -- whether they called 000
  p_reported_to_line text, -- yes, no or not_sure
  p_line_reference text, -- the line's reference number (optional)
  p_happened_on date, -- when it happened (optional)
  p_what_happened text, -- what happened
  p_about uuid[] default null -- the CLG workers it is about (optional)
) -- end of the inputs
returns uuid -- gives back the new concern's id
language plpgsql security definer -- saves to tables people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_me uuid := auth.uid(); -- who is raising it
  v_name text; -- the child's name
  v_state public.au_state; -- the child's state
  v_about uuid[] := coalesce(array(select distinct x from unnest(p_about) x where x is not null), '{}'); -- the people named, without blanks or repeats
  v_officer uuid := private.safety_contact('officer'); -- the Child Safety Officer
  v_deputy uuid := private.safety_contact('deputy'); -- the deputy
  v_names_officer boolean; -- whether it names the officer
  v_names_deputy boolean; -- whether it names the deputy
  v_send_to public.safety_contact_role := p_send_to; -- who it will go to (may change below)
  v_recipient uuid; -- the person it goes to
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
  if p_immediate_danger is null then -- the danger question wasn't answered
    raise exception 'Please say whether a child is in immediate danger.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if coalesce(p_reported_to_line, '') not in ('yes', 'no', 'not_sure') then -- the reporting-line question wasn't answered
    raise exception 'Please say whether you have reported this to the child protection line.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_what_happened, ''))) < 10 then -- too little written
    raise exception 'Please describe what happened (at least a sentence).' using errcode = '22023'; -- plain message
  end if; -- end of the check

  -- Checks the people named.
  if cardinality(v_about) > 5 then -- more than five people
    raise exception 'Please name at most five people. You can add more detail in "What happened".' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if v_me = any (v_about) then -- they named themselves
    raise exception 'You can''t name yourself here. Please describe what happened instead.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if exists (select 1 from unnest(v_about) x where x not in (select c.account_id from public.safety_concern_people_choices() c)) then -- someone not on their list
    raise exception 'Please choose people from the list.' using errcode = '42501'; -- plain message
  end if; -- end of the check

  -- Works out who it goes to.
  v_names_officer := v_officer is not null and v_officer = any (v_about); -- names the officer?
  v_names_deputy := v_deputy is not null and v_deputy = any (v_about); -- names the deputy?
  if v_names_officer and v_names_deputy then -- names both:
    v_send_to := 'officer'; -- the officer receives it (the deputy is added as a reader below)
  elsif v_names_officer then -- names only the officer:
    v_send_to := 'deputy'; -- it goes to the deputy
  elsif v_names_deputy then -- names only the deputy:
    v_send_to := 'officer'; -- it goes to the officer
  end if; -- otherwise their own pick stands
  v_recipient := private.safety_contact(v_send_to); -- the person who holds that job
  if v_recipient is null then -- nobody holds it
    if v_names_officer then -- it's about the officer and there's no deputy
      raise exception 'This is about CLG''s Child Safety Officer, and CLG hasn''t named a deputy yet. Please phone the child protection line, and the police if a crime may have happened.' using errcode = '22023'; -- plain message
    end if; -- end of the check
    raise exception 'CLG hasn''t named a % yet. Please phone CLG directly.', -- plain message
      case v_send_to when 'officer' then 'Child Safety Officer' else 'deputy Child Safety Officer' end -- naming the job
      using errcode = '22023'; -- "bad value" code
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
    v_send_to, v_recipient, -- the job and person it goes to,
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

  insert into public.safety_concern_people (concern_id, account_id, full_name) -- records who it's about:
  select v_id, a.id, coalesce(nullif(a.full_name, ''), 'Unknown') -- the concern, the worker and their name
  from public.accounts a where a.id = any (v_about); -- for each person named

  if v_names_officer and v_names_deputy then -- it names both contacts:
    insert into public.safety_concern_readers (concern_id, account_id, reason) -- the deputy can read it too
    values (v_id, v_deputy, 'names_both'); -- (and gets their own alert email)
  end if; -- end of the check

  perform private.log_event('raise_safety_concern', 'safety_concerns', v_id::text, '{}'); -- notes in the activity log that a concern was raised (id only, no details or names)
  return v_id; -- hands back the new id
end; -- ends the code
$$; -- end of the function
revoke all on function public.raise_safety_concern(uuid, text, public.au_state, public.safety_contact_role, boolean, boolean, text, text, date, text, uuid[]) from public, anon; -- not for signed-out visitors
grant execute on function public.raise_safety_concern(uuid, text, public.au_state, public.safety_contact_role, boolean, boolean, text, text, date, text, uuid[]) to authenticated; -- signed-in people

-- ---------------------------------------------------------------------------
-- Handling a concern: readers can now do what the recipient can
-- ---------------------------------------------------------------------------

-- Finds a concern the current person handles, or stops with a plain message.
-- (Same name as before, so notes and "where it's up to" work for readers too.)
create or replace function private.my_received_concern(p_id uuid) -- takes the concern's id
returns public.safety_concerns -- gives back the concern
language plpgsql stable security definer -- reads the concern
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_row public.safety_concerns; -- the concern
begin -- starts the code
  select * into v_row from public.safety_concerns where id = p_id; -- the concern
  if v_row.id is null or not private.handles_concern(p_id) then -- not one they handle (or no two-step sign-in)
    raise exception 'Only the people handling this concern can do that (with two-step sign-in).' using errcode = '42501'; -- plain message
  end if; -- end of the check
  return v_row; -- hands back the concern
end; -- ends the code
$$; -- end of the function
revoke all on function private.my_received_concern(uuid) from public; -- for the database's own use only

-- Passes a concern to the other contact. Now refuses when the other contact
-- is named in it: sharing (below) is the only way a named person can see a
-- concern, and it keeps the current person on it too.
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
  v_row := private.my_received_concern(p_id); -- checks they handle it (stops otherwise)
  if v_row.recipient_id is distinct from auth.uid() then -- they're a reader, not the person it was sent to
    raise exception 'Only the person this concern was sent to can pass it on.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if char_length(btrim(coalesce(p_reason, ''))) < 2 then -- no reason given
    raise exception 'Please say why you are passing this on.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_to_role := case when v_row.sent_to = 'officer' then 'deputy' else 'officer' end; -- the other job
  v_to := private.safety_contact(v_to_role); -- who holds it
  if v_to is null or v_to = auth.uid() then -- nobody else to pass it to
    raise exception 'There is nobody else to pass this to. The owner can name a deputy first.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if private.concern_names(p_id, v_to) then -- the other contact is named in it
    raise exception 'This concern is about the person you would pass it to, so it can''t be passed on. You can choose to share it with them instead.' using errcode = '22023'; -- plain message
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
  delete from public.safety_concern_readers where concern_id = p_id and account_id = v_to; -- they no longer need a reader row (they're the recipient now)
  perform private.log_event('safety_concern_pass_on', 'safety_concerns', p_id::text, '{}'); -- notes the hand-over (id only)
end; -- ends the code
$$; -- end of the function
revoke all on function public.safety_concern_pass_on(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.safety_concern_pass_on(uuid, text) to authenticated; -- signed-in people can try (the check is inside)

-- Shares a concern with the other contact, who can then read and handle it
-- too. The person sharing keeps it. This is how Lauren can choose to show
-- Carla one particular flag about Carla. It can't be undone, so the app asks
-- for a reason, and the reason is kept as a note.
create or replace function public.safety_concern_share(p_id uuid, p_reason text) -- takes the concern and why
returns void -- gives nothing back
language plpgsql security definer -- writes to tables people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_officer uuid := private.safety_contact('officer'); -- the Child Safety Officer
  v_deputy uuid := private.safety_contact('deputy'); -- the deputy
  v_to uuid; -- who it's being shared with
begin -- starts the code
  perform private.my_received_concern(p_id); -- checks they handle it (stops otherwise)
  if char_length(btrim(coalesce(p_reason, ''))) < 2 then -- no reason given
    raise exception 'Please say why you are sharing this.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_to := case when auth.uid() = v_deputy then v_officer else v_deputy end; -- the other contact
  if v_to is null or v_to = auth.uid() then -- nobody else to share with
    raise exception 'There is nobody else to share this with.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if private.handles_concern_account(p_id, v_to) then -- they can already read it
    raise exception 'They can already read this concern.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.safety_concern_readers (concern_id, account_id, reason, added_by) -- adds them as a reader:
  values (p_id, v_to, 'shared', auth.uid()); -- the concern, the person, "shared", and who shared it
  insert into public.safety_concern_notes (concern_id, author_id, author_name, note) -- records the sharing as a note:
  select p_id, a.id, a.full_name, -- the concern, who shared it and their name,
    left('Shared with ' || coalesce((select full_name from public.accounts where id = v_to), 'the other contact') || '. Reason: ' || btrim(p_reason), 4000) -- who with, and why
  from public.accounts a where a.id = auth.uid(); -- from their account
  perform private.log_event('safety_concern_share', 'safety_concerns', p_id::text, '{}'); -- notes the sharing (id only)
end; -- ends the code
$$; -- end of the function
revoke all on function public.safety_concern_share(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.safety_concern_share(uuid, text) to authenticated; -- signed-in people can try (the check is inside)

-- True when a given account (not just the signed-in person) can already read a concern as its recipient or a reader.
create or replace function private.handles_concern_account(p_concern uuid, p_account uuid) -- takes the concern and the account
returns boolean -- gives back yes or no
language sql stable security definer -- reads the concern and readers directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists (select 1 from public.safety_concerns where id = p_concern and recipient_id = p_account) -- it was sent to them,
    or exists (select 1 from public.safety_concern_readers where concern_id = p_concern and account_id = p_account) -- or they're a reader
$$; -- end of the function
revoke all on function private.handles_concern_account(uuid, uuid) from public; -- for the database's own use only

-- If the person a concern was sent to has their account deleted, the
-- concern moves to the other contact, but never to someone it names.
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
      and not private.concern_names(new.id, a.id) -- and not someone the concern is about
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

-- ---------------------------------------------------------------------------
-- Alert emails for extra readers (no names or details, only "open the app")
-- ---------------------------------------------------------------------------

-- Any reader alert waiting to be emailed? (Sent straight away, even in quiet hours.)
create or replace function private.safety_reader_emails_waiting() -- no inputs
returns boolean -- gives back yes or no
language sql stable security definer -- reads the readers table
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- is there one:
    select 1 from public.safety_concern_readers -- a reader row
    where emailed_at is null and added_at > now() - interval '30 days' -- not yet emailed, added in the last 30 days
  ) -- end of the check
$$; -- end of the function
revoke all on function private.safety_reader_emails_waiting() from public; -- for the database's own use only

-- Hands waiting reader alerts to the email sender and marks them sent.
create or replace function public.safety_reader_emails_claim(p_limit integer default 50) -- takes how many at most
returns table (id uuid, email text, first_name text, subject text, body text, link text, button text, footer text) -- one email per reader
language plpgsql security definer -- reads and marks reader rows
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  return query -- hands back:
  with due as ( -- the reader rows to email:
    select r.concern_id, r.account_id from public.safety_concern_readers r -- each reader row
    where r.emailed_at is null and r.added_at > now() - interval '30 days' -- not yet emailed, added in the last 30 days
    order by r.added_at -- oldest first
    limit least(greatest(p_limit, 1), 100) -- at most the number asked for (1 to 100)
    for update skip locked -- so two senders never take the same one
  ), marked as ( -- marks them sent:
    update public.safety_concern_readers r -- each row taken
    set email_id = gen_random_uuid(), emailed_at = now() -- gets a new email id and the time
    from due where r.concern_id = due.concern_id and r.account_id = due.account_id -- (only the ones taken)
    returning r.email_id, r.account_id, r.reason, r.concern_id -- what the email needs
  ) -- end of the steps
  select m.email_id, -- the email's id
    ap.email, -- who it goes to
    private.first_name(a.full_name), -- their first name
    case when c.immediate_danger then 'Urgent: a child safety concern was shared with you' else 'A child safety concern was shared with you' end, -- the subject
    case m.reason -- the message, depending on why they can read it:
      when 'names_both' then 'Someone raised a child safety concern in the CLG app that names both child safety contacts, so it was sent to both of you.' -- it names both of them
      else 'The person handling a child safety concern in the CLG app has shared it with you.' -- or it was shared with them
    end -- end of the choice
      || case when c.immediate_danger then E'\n\nThey said a child may be in immediate danger. Please read it now.' else '' end -- urgent ones say so,
      || E'\n\nTo keep it confidential, the details are only in the app. You''ll need two-step sign-in to open it.', -- and why there are no details
    '/safety/concerns'::text, -- the page the button opens
    'Read the concern'::text, -- the button's words
    'You get this email because CLG has named you as a child safety contact. These emails can''t be turned off.'::text -- the small print
  from marked m -- from the rows taken
  join public.safety_concerns c on c.id = m.concern_id -- with their concern (for "urgent")
  join public.accounts a on a.id = m.account_id -- with the reader's name
  join public.account_private ap on ap.account_id = m.account_id; -- and email
end; -- ends the code
$$; -- end of the function
revoke all on function public.safety_reader_emails_claim(integer) from public, anon, authenticated; -- the server only
grant execute on function public.safety_reader_emails_claim(integer) to service_role; -- the email sender

-- Puts reader alerts back if sending failed (only ones taken in the last hour).
create or replace function public.safety_reader_emails_release(p_ids uuid[]) -- takes the email ids
returns void -- gives nothing back
language sql security definer -- changes reader rows
set search_path = '' -- only fully named tables, for safety
as $$ -- the change
  update public.safety_concern_readers set email_id = null, emailed_at = null -- clears the email marks
  where email_id = any (p_ids) and emailed_at > now() - interval '1 hour' -- for those emails, taken in the last hour
$$; -- end of the function
revoke all on function public.safety_reader_emails_release(uuid[]) from public, anon, authenticated; -- the server only
grant execute on function public.safety_reader_emails_release(uuid[]) to service_role; -- the email sender

-- Wakes the email sender for reader alerts too. The shared check is
-- extended rather than copied, so changes other modules made to it are kept.
do $$ -- a small block of code
declare -- the working values:
  v_def text; -- the shared check's code
begin -- starts the block
  if to_regprocedure('private.emails_waiting()') is null then -- the shared check isn't there
    return; -- nothing to do
  end if; -- end of the check
  v_def := pg_catalog.pg_get_functiondef('private.emails_waiting()'::regprocedure); -- reads its current code
  if strpos(v_def, 'private.safety_reader_emails_waiting()') = 0 then -- not added yet
    v_def := regexp_replace(v_def, '\s*\$function\$\s*$', E'\n  or private.safety_reader_emails_waiting()\n$function$\n'); -- adds "or a reader alert is waiting" at the end
    execute v_def; -- saves the new code
  end if; -- end of the check
end; -- ends the block
$$; -- end of the code

-- ---------------------------------------------------------------------------
-- To-do number: new concerns now count for readers too
-- ---------------------------------------------------------------------------
do $$ -- a small block of code
declare -- the working values:
  v_def text; -- the to-do function's code
  v_old text := 'where recipient_id = v_me and status = ''new'''; -- the old count's condition
begin -- starts the block
  v_def := pg_get_functiondef('public.to_do_counts()'::regprocedure); -- reads the current code
  v_def := replace(v_def, chr(13), ''); -- line endings from pasting on Windows
  if strpos(v_def, 'private.is_concern_reader(id)') > 0 then -- already changed
    return; -- nothing to do
  end if; -- end of the check
  if strpos(v_def, v_old) = 0 then -- the line to change isn't there
    raise exception 'to_do_counts has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- end of the check
  v_def := replace(v_def, v_old, 'where (recipient_id = v_me or private.is_concern_reader(id)) and status = ''new'''); -- counts concerns sent to them or shared with them
  execute v_def; -- saves the new code
end; -- ends the block
$$; -- end of the code
