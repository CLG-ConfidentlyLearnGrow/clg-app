-- Away dates and the waitlist. Runs after scheduling.test.sql and reuses its
-- people: owner admin (...a0), tutors T3 (...13) and T4 (...14), parents P3
-- (...03, Sam Three's parent) and P4 (...04), and the two libraries.

-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Keeps the Monday after next as first_day.
select (current_date + 7 + ((8 - extract(isodow from current_date)::int) % 7)) as first_day \gset

-- ---------------------------------------------------------------------------
-- Away dates
-- ---------------------------------------------------------------------------

-- The family will be away on the second Monday.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(public.add_away_dates(null, :'sam', :'first_day'::date + 6, :'first_day'::date + 8, 'Camp'), 0, 'family adds away dates (nothing booked yet)'); -- Checks: family adds away dates (nothing booked yet).
select tests.fails(format($$select public.add_away_dates(null, %L, %L::date + 9, %L::date + 8)$$, :'sam', :'first_day', :'first_day'), 'dates out of order'); -- Checks this is refused: dates out of order.
select tests.fails(format($$select public.add_away_dates(null, %L, current_date - 10, current_date - 5)$$, :'sam'), 'dates in the past'); -- Checks this is refused: dates in the past.
select tests.fails($$select public.add_away_dates('00000000-0000-0000-0000-000000000013', null, current_date + 1, current_date + 2)$$, 'family adds a tutor''s away dates'); -- Checks this is refused: family adds a tutor's away dates.
select tests.fails($$insert into public.away_dates (student_id, from_date, to_date) select id, current_date, current_date from public.students$$, 'family writes the table directly'); -- Checks this is refused: family writes the table directly.
-- Asks for a Monday 4pm online booking with tutor T3 for four weeks, and keeps its id as booking.
select public.request_booking(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'online', null, :'first_day'::date, :'first_day'::date + 28) as booking \gset
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as test account ...04.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.add_away_dates(null, %L, current_date + 1, current_date + 2)$$, :'sam'), 'other parent adds away dates'); -- Checks this is refused: other parent adds away dates.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.respond_to_booking(:'booking', true); -- The tutor accepts the booking.
select tests.eq((select count(*) from public.sessions where booking_id = :'booking'), 4, 'away week skipped when sessions are made'); -- Checks: away week skipped when sessions are made.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The tutor is away the first Monday: that session is cancelled by the tutor.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal1'); -- Signs in as test account ...13.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.add_away_dates('00000000-0000-0000-0000-000000000013', null, %L::date, %L::date)$$, :'first_day', :'first_day'), 'tutor without two-step login'); -- Checks this is refused: tutor without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as test account ...14 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.add_away_dates('00000000-0000-0000-0000-000000000013', null, %L::date, %L::date)$$, :'first_day', :'first_day'), 'tutor adds another tutor''s away dates'); -- Checks this is refused: tutor adds another tutor's away dates.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- A tutor's away dates wait 2 hours, so a mistake can be fixed first.
select tests.eq(public.add_away_dates('00000000-0000-0000-0000-000000000013', null, :'first_day'::date, :'first_day'::date, 'Exam', 'Thursday 4pm that week'), 0, 'nothing cancelled straight away'); -- Checks: nothing cancelled straight away.
select tests.eq((select count(*) from public.sessions where booking_id = :'booking' and status = 'cancelled'), 0, 'session still on during the 2 hours'); -- Checks: session still on during the 2 hours.
-- Oops, wrong day: the tutor removes it inside the 2 hours, and enters it again.
select public.remove_away_dates(id) from public.away_dates where tutor_id = '00000000-0000-0000-0000-000000000013' and applied_at is null; -- Removes any tutor T3 away dates not yet applied.
select public.add_away_dates('00000000-0000-0000-0000-000000000013', null, :'first_day'::date, :'first_day'::date, 'Exam', 'Thursday 4pm that week'); -- Tutor T3 will be away on the first day, for an exam, offering Thursday 4pm instead.
select tests.eq((select count(*) from public.away_dates where student_id = :'sam'), 1, 'tutor sees their student''s away dates'); -- Checks: tutor sees their student's away dates.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select private.apply_due_away_dates(); -- Applies away dates that are due (this one isn't yet).
select tests.eq((select count(*) from public.sessions where booking_id = :'booking' and status = 'cancelled'), 0, 'not cancelled before the 2 hours are up'); -- Checks: not cancelled before the 2 hours are up.
update public.away_dates set applies_at = now() - interval '1 minute' where tutor_id = '00000000-0000-0000-0000-000000000013' and applied_at is null; -- Makes the away date due a minute ago.
-- Since 22 Nov 2026 (Carla) a tutor's away dates no longer cancel sessions on their own: admins are told and decide.
select tests.eq(private.apply_due_away_dates(), 0, 'tutor away cancels nothing after 2 hours'); -- Checks: nothing is cancelled when the 2 hours are up.
select tests.eq((select count(*) from public.sessions where booking_id = :'booking' and status = 'cancelled'), 0, 'the session is still booked'); -- Checks: the session is still on.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' -- Checks admins are told, and that nothing was cancelled:
  and kind = 'staff_alert' and title like 'Tutor away%' and body like '%Nothing has been cancelled%' and body like '%Thursday 4pm that week%'), 1, 'admins told, with the tutor''s other times'); -- (one "tutor away" alert).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003' and kind = 'tutor_away'), 0, 'the family is not told until an admin decides'); -- Checks: no notice to the family yet.
