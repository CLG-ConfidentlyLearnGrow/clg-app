-- Summary: tests for the tutors' private calendar link (feed). Reuses tutor
-- T3 (...13), tutor T4 (...14), parent P3 (...03), Sam Three and Alpha
-- Library from scheduling.test.sql. Checks that only tutors can make a link,
-- that the feed shows only that tutor's sessions with minimum detail, and
-- that replacing or turning off the link stops the old one working.

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Keeps Alpha Library's id as lib_a.
select id as lib_a from public.libraries where name = 'Alpha Library' \gset
update public.libraries set address = '1 Test St', suburb = 'Adelaide' where id = :'lib_a'; -- Gives Alpha Library an address, to check it shows in the feed.

-- ---------------------------------------------------------------------------
-- Set up: sessions for tutor T3 and one for tutor T4
-- ---------------------------------------------------------------------------
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, meeting_url) -- Adds an online session for T3 in 2 days, with a Teams link:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Cal Maths', 'school', 'online', -- (Sam, T3, online),
        now() + interval '2 days', now() + interval '2 days 1 hour', 'https://teams.example/cal-online') -- (an hour, with a link)
-- and keeps its id as c_online.
returning id as c_online \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, library_id, starts_at, ends_at) -- Adds a library session for T3 in 3 days:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Cal Maths', 'school', 'library', :'lib_a', -- (Sam, T3, at Alpha Library),
        now() + interval '3 days', now() + interval '3 days 1 hour') -- (an hour)
-- and keeps its id as c_library.
returning id as c_library \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, meeting_url, status, cancelled_at, cancelled_by_role) -- Adds a cancelled online session for T3 in 4 days:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Cal Maths', 'school', 'online', -- (Sam, T3, online),
        now() + interval '4 days', now() + interval '4 days 1 hour', 'https://teams.example/cal-cancelled', -- (an hour, with a link),
        'cancelled', now(), 'family') -- (cancelled by the family)
-- and keeps its id as c_cancelled.
returning id as c_cancelled \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) -- Adds a session for T3 from 60 days ago (too old for the feed):
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Cal Maths', 'school', 'online', -- (Sam, T3, online),
        now() - interval '60 days', now() - interval '60 days' + interval '1 hour'); -- (an hour).
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) -- Adds a session for tutor T4 in 2 days (must never show in T3's feed):
values (:'sam', '00000000-0000-0000-0000-000000000014', 'Cal Other', 'school', 'online', -- (Sam, T4, online),
        now() + interval '2 days', now() + interval '2 days 1 hour'); -- (an hour).
-- How many of T3's sessions fall in the feed's window (4 weeks ago to 6 months ahead), counting any from earlier tests.
select count(*) as t3_in_window from public.sessions -- Counts sessions:
where tutor_id = '00000000-0000-0000-0000-000000000013' -- for T3,
  and starts_at >= now() - interval '28 days' and starts_at < now() + interval '183 days' \gset

-- ---------------------------------------------------------------------------
-- Who may make a link
-- ---------------------------------------------------------------------------
set role anon; -- Acts as someone not signed in.
select tests.fails($$select public.reset_calendar_link()$$, 'not signed in makes a link'); -- Checks this is refused: not signed in makes a link.
select tests.fails($$select count(*) from public.tutor_calendar_links$$, 'not signed in reads the links table'); -- Checks this is refused: not signed in reads the links table.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000003', 'aal2'); -- Signs in as parent P3 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.reset_calendar_link()$$, 'parent makes a calendar link'); -- Checks this is refused: parent makes a calendar link.
select tests.fails($$select public.remove_calendar_link()$$, 'parent turns off a calendar link'); -- Checks this is refused: parent turns off a calendar link.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal1'); -- Signs in as tutor T3 without two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.reset_calendar_link()$$, 'tutor without two-step sign-in makes a link'); -- Checks this is refused: tutor without two-step sign-in makes a link.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Tutor T3 makes a link; the feed shows only their sessions, minimum detail
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Makes a link and keeps its secret as tok1.
select public.reset_calendar_link() as tok1 \gset
select tests.eq((select count(*) from public.tutor_calendar_links), 1, 'tutor sees their own link'); -- Checks: tutor sees their own link.
select tests.fails($$select link_hash from public.tutor_calendar_links$$, 'tutor reads the scrambled secret'); -- Checks this is refused: tutor reads the scrambled secret.
select tests.fails($$update public.tutor_calendar_links set last_used_at = now()$$, 'tutor edits the link directly'); -- Checks this is refused: tutor edits the link directly.
select tests.fails($$insert into public.tutor_calendar_links (tutor_id, link_hash) values ('00000000-0000-0000-0000-000000000014', 'x')$$, 'tutor adds a link for someone else'); -- Checks this is refused: tutor adds a link for someone else.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq(length(:'tok1'), 64, 'secret is 64 characters'); -- Checks: secret is 64 characters.
select tests.eq((select count(*) from public.tutor_calendar_links where link_hash = :'tok1'), 0, 'secret itself is never stored'); -- Checks: secret itself is never stored.

select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as tutor T4 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.tutor_calendar_links), 0, 'another tutor cannot see T3''s link'); -- Checks: another tutor cannot see T3's link.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as a calendar app (not signed in).
select tests.eq((select count(*) from public.calendar_feed(:'tok1')), :t3_in_window, 'feed shows all of T3''s sessions in the window'); -- Checks: feed shows all of T3's sessions in the window.
select tests.eq((select count(*) from public.calendar_feed(:'tok1') where subject = 'Cal Other'), 0, 'feed never shows another tutor''s session'); -- Checks: feed never shows another tutor's session.
select tests.eq((select count(*) from public.calendar_feed(:'tok1') where starts_at < now() - interval '28 days'), 0, 'feed leaves out old sessions'); -- Checks: feed leaves out old sessions.
select tests.eq((select count(*) from public.calendar_feed(:'tok1') where session_id = :'c_online' and student_first_name = 'Sam'), 1, 'feed shows the first name only'); -- Checks: feed shows the first name only.
select tests.eq((select count(*) from public.calendar_feed(:'tok1') where student_first_name like '% %'), 0, 'no surnames in the feed'); -- Checks: no surnames in the feed.
select tests.eq((select count(*) from public.calendar_feed(:'tok1') where session_id = :'c_online' and meeting_url = 'https://teams.example/cal-online'), 1, 'online session has its Teams link'); -- Checks: online session has its Teams link.
select tests.eq((select count(*) from public.calendar_feed(:'tok1') where session_id = :'c_cancelled' and status = 'cancelled' and meeting_url is null), 1, 'cancelled session listed without its Teams link'); -- Checks: cancelled session listed without its Teams link.
select tests.eq((select count(*) from public.calendar_feed(:'tok1') where session_id = :'c_library' and place_name = 'Alpha Library' and place_address = '1 Test St, Adelaide'), 1, 'library session has the library and address'); -- Checks: library session has the library and address.
select tests.eq((select count(*) from public.calendar_feed(:'tok1') where time_zone = 'Australia/Adelaide'), :t3_in_window, 'times use Adelaide when no work state is set'); -- Checks: times use Adelaide when no work state is set.
select tests.eq((select count(*) from public.calendar_feed(repeat('0', 64))), 0, 'wrong secret shows nothing'); -- Checks: wrong secret shows nothing.
select tests.eq((select count(*) from public.calendar_feed('not-a-secret')), 0, 'badly shaped secret shows nothing'); -- Checks: badly shaped secret shows nothing.
select tests.eq((select count(*) from public.calendar_feed(null)), 0, 'no secret shows nothing'); -- Checks: no secret shows nothing.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.tutor_calendar_links where tutor_id = '00000000-0000-0000-0000-000000000013' and last_used_at is not null), 1, 'reading the feed notes when it was last used'); -- Checks: reading the feed notes when it was last used.

