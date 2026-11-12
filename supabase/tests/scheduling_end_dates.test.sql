-- Booking end dates (Carla, 11 Nov 2026): the family's "book until" date
-- and the student's term dates. Reuses the earlier scheduling tests' people:
-- owner admin (...a0), tutor T3 (...13), parents P3 (...03, Sam Three's
-- parent) and P4 (...04).

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Make sure there is at least one term ahead to list.
insert into public.school_terms (state, calendar, year, term, starts_on, ends_on) -- Adds next year's SA Term 4 to the school terms:
values ('SA', 'public', extract(year from current_date)::int + 1, 4, -- (government schools, next year, term 4,
        make_date(extract(year from current_date)::int + 1, 10, 12), make_date(extract(year from current_date)::int + 1, 12, 11)) -- from 12 October to 11 December)
on conflict do nothing; -- unless it's already there.

-- The parent sets how long to book for: all three answers are needed.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.set_booking_length(%L, current_date + 60, null, false)$$, :'sam'), 'both holiday questions need an answer'); -- Checks this is refused: both holiday questions need an answer.
select public.set_booking_length(:'sam', current_date + 60, false, true); -- Sets Sam's booking to run 60 days, no school holidays, yes to public holidays.
select tests.eq((select count(*) from public.student_places where student_id = :'sam' and book_until = current_date + 60 -- Checks the parent can set how long to book for:
  and include_school_holidays = false and include_public_holidays = true), 1::bigint, 'the parent can set how long to book for'); -- (the date and both holiday answers saved).
select tests.fails(format($$select public.set_booking_length(%L, current_date - 1, false, true)$$, :'sam'), 'not in the past'); -- Checks this is refused: not in the past.
select tests.fails(format($$select public.set_booking_length(%L, current_date + 400, false, true)$$, :'sam'), 'not more than a year ahead'); -- Checks this is refused: not more than a year ahead.
select tests.eq((select (count(*) >= 1 and bool_and(ends_on >= current_date))::int from public.student_term_dates(:'sam')), 1, -- Checks the parent sees Sam's term dates that haven't finished:
  'the parent sees the student''s term dates that haven''t finished'); -- (at least one, all still to come).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- CLG admins see the term dates and can change the booking length.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select (count(*) >= 1)::int from public.student_term_dates(:'sam')), 1, 'admins see the term dates'); -- Checks: admins see the term dates.
select public.set_booking_length(:'sam', current_date + 90, false, true); -- Changes the end date to 90 days away.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.student_places where student_id = :'sam' and book_until = current_date + 90), 1::bigint, -- Checks an admin can change the date:
  'an admin can change the date'); -- (saved as 90 days away).

-- A new booking follows the holiday answers.
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by) -- Adds a booking for Sam with tutor T3:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 6, '10:00', 60, 'online', current_date + 14, current_date + 42, -- Saturday 10am online, starting in two weeks,
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0') -- the tutor has two days to reply, asked for by the owner,
-- and keeps its id as hb.
returning id as hb \gset
select tests.eq((select (skip_holidays and not skip_public_holidays)::int from public.bookings where id = :'hb'), 1, -- Checks the booking follows the family's holiday answers:
  'no sessions in school holidays, sessions on public holidays, as the family chose'); -- (skips school holidays, keeps public holidays).
delete from public.bookings where id = :'hb'; -- Removes the test booking.

-- Another family and tutors can't see the term dates or change the length.
select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as test account ...04.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select * from public.student_term_dates(%L)$$, :'sam'), 'another family can''t'); -- Checks this is refused: another family can't.
select tests.fails(format($$select public.set_booking_length(%L, current_date + 30, true, true)$$, :'sam'), 'another family can''t change the length'); -- Checks this is refused: another family can't change the length.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select * from public.student_term_dates(%L)$$, :'sam'), 'tutors can''t'); -- Checks this is refused: tutors can't.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.student_places where student_id = :'sam'; -- Removes Sam's places and booking length.

-- Prints that every check in this file passed.
\echo '  scheduling end dates: all checks passed'
