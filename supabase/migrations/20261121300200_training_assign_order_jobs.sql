-- Training (module: training): Carla's 18 Nov 2026 rules for assigning
-- modules, doing them in order, and being ready for a job.
--
--   * Assigning: a full admin can assign any published module to a tutor or
--     admin staff member, with a due date. An assigned module shows in their
--     To do list with that date (overdue after it), and is paid for its set
--     time when they finish it, even if it is optional. Doing other training
--     outside the time CLG gives is only paid with CLG's approval first
--     (logged under My pay, as before).
--   * In order: modules ticked "Must be done in order" (the safety modules 1
--     to 8) can only be finished once every earlier module with that tick is
--     done.
--   * Ready for a job: a module can be marked as needed before drafting work
--     or before a term review (18 and 19, 24 and 25). When a tutor is given a
--     term review to write and has not finished those modules, the modules
--     are assigned to them, due by the review's due date, and the tutor and
--     admins are told. Admins can see who is ready for each job. (The app
--     does not book drafting jobs yet, so Lauren checks the "Ready for"
--     column before giving one.)
--
-- Only training's own tables are written. Term reviews (module: progress)
-- are only read, by a trigger that runs when a review is made.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. New module settings: done in order, and needed before a job.
-- ---------------------------------------------------------------------------
alter table public.training_modules add column if not exists in_order boolean not null default false; -- must be finished in order (with the other modules that have this ticked)
alter table public.training_modules add column if not exists needed_for text; -- a job it is needed before: drafting, term_review, or blank
alter table public.training_modules drop constraint if exists training_modules_needed_for_check; -- removes the old rule (so this file can run twice)
alter table public.training_modules add constraint training_modules_needed_for_check check (needed_for is null or needed_for in ('drafting', 'term_review')); -- only those two jobs
grant update (in_order, needed_for) on public.training_modules to authenticated; -- admins can change these in Training setup (the access rules still apply)

-- The safety modules (1 to 8) are done in order; 18 and 19 come before drafting, 24 and 25 before term reviews.
update public.training_modules set in_order = true -- ticks "done in order"
where id in ('7a000000-0000-4000-8000-000000000001', '7a000000-0000-4000-8000-000000000002', '7a000000-0000-4000-8000-000000000003', '7a000000-0000-4000-8000-000000000004', -- modules 1 to 4
             '7a000000-0000-4000-8000-000000000005', '7a000000-0000-4000-8000-000000000006', '7a000000-0000-4000-8000-000000000007', '7a000000-0000-4000-8000-000000000008') -- modules 5 to 8
  and not in_order; -- only if not ticked yet
update public.training_modules set needed_for = 'drafting' -- needed before drafting work
where id in ('7a000000-0000-4000-8000-000000000018', '7a000000-0000-4000-8000-000000000019') and needed_for is null; -- modules 18 and 19, if not set yet
update public.training_modules set needed_for = 'term_review' -- needed before a term review
where id in ('7a000000-0000-4000-8000-000000000024', '7a000000-0000-4000-8000-000000000025') and needed_for is null; -- modules 24 and 25, if not set yet

-- ---------------------------------------------------------------------------
-- 2. Assignments: a module given to one person, with a due date.
-- ---------------------------------------------------------------------------
create table if not exists public.training_assignments ( -- the assignments
  account_id uuid not null references public.accounts (id) on delete cascade, -- who it is assigned to (removed with their account)
  module_id uuid not null references public.training_modules (id) on delete cascade, -- which module
  due_on date not null, -- when it is due
  reason text check (reason is null or char_length(reason) <= 300), -- why, for example "Before your first term review"
  assigned_by uuid references public.accounts (id) on delete set null, -- the admin who assigned it (blank when the app did it)
  assigned_at timestamptz not null default now(), -- when it was assigned
  primary key (account_id, module_id) -- one assignment per person per module
); -- end of the table

