-- Staff directory: who can see it, who can set job titles, and what it shows.
-- Runs after access_rules.test.sql and reuses owner (...a0), operations
-- admin (...b0), parent P1 (...01) and tutor T1 (...11).
-- Ids used here: support admin ...7d1, finance admin ...7d2 (removed at the end).

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000007d1', 'dir.desk@clg.example', now(), '{"signup_as":"parent","full_name":"Dir Desk"}'),
  ('00000000-0000-0000-0000-0000000007d2', 'dir.books@clg.example', now(), '{"signup_as":"parent","full_name":"Dir Books"}');
insert into public.account_roles (account_id, role) values
  ('00000000-0000-0000-0000-0000000007d1', 'admin'),
  ('00000000-0000-0000-0000-0000000007d2', 'admin')
on conflict do nothing;
insert into public.admin_profiles (account_id, level) values
  ('00000000-0000-0000-0000-0000000007d1', 'support'),
  ('00000000-0000-0000-0000-0000000007d2', 'finance')
on conflict (account_id) do update set level = excluded.level;

-- ---------------------------------------------------------------------------
-- Setting job titles
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.set_staff_job_title('00000000-0000-0000-0000-0000000000a0', '  Director   and Child Safety Officer ');
select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', 'Tutor');
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000001', 'Parent')$$, 'job title for a parent (not staff)');
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', 'T')$$, 'job title too short');
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', repeat('x', 81))$$, 'job title too long');
select tests.fails($$insert into public.staff_job_titles (account_id, job_title) values ('00000000-0000-0000-0000-0000000000b0', 'Direct write')$$, 'writes the table directly');
reset role;
select tests.eq((select count(*) from public.staff_job_titles where account_id = '00000000-0000-0000-0000-0000000000a0' and job_title = 'Director and Child Safety Officer'), 1, 'job title saved with spaces tidied');
select tests.eq((select count(*) from public.audit_log where action = 'job_title' and record_id = '00000000-0000-0000-0000-000000000011'), 1, 'job title change logged');

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.set_staff_job_title('00000000-0000-0000-0000-0000000000b0', 'Operations coordinator');
select public.set_staff_job_title('00000000-0000-0000-0000-0000000007d1', 'Office support');
reset role;
select tests.eq((select count(*) from public.staff_job_titles where account_id = '00000000-0000-0000-0000-0000000007d1'), 1, 'operations sets a job title');

-- Without two-step login, operations can't.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal1');
set role authenticated;
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', 'Senior tutor')$$, 'operations without two-step login');
reset role;

-- Support, finance, tutors and parents can't change job titles.
select tests.claims('00000000-0000-0000-0000-0000000007d1', 'aal2');
set role authenticated;
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-0000000007d1', 'Head of everything')$$, 'support sets a job title');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000007d2', 'aal2');
set role authenticated;
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', 'Senior tutor')$$, 'finance sets a job title');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', 'Senior tutor')$$, 'tutor sets own job title');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2');
set role authenticated;
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', 'Senior tutor')$$, 'parent sets a job title');
reset role;

-- ---------------------------------------------------------------------------
-- Reading the directory
-- ---------------------------------------------------------------------------
-- Every admin level sees every staff member.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.staff_directory()),
  (select count(distinct account_id) from public.account_roles where role in ('admin', 'tutor')), 'owner sees every staff member');
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-000000000001'), 0, 'parents are not in the directory');
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-000000000011' and is_tutor and job_title = 'Tutor'), 1, 'tutor shown with job title');
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000007d2' and is_admin and admin_level = 'finance' and job_title is null), 1, 'admin without a job title shows level');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000007d1', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000000a0'), 1, 'support sees the directory');
select tests.eq((select count(*) from public.staff_job_titles), 4, 'support reads every job title');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000007d2', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000000a0'), 1, 'finance sees the directory');
reset role;

-- Not admins, or admins without two-step login: nothing.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.staff_directory()), 0, 'tutor does not see the directory');
select tests.eq((select count(*) from public.staff_job_titles), 1, 'tutor reads only their own job title');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.staff_directory()), 0, 'parent does not see the directory');
select tests.eq((select count(*) from public.staff_job_titles), 0, 'parent reads no job titles');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000007d1', 'aal1');
set role authenticated;
select tests.eq((select count(*) from public.staff_directory()), 0, 'admin without two-step login sees nothing');
reset role;
select tests.claims(null);
set role anon;
select tests.fails($$select * from public.staff_directory()$$, 'signed-out visitor reads the directory');
reset role;

-- A blank title removes it.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.set_staff_job_title('00000000-0000-0000-0000-0000000007d1', '   ');
reset role;
select tests.eq((select count(*) from public.staff_job_titles where account_id = '00000000-0000-0000-0000-0000000007d1'), 0, 'blank title removes it');

-- Tidy up so later tests see the same staff as before.
delete from public.account_roles where account_id in ('00000000-0000-0000-0000-0000000007d1', '00000000-0000-0000-0000-0000000007d2');
delete from public.security_alerts where account_id in ('00000000-0000-0000-0000-0000000007d1', '00000000-0000-0000-0000-0000000007d2');
delete from auth.users where id in ('00000000-0000-0000-0000-0000000007d1', '00000000-0000-0000-0000-0000000007d2');
delete from public.staff_job_titles;
select tests.claims(null);
