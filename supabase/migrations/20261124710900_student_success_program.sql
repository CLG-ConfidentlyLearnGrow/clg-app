-- Summary: the Student Success Program tick box (Carla, 22 Nov 2026).
--
-- Carla's note: "need to have a space where can click or check off or
-- something if a student is part of the Student Success Program, and what
-- year level they are in, then it sets up their student and/or family
-- profile up accordingly." Her answer on what it sets up: "Study plan, term
-- reviews, a program label, book till date range (number of sessions) -
-- these are top priority for matching, as they have already paid the $500
-- deposit to secure their place."
--
-- What this adds (module: progress, which owns the program record, study
-- plans and term reviews):
--   * public.ssp_enrolments: one row per student in the program, with the
--     number of sessions planned, the book-till date, when the deposit was
--     paid, and a note. Owner and Operations admins add or remove students.
--     The student's family and tutors can see that they are in it.
--   * Ticking the box: gives the student the study plan add-on (shared core
--     add-ons list), and from then on each term review offer for the student
--     is accepted straight away at no charge, with the tutor's draft made and
--     the family told it is included.
--   * Matching puts program students at the top of the queue (and of "Fill
--     a tutor's times"), ahead of everyone else, longest waiting first.
--   * The book-till date is saved through scheduling's own set_booking_length
--     (the page calls it), so this module never writes scheduling's tables.
--
-- Safe to run more than once. Run after 20261124710800_policy_versions_read_again.sql.

-- ---------------------------------------------------------------------------
-- 1. The program record
-- ---------------------------------------------------------------------------
create table if not exists public.ssp_enrolments ( -- one row per student in the program
  student_id uuid primary key references public.students (id) on delete cascade, -- the student (removed with their records)
  sessions_planned integer check (sessions_planned between 1 and 200), -- how many sessions the program covers (if known)
  book_until date, -- the last date sessions are booked to
  deposit_paid_on date, -- when the $500 deposit was paid (if recorded)
  note text check (char_length(note) <= 500), -- anything else (optional)
  enrolled_by uuid references public.accounts (id) on delete set null, -- who ticked the box
  enrolled_at timestamptz not null default now(), -- when
  ended_at timestamptz, -- when they left the program (blank while in it)
  ended_by uuid references public.accounts (id) on delete set null -- who removed them
); -- end of the table
alter table public.ssp_enrolments enable row level security; -- access rules apply
revoke all on public.ssp_enrolments from anon; -- signed-out visitors get nothing
revoke insert, update, delete, truncate on public.ssp_enrolments from authenticated; -- changes only through the functions below
grant select on public.ssp_enrolments to authenticated; -- reading, limited by the rule below
drop trigger if exists audit on public.ssp_enrolments; -- replaces the change log trigger if run again
create trigger audit after insert or update or delete on public.ssp_enrolments -- logs every change
  for each row execute function private.audit_change(); -- in the shared change log
drop policy if exists "see program students" on public.ssp_enrolments; -- replaces the rule if run again
create policy "see program students" on public.ssp_enrolments -- who can read a row:
  for select to authenticated -- signed-in people
  using (private.is_front_desk() or private.can_view_student(student_id)); -- front desk admins, and anyone who can see the student (family, their tutors)

-- Is this student in the program now?
create or replace function private.ssp_member(p_student uuid) -- the student
returns boolean language sql stable security definer -- reads the program list for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select exists (select 1 from public.ssp_enrolments e where e.student_id = p_student and e.ended_at is null); -- in it, and not left
$$; -- end of the function
revoke all on function private.ssp_member(uuid) from public; -- inside use only
grant execute on function private.ssp_member(uuid) to authenticated, service_role; -- (matching runs as the caller, so it needs this)

-- ---------------------------------------------------------------------------
-- 2. Ticking and unticking the box (owner and Operations admins)
-- ---------------------------------------------------------------------------
create or replace function public.ssp_enrol( -- puts a student in the program (or updates their details):
  p_student uuid, -- the student
  p_sessions integer default null, -- sessions planned
  p_book_until date default null, -- the book-till date
  p_deposit_paid_on date default null, -- when the deposit was paid
  p_note text default null -- a note
)
returns void language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG''s owner or Operations admins can change the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if not exists (select 1 from public.students where id = p_student) then -- no such student
    raise exception 'That student could not be found' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
  if p_sessions is not null and (p_sessions < 1 or p_sessions > 200) then -- an odd number of sessions
    raise exception 'The number of sessions must be between 1 and 200' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.ssp_enrolments (student_id, sessions_planned, book_until, deposit_paid_on, note, enrolled_by) -- adds them:
  values (p_student, p_sessions, p_book_until, p_deposit_paid_on, nullif(left(btrim(coalesce(p_note, '')), 500), ''), auth.uid()) -- with the details given
  on conflict (student_id) do update set -- or, if they were in it before:
    sessions_planned = excluded.sessions_planned, book_until = excluded.book_until, -- updates the sessions and date,
    deposit_paid_on = excluded.deposit_paid_on, note = excluded.note, -- the deposit and note,
    enrolled_by = case when public.ssp_enrolments.ended_at is null then public.ssp_enrolments.enrolled_by else excluded.enrolled_by end, -- who added them (kept unless rejoining),
    enrolled_at = case when public.ssp_enrolments.ended_at is null then public.ssp_enrolments.enrolled_at else now() end, -- when (kept unless rejoining),
    ended_at = null, ended_by = null; -- and they are in it again
  -- The study plan add-on (shared core): given from today, open-ended.
  insert into public.add_on_members (add_on, student_id, note, created_by) -- gives the add-on:
  select 'study_plans', p_student, 'Student Success Program', auth.uid() -- study plans, for this student, noting why
  where exists (select 1 from public.add_ons where code = 'study_plans') -- if the add-on exists
  on conflict (add_on, student_id) do update set ends_on = null; -- already given: keeps it open-ended
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_enrol(uuid, integer, date, date, text) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_enrol(uuid, integer, date, date, text) to authenticated; -- signed-in people (the check is inside)

create or replace function public.ssp_leave(p_student uuid) -- takes a student out of the program
returns void language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG''s owner or Operations admins can change the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  update public.ssp_enrolments set ended_at = now(), ended_by = auth.uid() where student_id = p_student and ended_at is null; -- marks them as left
  if not found then raise exception 'That student is not in the Student Success Program' using errcode = 'P0002'; end if; -- not in it
  -- The study plan add-on given for the program ends today (one given for another reason is left alone).
  update public.add_on_members set ends_on = greatest(starts_on, (now() at time zone 'Australia/Adelaide')::date) -- ends it today
  where add_on = 'study_plans' and student_id = p_student and note = 'Student Success Program' and ends_on is null; -- only the program's one
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_leave(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_leave(uuid) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- 3. Term reviews are included: each offer is accepted at no charge
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's code
  v_old text := '      if v_offer is not null then -- a new offer:'; -- the line where a new offer is handled
begin -- start
  v_def := replace(pg_get_functiondef('private.queue_term_reviews()'::regprocedure), chr(13), ''); -- reads its current code
  if strpos(v_def, 'ssp_member') > 0 then return; end if; -- already added: nothing to do
  if strpos(v_def, v_old) = 0 then -- the place has changed:
    raise exception 'queue_term_reviews has changed since this update was written. Ask for an updated file.'; -- stops, so nothing half-changes
  end if; -- end of the check
  v_def := replace(v_def, v_old, -- a Student Success Program student first:
    E'      if v_offer is not null and private.ssp_member(r.student_id) then -- a new offer for a Student Success Program student (Carla, 22 Nov 2026):\n'
    || E'        v_count := v_count + 1; -- counts it\n'
    || E'        update public.term_review_offers set answer = ''yes'', no_charge = true, answered_at = now() where id = v_offer; -- accepted at no charge (included in the program)\n'
    || E'        perform private.make_term_review_draft(v_offer); -- makes the tutor''s draft\n'
    || E'        insert into public.progress_notices (account_id, student_id, offer_id, kind, title, body, deliver_at) -- tells the family\n'
    || E'        select f.account_id, r.student_id, v_offer, ''review_booked'', left(''Term review for '' || private.first_name(r.full_name), 200), -- a notice to each person who answers\n'
    || E'               left(''A written term review from '' || private.first_name(r.full_name) || ''''''s tutor is included in the Student Success Program, so there is nothing to pay. CLG checks it before you see it.'', 1000), now() -- that it is included\n'
    || E'        from private.term_review_family(r.student_id) f on conflict do nothing; -- never twice\n'
    || E'      elsif v_offer is not null then -- a new offer:'); -- otherwise the usual offer, as before
  execute v_def; -- saves the changed function
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 4. Matching: program students first
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_def text; -- a function's code
begin -- start
  v_def := replace(pg_get_functiondef('public.matching_queue(text, text, text, text, integer, integer)'::regprocedure), chr(13), ''); -- the queue's code
  if strpos(v_def, 'ssp_member') = 0 then -- not yet changed:
    if strpos(v_def, 'order by r.since, r.student_name, r.subject') = 0 then -- the order line has changed:
      raise exception 'matching_queue has changed since this update was written. Ask for an updated file.'; -- stops
    end if; -- end of the check
    v_def := replace(v_def, 'order by r.since, r.student_name, r.subject', 'order by private.ssp_member(r.student_id) desc, r.since, r.student_name, r.subject'); -- program students first, then as before
    execute v_def; -- saves it
  end if; -- end of the queue
  v_def := replace(pg_get_functiondef('public.matching_tutor_fill(uuid)'::regprocedure), chr(13), ''); -- "Fill a tutor's times"
  if strpos(v_def, 'ssp_member') = 0 then -- not yet changed:
    if strpos(v_def, 'order by m.since, m.student_name, m.subject') = 0 then -- the order line has changed:
      raise exception 'matching_tutor_fill has changed since this update was written. Ask for an updated file.'; -- stops
    end if; -- end of the check
    v_def := replace(v_def, 'order by m.since, m.student_name, m.subject', 'order by private.ssp_member(m.student_id) desc, m.since, m.student_name, m.subject'); -- program students first, then as before
    execute v_def; -- saves it
  end if; -- end of the fill list
end; -- finish
$$; -- end of the block
