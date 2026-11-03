-- Progress tracking (module: progress): only tutors add roadmap steps.
-- See docs/features/learning-roadmaps.md.
--
-- Carla, 2026-11-02: adding steps is the tutor's job. Parents and students
-- tick steps off when they're done, and tell the tutor about progress in
-- "Tell the tutor". So:
--   * a step can be added, renamed or re-dated by the student's current
--     tutor or an admin;
--   * "Plan study steps for me" (study plans add-on) still adds its steps,
--     because the app adds those, not the family;
--   * families and students still tick steps off (tick_roadmap_step) and
--     can remove a step they added before this change.
--
-- Needs 20261029500100 (roadmaps) and 20261102500100 (study plans add-on).
-- Safe to run more than once.

drop policy if exists "add roadmap steps" on public.roadmap_steps;
create policy "add roadmap steps" on public.roadmap_steps
  for insert to authenticated with check (private.is_tutor_of(student_id) or private.is_admin());

drop policy if exists "change roadmap steps" on public.roadmap_steps;
create policy "change roadmap steps" on public.roadmap_steps
  for update to authenticated
  using (private.is_tutor_of(student_id) or private.is_admin())
  with check (private.is_tutor_of(student_id) or private.is_admin());

-- The study plans add-on no longer covers steps the family adds.
update public.add_ons
set description = 'Assessments and goals on the roadmap, with study steps planned for each assessment. Free while it is being tested.'
where code = 'study_plans'
  and description like '%steps the family adds%';
