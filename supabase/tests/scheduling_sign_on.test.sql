-- Tutor sign on and off. Runs after scheduling_away.test.sql and reuses its
-- people: owner admin (...a0), tutors T3 (...13) and T4 (...14), parent P3
-- (...03, Sam Three's parent), and the libraries.

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Alpha Library is in the Adelaide CBD; Beta has no location recorded.
update public.libraries set latitude = -34.928500, longitude = 138.600700 where name = 'Alpha Library'; -- Gives Alpha Library a location in Adelaide.
-- Keeps Alpha Library's id as lib_a.
select id as lib_a from public.libraries where name = 'Alpha Library' \gset
-- Keeps Beta Library's id as lib_b.
select id as lib_b from public.libraries where name = 'Beta Library' \gset

-- Sessions happening now, later today and earlier today (made directly here;
-- the booking flow is tested in scheduling.test.sql).
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, library_id, starts_at, ends_at) -- Adds six sessions for Sam with tutor T3:
values -- (the list)
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', null, now() - interval '10 minutes', now() + interval '50 minutes'), -- online, started 10 minutes ago,
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'library', :'lib_a', now() - interval '5 minutes', now() + interval '55 minutes'), -- at Alpha, started 5 minutes ago,
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'library', :'lib_a', now() - interval '1 minute', now() + interval '59 minutes'), -- at Alpha, started a minute ago,
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'library', :'lib_b', now() - interval '2 minutes', now() + interval '58 minutes'), -- at Beta, started 2 minutes ago,
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', null, now() + interval '2 hours', now() + interval '3 hours'), -- online, in two hours,
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', null, now() - interval '3 hours', now() - interval '2 hours'); -- online, finished two hours ago.
-- Keeps the online one's id as s_online.
select id as s_online from public.sessions where booking_id is null and delivery = 'online' and starts_at between now() - interval '11 minutes' and now() \gset
-- Keeps the first Alpha one's id as s_lib.
select id as s_lib from public.sessions where booking_id is null and library_id = :'lib_a' and starts_at < now() - interval '4 minutes' and starts_at > now() - interval '6 minutes' \gset
-- Keeps the second Alpha one's id as s_lib_far.
select id as s_lib_far from public.sessions where booking_id is null and library_id = :'lib_a' and starts_at > now() - interval '2 minutes' \gset
-- Keeps the Beta one's id as s_lib_b.
select id as s_lib_b from public.sessions where booking_id is null and library_id = :'lib_b' and starts_at > now() - interval '3 minutes' \gset
-- Keeps the later one's id as s_later.
select id as s_later from public.sessions where booking_id is null and starts_at > now() + interval '1 hour' \gset
-- Keeps the finished one's id as s_past.
select id as s_past from public.sessions where booking_id is null and ends_at < now() - interval '1 hour' \gset

-- ---------------------------------------------------------------------------
-- Signing on
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as test account ...14 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.sign_on(%L)$$, :'s_online'), 'another tutor signs on'); -- Checks this is refused: another tutor signs on.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal1'); -- Signs in as test account ...13.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.sign_on(%L)$$, :'s_online'), 'without two-step login'); -- Checks this is refused: without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.sign_on(%L)$$, :'s_online'), 'parent signs on'); -- Checks this is refused: parent signs on.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.sign_on(%L)$$, :'s_later'), 'more than 30 minutes early'); -- Checks this is refused: more than 30 minutes early.
select tests.fails(format($$select public.sign_on(%L)$$, :'s_past'), 'after the session ended'); -- Checks this is refused: after the session ended.
select tests.eq((public.sign_on(:'s_online') = 'online')::int, 1, 'online sign on'); -- Checks: online sign on.
select tests.fails(format($$select public.sign_on(%L)$$, :'s_online'), 'signing on twice'); -- Checks this is refused: signing on twice.
-- About 15 m from the library, then about 2 km away, then no location given.
select tests.eq((public.sign_on(:'s_lib', -34.928600, 138.600800) = 'at_library')::int, 1, 'at the library'); -- Checks: at the library.
select tests.eq((public.sign_on(:'s_lib_far', -34.910000, 138.600700) = 'not_at_library')::int, 1, 'not at the library'); -- Checks: not at the library.
select tests.eq((public.sign_on(:'s_lib_b', -34.928600, 138.600800) = 'no_location')::int, 1, 'library with no location recorded'); -- Checks: library with no location recorded.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.sessions where id = :'s_lib' and signed_on_at is not null and sign_on_check = 'at_library'), 1, 'only the result is kept'); -- Checks: only the result is kept.

-- ---------------------------------------------------------------------------
-- Automatic sign-off at the scheduled end
-- ---------------------------------------------------------------------------
-- Move the online session into the past: it started 2 hr ago, the tutor
-- signed on 10 minutes late.
update public.sessions set starts_at = now() - interval '2 hours', ends_at = now() - interval '1 hour', -- Moves the online session into the past:
  signed_on_at = now() - interval '110 minutes' where id = :'s_online'; -- with a sign on 10 minutes late.
