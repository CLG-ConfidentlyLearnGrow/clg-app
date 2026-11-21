-- Summary: Progress (module: progress): the plan for the next session, files
-- from a session, and materials linked to the plan (Carla, 21 Nov 2026).
-- See docs/features/session-plans-and-files.md.
--
-- Carla: "Tutors need to send in the summary through the app, but also send
-- in their plan for the next session (in total, these two things are only
-- to take 15 minutes)." The 15 minutes paid after each session is already
-- 5 minutes for the summary and 10 minutes for planning the next session.
-- Carla also asked for a place to upload images and documents from a
-- session for the student to look back on, and a way to link materials to
-- the plan so the tutor knows they are ready and can open them easily.
--
-- What this adds:
--   * session_plans: one plan per session summary (session note). It says
--     what the next session will focus on, how it will be taught, what to
--     review first, how the tutor will know it worked, and any other
--     resources. It is linked to the next booked session with the same
--     tutor, worked out when it is saved. Staff only: the student's current
--     tutors (so a cover tutor can pick it up) and admins. Families already
--     see the "next step" on the summary.
--   * session_plan_materials: materials from CLG's materials library linked
--     to a plan. Only materials the tutor can open can be linked, and they
--     open through the existing stamped-copy route.
--   * session_note_files: images and PDFs from a session (for example a
--     photo of the whiteboard or a worked example), attached to the
--     summary. The student, their family, their current tutors and admins
--     can open them. Files sit in a private file store ("session-files") in
--     a folder named with the student's id, up to 5 MB each, PDF or photo
--     only, at most 10 per session. Tutors can add or remove files for 7
--     days after the summary, like correcting the summary itself.
--   * When a file record is deleted (by the tutor, an admin, or with the
--     student under automatic deletion) its file is queued and removed by
--     the app's daily progress job, as for uploaded evidence.
--   * The concerning-words check also reads plans and file names.
--
-- Access rules wrap private.is_admin() and auth.uid() in (select ...), so
-- the database works them out once per query, not once per row.
-- This module reads sessions (scheduling) and materials (materials) but
-- never writes them.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The private file store for session files.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) -- adds the file store:
values ( -- with these settings:
  'session-files', 'session-files', false, 5242880, -- its name, private (not public), and 5 MB per file at most,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'] -- PDF and photos only
) -- (end of the values)
on conflict (id) do nothing; -- already there (the file was run before): left as it is

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- The plan for the next session, one per session summary.
create table if not exists public.session_plans ( -- the plans table:
  id uuid primary key default gen_random_uuid(), -- the plan's own id
  note_id uuid not null unique references public.session_notes (id) on delete cascade, -- the summary it was written with (one plan each; goes with the summary)
  student_id uuid not null references public.students (id) on delete cascade, -- the student (goes with the student under automatic deletion)
  tutor_id uuid references public.tutor_profiles (account_id) on delete set null, -- the tutor whose plan it is
  next_session_id uuid references public.sessions (id) on delete set null, -- the next booked session it is for (if one was booked when saved)
  focus text not null check (char_length(focus) between 3 and 300), -- what the next session will focus on (the learning intention)
  activities text not null check (char_length(activities) between 3 and 1000), -- how it will be taught: the steps or activities
  review_first text check (char_length(review_first) <= 300), -- what to review at the start (quick recall of earlier work)
  success_check text check (char_length(success_check) <= 300), -- how the tutor will know it worked (success criteria)
  other_resources text check (char_length(other_resources) <= 500), -- other resources: textbook pages, links, equipment
  written_by uuid references public.accounts (id) on delete set null, -- who saved it
  created_at timestamptz not null default now(), -- when it was first saved
  updated_at timestamptz not null default now() -- when it was last changed
); -- end of the table
create index if not exists session_plans_student on public.session_plans (student_id, created_at desc); -- finds a student's latest plans quickly
create index if not exists session_plans_next_session on public.session_plans (next_session_id) where next_session_id is not null; -- finds the plan for a coming session quickly
create index if not exists session_plans_tutor on public.session_plans (tutor_id); -- finds a tutor's plans quickly (and keeps tutor deletions fast)

