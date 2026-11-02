-- Subjects follow the student's year level (Carla, 2 Nov 2026).
--   * Foundation to Year 10: "Mathematics" (Australian Curriculum).
--   * Years 11 and 12: "Mathematics: Essential", "Mathematics: General",
--     "Mathematics: Methods" and "Mathematics: Specialist" (SACE).
-- "Maths" on its own is still refused, and plain "Mathematics" is refused
-- for Year 11 and above. Existing entries are left as they are.
-- Safe to run more than once.

alter table public.student_subjects drop constraint if exists student_subjects_maths_split;
alter table public.student_subjects
  add constraint student_subjects_maths_split check (
    lower(trim(subject)) not in ('maths', 'math')
    and not (lower(trim(subject)) = 'mathematics'
             and working_level in ('Year 11', 'Year 12', 'University or TAFE', 'Adult learner'))
  ) not valid;

alter table public.tutor_teaching drop constraint if exists tutor_teaching_maths_split;
alter table public.tutor_teaching
  add constraint tutor_teaching_maths_split check (
    lower(trim(subject)) not in ('maths', 'math')
    and not (lower(trim(subject)) = 'mathematics'
             and to_level in ('Year 11', 'Year 12', 'University or TAFE', 'Adult learner'))
  ) not valid;

-- Puts a subject name in a standard form so curricula attach to the right
-- subject. New: "Mathematics: General" reads as "General Mathematics", and
-- "Mathematics: Methods" as SACE's "Mathematical Methods".
create or replace function private.norm_subject(p text)
returns text language sql immutable
set search_path = ''
as $$
  select trim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
    lower(trim(coalesce(p, ''))),
    '\(.*\)', '', 'g'),                                   -- drop "(...)" notes
    '\s+(f|\d+)\s*[-–]\s*\d+$', ''),                      -- drop "F-6", "7-10"
    '^mathematics:\s*(essential|general|methods|specialist)$', '\1 mathematics'),
    '^methods mathematics$', 'mathematical methods'),
    '\mmaths?\M', 'mathematics', 'g'),
    '^humanities and social sciences$', 'hass'),
    '\s+', ' ', 'g'))
$$;
