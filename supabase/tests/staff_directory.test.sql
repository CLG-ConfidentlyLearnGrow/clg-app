-- Staff directory: who can see it, who can set job titles, and what it shows.
-- Runs after access_rules.test.sql and reuses owner (...a0), operations
-- admin (...b0), parent P1 (...01) and tutor T1 (...11).
-- Ids used here: support admin ...7d1, finance admin ...7d2 (removed at the end).

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values -- Adds two test sign-ups:
  ('00000000-0000-0000-0000-0000000007d1', 'dir.desk@clg.example', now(), '{"signup_as":"parent","full_name":"Dir Desk"}'), -- Dir Desk,
  ('00000000-0000-0000-0000-0000000007d2', 'dir.books@clg.example', now(), '{"signup_as":"parent","full_name":"Dir Books"}'); -- and Dir Books.
insert into public.account_roles (account_id, role) values -- Makes both of them admins:
  ('00000000-0000-0000-0000-0000000007d1', 'admin'), -- Dir Desk,
  ('00000000-0000-0000-0000-0000000007d2', 'admin') -- Dir Books,
on conflict do nothing; -- (unless they already are).
insert into public.admin_profiles (account_id, level) values -- Sets their admin levels:
  ('00000000-0000-0000-0000-0000000007d1', 'support'), -- Dir Desk at support level,
  ('00000000-0000-0000-0000-0000000007d2', 'finance') -- Dir Books at finance level,
on conflict (account_id) do update set level = excluded.level; -- (replacing any level they had).

-- ---------------------------------------------------------------------------
-- Setting job titles
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.set_staff_job_title('00000000-0000-0000-0000-0000000000a0', '  Director   and Child Safety Officer '); -- Sets the owner's job title (with untidy spacing to be tidied).
select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', 'Tutor'); -- Sets tutor T1's job title.
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000001', 'Parent')$$, 'job title for a parent (not staff)'); -- Checks this is refused: job title for a parent (not staff).
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', 'T')$$, 'job title too short'); -- Checks this is refused: job title too short.
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', repeat('x', 81))$$, 'job title too long'); -- Checks this is refused: job title too long.
select tests.fails($$insert into public.staff_job_titles (account_id, job_title) values ('00000000-0000-0000-0000-0000000000b0', 'Direct write')$$, 'writes the table directly'); -- Checks this is refused: writes the table directly.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.staff_job_titles where account_id = '00000000-0000-0000-0000-0000000000a0' and job_title = 'Director and Child Safety Officer'), 1, 'job title saved with spaces tidied'); -- Checks: job title saved with spaces tidied.
select tests.eq((select count(*) from public.audit_log where action = 'job_title' and record_id = '00000000-0000-0000-0000-000000000011'), 1, 'job title change logged'); -- Checks: job title change logged.

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.set_staff_job_title('00000000-0000-0000-0000-0000000000b0', 'Operations coordinator'); -- Sets the staff admin's job title.
select public.set_staff_job_title('00000000-0000-0000-0000-0000000007d1', 'Office support'); -- Sets Dir Desk's job title.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.staff_job_titles where account_id = '00000000-0000-0000-0000-0000000007d1'), 1, 'operations sets a job title'); -- Checks: operations sets a job title.

