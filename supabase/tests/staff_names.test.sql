-- Summary: tests for first and last names (20261117400100_staff_names.sql):
-- the full name follows the first and last name, people change their own
-- name, only the owner and operations admins change a staff member's name,
-- nobody changes first or last name directly, and every change is logged.
-- Runs after access_rules.test.sql and reuses owner (...a0) and operations
-- admin (...b0).
-- Ids used here: tutor ...7f1 (joined as "amy.swann2000"), support admin
-- ...7f2 and parent ...7f3 (all removed at the end).

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values -- Adds three test sign-ups:
  ('00000000-0000-0000-0000-0000000007f1', 'amy.swann2000@clg.example', now(), '{"signup_as":"parent"}'), -- a tutor who gave no name (so her name is the start of her email),
  ('00000000-0000-0000-0000-0000000007f2', 'nina.desk@clg.example', now(), '{"signup_as":"parent","full_name":"Nina Desk"}'), -- a support admin,
  ('00000000-0000-0000-0000-0000000007f3', 'pete.parent@clg.example', now(), '{"signup_as":"parent","full_name":"Pete Parent"}'); -- and a parent.
insert into public.account_roles (account_id, role) values -- Gives two of them staff roles:
  ('00000000-0000-0000-0000-0000000007f1', 'tutor'), -- the first is a tutor,
  ('00000000-0000-0000-0000-0000000007f2', 'admin') -- the second is an admin,
on conflict do nothing; -- (unless they already are).
insert into public.admin_profiles (account_id, level) values ('00000000-0000-0000-0000-0000000007f2', 'support') -- at support level
on conflict (account_id) do update set level = excluded.level; -- (replacing any level she had).

-- ---------------------------------------------------------------------------
-- Before any names are set
-- ---------------------------------------------------------------------------
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-0000000007f1' and full_name = 'amy.swann2000'), 1, 'no name given: shows the start of the email'); -- Checks: the problem Carla saw.
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-0000000007f1' and first_name is null and last_name is null), 1, 'existing staff start with no first or last name'); -- Checks: the app will ask her for it.

-- ---------------------------------------------------------------------------
-- Changing your own name
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000007f1', 'aal2'); -- Signs in as the tutor.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.set_my_name('  Amy ', ' Swann   Smith '); -- Sets her own name (with untidy spacing to be tidied).
select tests.fails_with($$select public.set_my_name('', 'Swann')$$, 'enter a first name', 'blank first name refused'); -- Checks: a first name is needed.
select tests.fails_with($$select public.set_my_name('Amy', '   ')$$, 'enter a last name', 'blank last name refused'); -- Checks: a last name is needed.
select tests.fails_with($$select public.set_my_name(repeat('a', 101), 'Swann')$$, '100 characters', 'too-long name refused'); -- Checks: names have a length limit.
select tests.fails_with($$select public.set_my_name('amy.swann2000@gmail.com', 'Swann')$$, 'not an email address', 'email typed as a name refused'); -- Checks: an email address isn't a name.
select tests.fails($$update public.accounts set first_name = 'Sneaky' where id = '00000000-0000-0000-0000-0000000007f1'$$, 'first name changed directly'); -- Checks: nobody changes their first name directly.
select tests.fails($$update public.accounts set last_name = 'Sneaky' where id = '00000000-0000-0000-0000-0000000007f1'$$, 'last name changed directly'); -- Checks: nobody changes their last name directly.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-0000000007f1' and first_name || '|' || last_name = 'Amy|Swann Smith'), 1, 'own name saved with spaces tidied'); -- Checks: saved, tidied.
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-0000000007f1' and full_name = 'Amy Swann Smith'), 1, 'full name follows first and last name'); -- Checks: the name shown everywhere is now the real name.
select tests.eq((select count(*) from public.audit_log where action = 'name_change' and record_id = '00000000-0000-0000-0000-0000000007f1' and details ->> 'by' = 'self' and details ->> 'from' = 'amy.swann2000'), 1, 'own name change logged with the old name'); -- Checks: logged.

