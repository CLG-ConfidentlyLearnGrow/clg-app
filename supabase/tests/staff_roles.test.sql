-- Adding a staff role to an existing account. Runs after access_rules.test.sql
-- and reuses its helpers, owner (...a0) and staff admin (...b0).

-- Ids used here: parent ...f1 (confirmed), parent ...f2 (not confirmed).
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values -- Adds two test sign-ups:
  ('00000000-0000-0000-0000-0000000000f1', 'also.tutor@example.com', now(), '{"signup_as":"parent","full_name":"Fay Both"}'), -- Fay, a confirmed parent,
  ('00000000-0000-0000-0000-0000000000f2', 'unconfirmed@example.com', null, '{"signup_as":"parent","full_name":"Finn New"}'); -- and Finn, who hasn't confirmed their email yet.

-- A parent can't make themselves a tutor.
select tests.claims('00000000-0000-0000-0000-0000000000f1', 'aal2'); -- Signs in as test account ...f1 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.grant_staff_role('also.tutor@example.com', 'tutor')$$, 'parent grants self tutor'); -- Checks this is refused: parent grants self tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Admins must use two-step login.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal1'); -- Signs in as test account ...b0.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.grant_staff_role('also.tutor@example.com', 'tutor')$$, 'admin without two-step login'); -- Checks this is refused: admin without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Staff admin: may add tutors, not admins.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.grant_staff_role('also.tutor@example.com', 'admin')$$, 'staff admin adds an admin'); -- Checks this is refused: staff admin adds an admin.
select tests.eq((select public.grant_staff_role('nobody@example.com', 'tutor'))::int, 0, 'no account: send an invitation instead'); -- Checks: no account: send an invitation instead.
select tests.eq((select public.grant_staff_role('unconfirmed@example.com', 'tutor'))::int, 0, 'unconfirmed email is not used'); -- Checks: unconfirmed email is not used.
select tests.eq((select public.grant_staff_role(' Also.Tutor@example.com ', 'tutor'))::int, 1, 'staff admin adds tutor to a parent'); -- Checks: staff admin adds tutor to a parent.
select tests.fails($$select public.grant_staff_role('also.tutor@example.com', 'tutor')$$, 'role already held'); -- Checks this is refused: role already held.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000f1' and role in ('parent', 'tutor')), 2, 'keeps parent role and gains tutor'); -- Checks: keeps parent role and gains tutor.
select tests.eq((select count(*) from public.tutor_profiles where account_id = '00000000-0000-0000-0000-0000000000f1'), 1, 'tutor profile created'); -- Checks: tutor profile created.
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000f2' and role = 'tutor'), 0, 'unconfirmed account unchanged'); -- Checks: unconfirmed account unchanged.

-- The owner may add an admin, and may make themselves a tutor.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select public.grant_staff_role('also.tutor@example.com', 'admin'))::int, 1, 'owner adds an admin'); -- Checks: owner adds an admin.
select tests.eq((select public.grant_staff_role('owner@clg.example', 'tutor'))::int, 1, 'owner becomes a tutor'); -- Checks: owner becomes a tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.admin_profiles where account_id = '00000000-0000-0000-0000-0000000000f1' and level = 'operations'), 1, 'new admin is operations level'); -- Checks: new admin is operations level.

select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select public.grant_staff_role('also.tutor@example.com', 'tutor')$$, 'anon'); -- Checks this is refused: anon.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Prints that every check in this file passed.
\echo '  staff roles: all checks passed'