-- Without two-step login, operations can't.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal1'); -- Signs in as test account ...b0.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', 'Senior tutor')$$, 'operations without two-step login'); -- Checks this is refused: operations without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Support, finance, tutors and parents can't change job titles.
select tests.claims('00000000-0000-0000-0000-0000000007d1', 'aal2'); -- Signs in as test account ...7d1 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-0000000007d1', 'Head of everything')$$, 'support sets a job title'); -- Checks this is refused: support sets a job title.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000007d2', 'aal2'); -- Signs in as test account ...7d2 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', 'Senior tutor')$$, 'finance sets a job title'); -- Checks this is refused: finance sets a job title.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', 'Senior tutor')$$, 'tutor sets own job title'); -- Checks this is refused: tutor sets own job title.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- Signs in as test account ...01 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.set_staff_job_title('00000000-0000-0000-0000-000000000011', 'Senior tutor')$$, 'parent sets a job title'); -- Checks this is refused: parent sets a job title.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Reading the directory
-- ---------------------------------------------------------------------------
-- Every admin level sees every staff member.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.staff_directory()), -- Checks the owner sees every staff member:
  (select count(distinct account_id) from public.account_roles where role in ('admin', 'tutor')), 'owner sees every staff member'); -- (as many as there are admins and tutors).
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-000000000001'), 0, 'parents are not in the directory'); -- Checks: parents are not in the directory.
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-000000000011' and is_tutor and job_title = 'Tutor'), 1, 'tutor shown with job title'); -- Checks: tutor shown with job title.
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000007d2' and is_admin and admin_level = 'finance' and job_title is null), 1, 'admin without a job title shows level'); -- Checks: admin without a job title shows level.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000007d1', 'aal2'); -- Signs in as test account ...7d1 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000000a0'), 1, 'support sees the directory'); -- Checks: support sees the directory.
select tests.eq((select count(*) from public.staff_job_titles), 4, 'support reads every job title'); -- Checks: support reads every job title.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000007d2', 'aal2'); -- Signs in as test account ...7d2 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000000a0'), 1, 'finance sees the directory'); -- Checks: finance sees the directory.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Not admins, or admins without two-step login: nothing.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.staff_directory()), 0, 'tutor does not see the directory'); -- Checks: tutor does not see the directory.
select tests.eq((select count(*) from public.staff_job_titles), 1, 'tutor reads only their own job title'); -- Checks: tutor reads only their own job title.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- Signs in as test account ...01 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.staff_directory()), 0, 'parent does not see the directory'); -- Checks: parent does not see the directory.
select tests.eq((select count(*) from public.staff_job_titles), 0, 'parent reads no job titles'); -- Checks: parent reads no job titles.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000007d1', 'aal1'); -- Signs in as test account ...7d1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.staff_directory()), 0, 'admin without two-step login sees nothing'); -- Checks: admin without two-step login sees nothing.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.staff_directory()$$, 'signed-out visitor reads the directory'); -- Checks this is refused: signed-out visitor reads the directory.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- A blank title removes it.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.set_staff_job_title('00000000-0000-0000-0000-0000000007d1', '   '); -- Clears Dir Desk's job title (blank).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.staff_job_titles where account_id = '00000000-0000-0000-0000-0000000007d1'), 0, 'blank title removes it'); -- Checks: blank title removes it.

-- ---------------------------------------------------------------------------
-- Adding and removing roles from the directory
-- ---------------------------------------------------------------------------
-- (Test accounts sign up as parents, so take that role away first.)
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_remove_role('00000000-0000-0000-0000-0000000007d1', 'parent', 'Dir Desk'); -- Removes Dir Desk's parent role.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_add_role('00000000-0000-0000-0000-0000000007d2', 'tutor'); -- Gives Dir Books the tutor role.
select public.admin_add_role('00000000-0000-0000-0000-0000000007d1', 'parent'); -- Gives Dir Desk the parent role.
select tests.fails($$select public.admin_add_role('00000000-0000-0000-0000-0000000007d2', 'tutor')$$, 'adds a role they already have'); -- Checks this is refused: adds a role they already have.
select tests.fails($$select public.admin_add_role('00000000-0000-0000-0000-000000000011', 'admin', 'support')$$, 'operations adds an admin'); -- Checks this is refused: operations adds an admin.
select tests.fails($$select public.admin_add_role('00000000-0000-0000-0000-0000000007d1', 'student')$$, 'student role added here'); -- Checks this is refused: student role added here.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.tutor_profiles where account_id = '00000000-0000-0000-0000-0000000007d2' and active), 1, 'operations adds a tutor role'); -- Checks: operations adds a tutor role.
select tests.eq((select count(*) from public.tutor_work_settings where tutor_id = '00000000-0000-0000-0000-0000000007d2'), 1, 'new tutor gets work settings'); -- Checks: new tutor gets work settings.
select tests.eq((select count(*) from public.parent_profiles where account_id = '00000000-0000-0000-0000-0000000007d1'), 1, 'operations adds a parent role'); -- Checks: operations adds a parent role.
select tests.eq((select count(*) from public.audit_log where action = 'add_role' and record_id = '00000000-0000-0000-0000-0000000007d2'), 1, 'added role logged'); -- Checks: added role logged.

