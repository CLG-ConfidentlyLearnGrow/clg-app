-- A separate, optional place for families to describe a student's learning
-- needs in their own words (Carla, 2 Nov 2026), for example dyslexia or how
-- they cope with tests. It can hold health information, which is sensitive
-- under the Privacy Act (APP 3.3): it is only collected when the family
-- chooses to write it. The existing student rules decide who sees it: CLG
-- admins, the student's parents, the student, and their tutors.
-- Safe to run more than once.

alter table public.students add column if not exists learning_needs text;
alter table public.students drop constraint if exists students_learning_needs_length;
alter table public.students
  add constraint students_learning_needs_length check (char_length(learning_needs) <= 2000);
