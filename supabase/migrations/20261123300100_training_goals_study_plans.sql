-- Training (module: training): goals for every student, and study plans as
-- a paid add-on (Carla, 20 Nov 2026).
--
-- Carla: "The Yearly plan is just the goals ... The term and weekly plans are
-- extra add-ons to the Tutoring that customers can pay for."
--
-- What changes:
--   * Module 27 becomes "Setting a student's goals" (part of all tutoring),
--     with a practice task: write two measurable goals for a made-up student.
--   * Module 28 becomes "Each week's next step" (part of all tutoring).
--   * New module 29, "Term and weekly study plans", for tutors who teach a
--     student whose family pays for the study plan add-on. It is optional
--     for everyone else, has a practice task (set up a term plan), and is
--     marked as needed before study plan work.
--   * When a tutor teaches a student with the paid study plan add-on and has
--     not done module 29, it is assigned to them (due the day before their
--     next session with that student, or in a week) and they and the admins
--     are told. While study plans are free for everyone, nothing is assigned.
--   * The "Ready for" column also shows study plans.
--
-- Modules 27 and 28 are only rewritten while they are still drafts with
-- their 18 Nov titles, so anything Carla has published or renamed is kept.
-- Safe to run more than once. Run after 20261121300300_training_screenshots_tasks.sql.

-- ---------------------------------------------------------------------------
-- 1. A third job a module can be needed before: study plan work.
-- ---------------------------------------------------------------------------
alter table public.training_modules drop constraint if exists training_modules_needed_for_check; -- removes the old rule (so this file can run twice)
alter table public.training_modules add constraint training_modules_needed_for_check -- adds it back with the new job:
  check (needed_for is null or needed_for in ('drafting', 'term_review', 'study_plan')); -- drafting, term reviews or study plans

-- ---------------------------------------------------------------------------
-- 2. Module 27: "Setting a student's goals" (only while it is still the
--    18 Nov draft). Lessons, questions and the practice task are replaced.
-- ---------------------------------------------------------------------------
delete from public.training_lessons l -- removes the old lessons:
using public.training_modules m -- (of the module)
where l.module_id = m.id and m.id = '7a000000-0000-4000-8000-000000000027' -- of module 27
  and m.title = 'The yearly and term plan' and m.status = 'draft'; -- only while it is still the 18 Nov draft
delete from public.training_questions q -- removes the old questions:
using public.training_modules m -- (of the module)
where q.module_id = m.id and m.id = '7a000000-0000-4000-8000-000000000027' -- of module 27
  and m.title = 'The yearly and term plan' and m.status = 'draft'; -- only while it is still the 18 Nov draft
update public.training_modules m -- changes the module:
set title = 'Setting a student''s goals', -- the new title
    summary = 'Agreeing a new student''s goals for the year, and updating them each term. Part of all tutoring.', -- what it covers
    practice_task = $t$Write two measurable goals for this made-up student, written out here (not in the app).

Lily, Year 10, maths. Her family wants her ready for Year 11 Mathematical Methods by the end of the school year. In your first sessions you found she can expand brackets but struggles to factorise quadratics, and she often leaves worded problems blank.

Write two goals for the end of the school year. CLG checks that each goal says what, how well, by when and how it will be checked (module 26), and that each one fits what you know about Lily.$t$ -- the new practice task
where m.id = '7a000000-0000-4000-8000-000000000027' -- module 27
  and m.title = 'The yearly and term plan' and m.status = 'draft'; -- only while it is still the 18 Nov draft

-- ---------------------------------------------------------------------------
-- 3. Module 28: "Each week's next step" (only while it is still the 18 Nov
--    draft). Lessons and questions are replaced.
-- ---------------------------------------------------------------------------
delete from public.training_lessons l -- removes the old lessons:
using public.training_modules m -- (of the module)
where l.module_id = m.id and m.id = '7a000000-0000-4000-8000-000000000028' -- of module 28
  and m.title = 'The weekly plan' and m.status = 'draft'; -- only while it is still the 18 Nov draft
delete from public.training_questions q -- removes the old questions:
using public.training_modules m -- (of the module)
where q.module_id = m.id and m.id = '7a000000-0000-4000-8000-000000000028' -- of module 28
  and m.title = 'The weekly plan' and m.status = 'draft'; -- only while it is still the 18 Nov draft