-- Support, finance, tutors and admins without two-step login can't add roles.
select tests.claims('00000000-0000-0000-0000-0000000007d1', 'aal2'); -- Signs in as test account ...7d1 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.admin_add_role('00000000-0000-0000-0000-000000000001', 'tutor')$$, 'support adds a role'); -- Checks this is refused: support adds a role.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.admin_add_role('00000000-0000-0000-0000-000000000011', 'parent')$$, 'tutor adds a role'); -- Checks this is refused: tutor adds a role.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal1'); -- Signs in as test account ...b0.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.admin_add_role('00000000-0000-0000-0000-000000000001', 'tutor')$$, 'operations without two-step login adds a role'); -- Checks this is refused: operations without two-step login adds a role.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The directory shows every role and who has never signed in.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000007d1' and is_parent and is_admin and last_sign_in_at is null), 1, 'directory shows parent role and no sign-in yet'); -- Checks: directory shows parent role and no sign-in yet.

-- Owner: adds an admin at a level, removes it, and brings a finished tutor back.
select public.admin_add_role('00000000-0000-0000-0000-000000000011', 'admin', 'support'); -- Makes tutor T1 a support admin too.
select tests.fails($$select public.admin_add_role('00000000-0000-0000-0000-000000000001', 'admin', 'owner')$$, 'owner makes a second owner'); -- Checks this is refused: owner makes a second owner.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.admin_profiles where account_id = '00000000-0000-0000-0000-000000000011' and level = 'support'), 1, 'owner adds an admin at a level'); -- Checks: owner adds an admin at a level.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_remove_role('00000000-0000-0000-0000-000000000011', 'admin', (select full_name from public.accounts where id = '00000000-0000-0000-0000-000000000011')); -- Takes tutor T1's admin role away again.
select public.admin_remove_role('00000000-0000-0000-0000-0000000007d2', 'tutor', 'Dir Books'); -- Takes Dir Books's tutor role away.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-000000000011' and role = 'admin'), 0, 'owner removes the admin role'); -- Checks: owner removes the admin role.
select tests.eq((select count(*) from public.tutor_profiles where account_id = '00000000-0000-0000-0000-0000000007d2' and not active and ended_on is not null), 1, 'removed tutor is finished'); -- Checks: removed tutor is finished.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_add_role('00000000-0000-0000-0000-0000000007d2', 'tutor'); -- Gives Dir Books the tutor role again.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.tutor_profiles where account_id = '00000000-0000-0000-0000-0000000007d2' and active and ended_on is null), 1, 'finished tutor made current again'); -- Checks: finished tutor made current again.

-- Tidy up so later tests see the same staff as before.
delete from public.account_roles where account_id in ('00000000-0000-0000-0000-0000000007d1', '00000000-0000-0000-0000-0000000007d2'); -- Removes the test roles.
delete from public.security_alerts where account_id in ('00000000-0000-0000-0000-0000000007d1', '00000000-0000-0000-0000-0000000007d2'); -- Removes the alerts the test made.
delete from auth.users where id in ('00000000-0000-0000-0000-0000000007d1', '00000000-0000-0000-0000-0000000007d2'); -- Removes the test accounts.
delete from public.staff_job_titles; -- Clears the job titles.
select tests.claims(null); -- Signs out, so no one is signed in.
