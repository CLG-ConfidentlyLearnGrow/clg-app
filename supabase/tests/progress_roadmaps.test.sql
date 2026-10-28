-- Learning roadmaps. Runs after progress_follow_up.test.sql and reuses its
-- people: owner ...a0 (admin), tutor T1 ...11 (teaches Cara One), tutor T2
-- ...12, parent P1 ...01 (Cara's parent), parent P2 ...02 (Vic and Cal's
-- parent), and login ...31 (given to Cal Two for these tests).

-- The migration is safe to run twice.
\ir ../migrations/20261029500100_progress_roadmaps.sql

select tests.claims(null);
select id as cara from public.students where full_name = 'Cara One' \gset
select id as cal from public.students where full_name = 'Cal Two' \gset
select (now() at time zone 'Australia/Adelaide')::date as today \gset

-- ===========================================================================
-- Targets
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
insert into public.roadmap_targets (id, student_id, kind, subject, title, due_on, current_grade, target_grade)
  values ('00000000-0000-0000-0000-0000000d0001', :'cara', 'assessment', 'General Maths', 'fractions test', :'today'::date + 14, 'C', 'B');
select tests.eq((select count(*) from public.roadmap_targets where created_by = '00000000-0000-0000-0000-000000000001' and status = 'open'), 1, 'parent adds an assessment');
select tests.fails(format($$insert into public.roadmap_targets (student_id, kind, title) values (%L, 'assessment', 'No date test')$$, :'cara'), 'assessment without a date');
select tests.fails(format($$insert into public.roadmap_targets (student_id, kind, title, learning_goal_id)
  values (%L, 'goal', 'Borrowed goal', (select id from public.learning_goals limit 1))$$, :'cal'), 'parent of another child plans for Cal');
select tests.fails($$delete from public.roadmap_targets$$, 'targets cannot be deleted');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.roadmap_targets), 0, 'other parent sees no targets');
select tests.fails(format($$insert into public.roadmap_targets (student_id, kind, title) values (%L, 'goal', 'Not my child')$$, :'cara'), 'other parent adds a target');
-- A goal from another student can't be linked.
select tests.fails(format($$insert into public.roadmap_targets (student_id, kind, title, learning_goal_id)
  values (%L, 'goal', 'Borrowed goal', '00000000-0000-0000-0000-00000000a001')$$, :'cal'), 'linking another student''s goal');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.roadmap_targets), 0, 'other tutor sees no targets');
reset role;

-- ===========================================================================
-- Planned steps
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq(public.plan_assessment_steps('00000000-0000-0000-0000-0000000d0001'), 6, 'six steps planned');
select tests.eq((select count(*) from public.roadmap_steps where target_id = '00000000-0000-0000-0000-0000000d0001' and source = 'plan'), 6, 'labelled as planned');
select tests.eq((select count(*) from public.roadmap_steps where target_id = '00000000-0000-0000-0000-0000000d0001' and due_on = :'today'), 1, 'first step today');
select tests.eq((select count(*) from public.roadmap_steps where target_id = '00000000-0000-0000-0000-0000000d0001' and due_on = :'today'::date + 13), 1, 'last step the day before');
select tests.fails($$select public.plan_assessment_steps('00000000-0000-0000-0000-0000000d0001')$$, 'planning twice');

-- Steps added by hand are labelled by who added them.
insert into public.roadmap_steps (id, student_id, target_id, title, due_on, source)
  values ('00000000-0000-0000-0000-0000000d0101', :'cara', '00000000-0000-0000-0000-0000000d0001', 'Ask the teacher what the test covers', :'today'::date + 1, 'next_step');
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000d0101' and source = 'parent'), 1, 'parent''s step labelled parent');

