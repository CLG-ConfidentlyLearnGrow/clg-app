-- Teams links module, and scheduling's set_session_meeting_url.
-- Reuses the owner admin (...a0), tutor T3 (...13), parent P3 (...03) and
-- Sam Three from the earlier tests.

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset

-- Four sessions for Sam: online tomorrow, online in 3 days with a pasted
-- link, at a library tomorrow, and online in 20 days (too far ahead).
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) -- Adds an online session tomorrow:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Teams Test Maths', 'school', 'online', -- (online),
        now() + interval '1 day', now() + interval '1 day 1 hour') -- (an hour),
-- and keeps its id as s_online.
returning id as s_online \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, meeting_url) -- Adds an online session with a link already pasted in:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Teams Test Maths', 'school', 'online', -- (online),
        now() + interval '3 days', now() + interval '3 days 1 hour', 'https://example.com/pasted') -- (in three days),
-- and keeps its id as s_pasted.
returning id as s_pasted \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, library_id, starts_at, ends_at) -- Adds a library session tomorrow:
select :'sam', '00000000-0000-0000-0000-000000000013', 'Teams Test Maths', 'school', 'library', id, -- (at the library),
       now() + interval '1 day', now() + interval '1 day 1 hour' -- (an hour),
from public.libraries where name = 'Alpha Library' -- (Alpha Library)
-- and keeps its id as s_library.
returning id as s_library \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) -- Adds an online session in 20 days:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Teams Test Maths', 'school', 'online', -- (online),
        now() + interval '20 days', now() + interval '20 days 1 hour') -- (an hour),
-- and keeps its id as s_far.
returning id as s_far \gset

-- ---------------------------------------------------------------------------
-- Who may do what
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.save_teams_settings(true, 'meet@clg.example', 7, '11111111-2222-3333-4444-555555555555')$$, 'parent changes Teams settings'); -- Checks this is refused: parent changes Teams settings.
select tests.fails(format($$select public.set_session_meeting_url(%L, 'https://evil.example/x')$$, :'s_online'), 'parent sets a link'); -- Checks this is refused: parent sets a link.
select tests.fails($$select * from public.teams_claim_sessions(10)$$, 'parent runs the job'); -- Checks this is refused: parent runs the job.
select tests.fails($$select public.teams_start_run()$$, 'parent starts a run'); -- Checks this is refused: parent starts a run.
select tests.eq((select count(*) from public.teams_settings), 0, 'parent cannot see Teams settings'); -- Checks: parent cannot see Teams settings.
select tests.eq((select count(*) from public.teams_meetings), 0, 'parent cannot see Teams meetings'); -- Checks: parent cannot see Teams meetings.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.set_session_meeting_url(%L, 'https://evil.example/x')$$, :'s_online'), 'tutor sets a link'); -- Checks this is refused: tutor sets a link.
select tests.fails($$update public.teams_settings set enabled = true$$, 'tutor edits settings directly'); -- Checks this is refused: tutor edits settings directly.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Admin without two-step login can't change settings.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal1'); -- Signs in as test account ...a0.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.save_teams_settings(true, 'meet@clg.example', 7, '11111111-2222-3333-4444-555555555555')$$, 'admin without two-step login'); -- Checks this is refused: admin without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.save_teams_settings(true, null, 7, '11111111-2222-3333-4444-555555555555')$$, 'switching on with no organiser'); -- Checks this is refused: switching on with no organiser.
select tests.fails($$select public.save_teams_settings(true, 'meet@clg.example', 7, null)$$, 'switching on with no Object ID'); -- Checks this is refused: switching on with no Object ID (Microsoft needs it).
select tests.fails($$select public.save_teams_settings(false, 'meet@clg.example', 7, 'meet@clg.example')$$, 'an email as the Object ID'); -- Checks this is refused: an email typed where the Object ID goes.
select tests.fails($$select public.save_teams_settings(false, 'not an email', 7, '11111111-2222-3333-4444-555555555555')$$, 'bad organiser email'); -- Checks this is refused: bad organiser email.
select tests.fails($$select public.save_teams_settings(false, 'meet@clg.example', 60, '11111111-2222-3333-4444-555555555555')$$, 'too many days ahead'); -- Checks this is refused: too many days ahead.
select tests.fails($$select * from public.teams_claim_sessions(10)$$, 'admin runs the server job directly'); -- Checks this is refused: admin runs the server job directly.
select tests.fails(format($$select public.set_session_meeting_url(%L, 'https://example.com/x')$$, :'s_library'), 'link on a library session'); -- Checks this is refused: link on a library session.
select tests.fails(format($$select public.set_session_meeting_url(%L, 'http://example.com/x')$$, :'s_online'), 'link without https'); -- Checks this is refused: link without https.
select tests.fails($$update public.teams_meetings set status = 'made'$$, 'admin edits meetings directly'); -- Checks this is refused: admin edits meetings directly.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- While switched off, the job does nothing.
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((public.teams_start_run())::int, 0, 'no run while switched off'); -- Checks: no run while switched off.
select tests.eq((select count(*) from public.teams_claim_sessions(10)), 0, 'nothing claimed while switched off'); -- Checks: nothing claimed while switched off.

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.save_teams_settings(true, ' Meet@CLG.example ', 7, ' 11111111-2222-3333-4444-555555555555 '); -- Turns Teams links on, with the organiser email and Object ID (both untidy) and 7 days ahead.
select tests.eq((select count(*) from public.teams_settings where enabled and organiser_email = 'meet@clg.example' and organiser_id = '11111111-2222-3333-4444-555555555555'), 1, 'admin switches Teams links on'); -- Checks: admin switches Teams links on.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- The server job
-- ---------------------------------------------------------------------------
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((public.teams_start_run())::int, 1, 'first run starts'); -- Checks: first run starts.
select tests.eq((public.teams_start_run())::int, 0, 'second run straight after is skipped'); -- Checks: second run straight after is skipped.

