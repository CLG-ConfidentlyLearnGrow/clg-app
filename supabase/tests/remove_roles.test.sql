-- Removing roles and deleting accounts (owner only).
-- Reuses access_rules.test.sql helpers: owner (...a0), admin (...b0).

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000007a1', 'rm-parent@example.com', '{"signup_as":"parent","full_name":"Rae Parent"}'),
  ('00000000-0000-0000-0000-0000000007a2', 'rm-gone@example.com', '{"signup_as":"parent","full_name":"Gil Gone"}');
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000007a3', 'rm-learner@example.com',
   json_build_object('signup_as','learner','full_name','Lee Learner','state','SA','year_level','Year 12','school','Hill HS',
                     'date_of_birth', (current_date - interval '17 years')::date));
insert into public.invitations (email, role, invited_by)
values ('rm-tutor@example.com', 'tutor', '00000000-0000-0000-0000-0000000000a0');
insert into auth.users (id, email, invited_at, raw_user_meta_data)
values ('00000000-0000-0000-0000-0000000007a4', 'rm-tutor@example.com', now(), '{"full_name":"Tia Tutor"}');
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-0000000007a4';

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.admin_add_child('00000000-0000-0000-0000-0000000007a1', 'Rio Kid', (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[]') as rio \gset
select public.admin_add_child('00000000-0000-0000-0000-0000000007a2', 'Gus Kid', (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[]') as gk \gset
reset role;

-- Only the owner, and only with the right name.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.fails($$select public.admin_remove_role('00000000-0000-0000-0000-0000000007a1', 'parent', 'Rae Parent')$$, 'non-owner admin removes a role');
select tests.fails($$select public.admin_delete_account('00000000-0000-0000-0000-0000000007a2', 'Gil Gone', true)$$, 'non-owner admin deletes an account');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000007a1');
set role authenticated;
select tests.fails($$select public.admin_remove_role('00000000-0000-0000-0000-0000000007a1', 'parent', 'Rae Parent')$$, 'a parent removes a role');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails_with($$select public.admin_remove_role('00000000-0000-0000-0000-0000000007a1', 'parent', 'Someone Else')$$, 'doesn''t match', 'wrong name');
select tests.fails_with($$select public.admin_remove_role('00000000-0000-0000-0000-0000000007a1', 'tutor', 'Rae Parent')$$, 'doesn''t have that role', 'role they don''t have');
select tests.fails_with($$select public.admin_remove_role('00000000-0000-0000-0000-0000000000a0', 'admin', 'Olive Owner')$$, 'your own admin role', 'owner removes own admin role');
select tests.fails_with($$select public.admin_delete_account('00000000-0000-0000-0000-0000000000a0', 'Olive Owner')$$, 'your own account', 'owner deletes self');

-- Parent role: links go, the child is kept.
select public.admin_remove_role('00000000-0000-0000-0000-0000000007a1', 'parent', 'Rae Parent');
-- Student role: the login no longer opens the record; the record is kept.
select public.admin_remove_role('00000000-0000-0000-0000-0000000007a3', 'student', 'Lee Learner');
-- Tutor role: marked finished today.
select public.admin_remove_role('00000000-0000-0000-0000-0000000007a4', 'tutor', 'Tia Tutor');
reset role;
select tests.eq((select count(*) from public.parent_student_links where parent_id = '00000000-0000-0000-0000-0000000007a1'), 0, 'parent links removed');
select tests.eq((select count(*) from public.students where id = :'rio'), 1, 'child kept under the student rule');
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000007a1'), 0, 'parent role removed');
select tests.eq((select count(*) from public.students where full_name = 'Lee Learner' and account_id is null), 1, 'student record kept without the login');
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000007a3' and role = 'student'), 0, 'student role removed');
select tests.eq((select count(*) from public.tutor_profiles where account_id = '00000000-0000-0000-0000-0000000007a4' and not active and ended_on = current_date), 1, 'tutor marked finished today');
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000007a4' and role = 'tutor'), 0, 'tutor role removed');
select tests.eq((select count(*) from public.audit_log where action = 'remove_role'), 3, 'removals logged');

-- Deleting an account with its students.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.admin_delete_account('00000000-0000-0000-0000-0000000007a2', 'Gil Gone', true);
reset role;
select tests.eq((select count(*) from auth.users where id = '00000000-0000-0000-0000-0000000007a2'), 0, 'account deleted');
select tests.eq((select count(*) from public.students where id = :'gk'), 0, 'their child deleted too');

-- Clean up so later test files see the original fixtures.
delete from public.students where id = :'rio' or full_name = 'Lee Learner';
delete from auth.users where id in ('00000000-0000-0000-0000-0000000007a1', '00000000-0000-0000-0000-0000000007a3', '00000000-0000-0000-0000-0000000007a4');
delete from public.invitations where email = 'rm-tutor@example.com';

\echo '  remove roles and delete accounts: all checks passed'