update public.sessions set starts_at = now() - interval '2 hours', ends_at = now() - interval '1 hour', -- Moves the Alpha session into the past:
  signed_on_at = now() - interval '2 hours' where id = :'s_lib'; -- with a sign on at the start.
select tests.eq(private.auto_sign_off(), 2, 'two ended sessions signed off'); -- Checks: two ended sessions signed off.
select tests.eq((select count(*) from public.sessions where id = :'s_online' and status = 'completed' -- Checks pay runs from the late sign on to the booked end:
  and worked_from = signed_on_at and worked_to = ends_at), 1, 'paid from a late sign on to the booked end'); -- (completed, with those times).
select tests.eq((select count(*) from public.sessions where id = :'s_lib' and worked_from = starts_at), 1, 'on-time start paid from the booked start'); -- Checks: on-time start paid from the booked start.
select tests.eq((select count(*) from public.sessions where id = :'s_past' and status = 'scheduled'), 1, 'not signed on: left for the tutor or CLG'); -- Checks: not signed on: left for the tutor or CLG.

-- ---------------------------------------------------------------------------
-- A different end time waits for an admin
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.record_end_time(%L, (select ends_at + interval '30 minutes' from public.sessions where id = %L), '')$$, :'s_lib', :'s_lib'), 'reason needed'); -- Checks this is refused: reason needed.
select tests.fails(format($$select public.record_end_time(%L, (select ends_at + interval '3 hours' from public.sessions where id = %L), 'Long')$$, :'s_lib', :'s_lib'), 'too long after the booked end'); -- Checks this is refused: too long after the booked end.
select public.record_end_time(:'s_lib', (select ends_at + interval '30 minutes' from public.sessions where id = :'s_lib'), 'Finished a practice test'); -- The tutor says they finished 30 minutes late, with a reason.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.sessions where id = :'s_lib' and tutor_end_at is not null and worked_to is null), 1, 'worked times wait for CLG'); -- Checks: worked times wait for CLG.
select private.auto_sign_off(); -- Signs off sessions that have ended.
select tests.eq((select count(*) from public.sessions where id = :'s_lib' and worked_to is null), 1, 'auto sign-off leaves it for CLG'); -- Checks: auto sign-off leaves it for CLG.

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_times_to_check()), 0, 'parent sees no times to check'); -- Checks: parent sees no times to check.
select tests.fails(format($$select public.confirm_session_times(%L, now() - interval '2 hours', now())$$, :'s_lib'), 'parent confirms times'); -- Checks this is refused: parent confirms times.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.confirm_session_times(%L, now() - interval '2 hours', now())$$, :'s_lib'), 'tutor confirms own times'); -- Checks this is refused: tutor confirms own times.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_times_to_check() where id = :'s_lib' and reason = 'different_end'), 1, 'different end time listed'); -- Checks: different end time listed.
select tests.eq((select count(*) from public.list_times_to_check() where id = :'s_past' and reason = 'not_signed_on'), 1, 'not signed on listed'); -- Checks: not signed on listed.
select tests.eq((select count(*) from public.list_times_to_check() where id = :'s_lib_far' and reason = 'not_at_library'), 1, 'not at the library listed'); -- Checks: not at the library listed.
select public.confirm_session_times(:'s_lib', (select starts_at from public.sessions where id = :'s_lib'), (select tutor_end_at from public.sessions where id = :'s_lib')); -- An admin confirms the session times (the tutor's end time).
select tests.eq((select count(*) from public.sessions where id = :'s_lib' and worked_to = tutor_end_at and times_confirmed_at is not null), 1, 'admin confirms the longer time'); -- Checks: admin confirms the longer time.
select tests.eq((select count(*) from public.list_times_to_check() where id = :'s_lib'), 0, 'no longer listed'); -- Checks: no longer listed.
select tests.fails(format($$select public.confirm_session_times(%L, now(), now() - interval '1 hour')$$, :'s_past'), 'times out of order'); -- Checks this is refused: times out of order.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.record_end_time(%L, now(), 'Again')$$, :'s_lib'), 'change after CLG confirmed'); -- Checks this is refused: change after CLG confirmed.
-- Recording "done" by hand fills in the times too.
select public.record_session_outcome(:'s_past', 'completed'); -- Records the past session as done.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.sessions where id = :'s_past' and worked_from = starts_at and worked_to = ends_at), 1, 'done by hand: booked times'); -- Checks: done by hand: booked times.

-- Families can't change any of this directly.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$update public.sessions set worked_to = now() where id = %L$$, :'s_past'), 'family edits worked times'); -- Checks this is refused: family edits worked times.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- Prints that every check in this file passed.
\echo '  scheduling sign on and off: all checks passed'
