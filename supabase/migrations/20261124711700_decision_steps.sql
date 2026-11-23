-- Summary: the decision steps record and decisions log (Carla, 22 Nov 2026).
--
-- From How We Do Things v1.0, section 4: each person has a decision steps
-- record, one line for each kind of problem, showing their current step (1
-- Suggest then ask, 2 Fix then tell, 3 Fix and put in the daily update,
-- 4 Fix and record, 5 Overview only), the date it moved and a short note.
-- Carla moves the steps at accountability check-ins. At Step 4 decisions go
-- in a decisions log, which Carla can read at any time. During probation
-- everything is at Step 1. Carla agreed (22 Nov 2026) that Emma (Operations)
-- can read tutors' records and add notes, and only Carla moves the steps.
--
-- What this adds (module: staff, which owns staff records outside pay):
--   * public.decision_kinds: the kinds of problem, for admin or tutors, with
--     the starting step and goal from the guide's two tables (loaded here).
--   * public.decision_steps: a person's current step for a kind, when it
--     moved and a short note. No row means the kind's starting step.
--   * public.decision_step_moves: every move, so the pathway can be seen.
--   * public.decision_notes: notes from Carla or Operations on a record.
--   * public.decision_log: decisions the person records themselves.
--   * Functions to read a record, move a step (owner), add a note (owner,
--     or Operations for tutors), add to the log (the person), and change
--     the kinds of problem (owner).
--
-- Who sees what (row level security): the person sees their own record,
-- notes and log; CLG's owner sees everyone's; Operations admins see tutors'.
--
-- Safe to run more than once. Run after 20261123400100_staff_probation.sql.

-- ---------------------------------------------------------------------------
-- 1. The kinds of problem
-- ---------------------------------------------------------------------------
create table if not exists public.decision_kinds ( -- one row per kind of problem
  id uuid primary key default gen_random_uuid(), -- the kind's id
  key text unique, -- a fixed name for the starting rows (so loading them again changes nothing)
  audience text not null check (audience in ('admin', 'tutor')), -- whether it is for admin staff or tutors
  title text not null check (char_length(btrim(title)) between 3 and 300), -- the kind of problem, in plain words
  start_step smallint not null check (start_step between 1 and 5), -- the step everyone starts at
  goal_step smallint not null check (goal_step between 1 and 5), -- the step it is expected to reach
  goal_note text check (char_length(goal_note) <= 200), -- extra words for the goal, for example "later"
  position integer not null default 0, -- the order in the list
  active boolean not null default true, -- false hides it without losing records
  created_at timestamptz not null default now() -- when it was added
); -- end of the table
alter table public.decision_kinds enable row level security; -- access rules apply
revoke all on public.decision_kinds from anon; -- signed-out visitors get nothing
revoke insert, update, delete, truncate on public.decision_kinds from authenticated; -- changes only through the functions below
grant select on public.decision_kinds to authenticated; -- reading, limited by the rule below
drop trigger if exists audit on public.decision_kinds; -- replaces the change log trigger if run again
create trigger audit after insert or update or delete on public.decision_kinds for each row execute function private.audit_change(); -- logs every change
drop policy if exists "staff see decision kinds" on public.decision_kinds; -- replaces the rule if run again
create policy "staff see decision kinds" on public.decision_kinds for select to authenticated -- who can read the kinds:
  using ((select private.has_role('tutor')) or (select private.has_role('admin'))); -- every tutor and admin