-- The tutor and the family cannot see or use the admin list.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with($$select * from public.tutor_away_sessions()$$, 'Only CLG admins', 'tutors cannot see the list'); -- Checks this is refused: a tutor reads the list.
select tests.fails_with(format($$select public.cancel_for_tutor_away(%L)$$, (select id from public.sessions where booking_id = :'booking' order by starts_at limit 1)), 'Only CLG admins', 'tutors cannot cancel from the list'); -- Checks this is refused: a tutor cancels from the list.
reset role; -- Goes back to the all-powerful test user.
-- The owner admin sees the session in the list, and cancels it.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner admin.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.tutor_away_sessions() where tutor_offer = 'Thursday 4pm that week'), 1::bigint, 'admin sees the session on the tutor''s away dates'); -- Checks: one session in the list.
select tests.eq((select n::bigint from public.to_do_counts() where area = 'sessions' and section = 'away'), 1::bigint, 'the Away dates tab shows a number'); -- Checks: the to-do number is 1.
select public.cancel_for_tutor_away(session_id) from public.tutor_away_sessions(); -- The admin cancels it.
select tests.eq((select count(*) from public.tutor_away_sessions()), 0::bigint, 'the list is empty once it is cancelled'); -- Checks: the list is now empty.
select tests.fails_with(format($$select public.cancel_for_tutor_away(%L)$$, (select id from public.sessions where booking_id = :'booking' order by starts_at limit 1)), 'no longer booked', 'cannot cancel it twice'); -- Checks this is refused: cancelling again.
reset role; -- Goes back to the all-powerful test user.
select tests.claims(null); -- Signs out.
select tests.eq((select count(*) from public.sessions where booking_id = :'booking' and status = 'cancelled' and cancelled_by_role = 'tutor' and cancel_reason_kind = 'away' -- Checks the session is cancelled for the tutor, with a polite reason:
  and cancel_reason like 'Your tutor is not available that day%'), 1, 'cancelled for the tutor, politely'); -- (one cancelled session).
select tests.eq((select count(*) from public.sessions x join public.away_dates a on a.tutor_id = x.tutor_id where x.booking_id = :'booking' and x.status = 'cancelled' and x.cancelled_at = a.created_at), 1, 'cancelled from when the dates were entered (full credit)'); -- Checks: credit counts from when the dates were entered.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003' -- Checks the family is told, with the tutor's other times:
  and kind = 'tutor_away' and body like '%Thursday 4pm that week%' and body like '%Requests%' and body not like '%''t %'), 1, 'family told, with the tutor''s other times'); -- (one notice mentioning Thursday 4pm and Requests, with no contractions).
select tests.eq(private.apply_due_away_dates(), 0, 'applied once'); -- Checks: applied once.