update public.training_modules m -- changes the module:
set title = 'Each week''s next step', -- the new title
    summary = 'What you check before each session, and the one next step every session ends with. Part of all tutoring.' -- what it covers
where m.id = '7a000000-0000-4000-8000-000000000028' -- module 28
  and m.title = 'The weekly plan' and m.status = 'draft'; -- only while it is still the 18 Nov draft

-- ---------------------------------------------------------------------------
-- 4. New module 29 (a draft, optional, needed before study plan work).
-- ---------------------------------------------------------------------------
insert into public.training_modules (id, title, summary, audience, stage, required, holds_matching, counts_toward_certified, minutes, renew_months, status, position, in_order, needed_for, practice_task) values -- adds the module:
  ('7a000000-0000-4000-8000-000000000029', 'Term and weekly study plans', 'For tutors with a student whose family has the paid study plan add-on: setting up and keeping the term plan.', 'tutor', 'ongoing', false, false, true, 15, null, 'draft', 205, false, 'study_plan', -- 29. Term and weekly study plans, after the term review modules
   $t$Set up a term plan for this made-up student, written out here (not in the app).

Lily, Year 10, maths, has the study plan add-on. Her school has a test on quadratics in week 6 and an investigation due in week 9 this term.

Write the two assessment targets with their weeks, then the study steps for the week 6 test, each with a date, spread across the weeks before it. CLG checks that each target has a date, that each step is small and specific enough for Lily to do on her own, and that the steps are spread out rather than left to the last week.$t$) -- its practice task
on conflict (id) do nothing; -- already added before: left as it is