-- Access rules: the person (two-step login) and full admins can read them; only the steps below write them.
alter table public.training_assignments enable row level security; -- turns on access rules
revoke all on public.training_assignments from anon; -- signed-out visitors get nothing
drop policy if exists "own training assignments, admins all" on public.training_assignments; -- removes the old rule (so this file can run twice)
create policy "own training assignments, admins all" on public.training_assignments -- who can see an assignment
  for select to authenticated using ((account_id = auth.uid() and private.has_aal2()) or private.is_admin()); -- their own, or a full admin
revoke insert, update, delete, truncate on public.training_assignments from authenticated; -- only the steps below write them

-- A full admin assigns a module to someone (or changes the due date).
create or replace function public.training_assign(p_account uuid, p_module uuid, p_due date, p_reason text default null) -- takes the person, module, due date and reason
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  m public.training_modules; -- the module
begin -- start of the steps
  if not (private.is_admin() and private.has_aal2()) then -- not a full admin with two-step login:
    raise exception 'Only CLG owner or operations admins can assign training' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  select * into m from public.training_modules where id = p_module; -- reads the module
  if not found or m.status <> 'published' then -- missing or not published:
    raise exception 'Only published modules can be assigned' using errcode = '22023'; -- refuses, in plain words
  end if; -- end of that check
  if not private.training_fits(p_account, m.audience) then -- the module is not made for this person:
    raise exception 'This module is not made for that person (check who it is for)' using errcode = '22023'; -- refuses, in plain words
  end if; -- end of that check
  if p_due is null or p_due < private.training_today() then -- no date, or a date in the past:
    raise exception 'Please choose a due date from today on' using errcode = '22023'; -- refuses, in plain words
  end if; -- end of that check
  insert into public.training_assignments (account_id, module_id, due_on, reason, assigned_by) -- adds the assignment:
  values (p_account, p_module, p_due, nullif(trim(coalesce(p_reason, '')), ''), auth.uid()) -- who, which module, when, why and by whom
  on conflict (account_id, module_id) do update set -- already assigned: updates it
    due_on = excluded.due_on, reason = excluded.reason, assigned_by = excluded.assigned_by, assigned_at = now(); -- with the new date, reason and admin
  perform private.add_notice(p_account, null, null, 'check_renewal', 'Training assigned: ' || m.title, -- tells the person
    'CLG has assigned you "' || m.title || '" under Training, due by ' || to_char(p_due, 'FMDD FMMonth YYYY') || '. It is paid for its set time when you finish it.', now()); -- what, by when, and that it is paid
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_assign(uuid, uuid, date, text) from public, anon; -- not for signed-out visitors
grant execute on function public.training_assign(uuid, uuid, date, text) to authenticated; -- signed-in people (checked inside)

