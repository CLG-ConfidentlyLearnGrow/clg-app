-- Study details for university and TAFE students (Carla, 3 Nov 2026), so a
-- tutor can read about the course before the first session.
--
-- - On the student: their degree or course overall (program), for example
--   "Bachelor of Engineering (Civil)(Honours)". Where they study, for
--   example "Adelaide University", already goes in the school field.
-- - On each subject (unit): its code, for example "ENGC 3000", and a link to
--   the course page. The family or student fills these in.
-- - On each subject: a short course overview that admins write for now
--   (owner, operations or support). Later it may be gathered automatically.
--
-- Nothing here is sensitive. The existing student rules decide who sees it.
-- Safe to run more than once.

alter table public.students add column if not exists program text;
alter table public.students drop constraint if exists students_program_length;
alter table public.students
  add constraint students_program_length check (char_length(program) <= 300);

alter table public.student_subjects add column if not exists course_code text;
alter table public.student_subjects add column if not exists course_url text;
alter table public.student_subjects add column if not exists course_overview text;
alter table public.student_subjects drop constraint if exists student_subjects_course_code;
alter table public.student_subjects
  add constraint student_subjects_course_code check (char_length(course_code) <= 40);
-- Only web links, so a link can't run code when a tutor clicks it.
alter table public.student_subjects drop constraint if exists student_subjects_course_url;
alter table public.student_subjects
  add constraint student_subjects_course_url
  check (course_url is null or (course_url ~ '^https?://[^\s]+$' and char_length(course_url) <= 500));
alter table public.student_subjects drop constraint if exists student_subjects_course_overview;
alter table public.student_subjects
  add constraint student_subjects_course_overview check (char_length(course_overview) <= 4000);

-- Families and admins can change the level, code and link. The overview is
-- only changed through admin_set_course_overview below.
revoke update on public.student_subjects from authenticated;
grant update (working_level, course_code, course_url) on public.student_subjects to authenticated;

create or replace function public.admin_set_course_overview(p_subject uuid, p_overview text)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_text text := nullif(trim(coalesce(p_overview, '')), '');
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG admins can write a course overview' using errcode = '42501';
  end if;
  if char_length(v_text) > 4000 then
    raise exception 'Please keep the overview under 4,000 characters' using errcode = '22023';
  end if;
  update public.student_subjects set course_overview = v_text where id = p_subject;
  if not found then
    raise exception 'That subject wasn''t found' using errcode = '22023';
  end if;
end;
$$;
revoke execute on function public.admin_set_course_overview(uuid, text) from public, anon;
grant execute on function public.admin_set_course_overview(uuid, text) to authenticated;