-- Writing the full name directly can't undo the real name once it's set.
select tests.claims('00000000-0000-0000-0000-0000000007f1', 'aal2'); -- Signs in as the tutor again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
update public.accounts set full_name = 'Someone Else' where id = '00000000-0000-0000-0000-0000000007f1'; -- Tries to change the full name directly.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-0000000007f1' and full_name = 'Amy Swann Smith'), 1, 'full name stays first and last name'); -- Checks: still her real name.

-- A parent can set their own name too (it's not only for staff).
select tests.claims('00000000-0000-0000-0000-0000000007f3', 'aal1'); -- Signs in as the parent (no two-step sign-in needed).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.set_my_name('Peter', 'Parent'); -- Sets his own name.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-0000000007f3' and full_name = 'Peter Parent'), 1, 'parent sets own name'); -- Checks: saved.

-- Nobody signed in can't use it.
set role anon; -- Acts as a visitor who isn't signed in.
select tests.fails($$select public.set_my_name('No', 'Body')$$, 'visitor cannot set a name'); -- Checks: refused for visitors.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Admins changing a staff member's name
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the operations admin with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.set_staff_name('00000000-0000-0000-0000-0000000007f1', 'Amy', 'Swann'); -- Fixes the tutor's last name.
select tests.fails_with($$select public.set_staff_name('00000000-0000-0000-0000-0000000007f3', 'Pete', 'Parent')$$, 'is not a staff member', 'admin cannot use it for a parent'); -- Checks: only for staff.
select tests.fails_with($$select public.set_staff_name('00000000-0000-0000-0000-0000000007f1', 'Amy', '')$$, 'enter a last name', 'admin must give both names'); -- Checks: the same name checks apply.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-0000000007f1' and full_name = 'Amy Swann'), 1, 'operations admin changes a staff name'); -- Checks: saved.
select tests.eq((select count(*) from public.audit_log where action = 'name_change' and record_id = '00000000-0000-0000-0000-0000000007f1' and details ->> 'by' = 'admin'), 1, 'admin name change logged'); -- Checks: logged.

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.set_staff_name('00000000-0000-0000-0000-0000000007f2', 'Nina', 'Deskworth'); -- Changes the support admin's name.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-0000000007f2' and full_name = 'Nina Deskworth'), 1, 'owner changes a staff name'); -- Checks: saved.

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal1'); -- Signs in as the owner WITHOUT two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with($$select public.set_staff_name('00000000-0000-0000-0000-0000000007f1', 'Amy', 'Other')$$, 'Only the owner or an operations admin', 'owner needs two-step sign-in'); -- Checks: refused without two-step sign-in.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000007f2', 'aal2'); -- Signs in as the support admin.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with($$select public.set_staff_name('00000000-0000-0000-0000-0000000007f1', 'Amy', 'Other')$$, 'Only the owner or an operations admin', 'support admin cannot change staff names'); -- Checks: refused for support.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000007f1', 'aal2'); -- Signs in as the tutor.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with($$select public.set_staff_name('00000000-0000-0000-0000-0000000007f2', 'Nina', 'Other')$$, 'Only the owner or an operations admin', 'tutor cannot change another person''s name'); -- Checks: refused for a tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-0000000007f2' and full_name = 'Nina Deskworth'), 1, 'refused changes left the name alone'); -- Checks: nothing changed.

-- The new name shows in the staff directory.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000007f1' and full_name = 'Amy Swann'), 1, 'staff directory shows the real name'); -- Checks: the directory uses the real name.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Clean up
-- ---------------------------------------------------------------------------
delete from public.account_roles where account_id in ('00000000-0000-0000-0000-0000000007f1', '00000000-0000-0000-0000-0000000007f2'); -- Removes the test staff roles first.
delete from public.security_alerts where account_id in ('00000000-0000-0000-0000-0000000007f1', '00000000-0000-0000-0000-0000000007f2'); -- Removes the alerts the test made.
delete from auth.users where id in ('00000000-0000-0000-0000-0000000007f1', '00000000-0000-0000-0000-0000000007f2', '00000000-0000-0000-0000-0000000007f3'); -- Removes the three test sign-ups (their accounts go with them).
