-- Learning roadmaps. Runs after progress_follow_up.test.sql and reuses its
-- people: owner ...a0 (admin), tutor T1 ...11 (teaches Cara One), tutor T2
-- ...12, parent P1 ...01 (Cara's parent), parent P2 ...02 (Vic and Cal's
-- parent), and login ...31 (given to Cal Two for these tests).

-- The migration is safe to run twice.
-- Runs the database change 20261029500100_progress_roadmaps.sql first, as this test needs it.
\ir ../migrations/20261029500100_progress_roadmaps.sql

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset
-- Keeps Cal's student id as cal.
select id as cal from public.students where full_name = 'Cal Two' \gset
-- Keeps today's date in Adelaide as today.
select (now() at time zone 'Australia/Adelaide')::date as today \gset

-- ===========================================================================
-- Targets
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.roadmap_targets (id, student_id, kind, subject, title, due_on, current_grade, target_grade) -- Adds a maths test to Cara's roadmap:
  values ('00000000-0000-0000-0000-0000000d0001', :'cara', 'assessment', 'General Maths', 'fractions test', :'today'::date + 14, 'C', 'B'); -- (in two weeks, from a C aiming for a B).
select tests.eq((select count(*) from public.roadmap_targets where created_by = '00000000-0000-0000-0000-000000000001' and status = 'open'), 1, 'parent adds an assessment'); -- Checks: parent adds an assessment.
select tests.fails(format($$insert into public.roadmap_targets (student_id, kind, title) values (%L, 'assessment', 'No date test')$$, :'cara'), 'assessment without a date'); -- Checks this is refused: assessment without a date.
select tests.fails(format($$insert into public.roadmap_targets (student_id, kind, title, learning_goal_id) -- Checks a parent of another child can't plan for Cal:
  values (%L, 'goal', 'Borrowed goal', (select id from public.learning_goals limit 1))$$, :'cal'), 'parent of another child plans for Cal'); -- (adding a goal for Cal).
select tests.fails($$delete from public.roadmap_targets$$, 'targets cannot be deleted'); -- Checks this is refused: targets cannot be deleted.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.roadmap_targets), 0, 'other parent sees no targets'); -- Checks: other parent sees no targets.
select tests.fails(format($$insert into public.roadmap_targets (student_id, kind, title) values (%L, 'goal', 'Not my child')$$, :'cara'), 'other parent adds a target'); -- Checks this is refused: other parent adds a target.
-- A goal from another student can't be linked.
select tests.fails(format($$insert into public.roadmap_targets (student_id, kind, title, learning_goal_id) -- Checks linking another student's goal is refused:
  values (%L, 'goal', 'Borrowed goal', '00000000-0000-0000-0000-00000000a001')$$, :'cal'), 'linking another student''s goal'); -- (Cara's goal on Cal's roadmap).
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- Signs in as test account ...12 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.roadmap_targets), 0, 'other tutor sees no targets'); -- Checks: other tutor sees no targets.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Planned steps
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(public.plan_assessment_steps('00000000-0000-0000-0000-0000000d0001'), 6, 'six steps planned'); -- Checks: six steps planned.
select tests.eq((select count(*) from public.roadmap_steps where target_id = '00000000-0000-0000-0000-0000000d0001' and source = 'plan'), 6, 'labelled as planned'); -- Checks: labelled as planned.
select tests.eq((select count(*) from public.roadmap_steps where target_id = '00000000-0000-0000-0000-0000000d0001' and due_on = :'today'), 1, 'first step today'); -- Checks: first step today.
select tests.eq((select count(*) from public.roadmap_steps where target_id = '00000000-0000-0000-0000-0000000d0001' and due_on = :'today'::date + 13), 1, 'last step the day before'); -- Checks: last step the day before.
select tests.fails($$select public.plan_assessment_steps('00000000-0000-0000-0000-0000000d0001')$$, 'planning twice'); -- Checks this is refused: planning twice.

