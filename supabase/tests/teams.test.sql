-- Teams links module, and scheduling's set_session_meeting_url.
-- Reuses the owner admin (...a0), tutor T3 (...13), parent P3 (...03) and
-- Sam Three from the earlier tests.

select tests.claims(null);
select id as sam from public.students where full_name = 'Sam Three' \gset

-- Four sessions for Sam: online tomorrow, online in 3 days with a pasted
-- link, at a library tomorrow, and online in 20 days (too far ahead).
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at)
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Teams Test Maths', 'school', 'online',
        now() + interval '1 day', now() + interval '1 day 1 hour')
returning id as s_online \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, meeting_url)
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Teams Test Maths', 'school', 'online',
        now() + interval '3 days', now() + interval '3 days 1 hour', 'https://example.com/pasted')
returning id as s_pasted \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, library_id, starts_at, ends_at)
select :'sam', '00000000-0000-0000-0000-000000000013', 'Teams Test Maths', 'school', 'library', id,
       now() + interval '1 day', now() + interval '1 day 1 hour'
from public.libraries where name = 'Alpha Library'
returning id as s_library \gset
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at)
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Teams Test Maths', 'school', 'online',
        now() + interval '20 days', now() + interval '20 days 1 hour')
returning id as s_far \gset

-- ---------------------------------------------------------------------------
-- Who may do what
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails($$select public.save_teams_settings(true, 'meet@clg.example', 7)$$, 'parent changes Teams settings');
select tests.fails(format($$select public.set_session_meeting_url(%L, 'https://evil.example/x')$$, :'s_online'), 'parent sets a link');
select tests.fails($$select * from public.teams_claim_sessions(10)$$, 'parent runs the job');
select tests.fails($$select public.teams_start_run()$$, 'parent starts a run');
select tests.eq((select count(*) from public.teams_settings), 0, 'parent cannot see Teams settings');
select tests.eq((select count(*) from public.teams_meetings), 0, 'parent cannot see Teams meetings');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails(format($$select public.set_session_meeting_url(%L, 'https://evil.example/x')$$, :'s_online'), 'tutor sets a link');
select tests.fails($$update public.teams_settings set enabled = true$$, 'tutor edits settings directly');
reset role;

-- Admin without two-step login can't change settings.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal1');
set role authenticated;
select tests.fails($$select public.save_teams_settings(true, 'meet@clg.example', 7)$$, 'admin without two-step login');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails($$select public.save_teams_settings(true, null, 7)$$, 'switching on with no organiser');
select tests.fails($$select public.save_teams_settings(false, 'not an email', 7)$$, 'bad organiser email');
select tests.fails($$select public.save_teams_settings(false, 'meet@clg.example', 60)$$, 'too many days ahead');
select tests.fails($$select * from public.teams_claim_sessions(10)$$, 'admin runs the server job directly');
select tests.fails(format($$select public.set_session_meeting_url(%L, 'https://example.com/x')$$, :'s_library'), 'link on a library session');
select tests.fails(format($$select public.set_session_meeting_url(%L, 'http://example.com/x')$$, :'s_online'), 'link without https');
select tests.fails($$update public.teams_meetings set status = 'made'$$, 'admin edits meetings directly');
reset role;

-- While switched off, the job does nothing.
select tests.claims(null);
select tests.eq((public.teams_start_run())::int, 0, 'no run while switched off');
select tests.eq((select count(*) from public.teams_claim_sessions(10)), 0, 'nothing claimed while switched off');

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.save_teams_settings(true, ' Meet@CLG.example ', 7);
select tests.eq((select count(*) from public.teams_settings where enabled and organiser_email = 'meet@clg.example'), 1, 'admin switches Teams links on');
reset role;

-- ---------------------------------------------------------------------------
-- The server job
-- ---------------------------------------------------------------------------
select tests.claims(null);
select tests.eq((public.teams_start_run())::int, 1, 'first run starts');
select tests.eq((public.teams_start_run())::int, 0, 'second run straight after is skipped');

-- Only the online session within 7 days, with no pasted link, is claimed.
create temp table claimed as select * from public.teams_claim_sessions(10) where session_id in (:'s_online', :'s_pasted', :'s_library', :'s_far');
select tests.eq((select count(*) from claimed), 1, 'one session needs a meeting');
select tests.eq((select count(*) from claimed where session_id = :'s_online' and organiser_email = 'meet@clg.example'
  and subject = 'CLG session: Teams Test Maths'), 1, 'the online session, titled without names');
select meeting_id as m_online from claimed \gset
select tests.eq((select count(*) from public.teams_claim_sessions(10) where session_id = :'s_online'), 0, 'not claimed twice');