-- The starting points from How We Do Things v1.0 (section 6). Rows already
-- there are left alone, so Carla's later changes are kept.
insert into public.decision_kinds (key, audience, title, start_step, goal_step, goal_note, position) values -- the rows:
  ('admin_reschedule', 'admin', 'Rescheduling or a change of tutor where both sides agree in the app.', 1, 3, null, 10), -- admin row 1
  ('admin_chasing', 'admin', 'Chasing late approvals, summaries, checks and forms.', 2, 3, null, 20), -- admin row 2
  ('admin_last_minute', 'admin', 'Last-minute session problems (sick tutor, room or link issue).', 1, 2, null, 30), -- admin row 3
  ('admin_match_clear', 'admin', 'Matches where the right tutor is clear.', 1, 3, null, 40), -- admin row 4
  ('admin_match_unclear', 'admin', 'Matches where suitability is unclear.', 1, 3, 'later', 50), -- admin row 5
  ('admin_minor_concerns', 'admin', 'Minor family or tutor concerns (not complaints).', 1, 3, null, 60), -- admin row 6
  ('admin_small_fixes', 'admin', 'Small fixes to templates, wording or how-to guides.', 1, 3, null, 70), -- admin row 7
  ('admin_app_glitches', 'admin', 'App glitches with a known workaround (always report the bug).', 1, 3, null, 80), -- admin row 8
  ('admin_social', 'admin', 'Social posts, newsletter and reviews using approved templates.', 1, 3, null, 90), -- admin row 9
  ('admin_process', 'admin', 'Improving an admin process that does not change what families or tutors see.', 1, 2, null, 100), -- admin row 10
  ('tutor_late_no_show', 'tutor', 'A student is late or does not show up.', 2, 4, null, 10), -- tutor row 1
  ('tutor_move_session', 'tutor', 'Moving a session where both sides agree in the app.', 1, 3, null, 20), -- tutor row 2
  ('tutor_link_room', 'tutor', 'A link, room or resource problem during a session.', 2, 3, null, 30), -- tutor row 3
  ('tutor_change_plan', 'tutor', 'Changing the session plan when it does not suit the student that day.', 3, 4, null, 40), -- tutor row 4
  ('tutor_struggling', 'tutor', 'A student is struggling more than expected or may need different support.', 1, 2, null, 50), -- tutor row 5
  ('tutor_progress_question', 'tutor', 'A family asks about their child''s progress.', 1, 3, null, 60), -- tutor row 6
  ('tutor_money_question', 'tutor', 'A family asks about prices, payments or refunds.', 1, 1, 'for now (money sits with Carla)', 70) -- tutor row 7
on conflict (key) do nothing; -- keeps any row already there

-- ---------------------------------------------------------------------------
-- 2. Each person's steps, the moves, notes and the decisions log
-- ---------------------------------------------------------------------------
create table if not exists public.decision_steps ( -- a person's current step for one kind of problem
  account_id uuid not null references public.accounts (id) on delete cascade, -- the staff member
  kind_id uuid not null references public.decision_kinds (id) on delete cascade, -- the kind of problem
  step smallint not null check (step between 1 and 5), -- their current step
  moved_on date not null default (now() at time zone 'Australia/Adelaide')::date, -- the date it last moved
  note text check (char_length(note) <= 1000), -- a short note (why it moved)
  updated_by uuid references public.accounts (id) on delete set null, -- who moved it
  primary key (account_id, kind_id) -- one line per person and kind
); -- end of the table
create table if not exists public.decision_step_moves ( -- every move of a step
  id uuid primary key default gen_random_uuid(), -- the move's id
  account_id uuid not null references public.accounts (id) on delete cascade, -- the staff member
  kind_id uuid not null references public.decision_kinds (id) on delete cascade, -- the kind of problem
  from_step smallint not null check (from_step between 1 and 5), -- the step before
  to_step smallint not null check (to_step between 1 and 5), -- the step after
  note text check (char_length(note) <= 1000), -- why
  moved_by uuid references public.accounts (id) on delete set null, -- who moved it
  moved_at timestamptz not null default now() -- when
); -- end of the table
create index if not exists decision_step_moves_account on public.decision_step_moves (account_id, moved_at desc); -- finds a person's moves quickly
create table if not exists public.decision_notes ( -- notes on a person's record
  id uuid primary key default gen_random_uuid(), -- the note's id
  account_id uuid not null references public.accounts (id) on delete cascade, -- the staff member the note is about
  kind_id uuid references public.decision_kinds (id) on delete set null, -- the kind of problem (optional)
  author_id uuid references public.accounts (id) on delete set null, -- who wrote it
  body text not null check (char_length(btrim(body)) between 2 and 2000), -- the note
  created_at timestamptz not null default now() -- when
); -- end of the table
create index if not exists decision_notes_account on public.decision_notes (account_id, created_at desc); -- finds a person's notes quickly
create table if not exists public.decision_log ( -- decisions a person records themselves (Step 4)
  id uuid primary key default gen_random_uuid(), -- the entry's id
  account_id uuid not null references public.accounts (id) on delete cascade, -- who made the decision
  kind_id uuid references public.decision_kinds (id) on delete set null, -- the kind of problem (optional)
  problem text not null check (char_length(btrim(problem)) between 2 and 2000), -- the problem
  options text not null check (char_length(btrim(options)) between 2 and 2000), -- the options considered (at least three)
  choice text not null check (char_length(btrim(choice)) between 2 and 2000), -- the one chosen, and why
  done boolean not null default true, -- whether it is done
  created_at timestamptz not null default now() -- when it was recorded
); -- end of the table
create index if not exists decision_log_account on public.decision_log (account_id, created_at desc); -- finds a person's log quickly

