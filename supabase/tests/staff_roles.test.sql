-- Adding a staff role to an existing account. Runs after access_rules.test.sql
-- and reuses its helpers, owner (...a0) and staff admin (...b0).

-- Ids used here: parent ...f1 (confirmed), parent ...f2 (not confirmed).
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000f1', 'also.tutor@example.com', now(), '{"signup_as":"parent","full_name":"Fay Both"}'),
  ('00000000-0000-0000-0000-0000000000f2', 'unconfirmed@example.com', null, '{"signup_as":"parent","full_name":"Finn New"}');

-- A parent can't make themselves a tutor.
select tests.claims('00000000-0000-0000-0000-0000000000f1', 'aal2');
set role authenticated;
select tests.fails($$select public.grant_staff_role('also.tutor@example.com', 'tutor')$$, 'parent grants self tutor');
reset role;

-- Admins must use two-step login.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal1');
set role authenticated;
select tests.fails($$select public.grant_staff_role('also.tutor@example.com', 'tutor')$$, 'admin without two-step login');
reset role;

-- Staff admin: may add tutors, not admins.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.fails($$select public.grant_staff_role('also.tutor@example.com', 'admin')$$, 'staff admin adds an admin');
select tests.eq((select public.grant_staff_role('nobody@example.com', 'tutor'))::int, 0, 'no account: send an invitation instead');
select tests.eq((select public.grant_staff_role('unconfirmed@example.com', 'tutor'))::int, 0, 'unconfirmed email is not used');
select tests.eq((select public.grant_staff_role(' Also.Tutor@example.com ', 'tutor'))::int, 1, 'staff admin adds tutor to a parent');
select tests.fails($$select public.grant_staff_role('also.tutor@example.com', 'tutor')$$, 'role already held');
reset role;

select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000f1' and role in ('parent', 'tutor')), 2, 'keeps parent role and gains tutor');
select tests.eq((select count(*) from public.tutor_profiles where account_id = '00000000-0000-0000-0000-0000000000f1'), 1, 'tutor profile created');
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000f2' and role = 'tutor'), 0, 'unconfirmed account unchanged');

-- The owner may add an admin, and may make themselves a tutor.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select public.grant_staff_role('also.tutor@example.com', 'admin'))::int, 1, 'owner adds an admin');
select tests.eq((select public.grant_staff_role('owner@clg.example', 'tutor'))::int, 1, 'owner becomes a tutor');
reset role;
select tests.eq((select count(*) from public.admin_profiles where account_id = '00000000-0000-0000-0000-0000000000f1' and level = 'operations'), 1, 'new admin is operations level');

select tests.claims(null);
set role anon;
select tests.fails($$select public.grant_staff_role('also.tutor@example.com', 'tutor')$$, 'anon');
reset role;

\echo '  staff roles: all checks passed'
