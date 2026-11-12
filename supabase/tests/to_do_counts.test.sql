-- To-do counts across the app (Carla, 11 Nov 2026): numbers on menus and
-- dashboard tabs. Uses its own parent (...d7) and tutor (...d8), plus the
-- owner admin (...a0). Admin numbers are checked as changes, because other
-- tests leave their own to-dos behind.

create function tests.todo(p_area text, p_section text) returns bigint -- A test helper that gives the signed-in person's to-do number for one area and menu item:
language sql as $$ -- (written in SQL)
  select coalesce(sum(n), 0)::bigint from public.to_do_counts() where area = p_area and section = p_section -- adds up the matching numbers (0 if none).
$$; -- (end of the helper)
grant execute on function tests.todo(text, text) to authenticated; -- Lets signed-in test users run it.

select tests.claims(null); -- Signs out, so no one is signed in.
insert into auth.users (id, email, raw_user_meta_data) values -- Adds a test parent:
  ('00000000-0000-0000-0000-0000000000d7', 'todo-parent@example.com', '{"signup_as":"parent","full_name":"Tess Parent"}'); -- Tess (account ...d7).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.invitations (email, role, invited_by) values ('todo-tutor@clg.example', 'tutor', '00000000-0000-0000-0000-0000000000a0'); -- Invites a test tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).
insert into auth.users (id, email, raw_user_meta_data) values -- The tutor signs up from the invite:
  ('00000000-0000-0000-0000-0000000000d8', 'todo-tutor@clg.example', '{"full_name":"Toby Tutor"}'); -- Toby (account ...d8).
update auth.users set invited_at = now(), email_confirmed_at = now() where email = 'todo-tutor@clg.example'; -- Marks Toby as invited and confirmed.

-- Signed out: no counts at all.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($q$select * from public.to_do_counts()$q$, 'signed-out visitors get no counts'); -- Checks this is refused: signed-out visitors get no counts.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Parent: a child without an end goal is a detail to finish.
select tests.claims('00000000-0000-0000-0000-0000000000d7'); -- Signs in as test account ...d7.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.add_my_child('Tia Parent', (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Bay PS', -- Tess adds a child, Tia, 9, Year 4:
  '[{"subject": "Mathematics", "level": "Year 4"}]'); -- (Mathematics at Year 4).
select tests.eq(tests.todo('parent', 'children'), 1, 'parent: one child''s details to finish'); -- Checks: parent: one child's details to finish.
select tests.eq((select count(*) from public.to_do_counts() where area in ('admin', 'billing', 'privacy', 'tutor')), 0, -- Checks parents get no admin or tutor numbers:
  'parents get no admin or tutor counts'); -- (the label).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
update public.students set goals = 'Feel confident with fractions' where full_name = 'Tia Parent'; -- Writes Tia's goal.
select tests.claims('00000000-0000-0000-0000-0000000000d7'); -- Signs in as test account ...d7.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(tests.todo('parent', 'children'), 0, 'parent: details finished, nothing to do'); -- Checks: parent: details finished, nothing to do.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Parent: an unread session notice counts on Sessions.
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.session_notices (account_id, kind, title, body, deliver_at) -- Adds an unread notice for Tess:
values ('00000000-0000-0000-0000-0000000000d7', 'session_cancelled', 'To-do test', 'Test notice', now() - interval '1 minute'); -- (delivered a minute ago).
select tests.claims('00000000-0000-0000-0000-0000000000d7'); -- Signs in as test account ...d7.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(tests.todo('sessions', 'notices'), 1, 'unread notice counts on Sessions'); -- Checks: unread notice counts on Sessions.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
update public.session_notices set read_at = now() where account_id = '00000000-0000-0000-0000-0000000000d7'; -- Marks Tess's notices as read.
select tests.claims('00000000-0000-0000-0000-0000000000d7'); -- Signs in as test account ...d7.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(tests.todo('sessions', 'notices'), 0, 'read notice no longer counts'); -- Checks: read notice no longer counts.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Tutor: nothing in "What you teach" yet, and checks missing.
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.tutor_work_settings (tutor_id, work_state) values ('00000000-0000-0000-0000-0000000000d8', 'SA') -- Toby works in SA:
on conflict (tutor_id) do update set work_state = excluded.work_state; -- (or updates it if already set).
select tests.claims('00000000-0000-0000-0000-0000000000d8', 'aal2'); -- Signs in as test account ...d8 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(tests.todo('tutor', 'teaching'), 1, 'new tutor: what you teach to fill in'); -- Checks: new tutor: what you teach to fill in.
select tests.eq((tests.todo('tutor', 'checks') > 0)::int, 1, 'new tutor: checks missing'); -- Checks: new tutor: checks missing.
select tests.eq((select count(*) from public.to_do_counts() where area in ('admin', 'billing', 'privacy')), 0, -- Checks tutors get no admin numbers:
  'tutors get no admin counts'); -- (the label).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) -- Toby teaches Mathematics:
values ('00000000-0000-0000-0000-0000000000d8', 'Mathematics', 'Year 3', 'Year 6'); -- from Year 3 to Year 6.
select tests.claims('00000000-0000-0000-0000-0000000000d8', 'aal2'); -- Signs in as test account ...d8 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(tests.todo('tutor', 'teaching'), 0, 'tutor: what you teach filled in'); -- Checks: tutor: what you teach filled in.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Admin: a tutor's check waiting to be confirmed, and the tutor's own count
-- going down once it's confirmed.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Keeps the admin "tutors" number as tutors_before.
select tests.todo('admin', 'tutors') as tutors_before \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000d8', 'aal2'); -- Signs in as test account ...d8 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Keeps Toby's "checks" number as tutor_checks_before.
select tests.todo('tutor', 'checks') as tutor_checks_before \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.tutor_checks (tutor_id, kind, reference, expires_on, submitted_at) -- Toby sends in an SA WWCC:
values ('00000000-0000-0000-0000-0000000000d8', 'wwcc_sa', 'TODO-1', current_date + 365, now()) -- (expiring in a year, sent now),
-- and keeps its id as todo_check.
returning id as todo_check \gset
-- Made here to look like a tutor's own upload, still waiting for CLG.
update public.tutor_checks set verified_at = null, verified_by = null where id = :'todo_check'; -- Marks it as not yet confirmed.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(tests.todo('admin', 'tutors'), :tutors_before + 1, 'admin: new check to confirm'); -- Checks: admin: new check to confirm.
update public.tutor_checks set verified_at = now(), verified_by = '00000000-0000-0000-0000-0000000000a0' where id = :'todo_check'; -- The owner confirms it.
select tests.eq(tests.todo('admin', 'tutors'), :tutors_before, 'admin: confirmed check comes off'); -- Checks: admin: confirmed check comes off.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000d8', 'aal2'); -- Signs in as test account ...d8 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((tests.todo('tutor', 'checks') < :tutor_checks_before)::int, 1, 'tutor: confirmed check no longer missing'); -- Checks: tutor: confirmed check no longer missing.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Admin: a staff invitation that ran out unused.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Keeps the admin "staff" number as staff_before.
select tests.todo('admin', 'staff') as staff_before \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.invitations (email, role, invited_by, expires_at) -- Adds a tutor invite that ran out yesterday:
values ('todo-late@clg.example', 'tutor', '00000000-0000-0000-0000-0000000000a0', now() - interval '1 day'); -- (invited by the owner).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(tests.todo('admin', 'staff'), :staff_before + 1, 'admin: expired invitation to resend or remove'); -- Checks: admin: expired invitation to resend or remove.
-- Owner sees billing and records rows too (they may be 0).
select tests.eq((select count(*) from public.to_do_counts() where area = 'billing'), 3, 'owner gets the three billing counts'); -- Checks: owner gets the three billing counts.
select tests.eq((select count(*) from public.to_do_counts() where area = 'admin' and section = 'records'), 1, 'owner gets the records count'); -- Checks: owner gets the records count.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Put things back.
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.invitations where email in ('todo-late@clg.example'); -- Removes the test invite.
delete from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000d7'; -- Removes Tess's notices.

-- Prints that every check in this file passed.
\echo '  to-do counts: all checks passed'