-- Made: the link appears on the session for the family.
select public.teams_record_made(:'m_online', 'graph-1', 'https://teams.microsoft.com/l/meetup-join/one');
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.list_sessions(current_date, current_date + 30)
  where id = :'s_online' and meeting_url = 'https://teams.microsoft.com/l/meetup-join/one'), 1, 'family sees the Teams link');
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.teams_claim_removals(50) where meeting_id = :'m_online'), 0, 'a live session keeps its meeting');

-- Cancelled: the meeting is deleted and the link comes off.
update public.sessions set status = 'cancelled', cancelled_at = now(), cancelled_by_role = 'family' where id = :'s_online';
select tests.eq((select count(*) from public.teams_claim_removals(50) where meeting_id = :'m_online' and graph_meeting_id = 'graph-1'), 1, 'cancelled session meeting queued for deletion');
select tests.eq((select count(*) from public.teams_claim_removals(50) where meeting_id = :'m_online'), 0, 'deletion not handed out twice');
select public.teams_record_removed(:'m_online');
select tests.eq((select count(*) from public.sessions where id = :'s_online' and meeting_url is null), 1, 'link taken off the session');
select tests.eq((select count(*) from public.teams_meetings where id = :'m_online' and status = 'removed'), 1, 'meeting marked removed');
select tests.eq((select count(*) from public.teams_claim_sessions(10) where session_id = :'s_online'), 0, 'cancelled session gets no new meeting');

-- A failed attempt is tried again; a failed deletion is kept as made.
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at)
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Teams Test Maths', 'school', 'online',
        now() + interval '2 days', now() + interval '2 days 1 hour')
returning id as s_retry \gset
select meeting_id as m_retry from public.teams_claim_sessions(10) where session_id = :'s_retry' \gset
select public.teams_record_failed(:'m_retry', 'No application access policy found for this app');
select tests.eq((select count(*) from public.teams_claim_sessions(10) where session_id = :'s_retry'), 1, 'failed session tried again');
select tests.eq((select attempts from public.teams_meetings where id = :'m_retry'), 2, 'attempts counted');
select public.teams_record_made(:'m_retry', 'graph-2', 'https://teams.microsoft.com/l/meetup-join/two');

-- Finished more than an hour ago: deleted so the link can't be reused.
update public.sessions set starts_at = now() - interval '3 hours', ends_at = now() - interval '2 hours' where id = :'s_retry';
select tests.eq((select count(*) from public.teams_claim_removals(50) where meeting_id = :'m_retry'), 1, 'finished session meeting queued for deletion');
select public.teams_record_failed(:'m_retry', 'Microsoft was busy');
select tests.eq((select count(*) from public.teams_meetings where id = :'m_retry' and status = 'made'), 1, 'failed deletion kept for another try');

-- A made meeting whose session was cancelled meanwhile doesn't get its link set.
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at)
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Teams Test Maths', 'school', 'online',
        now() + interval '2 days', now() + interval '2 days 1 hour')
returning id as s_race \gset
select meeting_id as m_race from public.teams_claim_sessions(10) where session_id = :'s_race' \gset
update public.sessions set status = 'cancelled', cancelled_at = now(), cancelled_by_role = 'tutor' where id = :'s_race';
select public.teams_record_made(:'m_race', 'graph-3', 'https://teams.microsoft.com/l/meetup-join/three');
select tests.eq((select count(*) from public.sessions where id = :'s_race' and meeting_url is null), 1, 'no link on a cancelled session');
select tests.eq((select count(*) from public.teams_claim_removals(50) where meeting_id = :'m_race'), 1, 'its meeting is deleted');

-- An admin can paste a link by hand, and clear it.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.set_session_meeting_url(:'s_far', 'https://teams.microsoft.com/l/meetup-join/by-hand');
select tests.eq((select count(*) from public.list_sessions(current_date, current_date + 30) where id = :'s_far' and meeting_url like '%by-hand'), 1, 'admin pastes a link');
select public.set_session_meeting_url(:'s_far', '  ');
select tests.eq((select count(*) from public.sessions where id = :'s_far' and meeting_url is null), 1, 'admin clears a link');
select tests.eq((select count(*) from public.teams_meetings where session_id in (:'s_online', :'s_retry', :'s_race')), 3, 'admin sees the Teams meetings');
select public.save_teams_settings(false, 'meet@clg.example', 7);
reset role;

-- Leave the test sessions out of later tests.
select tests.claims(null);
delete from public.teams_meetings;
delete from public.sessions where subject = 'Teams Test Maths';

\echo '  Teams links: all checks passed'
