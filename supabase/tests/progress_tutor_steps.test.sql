-- Only tutors add roadmap steps; families tick them off. Reuses the people
-- from progress.test.sql: tutor T1 ...11 (teaches Cara One), parent P1 ...01.

-- Safe to run twice.
\ir ../migrations/20261102590100_progress_tutor_steps.sql

select tests.claims(null);
select id as cara from public.students where full_name = 'Cara One' \gset

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails(format($$insert into public.roadmap_steps (student_id, title) values (%L, 'Parent step')$$, :'cara'), 'parent adds a step');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
insert into public.roadmap_steps (id, student_id, title) values ('00000000-0000-0000-0000-0000000e5001', :'cara', 'Tutor step');
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000e5001'), 1, 'tutor adds a step');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
update public.roadmap_steps set title = 'Changed by parent' where id = '00000000-0000-0000-0000-0000000e5001';
select tests.eq((select count(*) from public.roadmap_steps where title = 'Changed by parent'), 0, 'parent can''t change a step');
select public.tick_roadmap_step('00000000-0000-0000-0000-0000000e5001');
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000e5001' and done_at is not null), 1, 'parent ticks it off');
reset role;

select tests.claims(null);
delete from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000e5001';

\echo '  tutor steps: all checks passed'