-- Only the tutor adds steps by hand (Carla, 2026-11-02); families tick them off.
select tests.fails(format($$insert into public.roadmap_steps (student_id, target_id, title) values (%L, '00000000-0000-0000-0000-0000000d0001', 'Parent step')$$, :'cara'), 'parent adds a step'); -- Checks this is refused: parent adds a step.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.roadmap_steps (id, student_id, target_id, title, due_on, source) -- Adds a step to the maths test:
  values ('00000000-0000-0000-0000-0000000d0101', :'cara', '00000000-0000-0000-0000-0000000d0001', 'Ask the teacher what the test covers', :'today'::date + 1, 'next_step'); -- (due tomorrow, from a next step).
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000d0101' and source = 'tutor'), 1, 'tutor''s step labelled tutor, whatever is sent'); -- Checks: tutor's step labelled tutor, whatever is sent.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.

-- Ticking off.
select public.tick_roadmap_step('00000000-0000-0000-0000-0000000d0101'); -- Ticks the step as done.
select tests.eq((select count(*) from public.roadmap_steps where done_at is not null and done_by = '00000000-0000-0000-0000-000000000001'), 1, 'parent ticks a step'); -- Checks: parent ticks a step.
select public.tick_roadmap_step('00000000-0000-0000-0000-0000000d0101', false); -- Unticks it.
select tests.eq((select count(*) from public.roadmap_steps where done_at is not null), 0, 'and un-ticks it'); -- Checks: and un-ticks it.
select tests.fails($$update public.roadmap_steps set done_at = now()$$, 'ticking by direct edit'); -- Checks this is refused: ticking by direct edit.
update public.roadmap_steps set title = 'Ask Ms Lee what the test covers' where id = '00000000-0000-0000-0000-0000000d0101'; -- Changes the step's words.
select tests.eq((select count(*) from public.roadmap_steps where title like 'Ask Ms Lee%'), 0, 'parent can''t rename a step'); -- Checks: parent can't rename a step.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.tick_roadmap_step('00000000-0000-0000-0000-0000000d0101')$$, 'other parent ticks a step'); -- Checks this is refused: other parent ticks a step.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.roadmap_steps where target_id = '00000000-0000-0000-0000-0000000d0001'), 7, 'tutor sees the roadmap'); -- Checks: tutor sees the roadmap.
insert into public.roadmap_steps (id, student_id, title, due_on) values ('00000000-0000-0000-0000-0000000d0102', :'cara', 'Read for 10 minutes each night', :'today'::date + 3); -- Adds a loose step: read for 10 minutes each night.
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000d0102' and source = 'tutor'), 1, 'tutor''s step labelled tutor'); -- Checks: tutor's step labelled tutor.
select tests.fails(format($$update public.roadmap_steps set student_id = %L where id = '00000000-0000-0000-0000-0000000d0102'$$, :'cal'), 'step moved to another student'); -- Checks this is refused: step moved to another student.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
delete from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000d0102'; -- Removes the reading step.
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000d0102'), 1, 'parent can''t remove the tutor''s step'); -- Checks: parent can't remove the tutor's step.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
delete from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000d0101'; -- Removes the first step.
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000d0101'), 0, 'tutor removes a step'); -- Checks: tutor removes a step.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- A session note's next step joins the roadmap
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- The tutor saves a session note with a next step, and keeps its id as note.
select public.save_session_note(:'cara', current_date, 60, 'attended', 'Great focus.', 'Practise the 8 times table for 5 minutes a day.') as note \gset
select tests.eq((select count(*) from public.roadmap_steps where note_id = :'note' and source = 'next_step' -- Checks the next step becomes a roadmap step:
  and created_by = '00000000-0000-0000-0000-000000000011' and title like 'Practise the 8 times%'), 1, 'next step becomes a step'); -- (one step from that note by tutor T1).
