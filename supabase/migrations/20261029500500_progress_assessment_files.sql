-- Progress tracking, part 7 (module: progress): task sheets and rubrics for
-- upcoming assessments, and only parents upload school reports and NAPLAN.
-- See docs/features/learning-roadmaps.md and docs/features/learning-evidence.md.
--
-- - When a family adds an upcoming school assessment to the roadmap, they
--   can attach the task sheet and the rubric (marking guide). These are
--   stored like other uploads (same private file store, same access rules)
--   and linked to the assessment.
-- - School reports and NAPLAN results come from parents (Carla, 2026-10-28).
--   Tutors can't add them. A student with their own login can add them only
--   if no parent manages their account (for example an adult learner).
--
-- Needs 20261029500100 (roadmaps) and 20261029500300 (uploads).
-- Safe to run more than once.

alter table public.learning_evidence
  add column if not exists target_id uuid references public.roadmap_targets (id) on delete cascade;
create index if not exists learning_evidence_target on public.learning_evidence (target_id) where target_id is not null;

alter table public.learning_evidence drop constraint if exists learning_evidence_kind_check;
alter table public.learning_evidence add constraint learning_evidence_kind_check
  check (kind in ('graded_work', 'school_report', 'naplan', 'other_assessment', 'work_sample', 'task_sheet', 'rubric'));

-- True when a parent manages this student's account.
create or replace function private.has_managing_parent(p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$ select exists (select 1 from public.parent_student_links where student_id = p_student and can_manage) $$;

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
    if new.target_id is not null and not exists (
      select 1 from public.roadmap_targets t where t.id = new.target_id and t.student_id = new.student_id
    ) then
      raise exception 'That assessment isn''t on this student''s roadmap' using errcode = '23514';
    end if;
    new.uploaded_by := auth.uid();
    new.uploaded_at := now();
    new.uploaded_by_role := private.planner_source(new.student_id);
    -- School reports and NAPLAN results come from parents.
    if new.kind in ('school_report', 'naplan') and not private.is_admin() and (
      new.uploaded_by_role = 'tutor'
      or (new.uploaded_by_role = 'student' and private.has_managing_parent(new.student_id))
    ) then
      raise exception 'School reports and NAPLAN results are uploaded by a parent' using errcode = '23514';
    end if;
    new.reviewed_by := null;
    new.reviewed_at := null;
    new.tutor_comment := null;
  end if;
  return new;
end;
$$;

-- The tutor hears about a task sheet or rubric as an upload for the assessment.
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
         left(case
           when new.kind in ('task_sheet', 'rubric') then
             'The family added the ' || case new.kind when 'task_sheet' then 'task sheet' else 'rubric' end
             || ' for "' || coalesce((select t.title from public.roadmap_targets t where t.id = new.target_id), new.title) || '".'
           else 'The family added "' || new.title || '". Have a look and link any skills it shows.'
         end, 1000),
         private.outside_quiet_hours(now())
  from (select distinct tutor_id from public.tutor_assignments
        where student_id = new.student_id and private.assignment_is_current(starts_on, ends_on)) ta
  cross join public.students st
  where st.id = new.student_id;
  return new;
end;
$$;