-- Only the online session within 7 days, with no pasted link, is claimed.
create temp table claimed as select * from public.teams_claim_sessions(10) where session_id in (:'s_online', :'s_pasted', :'s_library', :'s_far'); -- Claims sessions that need a link, keeping them in a short-lived table.
select tests.eq((select count(*) from claimed), 1, 'one session needs a meeting'); -- Checks: one session needs a meeting.
select tests.eq((select count(*) from claimed where session_id = :'s_online' and organiser_email = '11111111-2222-3333-4444-555555555555' -- Checks the online session is claimed with the Object ID (what Microsoft needs), titled without names:
  and subject = 'CLG session: Teams Test Maths'), 1, 'the online session, titled without names'); -- (the Object ID is what the job sends to Microsoft).
-- Keeps its meeting id as m_online.
select meeting_id as m_online from claimed \gset
select tests.eq((select count(*) from public.teams_claim_sessions(10) where session_id = :'s_online'), 0, 'not claimed twice'); -- Checks: not claimed twice.

-- Made: the link appears on the session for the family.
select public.teams_record_made(:'m_online', 'graph-1', 'https://teams.microsoft.com/l/meetup-join/one'); -- Records that the meeting was made, with its link.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_sessions(current_date, current_date + 30) -- Checks the family sees the Teams link:
  where id = :'s_online' and meeting_url = 'https://teams.microsoft.com/l/meetup-join/one'), 1, 'family sees the Teams link'); -- (in their session list).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.teams_claim_removals(50) where meeting_id = :'m_online'), 0, 'a live session keeps its meeting'); -- Checks: a live session keeps its meeting.

-- Cancelled: the meeting is deleted and the link comes off.
update public.sessions set status = 'cancelled', cancelled_at = now(), cancelled_by_role = 'family' where id = :'s_online'; -- The family cancels the session.
select tests.eq((select count(*) from public.teams_claim_removals(50) where meeting_id = :'m_online' and graph_meeting_id = 'graph-1'), 1, 'cancelled session meeting queued for deletion'); -- Checks: cancelled session meeting queued for deletion.
select tests.eq((select count(*) from public.teams_claim_removals(50) where meeting_id = :'m_online'), 0, 'deletion not handed out twice'); -- Checks: deletion not handed out twice.
select public.teams_record_removed(:'m_online'); -- Records that the meeting was removed.
select tests.eq((select count(*) from public.sessions where id = :'s_online' and meeting_url is null), 1, 'link taken off the session'); -- Checks: link taken off the session.
select tests.eq((select count(*) from public.teams_meetings where id = :'m_online' and status = 'removed'), 1, 'meeting marked removed'); -- Checks: meeting marked removed.
select tests.eq((select count(*) from public.teams_claim_sessions(10) where session_id = :'s_online'), 0, 'cancelled session gets no new meeting'); -- Checks: cancelled session gets no new meeting.

-- A failed attempt is tried again; a failed deletion is kept as made.
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) -- Adds another online session:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Teams Test Maths', 'school', 'online', -- (online),
        now() + interval '2 days', now() + interval '2 days 1 hour') -- (in two days),
