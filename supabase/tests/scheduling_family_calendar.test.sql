-- Summary: tests for the parents' and students' private calendar link
-- (family feed). Reuses parent P3 (...03, Sam Three's parent), parent P4
-- (...04), tutor T3 (...13, Tara Three) and Alpha Library from
-- scheduling.test.sql, and adds a student with their own login (...61).
-- Checks that only parents and students can make a link, that the feed
-- shows only their own family's sessions with minimum detail and no Teams
-- links, and that replacing or turning off the link stops the old one.

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Keeps Alpha Library's id as lib_a.
select id as lib_a from public.libraries where name = 'Alpha Library' \gset

-- ---------------------------------------------------------------------------
-- Set up: a student with their own login, and sessions
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values -- Ola signs up as a learner (17, with her own login):
  ('00000000-0000-0000-0000-000000000061', 'fc-ola@example.com', -- (account ...61),
   json_build_object('signup_as', 'learner', 'full_name', 'Ola Learner', 'date_of_birth', (current_date - interval '17 years')::date, -- (name and birthday),
                     'state', 'SA', 'year_level', 'Year 11', 'school', 'Hill HS')); -- (state, year level and school).
-- Keeps Ola's student id as ola.
select id as ola from public.students where account_id = '00000000-0000-0000-0000-000000000061' \gset

insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, meeting_url) -- Adds an online session for Sam in 2 days, with a Teams link:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Fam Maths', 'school', 'online', -- (Sam, tutor Tara, online),
        now() + interval '2 days', now() + interval '2 days 1 hour', 'https://teams.example/fam-online') -- (an hour, with a link)
-- and keeps its id as f_online.
returning id as f_online \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, library_id, starts_at, ends_at) -- Adds a library session for Sam in 3 days:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Fam Maths', 'school', 'library', :'lib_a', -- (Sam, Tara, Alpha Library),
        now() + interval '3 days', now() + interval '3 days 1 hour') -- (an hour)
-- and keeps its id as f_library.
returning id as f_library \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) -- Adds a session for Ola in 2 days:
values (:'ola', '00000000-0000-0000-0000-000000000013', 'Fam English', 'school', 'online', -- (Ola, Tara, online),
        now() + interval '2 days', now() + interval '2 days 1 hour'); -- (an hour).
-- How many of Sam's sessions fall in the feed's window (4 weeks ago to 6 months ahead), counting any from earlier tests.
select count(*) as sam_in_window from public.sessions -- Counts sessions:
where student_id = :'sam' -- for Sam,
  and starts_at >= now() - interval '28 days' and starts_at < now() + interval '183 days' \gset
-- The same for Ola.
select count(*) as ola_in_window from public.sessions -- Counts sessions:
where student_id = :'ola' -- for Ola,
  and starts_at >= now() - interval '28 days' and starts_at < now() + interval '183 days' \gset

-- ---------------------------------------------------------------------------
-- Who may make a link
-- ---------------------------------------------------------------------------
set role anon; -- Acts as someone not signed in.
select tests.fails($$select public.reset_family_calendar_link()$$, 'not signed in makes a family link'); -- Checks this is refused: not signed in makes a family link.
select tests.fails($$select count(*) from public.family_calendar_links$$, 'not signed in reads the family links table'); -- Checks this is refused: not signed in reads the family links table.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner admin (not a parent or student).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.reset_family_calendar_link()$$, 'admin who isn''t a parent makes a family link'); -- Checks this is refused: admin who isn't a parent makes a family link.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Parent P3 makes a link: only their child's sessions, minimum detail
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as parent P3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Makes a link and keeps its secret as ptok.
select public.reset_family_calendar_link() as ptok \gset
select tests.eq((select count(*) from public.family_calendar_links), 1, 'parent sees their own link'); -- Checks: parent sees their own link.
select tests.fails($$select link_hash from public.family_calendar_links$$, 'parent reads the scrambled secret'); -- Checks this is refused: parent reads the scrambled secret.
select tests.fails($$update public.family_calendar_links set last_used_at = now()$$, 'parent edits the link directly'); -- Checks this is refused: parent edits the link directly.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.family_calendar_links where link_hash = :'ptok'), 0, 'secret itself is never stored'); -- Checks: secret itself is never stored.

