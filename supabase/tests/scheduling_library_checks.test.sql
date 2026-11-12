-- Library opening hours when needed, re-checks and the first-booking
-- holiday reminder (Carla, 11 Nov 2026). Reuses the earlier scheduling
-- tests' people: owner admin (...a0), tutor T3 (...13), Sam Three.

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Adds a library with no opening hours, and keeps its id as lib.
insert into public.libraries (name, suburb) values ('Hours Test Library', 'Glenelg') returning id as lib \gset
delete from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' -- Clears earlier library notices for the owner:
  and title in ('Library opening hours needed', 'First sessions at a library'); -- (the two kinds this test makes).

-- Loaded but unused: nothing asked.
select tests.eq((select count(*) from public.session_notices where title = 'Library opening hours needed' and body like 'Hours Test Library%'), 0::bigint, 'no request while unused'); -- Checks: no request while unused.

-- A tutor adds it: admins are asked once.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000013', :'lib'); -- Tutor T3 can work at the new library.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.student_places (student_id, online, library_ids) values (:'sam', true, array[:'lib']::uuid[]) -- Sam can have sessions online or at the new library:
on conflict (student_id) do update set library_ids = excluded.library_ids; -- (or updates his places if already saved).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' -- Checks admins are asked for the hours once:
  and title = 'Library opening hours needed' and body like 'Hours Test Library%'), 1::bigint, 'admins are asked for hours once'); -- (one notice naming the library).

-- It shows on the to-do list until hours are added, then again after 6 months.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.library_checks() where library_id = :'lib' and problem = 'Opening hours needed'), 1::bigint, 'to-do: hours needed'); -- Checks: to-do: hours needed.
select tests.fails(format($$select public.mark_library_hours_checked(%L)$$, :'lib'), 'can''t say hours are right with none entered'); -- Checks this is refused: can't say hours are right with none entered.
insert into public.library_hours (library_id, weekday, opens, closes) values (:'lib', 1, '09:00', '17:00'); -- Adds Monday hours, 9am to 5pm.
select tests.eq((select count(*) from public.library_checks() where library_id = :'lib'), 0::bigint, 'off the list once hours are in'); -- Checks: off the list once hours are in.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
update public.libraries set hours_checked_at = now() - interval '7 months' where id = :'lib'; -- Makes the hours look 7 months old.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.library_checks() where library_id = :'lib' and problem like 'Check%'), 1::bigint, 'back on the list after 6 months'); -- Checks: back on the list after 6 months.
select public.mark_library_hours_checked(:'lib'); -- An admin marks the hours as checked.
select tests.eq((select count(*) from public.library_checks() where library_id = :'lib'), 0::bigint, 'marked as still right'); -- Checks: marked as still right.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Families and tutors can't see the list.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($q$select * from public.library_checks()$q$, 'tutors can''t see library checks'); -- Checks this is refused: tutors can't see library checks.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- First sessions at the library: one holiday reminder.
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, library_id, first_date, last_date, tutor_reply_by, requested_by) -- Adds two Monday bookings for Sam at the new library:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 1, '10:00', 60, 'library', :'lib', current_date + 14, current_date + 42, -- 10am, starting in two weeks,
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0'), -- (the tutor has two days to reply, offered by the owner),
       (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 1, '12:00', 60, 'library', :'lib', current_date + 14, current_date + 42, -- and noon,
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0'); -- (the same).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' -- Checks there's one holiday reminder for the first booking:
  and title = 'First sessions at a library' and body like '%Hours Test Library%'), 1::bigint, 'one holiday reminder for the first booking'); -- (one notice naming the library).

-- Put things back.
delete from public.session_notices where booking_id in (select id from public.bookings where library_id = :'lib'); -- Removes the bookings' notices.
delete from public.bookings where library_id = :'lib'; -- Removes the bookings.
delete from public.student_places where student_id = :'sam'; -- Removes Sam's places.
delete from public.tutor_places where library_id = :'lib'; -- Removes the library from tutors' libraries.
delete from public.libraries where id = :'lib'; -- Removes the library.
delete from public.session_notices where title in ('Library opening hours needed', 'First sessions at a library'); -- Clears the library notices.

-- Prints that every check in this file passed.
\echo '  scheduling library checks: all checks passed'

-- Numbers on tabs (Carla, 11 Nov 2026).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.scheduling_counts() where key in ('matching', 'libraries')), 2::bigint, 'admins get matching and library counts'); -- Checks: admins get matching and library counts.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select n from public.scheduling_counts() where key = 'booking-length'), 1, 'a family with an unanswered "How long to book" sees 1'); -- Checks: a family with an unanswered "How long to book" sees 1.
select tests.eq((select count(*) from public.scheduling_counts() where key = 'matching'), 0::bigint, 'families don''t get the matching count'); -- Checks: families don't get the matching count.
select public.set_booking_length(:'sam', current_date + 30, true, true); -- Sets Sam's booking to run 30 days, including school and public holidays.
select tests.eq((select n from public.scheduling_counts() where key = 'booking-length'), 0, 'answered: 0'); -- Checks: answered: 0.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.student_places where student_id = :'sam'; -- Removes Sam's places.

-- Prints that every check in this file passed.
\echo '  scheduling tab counts: all checks passed'