-- Materials from the materials library linked to a plan.
create table if not exists public.session_plan_materials ( -- the linked materials table:
  plan_id uuid not null references public.session_plans (id) on delete cascade, -- the plan (goes with the plan)
  material_id uuid not null references public.materials (id) on delete cascade, -- the material (goes if the material is deleted)
  primary key (plan_id, material_id) -- each material once per plan
); -- end of the table
create index if not exists session_plan_materials_material on public.session_plan_materials (material_id); -- keeps material deletions fast

-- Images and PDFs from a session, attached to its summary.
create table if not exists public.session_note_files ( -- the session files table:
  id uuid primary key default gen_random_uuid(), -- the file record's own id
  note_id uuid not null references public.session_notes (id) on delete cascade, -- the summary it belongs to (goes with the summary)
  student_id uuid not null references public.students (id) on delete cascade, -- the student (goes with the student under automatic deletion)
  title text not null check (char_length(title) between 2 and 200), -- a short name, for example "Whiteboard: fractions"
  file_path text not null unique check (file_path ~ '^[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$'), -- where it is stored: the student's folder and a file name
  file_type text not null check (file_type in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')), -- PDF or photo only
  uploaded_by uuid references public.accounts (id) on delete set null, -- who added it
  uploaded_at timestamptz not null default now() -- when it was added
); -- end of the table
create index if not exists session_note_files_note on public.session_note_files (note_id); -- finds a summary's files quickly
create index if not exists session_note_files_student on public.session_note_files (student_id, uploaded_at desc); -- finds a student's files quickly

-- Session files waiting to be removed from the file store by the daily job.
create table if not exists public.session_file_removals ( -- the removal queue:
  file_path text primary key, -- the stored file to remove
  queued_at timestamptz not null default now() -- when it was queued
); -- end of the table

-- Access rules on, nothing for people who are not signed in.
alter table public.session_plans enable row level security; -- plans: access rules on
alter table public.session_plan_materials enable row level security; -- linked materials: access rules on
alter table public.session_note_files enable row level security; -- session files: access rules on
alter table public.session_file_removals enable row level security; -- removal queue: access rules on
revoke all on public.session_plans, public.session_plan_materials, public.session_note_files, public.session_file_removals from anon; -- nothing for people not signed in
revoke all on public.session_file_removals from authenticated; -- the queue is for the daily job only
-- Plans and their materials are saved only through public.save_session_plan.
revoke insert, update, delete, truncate on public.session_plans, public.session_plan_materials from authenticated; -- no direct changes
-- Files are added and removed directly (the rules below decide who), never changed.
revoke update, truncate on public.session_note_files from authenticated; -- no edits after upload (remove and add again instead)

-- Every change is logged, and plans keep their "last changed" time.
drop trigger if exists audit on public.session_plans; -- removes the old log trigger if the file is run again
create trigger audit after insert or update or delete on public.session_plans -- logs every change to plans
  for each row execute function private.audit_change(); -- using the app's shared change log
drop trigger if exists audit on public.session_plan_materials; -- removes the old log trigger if the file is run again
create trigger audit after insert or update or delete on public.session_plan_materials -- logs every change to linked materials
  for each row execute function private.audit_change(); -- using the app's shared change log
drop trigger if exists audit on public.session_note_files; -- removes the old log trigger if the file is run again
create trigger audit after insert or update or delete on public.session_note_files -- logs every change to session files
  for each row execute function private.audit_change(); -- using the app's shared change log
drop trigger if exists touch on public.session_plans; -- removes the old time trigger if the file is run again
create trigger touch before update on public.session_plans -- keeps updated_at current
  for each row execute function private.touch_updated_at(); -- using the app's shared helper

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- The student a plan is for (used by the linked materials rule).
create or replace function private.plan_student(p_plan uuid) -- takes a plan id
returns uuid language sql stable security definer -- reads past the access rules (the caller's rule still checks the student)
set search_path = '' -- no hidden schema lookups (safety)
as $$ select student_id from public.session_plans where id = p_plan $$; -- the plan's student
revoke all on function private.plan_student(uuid) from public, anon; -- not for people who are not signed in
grant execute on function private.plan_student(uuid) to authenticated; -- the access rules run it as the signed-in person

-- Whether a stored file is attached to a session file record.
create or replace function private.session_file_in_use(p_name text) -- takes a stored file's name
returns boolean language sql stable security definer -- reads past the access rules
set search_path = '' -- no hidden schema lookups (safety)
as $$ select exists (select 1 from public.session_note_files where file_path = p_name) $$; -- true if a record uses it
revoke all on function private.session_file_in_use(text) from public, anon; -- not for people who are not signed in
grant execute on function private.session_file_in_use(text) to authenticated; -- the access rules run it as the signed-in person

-- Whether the signed-in person may add or remove files on a summary: an
-- admin, or the summary's own tutor (still matched, with two-step sign-in)
-- within 7 days of writing it.
create or replace function private.can_change_session_files(p_note uuid) -- takes a summary id
returns boolean language sql stable security definer -- reads past the access rules
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the check:
  select private.is_admin() -- an admin may,
    or exists ( -- or the tutor, when:
      select 1 from public.session_notes n -- the summary
      where n.id = p_note -- is this one,
        and n.tutor_id = auth.uid() -- they wrote it (it is their session),
        and n.created_at > now() - interval '7 days' -- it is less than 7 days old,
        and private.is_tutor_of(n.student_id) -- and they still teach the student.
    ) -- (end of the tutor check)
$$; -- end of the function
revoke all on function private.can_change_session_files(uuid) from public, anon; -- not for people who are not signed in
grant execute on function private.can_change_session_files(uuid) to authenticated; -- the access rules run it as the signed-in person

-- The next booked session for a student after now, with the given tutor
-- (any tutor if none is given). Used to link a plan to its session.
create or replace function private.next_booked_session(p_student uuid, p_tutor uuid) -- takes the student and the tutor
returns uuid language sql stable security definer -- reads sessions past the access rules
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the lookup:
  select se.id -- the session's id
  from public.sessions se -- from the sessions
  where se.student_id = p_student -- for this student,
    and (p_tutor is null or se.tutor_id = p_tutor) -- with this tutor (if given),
    and se.status = 'scheduled' -- still booked (not cancelled or done),
    and se.starts_at > now() -- and still to come,
  order by se.starts_at -- soonest first,
  limit 1 -- just that one
$$; -- end of the function
revoke all on function private.next_booked_session(uuid, uuid) from public, anon, authenticated; -- only used inside the database

-- ---------------------------------------------------------------------------
-- Access rules
-- ---------------------------------------------------------------------------

-- Plans: the student's current tutors and admins. Never families.
drop policy if exists "staff see session plans" on public.session_plans; -- removes the old rule if the file is run again
create policy "staff see session plans" on public.session_plans -- who can read plans:
  for select to authenticated -- for signed-in people reading,
  using ((select private.is_admin()) or private.is_tutor_of(student_id)); -- admins, or a current tutor of the student

-- Linked materials: the same people as the plan.
drop policy if exists "staff see plan materials" on public.session_plan_materials; -- removes the old rule if the file is run again
create policy "staff see plan materials" on public.session_plan_materials -- who can read linked materials:
  for select to authenticated -- for signed-in people reading,
  using ((select private.is_admin()) or private.is_tutor_of(private.plan_student(plan_id))); -- admins, or a current tutor of the plan's student

-- Session files: everyone who can see the student (the student, their
-- family, their current tutors and admins).
drop policy if exists "see session files" on public.session_note_files; -- removes the old rule if the file is run again
create policy "see session files" on public.session_note_files -- who can read file records:
  for select to authenticated -- for signed-in people reading,
  using ((select private.is_admin()) or private.can_view_student(student_id)); -- admins, or anyone who can see the student
drop policy if exists "tutor adds session files" on public.session_note_files; -- removes the old rule if the file is run again
create policy "tutor adds session files" on public.session_note_files -- who can add file records:
  for insert to authenticated -- for signed-in people adding,
  with check (private.can_change_session_files(note_id)); -- the summary's tutor within 7 days, or an admin
drop policy if exists "tutor removes session files" on public.session_note_files; -- removes the old rule if the file is run again
create policy "tutor removes session files" on public.session_note_files -- who can remove file records:
  for delete to authenticated -- for signed-in people removing,
  using (private.can_change_session_files(note_id)); -- the summary's tutor within 7 days, or an admin

-- The stored files: uploads by the student's tutor or an admin, opened by
-- anyone who can see the student.
drop policy if exists "session files: upload" on storage.objects; -- removes the old rule if the file is run again
create policy "session files: upload" on storage.objects -- who can upload:
  for insert to authenticated -- for signed-in people uploading,
  with check ( -- when:
    bucket_id = 'session-files' -- it is the session files store,
    and private.evidence_folder_student(name) is not null -- the file is in a student's folder,
    and ((select private.is_admin()) or private.is_tutor_of(private.evidence_folder_student(name))) -- and they are an admin or that student's current tutor
  ); -- (end of the rule)
drop policy if exists "session files: open" on storage.objects; -- removes the old rule if the file is run again
create policy "session files: open" on storage.objects -- who can open:
  for select to authenticated -- for signed-in people opening,
  using ( -- when:
    bucket_id = 'session-files' -- it is the session files store,
    and private.evidence_folder_student(name) is not null -- the file is in a student's folder,
    and ((select private.is_admin()) or private.can_view_student(private.evidence_folder_student(name))) -- and they can see that student
  ); -- (end of the rule)
-- Only a file not attached to a record (an upload that failed half way).
drop policy if exists "session files: remove unattached" on storage.objects; -- removes the old rule if the file is run again
create policy "session files: remove unattached" on storage.objects -- who can remove a stray file:
  for delete to authenticated -- for signed-in people removing,
  using ( -- when:
    bucket_id = 'session-files' -- it is the session files store,
    and private.evidence_folder_student(name) is not null -- the file is in a student's folder,
    and ((select private.is_admin()) or private.is_tutor_of(private.evidence_folder_student(name))) -- they are an admin or that student's tutor,
    and not private.session_file_in_use(name) -- and no record uses the file
  ); -- (end of the rule)

-- ---------------------------------------------------------------------------
-- Guards on session files
-- ---------------------------------------------------------------------------

-- Checks a new file record: it matches its summary's student and folder,
-- the file really uploaded, and the summary has fewer than 10 files.
-- Stamps who added it and when.
create or replace function private.guard_session_note_file() -- runs before a file record is added
returns trigger language plpgsql security definer -- reads the summary and file store past the access rules
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if new.student_id is distinct from (select n.student_id from public.session_notes n where n.id = new.note_id) then -- the student does not match the summary:
    raise exception 'That file does not belong to this student''s session' using errcode = '23514'; -- plain message
  end if; -- (end of the check)
  if private.evidence_folder_student(new.file_path) is distinct from new.student_id then -- the file is not in this student's folder:
    raise exception 'That file is not in this student''s folder' using errcode = '23514'; -- plain message
  end if; -- (end of the check)
  if not exists (select 1 from storage.objects where bucket_id = 'session-files' and name = new.file_path) then -- the file is not in the store:
    raise exception 'The file did not upload. Please try again.' using errcode = '23514'; -- plain message
  end if; -- (end of the check)
  if (select count(*) from public.session_note_files f where f.note_id = new.note_id) >= 10 then -- already 10 files on this summary:
    raise exception 'A session can have up to 10 files. Remove one first.' using errcode = '23514'; -- plain message
  end if; -- (end of the check)
  new.uploaded_by := auth.uid(); -- stamps who added it (not what the form said)
  new.uploaded_at := now(); -- stamps when
  return new; -- saves the record
end; -- finish
$$; -- end of the function
drop trigger if exists guard on public.session_note_files; -- removes the old guard if the file is run again
create trigger guard before insert on public.session_note_files -- checks every new file record
  for each row execute function private.guard_session_note_file(); -- using the function above

-- The stored file goes when its record goes (including with the student).
create or replace function private.queue_session_file_removal() -- runs after a file record is deleted
returns trigger language plpgsql security definer -- writes the queue, which people cannot write
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  insert into public.session_file_removals (file_path) values (old.file_path) on conflict do nothing; -- queues the file for the daily job
  return old; -- (an "after" trigger: nothing to change)
end; -- finish
$$; -- end of the function
drop trigger if exists remove_file on public.session_note_files; -- removes the old trigger if the file is run again
create trigger remove_file after delete on public.session_note_files -- after each deleted file record
  for each row execute function private.queue_session_file_removal(); -- queues its file

-- For the app's daily job (secret key only): files to remove, then mark
-- them done.
create or replace function public.session_files_to_remove() -- lists queued files
returns setof text language sql stable security definer -- reads the queue past the access rules
set search_path = '' -- no hidden schema lookups (safety)
as $$ select file_path from public.session_file_removals order by queued_at limit 500 $$; -- up to 500, oldest first
revoke all on function public.session_files_to_remove() from public, anon, authenticated; -- not for people
grant execute on function public.session_files_to_remove() to service_role; -- only the daily job's secret key

create or replace function public.session_files_removed(p_paths text[]) -- clears files the job removed
returns void language sql security definer -- writes the queue past the access rules
set search_path = '' -- no hidden schema lookups (safety)
as $$ delete from public.session_file_removals where file_path = any(p_paths) $$; -- removes them from the queue
revoke all on function public.session_files_removed(text[]) from public, anon, authenticated; -- not for people
grant execute on function public.session_files_removed(text[]) to service_role; -- only the daily job's secret key

-- ---------------------------------------------------------------------------
-- Saving a plan
-- ---------------------------------------------------------------------------
-- Saves (or corrects) the plan for the next session that goes with a
-- summary, with up to 10 linked materials. The summary's own tutor can save
-- or correct it for 7 days after writing the summary; admins at any time.
-- The plan is linked to the next booked session with the same tutor.
create or replace function public.save_session_plan( -- takes:
  p_note uuid, -- the summary the plan goes with,
  p_focus text, -- what the next session will focus on,
  p_activities text, -- how it will be taught,
  p_review_first text default null, -- what to review first (optional),
  p_success_check text default null, -- how the tutor will know it worked (optional),
  p_other_resources text default null, -- other resources (optional),
  p_materials uuid[] default '{}' -- materials library items to link (optional)
) -- (end of the inputs)
returns uuid language plpgsql security definer -- gives back the plan's id; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values:
  v_note public.session_notes; -- the summary
  v_admin boolean := private.is_admin(); -- whether an admin is asking
  v_plan uuid; -- the plan's id
  v_material uuid; -- one linked material
begin -- start
  select * into v_note from public.session_notes where id = p_note; -- reads the summary
  if v_note.id is null then -- no such summary:
    raise exception 'That session summary was not found' using errcode = 'P0002'; -- plain message
  end if; -- (end of the check)
  if not v_admin and not ( -- not an admin, and not:
    v_note.tutor_id = auth.uid() -- the summary's own tutor,
    and private.is_tutor_of(v_note.student_id) -- still teaching the student,
  ) then -- (end of the check)
    raise exception 'Only this student''s tutor can write the plan for the next session' using errcode = '42501'; -- plain message
  end if; -- (end of the check)
  if not v_admin and v_note.created_at <= now() - interval '7 days' then -- the tutor is more than 7 days late:
    raise exception 'Plans can be written or corrected for 7 days after the session summary. Please ask CLG to help.' using errcode = '22023'; -- plain message
  end if; -- (end of the check)
  if char_length(btrim(coalesce(p_focus, ''))) < 3 then -- no focus written:
    raise exception 'Write what the next session will focus on' using errcode = '22023'; -- plain message
  end if; -- (end of the check)
  if char_length(btrim(coalesce(p_activities, ''))) < 3 then -- no activities written:
    raise exception 'Write how you will teach it: the steps or activities' using errcode = '22023'; -- plain message
  end if; -- (end of the check)
  if cardinality(coalesce(p_materials, '{}')) > 10 then -- too many materials:
    raise exception 'Link up to 10 materials for one session' using errcode = '22023'; -- plain message
  end if; -- (end of the check)
  foreach v_material in array coalesce(p_materials, '{}') loop -- for each material to link:
    if not private.can_open_material(v_material) then -- the person cannot open it:
      raise exception 'One of those materials is not available to you' using errcode = '42501'; -- plain message
    end if; -- (end of the check)
  end loop; -- next material

  insert into public.session_plans as sp -- saves the plan:
    (note_id, student_id, tutor_id, next_session_id, focus, activities, review_first, success_check, other_resources, written_by) -- these details,
  values ( -- the values:
    p_note, v_note.student_id, v_note.tutor_id, -- the summary, its student and tutor,
    private.next_booked_session(v_note.student_id, v_note.tutor_id), -- the next booked session with that tutor (or none),
    left(btrim(p_focus), 300), left(btrim(p_activities), 1000), -- the focus and activities,
    left(nullif(btrim(p_review_first), ''), 300), -- what to review first (or none),
    left(nullif(btrim(p_success_check), ''), 300), -- how they will know it worked (or none),
    left(nullif(btrim(p_other_resources), ''), 500), -- other resources (or none),
    auth.uid() -- who saved it
  ) -- (end of the values)
  on conflict (note_id) do update set -- a plan is already there: corrects it:
    focus = excluded.focus, -- the focus,
    activities = excluded.activities, -- the activities,
    review_first = excluded.review_first, -- what to review first,
    success_check = excluded.success_check, -- how they will know it worked,
    other_resources = excluded.other_resources, -- other resources,
    next_session_id = coalesce(excluded.next_session_id, sp.next_session_id), -- the next session (kept if none is booked now),
    written_by = excluded.written_by -- who changed it
  returning id into v_plan; -- keeps the plan's id

  delete from public.session_plan_materials where plan_id = v_plan; -- clears the old list of materials
  insert into public.session_plan_materials (plan_id, material_id) -- links the chosen materials:
  select v_plan, m from unnest(coalesce(p_materials, '{}')) m -- one row each,
  on conflict do nothing; -- each material once

  return v_plan; -- gives back the plan's id
end; -- finish
$$; -- end of the function
revoke all on function public.save_session_plan(uuid, text, text, text, text, text, uuid[]) from public, anon; -- not for people who are not signed in
grant execute on function public.save_session_plan(uuid, text, text, text, text, text, uuid[]) to authenticated; -- signed-in people (the function checks who)

-- ---------------------------------------------------------------------------
-- The concerning-words check also reads plans and file names.
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
begin -- start
  if to_regprocedure('private.scan_watch_words()') is null then return; end if; -- the check is not installed: nothing to do
  drop trigger if exists watch_words_scan on public.session_plans; -- removes the old check if the file is run again
  create trigger watch_words_scan after insert or update of focus, activities, review_first, success_check, other_resources on public.session_plans -- after a new plan or a change to its words,
    for each row execute function private.scan_watch_words('focus', 'activities', 'review_first', 'success_check', 'other_resources'); -- checks those boxes
  drop trigger if exists watch_words_scan on public.session_note_files; -- removes the old check if the file is run again
  create trigger watch_words_scan after insert on public.session_note_files -- after a new file,
    for each row execute function private.scan_watch_words('title'); -- checks its name
end; -- finish
$$; -- end of the block