select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as test account ...14 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.away_dates), 0, 'other tutor sees none'); -- Checks: other tutor sees none.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's away date id as sam_away.
select id as sam_away from public.away_dates where student_id = :'sam' \gset
select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as test account ...04.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.away_dates), 0, 'other parent sees none'); -- Checks: other parent sees none.
select tests.fails(format($$select public.remove_away_dates(%L)$$, :'sam_away'), 'other parent removes'); -- Checks this is refused: other parent removes.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.away_dates), 1, 'family sees only their child''s'); -- Checks: family sees only their child's.
select public.remove_away_dates(id) from public.away_dates where student_id = :'sam'; -- Removes Sam's away dates.
select tests.eq((select count(*) from public.away_dates), 0, 'family removes away dates'); -- Checks: family removes away dates.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.away_dates$$, 'anon'); -- Checks this is refused: anon.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Waitlist
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', null, array[2]::smallint[])), 0, 'nobody free on Tuesdays'); -- Checks: nobody free on Tuesdays.
-- Puts Sam on the General Maths waitlist for Tuesdays, and keeps the id as wait.
select public.join_waitlist(:'sam', 'General Maths', 60, true, '{}', array[2]::smallint[], null, null, null, 'Any Tuesday') as wait \gset
select tests.fails(format($$select public.join_waitlist(%L, 'general maths', 60, true)$$, :'sam'), 'same subject twice'); -- Checks this is refused: same subject twice.
select tests.fails(format($$select public.join_waitlist(%L, 'Science', 60, false, '{}')$$, :'sam'), 'no place chosen'); -- Checks this is refused: no place chosen.
select tests.fails($$insert into public.waitlist (student_id, subject, minutes) select id, 'x', 60 from public.students$$, 'family writes the table directly'); -- Checks this is refused: family writes the table directly.
select tests.eq((select count(*) from public.list_waitlist()), 1, 'family sees their place'); -- Checks: family sees their place.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as test account ...04.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.waitlist), 0, 'other parent sees no places'); -- Checks: other parent sees no places.
select tests.eq((select count(*) from public.list_waitlist()), 0, 'other parent list is empty'); -- Checks: other parent list is empty.
select tests.fails(format($$select public.join_waitlist(%L, 'English', 60, true)$$, :'sam'), 'other parent joins for Sam'); -- Checks this is refused: other parent joins for Sam.
select tests.fails(format($$select public.leave_waitlist(%L)$$, :'wait'), 'other parent removes Sam''s place'); -- Checks this is refused: other parent removes Sam's place.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select times_now_free from public.list_waitlist() where id = :'wait'), 0, 'no times free yet'); -- Checks: no times free yet.
select tests.eq((select count(*) from public.list_waitlist() where check_in_due), 0, 'no check-in due yet'); -- Checks: no weekly check-in is due on a place that has just started (Carla, 22 Nov 2026).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- T3 adds Tuesday availability: the admin list now shows free times.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at) -- Adds a Tuesday time for tutor T3:
  values ('00000000-0000-0000-0000-000000000013', 2, '15:00', '17:00'); -- 3pm to 5pm.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
update public.waitlist set created_at = now() - interval '30 days' where id = :'wait'; -- Makes the waitlist entry 30 days old.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select times_now_free from public.list_waitlist() where id = :'wait'), 5, 'five Tuesday times now free'); -- Checks: five Tuesday start times are now free (3pm to 4pm, every 15 min).
select tests.eq((select count(*) from public.list_waitlist() where check_in_due), 1, 'check-in due after a week with no check-in'); -- Checks: a check-in is due once 7 days pass with none (here 30 days).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Booking that subject closes the place.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.request_booking(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000013', 2::smallint, '15:00', 60, 'online', null, :'first_day'::date, :'first_day'::date + 14); -- Asks for a Tuesday 3pm booking with tutor T3.
select tests.eq((select count(*) from public.waitlist where id = :'wait' and closed_reason = 'booked'), 1, 'place closed when booked'); -- Checks: place closed when booked.
select tests.eq((select count(*) from public.list_waitlist()), 0, 'no open places left'); -- Checks: no open places left.
select public.join_waitlist(:'sam', 'General Maths', 90, false, array[(select id from public.libraries where name = 'Beta Library')]); -- Puts Sam on the waitlist for a 90-minute session at Beta Library.
select public.leave_waitlist(id) from public.waitlist where closed_at is null; -- Takes everyone off the waitlist.
select tests.eq((select count(*) from public.waitlist where closed_reason = 'withdrawn'), 1, 'family leaves the waitlist'); -- Checks: family leaves the waitlist.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- Prints that every check in this file passed.
\echo '  scheduling away dates and waitlist: all checks passed'