-- The tutor's own state sets the time zone (a Victorian tutor sees Melbourne time).
update public.tutor_work_settings set work_state = 'VIC' where tutor_id = '00000000-0000-0000-0000-000000000013'; -- Sets T3's work state to Victoria.
set role anon; -- Acts as a calendar app (not signed in).
select tests.eq((select count(*) from public.calendar_feed(:'tok1') where time_zone = 'Australia/Melbourne'), :t3_in_window, 'feed uses the tutor''s own time zone'); -- Checks: feed uses the tutor's own time zone.
reset role; -- Goes back to the all-powerful test user (access rules off).
update public.tutor_work_settings set work_state = null where tutor_id = '00000000-0000-0000-0000-000000000013'; -- Puts T3's work state back to not set.

-- ---------------------------------------------------------------------------
-- The link stops working when the person is no longer a tutor
-- ---------------------------------------------------------------------------
begin; -- Starts a change that will be undone, so T3 stays a tutor for later tests.
delete from public.account_roles where account_id = '00000000-0000-0000-0000-000000000013' and role = 'tutor'; -- Takes away T3's tutor role.
set local role anon; -- Acts as a calendar app (not signed in), just inside this change.
select tests.eq((select count(*) from public.calendar_feed(:'tok1')), 0, 'feed stops when the tutor role is removed'); -- Checks: feed stops when the tutor role is removed.
rollback; -- Undoes the change (T3 is a tutor again).

begin; -- Starts another change that will be undone.
update public.tutor_profiles set active = false where account_id = '00000000-0000-0000-0000-000000000013'; -- Switches off T3's tutor profile.
set local role anon; -- Acts as a calendar app (not signed in), just inside this change.
select tests.eq((select count(*) from public.calendar_feed(:'tok1')), 0, 'feed stops when the tutor profile is switched off'); -- Checks: feed stops when the tutor profile is switched off.
rollback; -- Undoes the change (the profile is on again).

-- ---------------------------------------------------------------------------
-- A new link replaces the old; turning it off stops it
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Makes a new link and keeps its secret as tok2.
select public.reset_calendar_link() as tok2 \gset
select tests.eq((select count(*) from public.tutor_calendar_links where last_used_at is null), 1, 'new link starts as not yet used'); -- Checks: new link starts as not yet used.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.tutor_calendar_links where tutor_id = '00000000-0000-0000-0000-000000000013'), 1, 'still one link per tutor'); -- Checks: still one link per tutor.

select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as a calendar app (not signed in).
select tests.eq((select count(*) from public.calendar_feed(:'tok1')), 0, 'old link stops working after a new one is made'); -- Checks: old link stops working after a new one is made.
select tests.eq((select count(*) from public.calendar_feed(:'tok2')), :t3_in_window, 'new link works'); -- Checks: new link works.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.remove_calendar_link(); -- Turns off the link.
select tests.eq((select count(*) from public.tutor_calendar_links), 0, 'link is gone after turning it off'); -- Checks: link is gone after turning it off.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as a calendar app (not signed in).
select tests.eq((select count(*) from public.calendar_feed(:'tok2')), 0, 'turned-off link shows nothing'); -- Checks: turned-off link shows nothing.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Making and replacing links is written to the audit log.
select tests.eq((select count(*) >= 3 from public.audit_log where table_name = 'tutor_calendar_links')::int, 1, 'link changes are in the audit log'); -- Checks: link changes are in the audit log (made, replaced, turned off).

-- Prints that every check in this file passed.
\echo '  tutor calendar: all checks passed'
