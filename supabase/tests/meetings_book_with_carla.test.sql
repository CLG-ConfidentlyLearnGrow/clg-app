-- Summary: tests booking a meeting with Carla (Carla, 22 Nov 2026). Reuses
-- tutor T1 (...11), tutor T3 (...13), parent P1 (...01), the owner (...a0)
-- and the Operations admin (...b0). Everything is undone at the end.
-- Checks: who can send a request, the 2 or 3 times rule, privacy, confirming
-- a suggested time, offering a different time, answering without a meeting,
-- cancelling, marking as held, notices and the menu number.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the file again, to check it is safe to run more than once.
\ir ../migrations/20261124711600_meeting_requests.sql

begin; -- Starts a change that is undone at the end, so nothing is left behind.

-- Three future Adelaide clock times, and one in the past, for the tests.
select (date_trunc('hour', now() at time zone 'Australia/Adelaide') + interval '2 days')::timestamp as t1, -- in 2 days
       (date_trunc('hour', now() at time zone 'Australia/Adelaide') + interval '3 days')::timestamp as t2, -- in 3 days
       (date_trunc('hour', now() at time zone 'Australia/Adelaide') + interval '4 days')::timestamp as t3, -- in 4 days
       (date_trunc('hour', now() at time zone 'Australia/Adelaide') - interval '1 day')::timestamp as past \gset

-- 1. Tutor T1 sends two requests; the rules are checked.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.meeting_request_send('Planning for a new student', 'A Year 9 student starts next week with big gaps in fractions.', 'Agree a starting plan.', 'this_week', 30, 'online', array[:'t1', :'t2']::timestamp[]) as one \gset
select public.meeting_request_send('Travel time question', 'The new library is far from my other sessions.', 'Know whether travel is paid.', 'urgent', 15, 'phone', array[:'t1', :'t2', :'t3']::timestamp[]) as two \gset
select tests.eq((select count(*) from public.meeting_requests where requester_id = auth.uid()), 2, 'a tutor sees their own requests'); -- Checks: saved and visible.
select tests.fails_with(format($$select public.meeting_request_send('One time only', 'Context here', 'Goal here', 'no_rush', 30, 'online', array[%L]::timestamp[])$$, :'t1'), '2 or 3 different times', 'one time is not enough'); -- Checks: at least 2 times.
select tests.fails_with(format($$select public.meeting_request_send('Same time twice', 'Context here', 'Goal here', 'no_rush', 30, 'online', array[%L, %L]::timestamp[])$$, :'t1', :'t1'), '2 or 3 different times', 'the same time twice does not count'); -- Checks: different times.
select tests.fails_with(format($$select public.meeting_request_send('Old time', 'Context here', 'Goal here', 'no_rush', 30, 'online', array[%L, %L]::timestamp[])$$, :'past', :'t1'), 'in the future', 'a past time is refused'); -- Checks: future only.
select tests.fails_with(format($$select public.meeting_request_send('Bad urgency', 'Context here', 'Goal here', 'someday', 30, 'online', array[%L, %L]::timestamp[])$$, :'t1', :'t2'), 'how urgent', 'an unknown urgency is refused'); -- Checks: urgency.
select tests.fails($$insert into public.meeting_requests (requester_id, about, context, goal, urgency, suggested_times) values (auth.uid(), 'Sneaky', 'Straight in', 'Skip checks', 'urgent', array[now() + interval '1 day', now() + interval '2 days'])$$, 'requests cannot be written straight into the table'); -- Checks: only through the functions.
select tests.fails(format($$select public.meeting_request_confirm(%L, %L, null)$$, :'one', :'t1'), 'a tutor cannot confirm a meeting'); -- Checks: owner only.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title in ('Meeting request', 'Urgent meeting request')), 2, 'the owner is told about each request'); -- Checks: notices.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Urgent meeting request'), 1, 'an urgent request says so'); -- Checks: urgent title.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000b0' and title in ('Meeting request', 'Urgent meeting request')), 0, 'Operations is not told (meetings are with Carla)'); -- Checks: owner only.