update public.session_notes set next_step = 'Practise the 8 times table for 10 minutes a day.' where id = :'note'; -- Changes the note's next step.
select tests.eq((select count(*) from public.roadmap_steps where note_id = :'note' and title like '%10 minutes%'), 1, 'step follows a corrected next step'); -- Checks: step follows a corrected next step.
-- Saves a note for an absent session, and keeps its id as absent_note.
select public.save_session_note(:'cara', current_date, 0, 'absent', null, null) as absent_note \gset
select tests.eq((select count(*) from public.roadmap_steps where note_id = :'absent_note'), 0, 'absent session adds no step'); -- Checks: absent session adds no step.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Reminders the afternoon before
-- ===========================================================================
select tests.claims(null); -- Signs out, so no one is signed in.
update public.roadmap_steps set due_on = :'today'::date + 1 where id = '00000000-0000-0000-0000-0000000d0102'; -- Makes the reading step due tomorrow.
select private.queue_step_reminders(); -- Queues step reminders.
select private.queue_step_reminders(); -- Queues them again (should not repeat).
select tests.eq((select count(*) from public.progress_notices where kind = 'step_due' and student_id = :'cara' -- Checks the parent is reminded once:
  and account_id = '00000000-0000-0000-0000-000000000001' and for_date = :'today'::date + 1), 1, 'parent reminded once'); -- (for tomorrow).
select tests.eq((select count(*) from public.progress_notices where kind = 'step_due' and student_id = :'cara' -- Checks the reminder lists the step:
  and body like '%Read for 10 minutes%'), 1, 'reminder lists the step'); -- (mentions reading).
select tests.eq((select count(*) from public.progress_notices where kind = 'step_due' -- Checks the tutor isn't reminded about family steps:
  and account_id = '00000000-0000-0000-0000-000000000011'), 0, 'tutor not reminded about family steps'); -- (no reminder for tutor T1).

-- ===========================================================================
-- A student with their own login plans for themselves
-- ===========================================================================
update public.students set account_id = '00000000-0000-0000-0000-000000000031', date_of_birth = current_date - interval '17 years' where id = :'cal'; -- Gives Cal his own login and makes him 17.
select tests.claims('00000000-0000-0000-0000-000000000031'); -- Signs in as test account ...31.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.roadmap_targets (id, student_id, kind, subject, title, due_on) -- Cal adds an English essay draft:
  values ('00000000-0000-0000-0000-0000000d0002', :'cal', 'assessment', 'English', 'essay draft', :'today'::date + 3); -- (due in three days).
select tests.eq(public.plan_assessment_steps('00000000-0000-0000-0000-0000000d0002'), 3, 'short time: three steps'); -- Checks: short time: three steps.
select tests.fails(format($$insert into public.roadmap_steps (student_id, title) values (%L, 'Pick my essay question')$$, :'cal'), 'student adds their own step'); -- Checks this is refused: student adds their own step.
select tests.eq((select count(*) from public.roadmap_steps where student_id = :'cal' and source = 'plan'), 3, 'student''s planned steps are there'); -- Checks: student's planned steps are there.
select tests.eq((select count(*) from public.roadmap_targets where student_id = :'cara'), 0, 'student sees only their own roadmap'); -- Checks: student sees only their own roadmap.
update public.roadmap_targets set status = 'done' where id = '00000000-0000-0000-0000-0000000d0002'; -- Marks it done.
select tests.eq((select count(*) from public.roadmap_targets where id = '00000000-0000-0000-0000-0000000d0002' and closed_at is not null), 1, 'finishing a target records when'); -- Checks: finishing a target records when.
reset role; -- Goes back to the all-powerful test user (access rules off).

set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.roadmap_steps$$, 'anon reads steps'); -- Checks this is refused: anon reads steps.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Tidy up.
select tests.claims(null); -- Signs out, so no one is signed in.
update public.students set account_id = null, date_of_birth = current_date - interval '12 years' where id = :'cal'; -- Takes Cal's login away and makes him 12 again.

-- Prints that every check in this file passed.
\echo '  progress roadmaps: all checks passed'