select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as parent P4 (another family).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.family_calendar_links), 0, 'another parent cannot see P3''s link'); -- Checks: another parent cannot see P3's link.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as a calendar app (not signed in).
select tests.eq((select count(*) from public.family_calendar_feed(:'ptok')), :sam_in_window, 'parent feed shows all of Sam''s sessions in the window'); -- Checks: parent feed shows all of Sam's sessions in the window.
select tests.eq((select count(*) from public.family_calendar_feed(:'ptok') where subject = 'Fam English'), 0, 'parent feed never shows another family''s session'); -- Checks: parent feed never shows another family's session.
select tests.eq((select count(*) from public.family_calendar_feed(:'ptok') where session_id = :'f_online' and student_first_name = 'Sam' and tutor_first_name = 'Tara'), 1, 'first names only'); -- Checks: first names only.
select tests.eq((select count(*) from public.family_calendar_feed(:'ptok') where session_id = :'f_library' and place_name = 'Alpha Library'), 1, 'library session has the library'); -- Checks: library session has the library.
select tests.fails(format($$select meeting_url from public.family_calendar_feed(%L)$$, :'ptok'), 'family feed gives out Teams links'); -- Checks this is refused: family feed gives out Teams links.
select tests.eq((select count(*) from public.family_calendar_feed(:'ptok') where time_zone = 'Australia/Adelaide'), :sam_in_window, 'times use the student''s state'); -- Checks: times use the student's state.
select tests.eq((select count(*) from public.family_calendar_feed(repeat('0', 64))), 0, 'wrong secret shows nothing'); -- Checks: wrong secret shows nothing.
select tests.eq((select count(*) from public.family_calendar_feed('not-a-secret')), 0, 'badly shaped secret shows nothing'); -- Checks: badly shaped secret shows nothing.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.family_calendar_links where account_id = '00000000-0000-0000-0000-000000000003' and last_used_at is not null), 1, 'reading the feed notes when it was last used'); -- Checks: reading the feed notes when it was last used.

-- A tutor's link (a different secret) never opens the family feed, and the reverse.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Makes a tutor link and keeps its secret as ttok.
select public.reset_calendar_link() as ttok \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
set role anon; -- Acts as a calendar app (not signed in).
select tests.eq((select count(*) from public.family_calendar_feed(:'ttok')), 0, 'tutor link does not open a family feed'); -- Checks: tutor link does not open a family feed.
select tests.eq((select count(*) from public.calendar_feed(:'ptok')), 0, 'family link does not open a tutor feed'); -- Checks: family link does not open a tutor feed.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3 again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.remove_calendar_link(); -- Turns the tutor link off again (tidy up).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- A child unlinked from the parent drops out of the parent's feed.
begin; -- Starts a change that will be undone.
delete from public.parent_student_links where parent_id = '00000000-0000-0000-0000-000000000003' and student_id = :'sam'; -- Unlinks Sam from P3.
set local role anon; -- Acts as a calendar app, just inside this change.
select tests.eq((select count(*) from public.family_calendar_feed(:'ptok')), 0, 'unlinked child drops out of the parent feed'); -- Checks: unlinked child drops out of the parent feed.
rollback; -- Undoes the change (Sam is linked again).

-- ---------------------------------------------------------------------------
-- A student with their own login sees only their own sessions
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000061'); -- Signs in as student Ola.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Makes a link and keeps its secret as stok.
select public.reset_family_calendar_link() as stok \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
set role anon; -- Acts as a calendar app (not signed in).
select tests.eq((select count(*) from public.family_calendar_feed(:'stok')), :ola_in_window, 'student feed shows their own sessions'); -- Checks: student feed shows their own sessions.
select tests.eq((select count(*) from public.family_calendar_feed(:'stok') where student_first_name <> 'Ola'), 0, 'student feed shows nobody else'); -- Checks: student feed shows nobody else.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The link stops when the person no longer has the student role.
begin; -- Starts a change that will be undone.
delete from public.account_roles where account_id = '00000000-0000-0000-0000-000000000061' and role = 'student'; -- Takes away Ola's student role.
set local role anon; -- Acts as a calendar app, just inside this change.
select tests.eq((select count(*) from public.family_calendar_feed(:'stok')), 0, 'feed stops when the student role is removed'); -- Checks: feed stops when the student role is removed.
rollback; -- Undoes the change.

-- ---------------------------------------------------------------------------
-- A new link replaces the old; turning it off stops it
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as parent P3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Makes a new link and keeps its secret as ptok2.
select public.reset_family_calendar_link() as ptok2 \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
set role anon; -- Acts as a calendar app (not signed in).
select tests.eq((select count(*) from public.family_calendar_feed(:'ptok')), 0, 'old family link stops after a new one is made'); -- Checks: old family link stops after a new one is made.
select tests.eq((select count(*) from public.family_calendar_feed(:'ptok2')), :sam_in_window, 'new family link works'); -- Checks: new family link works.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as parent P3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.remove_family_calendar_link(); -- Turns the link off.
select tests.eq((select count(*) from public.family_calendar_links), 0, 'family link is gone after turning it off'); -- Checks: family link is gone after turning it off.
reset role; -- Goes back to the all-powerful test user (access rules off).
set role anon; -- Acts as a calendar app (not signed in).
select tests.eq((select count(*) from public.family_calendar_feed(:'ptok2')), 0, 'turned-off family link shows nothing'); -- Checks: turned-off family link shows nothing.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.eq((select count(*) >= 3 from public.audit_log where table_name = 'family_calendar_links')::int, 1, 'family link changes are in the audit log'); -- Checks: family link changes are in the audit log.

-- Tidies up this file's sessions, so later tests that look for sessions by time and place aren't confused.
delete from public.sessions where subject in ('Fam Maths', 'Fam English'); -- Removes the sessions added above.

-- Prints that every check in this file passed.
\echo '  family calendar: all checks passed'