-- 2. Privacy: only the person who asked and the owner see a request.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.meeting_requests), 0, 'another tutor cannot see them'); -- Checks: private.
select tests.fails(format($$select public.meeting_request_cancel(%L, null)$$, :'one'), 'another tutor cannot cancel them'); -- Checks: not theirs.
reset role; -- Back to the test user.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the Operations admin.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.meeting_requests), 0, 'the Operations admin cannot see them'); -- Checks: owner only.
reset role; -- Back to the test user.
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- Signs in as parent P1.
set role authenticated; -- Acts as a signed-in user.
select tests.fails_with(format($$select public.meeting_request_send('Parent request', 'Context here', 'Goal here', 'no_rush', 30, 'online', array[%L, %L]::timestamp[])$$, :'t1', :'t2'), 'Only CLG tutors and admin staff', 'a parent cannot send one here'); -- Checks: staff only.
reset role; -- Back to the test user.

-- 3. The owner confirms one suggested time and offers a different time for the other.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner.
set role authenticated; -- Acts as a signed-in user.
select tests.eq(public.meeting_requests_to_do(), 2, 'two requests wait for the owner'); -- Checks: the menu number.
select tests.eq((public.meeting_request_confirm(:'one', :'t2', 'Bring the diagnostic results.') = 'confirmed')::int, 1, 'a suggested time is confirmed'); -- Confirms the first at T2.
select tests.eq((public.meeting_request_confirm(:'two', (:'t3'::timestamp + interval '30 minutes'), null) = 'new_time')::int, 1, 'any other time is offered instead'); -- Offers a different time for the second.
select tests.eq(public.meeting_requests_to_do(), 0, 'none wait after answering'); -- Checks: cleared.
select tests.fails(format($$select public.meeting_request_held(%L)$$, :'two'), 'an offered time cannot be marked held'); -- Checks: only confirmed ones.
reset role; -- Back to the test user.
select tests.eq((select count(*) from public.meeting_requests where id = :'one' and status = 'confirmed' and meeting_at = :'t2'::timestamp at time zone 'Australia/Adelaide'), 1, 'the confirmed time is saved'); -- Checks: saved.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000011' and title in ('Meeting confirmed', 'Carla offered a different meeting time')), 2, 'the tutor is told about both answers'); -- Checks: notices.

-- 4. T1 accepts the different time, then cancels it.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user.
select tests.eq(public.meeting_requests_to_do(), 1, 'the tutor has one offered time to answer'); -- Checks: their menu number.
select public.meeting_request_accept_time(:'two'); -- Accepts it.
select tests.eq((select count(*) from public.meeting_requests where id = :'two' and status = 'confirmed'), 1, 'accepting confirms it'); -- Checks: confirmed.
select public.meeting_request_cancel(:'two', 'Sorted it with the timetable.'); -- Cancels it.
select tests.fails(format($$select public.meeting_request_cancel(%L, null)$$, :'two'), 'a closed request cannot be cancelled again'); -- Checks: closed.
reset role; -- Back to the test user.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title in ('Meeting time accepted', 'Meeting request cancelled')), 2, 'the owner is told about accepting and cancelling'); -- Checks: notices.

-- 5. A third request is answered without a meeting; the first is marked held.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user.
select public.meeting_request_send('Where is the handbook page', 'I cannot find the sick day steps.', 'Find the page.', 'no_rush', 15, 'online', array[:'t1', :'t3']::timestamp[]) as three \gset
reset role; -- Back to the test user.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner.
set role authenticated; -- Acts as a signed-in user.
select tests.fails_with(format($$select public.meeting_request_answer(%L, '')$$, :'three'), 'write your answer', 'an empty answer is refused'); -- Checks: an answer is needed.
select public.meeting_request_answer(:'three', 'It is in Handbooks under Sick days.'); -- Answers it.
select tests.fails(format($$select public.meeting_request_answer(%L, 'Already confirmed')$$, :'one'), 'a confirmed meeting cannot be answered without a meeting'); -- Checks: only unconfirmed ones.
select public.meeting_request_held(:'one'); -- Marks the first as held.
reset role; -- Back to the test user.
select tests.eq((select count(*) from public.meeting_requests where (id, status) in ((:'one'::uuid, 'held'), (:'two'::uuid, 'cancelled'), (:'three'::uuid, 'answered'))), 3, 'each request ends in the right state'); -- Checks: final states.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000011' and title = 'Carla answered your meeting request'), 1, 'the tutor is told the answer'); -- Checks: notice.

rollback; -- Undoes everything above.
\echo '  meetings with Carla: all checks passed'