-- Can the signed-in person read this staff member's record? Their own; the
-- owner for everyone; Operations admins for tutors.
create or replace function private.can_read_decision_record(p_account uuid) -- takes the staff member
returns boolean language sql stable security definer -- reads roles
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the answer
  select coalesce(p_account = auth.uid(), false) -- their own,
    or private.is_owner() -- or the owner,
    or (coalesce(private.my_admin_level() = 'operations', false) and exists (select 1 from public.account_roles where account_id = p_account and role = 'tutor')) -- or Operations, for a tutor (blanks count as no)
$$; -- end of the answer
revoke all on function private.can_read_decision_record(uuid) from public; -- inside use only
grant execute on function private.can_read_decision_record(uuid) to authenticated; -- used by the access rules below

-- The same access rules for all four tables.
do $$ -- a short block that repeats the setup for each table
declare -- working values
  t text; -- each table name
begin -- start
  foreach t in array array['decision_steps', 'decision_step_moves', 'decision_notes', 'decision_log'] loop -- each table:
    execute format('alter table public.%I enable row level security', t); -- access rules apply
    execute format('revoke all on public.%I from anon', t); -- signed-out visitors get nothing
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t); -- changes only through the functions below
    execute format('grant select on public.%I to authenticated', t); -- reading, limited by the rule below
    execute format('drop trigger if exists audit on public.%I', t); -- replaces the change log trigger if run again
    execute format('create trigger audit after insert or update or delete on public.%I for each row execute function private.audit_change()', t); -- logs every change
    execute format('drop policy if exists "read decision record" on public.%I', t); -- replaces the rule if run again
    execute format('create policy "read decision record" on public.%I for select to authenticated using ((select private.can_read_decision_record(account_id)))', t); -- who can read: see the function above
  end loop; -- next table
end; -- end of the block
$$; -- end of the setup

-- ---------------------------------------------------------------------------
-- 3. Reading a record
-- ---------------------------------------------------------------------------
-- One line per kind of problem for the person's roles: the current step
-- (Step 1 while on probation for that role), when it moved, and the note.
create or replace function public.decision_record(p_account uuid) -- takes the staff member
returns table (kind_id uuid, audience text, title text, step smallint, on_probation boolean, moved_on date, note text, start_step smallint, goal_step smallint, goal_note text) -- the lines
language plpgsql stable security definer -- reads for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.can_read_decision_record(p_account) then -- not allowed
    raise exception 'You cannot see this decision steps record.' using errcode = '42501'; -- plain refusal
  end if; -- end of the check
  return query -- hands back:
  select k.id, k.audience, k.title, -- the kind,
    (case when p.account_id is not null then 1 else coalesce(s.step, k.start_step) end)::smallint, -- Step 1 on probation, otherwise their step or the starting step,
    p.account_id is not null, -- whether they are on probation for this role,
    s.moved_on, s.note, k.start_step, k.goal_step, k.goal_note -- when it moved, the note, and the guide's start and goal
  from public.decision_kinds k -- each kind
  join public.account_roles ar on ar.account_id = p_account and ar.role::text = k.audience -- that matches one of their roles
  left join public.decision_steps s on s.account_id = p_account and s.kind_id = k.id -- their step, if set
  left join public.staff_probations p on p.account_id = p_account and p.kind = k.audience and p.status = 'on_probation' -- their probation, if any
  where k.active -- only kinds in use
  order by k.audience, k.position, k.title; -- in the guide's order