-- Ticking off.
select public.tick_roadmap_step('00000000-0000-0000-0000-0000000d0101');
select tests.eq((select count(*) from public.roadmap_steps where done_at is not null and done_by = '00000000-0000-0000-0000-000000000001'), 1, 'parent ticks a step');
select public.tick_roadmap_step('00000000-0000-0000-0000-0000000d0101', false);
select tests.eq((select count(*) from public.roadmap_steps where done_at is not null), 0, 'and un-ticks it');
select tests.fails($$update public.roadmap_steps set done_at = now()$$, 'ticking by direct edit');
update public.roadmap_steps set title = 'Ask Ms Lee what the test covers' where id = '00000000-0000-0000-0000-0000000d0101';
select tests.eq((select count(*) from public.roadmap_steps where title like 'Ask Ms Lee%'), 1, 'parent edits a step');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.fails($$select public.tick_roadmap_step('00000000-0000-0000-0000-0000000d0101')$$, 'other parent ticks a step');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.roadmap_steps where target_id = '00000000-0000-0000-0000-0000000d0001'), 7, 'tutor sees the roadmap');
insert into public.roadmap_steps (id, student_id, title, due_on) values ('00000000-0000-0000-0000-0000000d0102', :'cara', 'Read for 10 minutes each night', :'today'::date + 3);
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000d0102' and source = 'tutor'), 1, 'tutor''s step labelled tutor');
select tests.fails(format($$update public.roadmap_steps set student_id = %L where id = '00000000-0000-0000-0000-0000000d0102'$$, :'cal'), 'step moved to another student');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
delete from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000d0102';
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000d0102'), 1, 'parent can''t remove the tutor''s step');
delete from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000d0101';
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000d0101'), 0, 'parent removes their own step');
reset role;

-- ===========================================================================
-- A session note's next step joins the roadmap
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select public.save_session_note(:'cara', current_date, 60, 'attended', 'Great focus.', 'Practise the 8 times table for 5 minutes a day.') as note \gset
select tests.eq((select count(*) from public.roadmap_steps where note_id = :'note' and source = 'next_step'
  and created_by = '00000000-0000-0000-0000-000000000011' and title like 'Practise the 8 times%'), 1, 'next step becomes a step');
update public.session_notes set next_step = 'Practise the 8 times table for 10 minutes a day.' where id = :'note';
select tests.eq((select count(*) from public.roadmap_steps where note_id = :'note' and title like '%10 minutes%'), 1, 'step follows a corrected next step');
select public.save_session_note(:'cara', current_date, 0, 'absent', null, null) as absent_note \gset
select tests.eq((select count(*) from public.roadmap_steps where note_id = :'absent_note'), 0, 'absent session adds no step');
reset role;

-- ===========================================================================
-- Reminders the afternoon before
-- ===========================================================================
select tests.claims(null);
update public.roadmap_steps set due_on = :'today'::date + 1 where id = '00000000-0000-0000-0000-0000000d0102';
select private.queue_step_reminders();
select private.queue_step_reminders();
select tests.eq((select count(*) from public.progress_notices where kind = 'step_due' and student_id = :'cara'
  and account_id = '00000000-0000-0000-0000-000000000001' and for_date = :'today'::date + 1), 1, 'parent reminded once');
select tests.eq((select count(*) from public.progress_notices where kind = 'step_due' and student_id = :'cara'
  and body like '%Read for 10 minutes%'), 1, 'reminder lists the step');
select tests.eq((select count(*) from public.progress_notices where kind = 'step_due'
  and account_id = '00000000-0000-0000-0000-000000000011'), 0, 'tutor not reminded about family steps');

-- ===========================================================================
-- A student with their own login plans for themselves
-- ===========================================================================
update public.students set account_id = '00000000-0000-0000-0000-000000000031', date_of_birth = current_date - interval '17 years' where id = :'cal';
select tests.claims('00000000-0000-0000-0000-000000000031');
set role authenticated;
insert into public.roadmap_targets (id, student_id, kind, subject, title, due_on)
  values ('00000000-0000-0000-0000-0000000d0002', :'cal', 'assessment', 'English', 'essay draft', :'today'::date + 3);
select tests.eq(public.plan_assessment_steps('00000000-0000-0000-0000-0000000d0002'), 3, 'short time: three steps');
insert into public.roadmap_steps (student_id, title) values (:'cal', 'Pick my essay question');
select tests.eq((select count(*) from public.roadmap_steps where student_id = :'cal' and source = 'student'), 1, 'student''s step labelled student');
select tests.eq((select count(*) from public.roadmap_targets where student_id = :'cara'), 0, 'student sees only their own roadmap');
update public.roadmap_targets set status = 'done' where id = '00000000-0000-0000-0000-0000000d0002';
select tests.eq((select count(*) from public.roadmap_targets where id = '00000000-0000-0000-0000-0000000d0002' and closed_at is not null), 1, 'finishing a target records when');
reset role;

set role anon;
select tests.fails($$select * from public.roadmap_steps$$, 'anon reads steps');
reset role;

-- Tidy up.
select tests.claims(null);
update public.students set account_id = null, date_of_birth = current_date - interval '12 years' where id = :'cal';

\echo '  progress roadmaps: all checks passed'