-- and keeps its id as s_retry.
returning id as s_retry \gset
-- Claims it and keeps its meeting id as m_retry.
select meeting_id as m_retry from public.teams_claim_sessions(10) where session_id = :'s_retry' \gset
select public.teams_record_failed(:'m_retry', 'No application access policy found for this app'); -- Records that making the meeting failed.
select tests.eq((select count(*) from public.teams_claim_sessions(10) where session_id = :'s_retry'), 1, 'failed session tried again'); -- Checks: failed session tried again.
select tests.eq((select attempts from public.teams_meetings where id = :'m_retry'), 2, 'attempts counted'); -- Checks: attempts counted.
select public.teams_record_made(:'m_retry', 'graph-2', 'https://teams.microsoft.com/l/meetup-join/two'); -- Records that it worked on a retry.

-- Finished more than an hour ago: deleted so the link can't be reused.
update public.sessions set starts_at = now() - interval '3 hours', ends_at = now() - interval '2 hours' where id = :'s_retry'; -- Moves the session into the past.
select tests.eq((select count(*) from public.teams_claim_removals(50) where meeting_id = :'m_retry'), 1, 'finished session meeting queued for deletion'); -- Checks: finished session meeting queued for deletion.
select public.teams_record_failed(:'m_retry', 'Microsoft was busy'); -- Records another failure.
select tests.eq((select count(*) from public.teams_meetings where id = :'m_retry' and status = 'made'), 1, 'failed deletion kept for another try'); -- Checks: failed deletion kept for another try.

-- A made meeting whose session was cancelled meanwhile doesn't get its link set.
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) -- Adds another online session:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Teams Test Maths', 'school', 'online', -- (online),
        now() + interval '2 days', now() + interval '2 days 1 hour') -- (in two days),
-- and keeps its id as s_race.
returning id as s_race \gset
-- Claims it and keeps its meeting id as m_race.
select meeting_id as m_race from public.teams_claim_sessions(10) where session_id = :'s_race' \gset
update public.sessions set status = 'cancelled', cancelled_at = now(), cancelled_by_role = 'tutor' where id = :'s_race'; -- The tutor cancels before the meeting is made.
select public.teams_record_made(:'m_race', 'graph-3', 'https://teams.microsoft.com/l/meetup-join/three'); -- The meeting is made anyway.
select tests.eq((select count(*) from public.sessions where id = :'s_race' and meeting_url is null), 1, 'no link on a cancelled session'); -- Checks: no link on a cancelled session.
select tests.eq((select count(*) from public.teams_claim_removals(50) where meeting_id = :'m_race'), 1, 'its meeting is deleted'); -- Checks: its meeting is deleted.

-- An admin can paste a link by hand, and clear it.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.set_session_meeting_url(:'s_far', 'https://teams.microsoft.com/l/meetup-join/by-hand'); -- Pastes a link by hand.
select tests.eq((select count(*) from public.list_sessions(current_date, current_date + 30) where id = :'s_far' and meeting_url like '%by-hand'), 1, 'admin pastes a link'); -- Checks: admin pastes a link.
select public.set_session_meeting_url(:'s_far', '  '); -- Clears it (blank).
select tests.eq((select count(*) from public.sessions where id = :'s_far' and meeting_url is null), 1, 'admin clears a link'); -- Checks: admin clears a link.
select tests.eq((select count(*) from public.teams_meetings where session_id in (:'s_online', :'s_retry', :'s_race')), 3, 'admin sees the Teams meetings'); -- Checks: admin sees the Teams meetings.
select public.save_teams_settings(false, 'meet@clg.example', 7, '11111111-2222-3333-4444-555555555555'); -- Turns Teams links off.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Switched on from before the Object ID existed (as on CLG's live site): the job waits for the Object ID.
select tests.claims(null); -- Signs out, so the next lines run as the server.
update public.teams_settings set enabled = true, organiser_id = null where id; -- Switched on, but no Object ID (as the server, which skips the access rules).
select tests.eq((public.teams_start_run(interval '0 seconds'))::int, 0, 'no run without an Object ID'); -- Checks: no run without an Object ID.
select tests.eq((select count(*) from public.teams_claim_sessions(10)), 0, 'nothing claimed without an Object ID'); -- Checks: nothing handed out without an Object ID.

-- Leave the test sessions out of later tests.
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.teams_meetings; -- Clears the test meetings.
delete from public.sessions where subject = 'Teams Test Maths'; -- Removes the test sessions.

-- Prints that every check in this file passed.
\echo '  Teams links: all checks passed'