-- A full admin removes an assignment.
create or replace function public.training_unassign(p_account uuid, p_module uuid) -- takes the person and module
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
begin -- start of the steps
  if not (private.is_admin() and private.has_aal2()) then -- not a full admin with two-step login:
    raise exception 'Only CLG owner or operations admins can change assigned training' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  delete from public.training_assignments where account_id = p_account and module_id = p_module; -- removes it
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_unassign(uuid, uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.training_unassign(uuid, uuid) to authenticated; -- signed-in people (checked inside)

-- ---------------------------------------------------------------------------
-- 3. Where a person is up to: an assigned module is to do (or overdue) by
-- its due date, until they finish it after it was assigned. The existing
-- step is edited in place, so other changes made to it are kept.
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_def text; -- the step's current code
begin -- start
  v_def := pg_catalog.pg_get_functiondef('private.training_state(uuid, uuid)'::regprocedure); -- reads its current code
  if strpos(v_def, 'training_assignments') = 0 then -- not changed yet:
    v_def := regexp_replace(v_def, '(\n\s*v_current boolean;[^\n]*)', -- after the last working value,
      E'\\1\n  v_assign public.training_assignments; -- an admin''s assignment of this module to the person (if any)'); -- adds one for the assignment
    v_def := regexp_replace(v_def, '(\n\s*if not m\.required then)', -- before the "not compulsory" case,
      E'\n  select * into v_assign from public.training_assignments a where a.account_id = p_account and a.module_id = p_module; -- reads any assignment\n'
      || E'  if found and (c.id is null or c.completed_at < v_assign.assigned_at) then -- assigned, and not finished since:\n'
      || E'    return query select case when v_today > v_assign.due_on then ''overdue'' else ''to_do'' end, v_assign.due_on, c.completed_on, c.expires_on, c.id; -- to do by the due date, then overdue\n'
      || E'    return; -- finished\n'
      || E'  end if; -- end of the assigned case\\1'); -- adds the assigned case
    execute v_def; -- saves the changed step
  end if; -- done
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 4. Finishing a module: assigned modules are paid, and "done in order"
-- modules wait for the earlier ones. Edited in place, as above.
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_def text; -- the step's current code
begin -- start
  v_def := pg_catalog.pg_get_functiondef('public.training_finish(uuid, integer[])'::regprocedure); -- reads its current code
  if strpos(v_def, 'training_assignments') = 0 then -- not changed yet:
    v_def := regexp_replace(v_def, '\n(\s*)m\.required, -- paid automatically[^\n]*', -- the "paid when compulsory" line
      E'\n\\1(m.required or exists (select 1 from public.training_assignments a where a.account_id = auth.uid() and a.module_id = p_module)), -- paid automatically when it is compulsory or assigned to them'); -- now also when assigned
    v_def := regexp_replace(v_def, '(available to you'' using errcode = ''42501'';[^\n]*\n\s*end if;[^\n]*)', -- after the "not available to you" check,
      E'\\1\n  if m.in_order and exists ( -- a "done in order" module, with an earlier one\n'
      || E'    select 1 from public.training_modules e cross join lateral private.training_state(auth.uid(), e.id) s -- (each earlier module, with where they are up to)\n'
      || E'    where e.in_order and e.status = ''published'' and e.position < m.position -- also "done in order", published and earlier in the list,\n'
      || E'      and private.training_fits(auth.uid(), e.audience) and s.state not in (''done'', ''renew_soon'')) then -- made for them and not finished:\n'
      || E'    raise exception ''Please finish the earlier modules first. These modules are done in order'' using errcode = ''22023''; -- refuses, in plain words\n'
      || E'  end if; -- end of the order check'); -- adds the order check
    execute v_def; -- saves the changed step
  end if; -- done
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 5. Ready for a job: the modules a person still needs before drafting or a
-- term review (published, made for them, and not finished).
-- ---------------------------------------------------------------------------
create or replace function private.training_job_missing(p_account uuid, p_job text) -- takes the person and the job
returns table (module_id uuid, title text) -- the modules still needed
language sql stable security definer -- reads with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the list:
  select m.id, m.title -- the module
  from public.training_modules m -- from the modules
  cross join lateral private.training_state(p_account, m.id) s -- with where the person is up to
  where m.needed_for = p_job and m.status = 'published' -- needed for this job and published
    and private.training_fits(p_account, m.audience) -- made for them
    and s.state not in ('done', 'renew_soon') -- not finished
  order by m.position, m.title -- in list order
$$; -- end of the function
revoke all on function private.training_job_missing(uuid, text) from public; -- for the database's own use

-- For full admins: each tutor's readiness for drafting and term reviews.
create or replace function public.training_job_readiness() -- no inputs
returns table (account_id uuid, job text, missing text[]) -- the person, the job, and the modules still needed (empty: ready)
language plpgsql stable security definer -- runs steps; reads with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
begin -- start of the steps
  if not private.is_admin() then -- not a full admin:
    raise exception 'Only CLG owner or operations admins can see training progress' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  return query -- gives back:
    select tp.account_id, j.job, -- each tutor and job,
      coalesce((select array_agg(x.title) from private.training_job_missing(tp.account_id, j.job) x), '{}') -- with the modules still needed
    from public.tutor_profiles tp -- from the tutors
    cross join (values ('drafting'), ('term_review')) as j(job) -- for each job
    where tp.active; -- active tutors only
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_job_readiness() from public, anon; -- not for signed-out visitors
grant execute on function public.training_job_readiness() to authenticated; -- signed-in people (checked inside)

-- ---------------------------------------------------------------------------
-- 6. When a tutor is given a term review: if they still need modules, the
-- modules are assigned (due by the review's due date) and everyone is told.
-- ---------------------------------------------------------------------------
create or replace function private.training_term_review_ready() -- runs after a term review is made
returns trigger language plpgsql security definer -- a trigger; runs with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  v_titles text[]; -- the modules still needed
  v_due date; -- when they are due
  v_name text; -- the tutor's name
begin -- start of the steps
  if new.tutor_id is null then return new; end if; -- no tutor yet: nothing to check
  select array_agg(x.title) into v_titles from private.training_job_missing(new.tutor_id, 'term_review') x; -- the modules still needed
  if v_titles is null then return new; end if; -- ready: nothing to do
  v_due := greatest(coalesce(new.due_on, private.training_today() + 14) - 1, private.training_today()); -- due the day before the review is due (never in the past)
  insert into public.training_assignments (account_id, module_id, due_on, reason) -- assigns each module still needed:
  select new.tutor_id, x.module_id, v_due, 'Needed before your term review for ' || new.term_label -- to the tutor, due before the review, with why
  from private.training_job_missing(new.tutor_id, 'term_review') x -- (each module still needed)
  on conflict (account_id, module_id) do update set due_on = least(public.training_assignments.due_on, excluded.due_on); -- already assigned: keeps the earlier date
  select a.full_name into v_name from public.accounts a where a.id = new.tutor_id; -- the tutor's name
  perform private.add_notice(new.tutor_id, null, null, 'check_renewal', 'Training to do before your term review', -- tells the tutor
    'Before you write the ' || new.term_label || ' term review, please finish: ' || array_to_string(v_titles, ', ') || '. You will find them under Training, due by ' || to_char(v_due, 'FMDD FMMonth YYYY') || '. They are paid for their set time.', now()); -- what, by when, and that they are paid
  perform private.notify_admins('Training needed: ' || coalesce(v_name, 'a tutor'), -- tells the admins
    coalesce(v_name, 'A tutor') || ' has been given a term review (' || new.term_label || ') but has not finished: ' || array_to_string(v_titles, ', ') || '. These are now assigned, due by ' || to_char(v_due, 'FMDD FMMonth YYYY') || '.'); -- who, which review and what is missing
  return new; -- the review goes ahead
end; -- end of the steps
$$; -- end of the function
revoke all on function private.training_term_review_ready() from public; -- for the database's own use
drop trigger if exists training_term_review_ready on public.term_reviews; -- removes the old trigger (so this file can run twice)
create trigger training_term_review_ready after insert on public.term_reviews -- runs after each new term review
  for each row execute function private.training_term_review_ready(); -- using the steps above

-- ---------------------------------------------------------------------------
-- 7. The handbook's pay page: assigned modules are paid; other training is
-- only paid with approval first. Swaps one exact line, so other edits to the
-- page are kept; running it again changes nothing.
-- ---------------------------------------------------------------------------
update public.handbook_pages p -- changes a handbook page:
set body = replace(p.body, -- swaps one exact line:
  $t$- Optional training is paid only if CLG agreed to it first. Log it under My pay.$t$, -- the old line
  $t$- Modules CLG assigns to you are paid for their set time, like compulsory ones.
- Any other training you choose to do is paid only if CLG agreed to it first. Log it under My pay.$t$) -- the new lines
where p.id = '7b000000-0000-4000-8000-000000000007'; -- the "Pay, hours and training" page