end; -- end of the code
$$; -- end of the function
revoke all on function public.decision_record(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.decision_record(uuid) to authenticated; -- signed-in people (the check is inside)

-- The staff whose records the signed-in person can open (for the list page).
create or replace function public.decision_record_people() -- no inputs
returns table (account_id uuid, full_name text, roles text[]) -- each person
language sql stable security definer -- reads for them; limited inside
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the list
  select a.id, a.full_name, array_agg(distinct ar.role::text order by ar.role::text) -- each person, with their staff roles
  from public.accounts a join public.account_roles ar on ar.account_id = a.id and ar.role in ('tutor', 'admin') -- staff only
  where a.id <> auth.uid() and private.can_read_decision_record(a.id) -- other people they may read
  group by a.id, a.full_name order by a.full_name -- one line each, by name
$$; -- end of the list
revoke all on function public.decision_record_people() from public, anon; -- not for signed-out visitors
grant execute on function public.decision_record_people() to authenticated; -- signed-in people (limited inside)

-- ---------------------------------------------------------------------------
-- 4. Changing a record
-- ---------------------------------------------------------------------------
create or replace function public.decision_step_move(p_account uuid, p_kind uuid, p_step integer, p_note text) -- moves a step (owner only)
returns void language plpgsql security definer -- writes for the owner; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  k public.decision_kinds; -- the kind of problem
  v_from smallint; -- the step before
begin -- start
  if not private.is_owner() then raise exception 'Only Carla (CLG''s owner) moves decision steps.' using errcode = '42501'; end if; -- owner only
  if p_step is null or p_step not between 1 and 5 then raise exception 'Please choose a step from 1 to 5.' using errcode = '22023'; end if; -- a real step
  select * into k from public.decision_kinds where id = p_kind; -- reads the kind
  if k.id is null or not exists (select 1 from public.account_roles where account_id = p_account and role::text = k.audience) then -- unknown, or not for this person
    raise exception 'That kind of problem is not part of this person''s record.' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
  select coalesce((select step from public.decision_steps where account_id = p_account and kind_id = p_kind), k.start_step) into v_from; -- the step before (or the starting step)
  insert into public.decision_steps (account_id, kind_id, step, moved_on, note, updated_by) -- saves the new step:
  values (p_account, p_kind, p_step, (now() at time zone 'Australia/Adelaide')::date, nullif(left(btrim(coalesce(p_note, '')), 1000), ''), auth.uid()) -- with today's date and the note
  on conflict (account_id, kind_id) do update set step = excluded.step, moved_on = excluded.moved_on, note = excluded.note, updated_by = excluded.updated_by; -- or updates the line already there
  insert into public.decision_step_moves (account_id, kind_id, from_step, to_step, note, moved_by) -- records the move
  values (p_account, p_kind, v_from, p_step, nullif(left(btrim(coalesce(p_note, '')), 1000), ''), auth.uid()); -- from, to, why and who
  if p_account <> auth.uid() then -- tells the person (unless Carla moved her own):
    perform private.add_notice(p_account, null, null, 'staff_alert', 'Your decision steps record changed', -- a staff notice
      left('"' || k.title || '" is now at Step ' || p_step || ' (was Step ' || v_from || ').' || coalesce(' Note: ' || nullif(btrim(coalesce(p_note, '')), ''), '') || ' See Decision steps.', 1000), now()); -- what, and any note
  end if; -- end of the choice
end; -- end of the code
$$; -- end of the function
revoke all on function public.decision_step_move(uuid, uuid, integer, text) from public, anon; -- not for signed-out visitors
grant execute on function public.decision_step_move(uuid, uuid, integer, text) to authenticated; -- signed-in people (the check is inside)

create or replace function public.decision_note_add(p_account uuid, p_kind uuid, p_body text) -- adds a note to a record (owner, or Operations for tutors)
returns uuid language plpgsql security definer -- writes for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_id uuid; -- the new note
begin -- start
  if p_account = auth.uid() or not private.can_read_decision_record(p_account) or not (private.is_owner() or coalesce(private.my_admin_level() = 'operations', false)) then -- only the owner, or Operations for a tutor, on someone else
    raise exception 'Only Carla, or Operations admins for tutors, add notes to a decision steps record.' using errcode = '42501'; -- plain refusal
  end if; -- end of the check
  if char_length(btrim(coalesce(p_body, ''))) < 2 then raise exception 'Please write the note.' using errcode = '22023'; end if; -- a note is needed
  insert into public.decision_notes (account_id, kind_id, author_id, body) values (p_account, p_kind, auth.uid(), left(btrim(p_body), 2000)) returning id into v_id; -- saves it
  return v_id; -- hands back its id
end; -- end of the code
$$; -- end of the function
revoke all on function public.decision_note_add(uuid, uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.decision_note_add(uuid, uuid, text) to authenticated; -- signed-in people (the check is inside)

create or replace function public.decision_log_add(p_kind uuid, p_problem text, p_options text, p_choice text, p_done boolean) -- the person adds to their own decisions log
returns uuid language plpgsql security definer -- writes for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_id uuid; -- the new entry
begin -- start
  if not (private.has_role('tutor') or private.has_role('admin')) then raise exception 'Only CLG tutors and admin staff keep a decisions log.' using errcode = '42501'; end if; -- staff only
  if char_length(btrim(coalesce(p_problem, ''))) < 2 or char_length(btrim(coalesce(p_options, ''))) < 2 or char_length(btrim(coalesce(p_choice, ''))) < 2 then -- missing words
    raise exception 'Please write the problem, the options you considered, and the one you chose and why.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_kind is not null and not exists (select 1 from public.decision_kinds k join public.account_roles ar on ar.role::text = k.audience and ar.account_id = auth.uid() where k.id = p_kind) then -- a kind that is not theirs
    raise exception 'That kind of problem is not part of your record.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.decision_log (account_id, kind_id, problem, options, choice, done) -- saves it:
  values (auth.uid(), p_kind, left(btrim(p_problem), 2000), left(btrim(p_options), 2000), left(btrim(p_choice), 2000), coalesce(p_done, true)) returning id into v_id; -- with their words
  return v_id; -- hands back its id
end; -- end of the code
$$; -- end of the function
revoke all on function public.decision_log_add(uuid, text, text, text, boolean) from public, anon; -- not for signed-out visitors
grant execute on function public.decision_log_add(uuid, text, text, text, boolean) to authenticated; -- signed-in people (the check is inside)

create or replace function public.decision_kind_save(p_id uuid, p_audience text, p_title text, p_start integer, p_goal integer, p_goal_note text, p_active boolean) -- adds or changes a kind of problem (owner only)
returns uuid language plpgsql security definer -- writes for the owner; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_id uuid; -- the kind
begin -- start
  if not private.is_owner() then raise exception 'Only Carla (CLG''s owner) changes the kinds of problem.' using errcode = '42501'; end if; -- owner only
  if p_audience is null or p_audience not in ('admin', 'tutor') then raise exception 'Please choose admin or tutors.' using errcode = '22023'; end if; -- who it is for
  if char_length(btrim(coalesce(p_title, ''))) < 3 then raise exception 'Please describe the kind of problem.' using errcode = '22023'; end if; -- a title
  if p_start is null or p_goal is null or p_start not between 1 and 5 or p_goal not between 1 and 5 then raise exception 'Please choose steps from 1 to 5.' using errcode = '22023'; end if; -- real steps
  if p_id is null then -- a new kind:
    insert into public.decision_kinds (audience, title, start_step, goal_step, goal_note, position) -- adds it at the end of its list
    values (p_audience, left(btrim(p_title), 300), p_start, p_goal, nullif(left(btrim(coalesce(p_goal_note, '')), 200), ''), coalesce((select max(position) from public.decision_kinds where audience = p_audience), 0) + 10) returning id into v_id; -- with its words and steps
  else -- a change:
    update public.decision_kinds set audience = p_audience, title = left(btrim(p_title), 300), start_step = p_start, goal_step = p_goal, -- the new words and steps
      goal_note = nullif(left(btrim(coalesce(p_goal_note, '')), 200), ''), active = coalesce(p_active, true) where id = p_id returning id into v_id; -- the goal note and whether it is in use
    if v_id is null then raise exception 'That kind of problem could not be found.' using errcode = 'P0002'; end if; -- not there
  end if; -- end of the choice
  return v_id; -- hands back its id
end; -- end of the code
$$; -- end of the function
revoke all on function public.decision_kind_save(uuid, text, text, integer, integer, text, boolean) from public, anon; -- not for signed-out visitors
grant execute on function public.decision_kind_save(uuid, text, text, integer, integer, text, boolean) to authenticated; -- signed-in people (the check is inside)
