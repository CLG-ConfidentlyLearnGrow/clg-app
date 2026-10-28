-- Progress tracking, part 5 (module: progress): evidence of learning and
-- the family upload portal. See docs/features/learning-evidence.md.
--
-- Families and students upload graded school work, school reports, NAPLAN
-- results and other assessments from a phone camera or a file. Tutors add
-- samples of work from sessions. Each upload has a subject, a date and,
-- once the tutor has looked at it, the skills it shows. Uploads help set the
-- starting point and show where to focus; no single upload decides a level.
--
-- Files sit in a private file store ("learning-evidence"), in a folder named
-- with the student's id. Only people who can see the student can open them:
-- the family, the student's current tutors (with two-step login) and admins.
-- When a record is deleted (by the family, or with the student under
-- automatic deletion) its file is queued and removed by the app's daily job,
-- because files can only be deleted through the file store itself.
--
-- Safe to run more than once.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'learning-evidence', 'learning-evidence', false, 5242880,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.learning_evidence (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  kind text not null check (kind in ('graded_work', 'school_report', 'naplan', 'other_assessment', 'work_sample')),
  subject text check (char_length(subject) <= 100),
  title text not null check (char_length(title) between 2 and 200),
  -- When the work was done or the report issued.
  dated_on date,
  -- As written on it, for example "B+", "15/20" or "Band 6".
  grade text check (char_length(grade) <= 30),
  note text check (char_length(note) <= 1000),
  file_path text not null check (file_path ~ '^[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$'),
  file_type text not null check (file_type in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')),
  uploaded_by uuid references public.accounts (id) on delete set null,
  uploaded_by_role text not null check (uploaded_by_role in ('student', 'parent', 'tutor')),
  uploaded_at timestamptz not null default now(),
  -- The tutor has looked at it (and linked any skills).
  reviewed_by uuid references public.accounts (id) on delete set null,
  reviewed_at timestamptz,
  tutor_comment text check (char_length(tutor_comment) <= 1000)
);
create index if not exists learning_evidence_student on public.learning_evidence (student_id, uploaded_at desc);
create unique index if not exists learning_evidence_file_once on public.learning_evidence (file_path);

create table if not exists public.evidence_skills (
  evidence_id uuid not null references public.learning_evidence (id) on delete cascade,
  skill_id uuid not null references public.curriculum_skills (id) on delete restrict,
  primary key (evidence_id, skill_id)
);

-- Files waiting to be removed from the file store by the daily job.
create table if not exists public.evidence_file_removals (
  file_path text primary key,
  queued_at timestamptz not null default now()
);

alter table public.learning_evidence enable row level security;
alter table public.evidence_skills enable row level security;
alter table public.evidence_file_removals enable row level security;
revoke all on public.learning_evidence, public.evidence_skills, public.evidence_file_removals from anon;
revoke all on public.evidence_file_removals from authenticated;
revoke truncate on public.learning_evidence, public.evidence_skills from authenticated;
-- Families can't change a record after upload (they can delete it and add
-- it again); the tutor's review goes through review_evidence.
revoke update on public.learning_evidence from authenticated;

drop trigger if exists audit on public.learning_evidence;
create trigger audit after insert or update or delete on public.learning_evidence
  for each row execute function private.audit_change();
drop trigger if exists audit on public.evidence_skills;
create trigger audit after insert or update or delete on public.evidence_skills
  for each row execute function private.audit_change();

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- The student a file belongs to, from its folder name (null if the name
-- isn't a student folder).
create or replace function private.evidence_folder_student(p_name text)
returns uuid language sql immutable
set search_path = ''
as $$
  select case when split_part(p_name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then split_part(p_name, '/', 1)::uuid end
$$;

create or replace function private.evidence_file_in_use(p_name text)
returns boolean language sql stable security definer
set search_path = ''
as $$ select exists (select 1 from public.learning_evidence where file_path = p_name) $$;

create or replace function private.evidence_student(p_evidence uuid)
returns uuid language sql stable security definer
set search_path = ''
as $$ select student_id from public.learning_evidence where id = p_evidence $$;

-- ---------------------------------------------------------------------------
-- Access rules
-- ---------------------------------------------------------------------------
drop policy if exists "see evidence" on public.learning_evidence;
create policy "see evidence" on public.learning_evidence
  for select to authenticated using (private.can_view_student(student_id));
-- The student (own login), a parent who manages them, their tutor, or an admin.
drop policy if exists "add evidence" on public.learning_evidence;
create policy "add evidence" on public.learning_evidence
  for insert to authenticated with check (private.can_plan_for(student_id));
-- Whoever uploaded it, a parent who manages the student, or an admin.
drop policy if exists "remove evidence" on public.learning_evidence;
create policy "remove evidence" on public.learning_evidence
  for delete to authenticated using (
    uploaded_by = auth.uid() or private.can_manage_student(student_id)
    or private.is_student_self(student_id) or private.is_admin()
  );

drop policy if exists "see evidence skills" on public.evidence_skills;
create policy "see evidence skills" on public.evidence_skills
  for select to authenticated using (private.can_view_student(private.evidence_student(evidence_id)));
revoke insert, update, delete on public.evidence_skills from authenticated;

-- Files: the same people as the records.
drop policy if exists "learning evidence: upload" on storage.objects;
create policy "learning evidence: upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'learning-evidence'
    and private.evidence_folder_student(name) is not null
    and private.can_plan_for(private.evidence_folder_student(name))
  );
drop policy if exists "learning evidence: open" on storage.objects;
create policy "learning evidence: open" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'learning-evidence'
    and private.evidence_folder_student(name) is not null
    and private.can_view_student(private.evidence_folder_student(name))
  );