-- The lessons for modules 27, 28 and 29 (only when the module has none yet).
insert into public.training_lessons (module_id, position, title, body) -- adds the lessons:
select v.mod::uuid, v.pos, v.title, v.body -- to its module, in order, with its heading and text
from (values -- the lessons (module, order, heading, text):
  ('7a000000-0000-4000-8000-000000000027', 1, 'The student''s goals', $t$Goals are part of every student's tutoring.

- In the first three sessions, agree with the student (and family) where they want to be by the end of the school year.
- Write two or three measurable goals on the Progress page (module 26), linked to the school curriculum.
- At the end of each term, update them: mark goals reached, record progress on ongoing ones, and note any changed or dropped, with why.

These feed straight into term reviews.$t$),
  ('7a000000-0000-4000-8000-000000000028', 1, 'Each week', $t$Every week follows the same pattern:
- Before the session, check last week's next step and any notes from home.
- Run the session using the CLG session routine (module 11).
- End with one next step. The app adds it to the student's steps automatically, due by the next session, and the student or parent ticks it off.$t$),
  ('7a000000-0000-4000-8000-000000000029', 1, 'What families get', $t$Study plans are an extra service families can pay for on top of tutoring. They turn the term's school assessments and learning targets into small, dated steps between sessions, so the student keeps moving all week.

You only set up study plans for students whose family has the add-on. Goals and each session's next step are part of all tutoring (modules 27 and 28).$t$),
  ('7a000000-0000-4000-8000-000000000029', 2, 'Setting up the term plan', $t$At the start of each term:
- Add the term's assessments as targets, with their dates and any task sheets and rubrics the family uploaded.
- Use "Plan study steps for me" to spread the work out, then adjust the steps to suit the student.
- Add weekly steps the student agrees to.

Review the plan in each session, and update it when dates or priorities change.$t$)
) as v(mod, pos, title, body) -- (the columns of the list above)
where not exists (select 1 from public.training_lessons l where l.module_id = v.mod::uuid); -- only for a module with no lessons yet

-- Their quiz questions (only when the module has none yet).
insert into public.training_questions (module_id, position, prompt, options, correct_option) -- adds the questions:
select v.mod::uuid, v.pos, v.prompt, v.options, v.correct -- to its module, in order, with the question, choices and right answer
from (values -- the questions (module, order, question, choices, right answer):
  ('7a000000-0000-4000-8000-000000000027', 1, 'When do you agree a new student''s goals?', array['By the end of the first three sessions', 'At the end of the year', 'Only if the family asks', 'Before you meet the student'], 1),
  ('7a000000-0000-4000-8000-000000000027', 2, 'A goal no longer fits the student. What do you do?', array['Delete it quietly', 'Change or drop it on the Progress page and note why', 'Leave it as it is', 'Ask the school'], 2),
  ('7a000000-0000-4000-8000-000000000028', 1, 'What happens to the next step in your session summary?', array['Nothing', 'It becomes a step due by the next session', 'It is emailed to the school', 'It is deleted after a week'], 2),
  ('7a000000-0000-4000-8000-000000000028', 2, 'What do you check before each session?', array['Last week''s next step and notes from home', 'Only the time', 'The family''s invoices', 'Nothing, plan on the day'], 1),
  ('7a000000-0000-4000-8000-000000000029', 1, 'Who gets a term and weekly study plan?', array['Every student', 'Students whose family has the study plan add-on', 'Only Year 12 students', 'Only students who ask'], 2),
  ('7a000000-0000-4000-8000-000000000029', 2, 'What does "Plan study steps for me" do?', array['Writes the assessment for the student', 'Spreads the work for an assessment into small dated steps, which you then adjust', 'Books extra sessions', 'Emails the teacher'], 2)
) as v(mod, pos, prompt, options, correct) -- (the columns of the list above)
where not exists (select 1 from public.training_questions q where q.module_id = v.mod::uuid); -- only for a module with no questions yet

-- ---------------------------------------------------------------------------
-- 5. Readiness for full admins now includes study plans.
-- ---------------------------------------------------------------------------
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
    cross join (values ('drafting'), ('term_review'), ('study_plan')) as j(job) -- for each job
    where tp.active; -- active tutors only
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_job_readiness() from public, anon; -- not for signed-out visitors
grant execute on function public.training_job_readiness() to authenticated; -- signed-in people (checked inside)

-- ---------------------------------------------------------------------------
-- 6. Tutors of a student with the paid study plan add-on get the study plan
--    modules they still need, and everyone is told. Reads add-ons, tutor
--    assignments and sessions; writes only training assignments.
-- ---------------------------------------------------------------------------
create or replace function private.training_study_plan_check(p_student uuid) -- takes the student
returns void language plpgsql security definer -- runs steps; runs with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  r record; -- one tutor at a time
  v_due date; -- when the modules are due
  v_added int; -- how many modules were newly assigned
  v_titles text; -- their titles
  v_tutor text; -- the tutor's name
  v_student text; -- the student's first name
begin -- start of the steps
  if not exists ( -- the student does not have the paid add-on today:
    select 1 from public.add_ons a -- the add-on
    join public.add_on_members am on am.add_on = a.code -- and who has it
    where a.code = 'study_plans' and a.mode = 'paid' -- study plans, while families pay for them
      and am.student_id = p_student -- this student
      and am.starts_on <= private.training_today() and (am.ends_on is null or am.ends_on >= private.training_today()) -- has it today
  ) then -- (end of the test)
    return; -- nothing to do (while study plans are free for everyone, no one is assigned anything)
  end if; -- end of that check
  select private.first_name(s.full_name) into v_student from public.students s where s.id = p_student; -- the student's first name
  for r in -- each tutor currently teaching the student:
    select ta.tutor_id from public.tutor_assignments ta -- tutor assignments belong to the shared core; training only reads them
    where ta.student_id = p_student and private.assignment_is_current(ta.starts_on, ta.ends_on) -- current ones for this student
  loop -- for each tutor:
    v_due := greatest(coalesce( -- the due date:
      (select min((se.starts_at at time zone 'Australia/Adelaide')::date) - 1 from public.sessions se -- the day before their next session with this student,
        where se.tutor_id = r.tutor_id and se.student_id = p_student and se.status::text = 'scheduled' and se.starts_at > now()), -- (booked, still to come)
      private.training_today() + 7), private.training_today()); -- or in a week if none is booked; never in the past
    with added as ( -- assigns each module still needed:
      insert into public.training_assignments (account_id, module_id, due_on, reason) -- to the tutor
      select r.tutor_id, x.module_id, v_due, left('Needed before study plan work with ' || coalesce(v_student, 'your student'), 300) -- due before their next session, with why
      from private.training_job_missing(r.tutor_id, 'study_plan') x -- (each module still needed)
      on conflict (account_id, module_id) do nothing -- already assigned: left as it is
      returning module_id -- the ones newly assigned
    ) select count(*), string_agg(m.title, ', ') into v_added, v_titles -- counts them, with their titles
      from added join public.training_modules m on m.id = added.module_id; -- (the module titles)
    if v_added > 0 then -- something new was assigned:
      select a.full_name into v_tutor from public.accounts a where a.id = r.tutor_id; -- the tutor's name
      perform private.add_notice(r.tutor_id, null, null, 'check_renewal', 'Training to do before study plan work', -- tells the tutor
        coalesce(v_student, 'Your student') || ' has study plans with CLG. Before you set up their plan, please finish: ' || v_titles || '. You will find it under Training, due by ' || to_char(v_due, 'FMDD FMMonth YYYY') || '. It is paid for its set time.', now()); -- what, by when, and that it is paid
      perform private.notify_admins('Training needed: ' || coalesce(v_tutor, 'a tutor'), -- tells the admins
        coalesce(v_tutor, 'A tutor') || ' teaches a student with the study plan add-on but has not finished: ' || v_titles || '. It is now assigned, due by ' || to_char(v_due, 'FMDD FMMonth YYYY') || '.'); -- who and what is missing
    end if; -- end of that case
  end loop; -- end of the tutors
end; -- end of the steps
$$; -- end of the function
revoke all on function private.training_study_plan_check(uuid) from public; -- for the database's own use

-- When a student is given the add-on (or its dates change).
create or replace function private.training_study_plan_member() -- runs after an add-on member row is added or changed
returns trigger language plpgsql security definer -- a trigger; runs with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
begin -- start of the steps
  if new.add_on = 'study_plans' then -- the study plan add-on:
    perform private.training_study_plan_check(new.student_id); -- checks the student's tutors
  end if; -- end of that case
  return new; -- the change goes ahead
end; -- end of the steps
$$; -- end of the function
revoke all on function private.training_study_plan_member() from public; -- for the database's own use
drop trigger if exists training_study_plan_member on public.add_on_members; -- removes the old trigger (so this file can run twice)
create trigger training_study_plan_member after insert or update on public.add_on_members -- runs after each added or changed member
  for each row execute function private.training_study_plan_member(); -- using the steps above

-- When a tutor starts teaching a student.
create or replace function private.training_study_plan_tutor() -- runs after a tutor assignment is added or changed
returns trigger language plpgsql security definer -- a trigger; runs with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
begin -- start of the steps
  perform private.training_study_plan_check(new.student_id); -- checks the student's tutors
  return new; -- the change goes ahead
end; -- end of the steps
$$; -- end of the function
revoke all on function private.training_study_plan_tutor() from public; -- for the database's own use
drop trigger if exists training_study_plan_tutor on public.tutor_assignments; -- removes the old trigger (so this file can run twice)
create trigger training_study_plan_tutor after insert or update on public.tutor_assignments -- runs after each added or changed assignment
  for each row execute function private.training_study_plan_tutor(); -- using the steps above

-- When study plans become a paid add-on: checks every student who has it.
create or replace function private.training_study_plan_paid() -- runs after an add-on's switch changes
returns trigger language plpgsql security definer -- a trigger; runs with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  r record; -- one student at a time
begin -- start of the steps
  if new.code = 'study_plans' and new.mode = 'paid' and old.mode is distinct from 'paid' then -- study plans just became paid:
    for r in select distinct am.student_id from public.add_on_members am where am.add_on = 'study_plans' loop -- each student given it
      perform private.training_study_plan_check(r.student_id); -- checks their tutors
    end loop; -- end of the students
  end if; -- end of that case
  return new; -- the change goes ahead
end; -- end of the steps
$$; -- end of the function
revoke all on function private.training_study_plan_paid() from public; -- for the database's own use
drop trigger if exists training_study_plan_paid on public.add_ons; -- removes the old trigger (so this file can run twice)
create trigger training_study_plan_paid after update of mode on public.add_ons -- runs after an add-on's switch changes
  for each row execute function private.training_study_plan_paid(); -- using the steps above
