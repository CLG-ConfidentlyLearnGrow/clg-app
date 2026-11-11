-- Only tutors add roadmap steps; families tick them off. Reuses the people
-- from progress.test.sql: tutor T1 ...11 (teaches Cara One), parent P1 ...01.

-- Safe to run twice.
-- Runs the database change 20261102590100_progress_tutor_steps.sql first, as this test needs it.
\ir ../migrations/20261102590100_progress_tutor_steps.sql

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$insert into public.roadmap_steps (student_id, title) values (%L, 'Parent step')$$, :'cara'), 'parent adds a step'); -- Checks this is refused: parent adds a step.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.roadmap_steps (id, student_id, title) values ('00000000-0000-0000-0000-0000000e5001', :'cara', 'Tutor step'); -- Adds a roadmap step for Cara.
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000e5001'), 1, 'tutor adds a step'); -- Checks: tutor adds a step.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
update public.roadmap_steps set title = 'Changed by parent' where id = '00000000-0000-0000-0000-0000000e5001'; -- Tries to change the step's words.
select tests.eq((select count(*) from public.roadmap_steps where title = 'Changed by parent'), 0, 'parent can''t change a step'); -- Checks: parent can't change a step.
select public.tick_roadmap_step('00000000-0000-0000-0000-0000000e5001'); -- Ticks the step as done.
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000e5001' and done_at is not null), 1, 'parent ticks it off'); -- Checks: parent ticks it off.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000e5001'; -- Removes the test step.

-- Prints that every check in this file passed.
\echo '  tutor steps: all checks passed'
