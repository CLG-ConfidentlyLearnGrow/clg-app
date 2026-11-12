-- Removing roles and deleting accounts (owner only).
-- Reuses access_rules.test.sql helpers: owner (...a0), admin (...b0).

insert into auth.users (id, email, raw_user_meta_data) values -- Adds two test parents:
  ('00000000-0000-0000-0000-0000000007a1', 'rm-parent@example.com', '{"signup_as":"parent","full_name":"Rae Parent"}'), -- Rae,
  ('00000000-0000-0000-0000-0000000007a2', 'rm-gone@example.com', '{"signup_as":"parent","full_name":"Gil Gone"}'); -- and Gil.
insert into auth.users (id, email, raw_user_meta_data) values -- Adds a learner with their own login:
  ('00000000-0000-0000-0000-0000000007a3', 'rm-learner@example.com', -- Lee,
   json_build_object('signup_as','learner','full_name','Lee Learner','state','SA','year_level','Year 12','school','Hill HS', -- in Year 12 in SA,
                     'date_of_birth', (current_date - interval '17 years')::date)); -- aged 17.
insert into public.invitations (email, role, invited_by) -- Invites a tutor:
values ('rm-tutor@example.com', 'tutor', '00000000-0000-0000-0000-0000000000a0'); -- (invited by the owner).
insert into auth.users (id, email, invited_at, raw_user_meta_data) -- The tutor signs up from the invite:
values ('00000000-0000-0000-0000-0000000007a4', 'rm-tutor@example.com', now(), '{"full_name":"Tia Tutor"}'); -- Tia.
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-0000000007a4'; -- Tia confirms their email.

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Adds a child, Rio, to Rae's family and keeps the id as rio.
select public.admin_add_child('00000000-0000-0000-0000-0000000007a1', 'Rio Kid', (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[]') as rio \gset
-- Adds a child, Gus, to Gil's family and keeps the id as gk.
select public.admin_add_child('00000000-0000-0000-0000-0000000007a2', 'Gus Kid', (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[]') as gk \gset
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Only the owner, and only with the right name.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.admin_remove_role('00000000-0000-0000-0000-0000000007a1', 'parent', 'Rae Parent')$$, 'non-owner admin removes a role'); -- Checks this is refused: non-owner admin removes a role.
select tests.fails($$select public.admin_delete_account('00000000-0000-0000-0000-0000000007a2', 'Gil Gone', true)$$, 'non-owner admin deletes an account'); -- Checks this is refused: non-owner admin deletes an account.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000007a1'); -- Signs in as test account ...7a1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.admin_remove_role('00000000-0000-0000-0000-0000000007a1', 'parent', 'Rae Parent')$$, 'a parent removes a role'); -- Checks this is refused: a parent removes a role.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with($$select public.admin_remove_role('00000000-0000-0000-0000-0000000007a1', 'parent', 'Someone Else')$$, 'doesn''t match', 'wrong name'); -- Checks this is refused with the expected message.
select tests.fails_with($$select public.admin_remove_role('00000000-0000-0000-0000-0000000007a1', 'tutor', 'Rae Parent')$$, 'doesn''t have that role', 'role they don''t have'); -- Checks this is refused with the expected message.
select tests.fails_with($$select public.admin_remove_role('00000000-0000-0000-0000-0000000000a0', 'admin', 'Olive Owner')$$, 'your own admin role', 'owner removes own admin role'); -- Checks this is refused with the expected message.
select tests.fails_with($$select public.admin_delete_account('00000000-0000-0000-0000-0000000000a0', 'Olive Owner')$$, 'your own account', 'owner deletes self'); -- Checks this is refused with the expected message.

-- Parent role: links go, the child is kept.
select public.admin_remove_role('00000000-0000-0000-0000-0000000007a1', 'parent', 'Rae Parent'); -- Removes Rae's parent role (typing their name to confirm).
-- Student role: the login no longer opens the record; the record is kept.
select public.admin_remove_role('00000000-0000-0000-0000-0000000007a3', 'student', 'Lee Learner'); -- Removes Lee's student role.
-- Tutor role: marked finished today.
select public.admin_remove_role('00000000-0000-0000-0000-0000000007a4', 'tutor', 'Tia Tutor'); -- Removes Tia's tutor role.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.parent_student_links where parent_id = '00000000-0000-0000-0000-0000000007a1'), 0, 'parent links removed'); -- Checks: parent links removed.
select tests.eq((select count(*) from public.students where id = :'rio'), 1, 'child kept under the student rule'); -- Checks: child kept under the student rule.
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000007a1'), 0, 'parent role removed'); -- Checks: parent role removed.
select tests.eq((select count(*) from public.students where full_name = 'Lee Learner' and account_id is null), 1, 'student record kept without the login'); -- Checks: student record kept without the login.
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000007a3' and role = 'student'), 0, 'student role removed'); -- Checks: student role removed.
select tests.eq((select count(*) from public.tutor_profiles where account_id = '00000000-0000-0000-0000-0000000007a4' and not active and ended_on = current_date), 1, 'tutor marked finished today'); -- Checks: tutor marked finished today.
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000007a4' and role = 'tutor'), 0, 'tutor role removed'); -- Checks: tutor role removed.
select tests.eq((select count(*) from public.audit_log where action = 'remove_role'), 3, 'removals logged'); -- Checks: removals logged.

-- Deleting an account with its students.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_delete_account('00000000-0000-0000-0000-0000000007a2', 'Gil Gone', true); -- Deletes Gil's account, and their students too.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from auth.users where id = '00000000-0000-0000-0000-0000000007a2'), 0, 'account deleted'); -- Checks: account deleted.
select tests.eq((select count(*) from public.students where id = :'gk'), 0, 'their child deleted too'); -- Checks: their child deleted too.

-- Clean up so later test files see the original fixtures.
delete from public.students where id = :'rio' or full_name = 'Lee Learner'; -- Removes the test students.
delete from auth.users where id in ('00000000-0000-0000-0000-0000000007a1', '00000000-0000-0000-0000-0000000007a3', '00000000-0000-0000-0000-0000000007a4'); -- Removes the test accounts.
delete from public.invitations where email = 'rm-tutor@example.com'; -- Removes the test invite.

-- Prints that every check in this file passed.
\echo '  remove roles and delete accounts: all checks passed'