-- Only a file not attached to a record (an upload that failed half way).
drop policy if exists "learning evidence: remove unattached" on storage.objects;
create policy "learning evidence: remove unattached" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'learning-evidence'
    and private.evidence_folder_student(name) is not null
    and private.can_plan_for(private.evidence_folder_student(name))
    and not private.evidence_file_in_use(name)
  );

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------
create or replace function private.guard_evidence()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if private.evidence_folder_student(new.file_path) is distinct from new.student_id then
      raise exception 'That file isn''t in this student''s folder' using errcode = '23514';
    end if;
    if not exists (select 1 from storage.objects where bucket_id = 'learning-evidence' and name = new.file_path) then
      raise exception 'The file didn''t upload. Please try again.' using errcode = '23514';
    end if;
    if new.dated_on is not null and new.dated_on > (now() at time zone 'Australia/Adelaide')::date then
      raise exception 'The date can''t be in the future' using errcode = '23514';
    end if;
    new.uploaded_by := auth.uid();
    new.uploaded_at := now();
    new.uploaded_by_role := private.planner_source(new.student_id);
    new.reviewed_by := null;
    new.reviewed_at := null;
    new.tutor_comment := null;
  end if;
  return new;
end;
$$;
drop trigger if exists guard on public.learning_evidence;
create trigger guard before insert on public.learning_evidence
  for each row execute function private.guard_evidence();

-- The file goes when its record goes.
create or replace function private.queue_evidence_file_removal()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.evidence_file_removals (file_path) values (old.file_path) on conflict do nothing;
  return old;
end;
$$;
drop trigger if exists remove_file on public.learning_evidence;
create trigger remove_file after delete on public.learning_evidence
  for each row execute function private.queue_evidence_file_removal();

-- The student's current tutors hear about a family upload.
alter table public.progress_notices add column if not exists evidence_id uuid references public.learning_evidence (id) on delete cascade;
alter table public.progress_notices drop constraint if exists progress_notices_kind_check;
alter table public.progress_notices add constraint progress_notices_kind_check
  check (kind in ('session_update', 'note_reminder', 'note_overdue', 'step_due',
                  'review_due', 'review_to_check', 'review_returned', 'review_ready', 'review_reply',
                  'monthly_summary', 'evidence_added'));

create or replace function private.notice_evidence_added()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if new.uploaded_by_role = 'tutor' then
    return new;
  end if;
  insert into public.progress_notices (account_id, student_id, evidence_id, kind, title, body, deliver_at)
  select ta.tutor_id, new.student_id, new.id, 'evidence_added',
         left('New upload for ' || st.full_name, 200),
         left('The family added "' || new.title || '". Have a look and link any skills it shows.', 1000),
         private.outside_quiet_hours(now())
  from (select distinct tutor_id from public.tutor_assignments
        where student_id = new.student_id and private.assignment_is_current(starts_on, ends_on)) ta
  cross join public.students st
  where st.id = new.student_id;
  return new;
end;
$$;
drop trigger if exists notice on public.learning_evidence;
create trigger notice after insert on public.learning_evidence
  for each row execute function private.notice_evidence_added();

-- ---------------------------------------------------------------------------
-- The tutor reviews an upload: a comment for the family and the skills it
-- shows (from the student's current goals).
-- ---------------------------------------------------------------------------
create or replace function public.review_evidence(p_evidence uuid, p_comment text default null, p_skills uuid[] default '{}')
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_student uuid := private.evidence_student(p_evidence);
  v_skill uuid;
begin
  if v_student is null or not (private.is_tutor_of(v_student) or private.is_admin()) then
    raise exception 'Upload not found' using errcode = 'P0002';
  end if;
  foreach v_skill in array coalesce(p_skills, '{}') loop
    if not exists (
      select 1 from public.goal_skills gs join public.learning_goals g on g.id = gs.goal_id
      where gs.skill_id = v_skill and g.student_id = v_student
    ) then
      raise exception 'A skill isn''t part of this student''s goals' using errcode = '23514';
    end if;
  end loop;

  update public.learning_evidence
  set reviewed_by = auth.uid(), reviewed_at = now(), tutor_comment = left(nullif(btrim(p_comment), ''), 1000)
  where id = p_evidence;
  delete from public.evidence_skills where evidence_id = p_evidence;
  insert into public.evidence_skills (evidence_id, skill_id)
  select p_evidence, unnest(coalesce(p_skills, '{}')) on conflict do nothing;
end;
$$;
revoke all on function public.review_evidence(uuid, text, uuid[]) from public, anon;
grant execute on function public.review_evidence(uuid, text, uuid[]) to authenticated;

-- For the app's daily job (secret key only): files to remove, then mark
-- them done.
create or replace function public.evidence_files_to_remove()
returns setof text language sql stable security definer
set search_path = ''
as $$ select file_path from public.evidence_file_removals order by queued_at limit 500 $$;
revoke all on function public.evidence_files_to_remove() from public, anon, authenticated;
grant execute on function public.evidence_files_to_remove() to service_role;

create or replace function public.evidence_files_removed(p_paths text[])
returns void language sql security definer
set search_path = ''
as $$ delete from public.evidence_file_removals where file_path = any(p_paths) $$;
revoke all on function public.evidence_files_removed(text[]) from public, anon, authenticated;
grant execute on function public.evidence_files_removed(text[]) to service_role;
