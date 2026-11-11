-- School terms and renewing each term. Runs after the other scheduling tests
-- and reuses their people: tutors T3 (...13) and T4 (...14), parents P3
-- (...03, Sam Three's parent) and P4 (...04).

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam and his family id as sam_family.
select id as sam, family_id as sam_family from public.students where full_name = 'Sam Three' \gset

-- The real SA dates are loaded by the migration.
select tests.eq((select count(*) from public.school_terms where state = 'SA' and calendar = 'public' and year = 2027), 4, 'SA 2027 terms loaded'); -- Checks: SA 2027 terms loaded.
select tests.eq((select count(*) from public.school_terms g join public.school_terms p -- Checks SA private school terms for 2027 match, except Term 2 ends a week early:
  on p.state = g.state and p.year = g.year and p.term = g.term and p.calendar = 'private' -- (pairs each government term with the private one),
  where g.state = 'SA' and g.calendar = 'public' and g.year = 2027 -- (SA, 2027),
    and p.starts_on = g.starts_on and p.ends_on = g.ends_on - case when g.term = 2 then 7 else 0 end), 4, -- (same start, and same end apart from Term 2), expecting all 4 terms,
  'SA private 2027 terms: Term 2 ends a week early'); -- (the label).

-- Swap in made-up terms around today: this term ends in 10 days, next term
-- starts in 24 days.
delete from public.school_terms where state = 'SA'; -- Clears the SA terms.
insert into public.school_terms (state, year, term, starts_on, ends_on) -- Adds a test term ending in 10 days:
select 'SA', extract(year from current_date - 50)::int, 2, current_date - 50, current_date + 10; -- (started 50 days ago).
insert into public.school_terms (state, year, term, starts_on, ends_on) -- Adds the next term:
select 'SA', extract(year from current_date + 24)::int, 3, current_date + 24, current_date + 80; -- (starting in 24 days).

select tests.eq(private.in_school_holidays('SA', current_date + 15)::int, 1, 'between terms is holidays'); -- Checks: between terms is holidays.
select tests.eq(private.in_school_holidays('SA', current_date)::int, 0, 'term time is not holidays'); -- Checks: term time is not holidays.
select tests.eq(private.in_school_holidays('VIC', current_date + 15)::int, 0, 'no terms for the state: not holidays'); -- Checks: no terms for the state: not holidays.

-- Only admins change terms.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.school_terms where state = 'SA'), 2, 'families can read terms'); -- Checks: families can read terms.
select tests.fails($$insert into public.school_terms (state, year, term, starts_on, ends_on) values ('NSW', 2027, 1, '2027-02-01', '2027-04-09')$$, 'family adds a term'); -- Checks this is refused: family adds a term.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.school_terms$$, 'anon reads terms'); -- Checks this is refused: anon reads terms.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- A booking that skips the holidays gets no sessions between terms.
-- Clear away dates left by earlier tests first: on some days of the week
-- they land on this booking's dates and drop a session.
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.away_dates where tutor_id = '00000000-0000-0000-0000-000000000013' or student_id = :'sam'; -- Clears away dates for tutor T3 and Sam.
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery, -- Adds a confirmed booking that skips holidays:
                             first_date, last_date, status, confirmed_at, skip_holidays) -- (with its dates, status and holiday choice)
select :'sam', '00000000-0000-0000-0000-000000000013', :'sam_family', 'General Maths', -- (for Sam with tutor T3, General Maths)
       extract(isodow from current_date + 1)::smallint, '20:00', 60, 'online', -- tomorrow's weekday, 8pm, online,
       current_date + 1, current_date + 36, 'confirmed', now(), true -- for five weeks, confirmed now, skipping holidays,
-- and keeps its id as skipper.
returning id as skipper \gset
select private.make_sessions(:'skipper'); -- Makes its sessions.
select tests.eq((select count(*) from public.sessions where booking_id = :'skipper'), 4, 'sessions only in term time (2 this term, 2 next)'); -- Checks: sessions only in term time (2 this term, 2 next).
delete from public.sessions where booking_id = :'skipper'; -- Removes its sessions.
delete from public.bookings where id = :'skipper'; -- Removes the booking.

-- A booking that ends this term.
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery, -- Adds a confirmed booking ending in 8 days:
                             first_date, last_date, status, confirmed_at) -- (with its dates and status)
select :'sam', '00000000-0000-0000-0000-000000000013', :'sam_family', 'General Maths', -- (for Sam with tutor T3, General Maths)
       extract(isodow from current_date + 1)::smallint, '19:00', 60, 'online', -- tomorrow's weekday, 7pm, online,
       current_date + 1, current_date + 8, 'confirmed', now() -- for a week, confirmed now,
-- and keeps its id as ending.
returning id as ending \gset

select private.queue_renewals(); -- Queues "same again next term?" questions.
select tests.eq((select count(*) from public.term_renewals where booking_id = :'ending'), 1, 'family asked about next term'); -- Checks: family asked about next term.
-- Keeps the question's id as renewal.
select id as renewal from public.term_renewals where booking_id = :'ending' \gset
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003' -- Checks the parent gets a notice:
  and booking_id = :'ending' and kind = 'renewal_due'), 1, 'parent gets a notice'); -- (one renewal notice).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000013' -- Checks the tutor isn't asked:
  and booking_id = :'ending' and kind = 'renewal_due'), 0, 'tutor isn''t asked'); -- (none for tutor T3).
select private.queue_renewals(); -- Queues them again (should not repeat).
select tests.eq((select count(*) from public.term_renewals where booking_id = :'ending'), 1, 'asked only once'); -- Checks: asked only once.

-- Who can see and answer.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.term_renewals), 0, 'tutor can''t see renewal answers'); -- Checks: tutor can't see renewal answers.
select tests.fails(format($$select public.answer_renewal(%L, true, false)$$, :'renewal'), 'tutor answers'); -- Checks this is refused: tutor answers.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as test account ...04.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_renewals()), 0, 'other parent sees none'); -- Checks: other parent sees none.
select tests.fails(format($$select public.answer_renewal(%L, true, false)$$, :'renewal'), 'other parent answers'); -- Checks this is refused: other parent answers.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.term_renewals$$, 'anon'); -- Checks this is refused: anon.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The family answers: same again, no holiday sessions, with feedback.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_renewals() where booking_id = :'ending'), 1, 'family sees the question'); -- Checks: family sees the question.
select tests.fails(format($$select public.answer_renewal(%L, false, false)$$, :'renewal'), 'a change without saying what'); -- Checks this is refused: a change without saying what.
select tests.fails(format($$update public.term_renewals set same_again = true where id = %L$$, :'renewal'), 'family edits the table directly'); -- Checks this is refused: family edits the table directly.
-- The family says same again, no holidays, with feedback and a testimonial OK; keeps the new booking's id.
select public.answer_renewal(:'renewal', true, false, null, null, 'Sam loves it', true) as next_booking \gset
select tests.fails(format($$select public.answer_renewal(%L, true, true)$$, :'renewal'), 'answered twice'); -- Checks this is refused: answered twice.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.bookings where id = :'next_booking' and status = 'requested' -- Checks the tutor gets a request for next term, skipping holidays:
  and renews_booking = :'ending' and skip_holidays and first_date >= current_date + 24 and last_date = current_date + 80), 1, -- (asked for, renewing the old booking, running through next term),
  'tutor gets a request for next term, skipping the holidays'); -- (the label).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000013' -- Checks the tutor is told about the request:
  and booking_id = :'next_booking' and kind = 'booking_requested'), 1, 'tutor told about the request'); -- (one notice).
select tests.eq((select testimonial_ok::int from public.term_renewals where id = :'renewal'), 1, 'testimonial permission kept'); -- Checks: testimonial permission kept.

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.respond_to_booking(:'next_booking', true); -- The tutor accepts.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select (count(*) > 0)::int from public.sessions where booking_id = :'next_booking'), 1, 'next term''s sessions made'); -- Checks: next term's sessions made.
select tests.eq((select count(*) from public.sessions where booking_id = :'next_booking' and starts_at < (current_date + 24)::timestamptz), 0, 'none in the holidays'); -- Checks: none in the holidays.

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_renewals() where booking_id = :'ending' and next_status = 'confirmed'), 1, 'family sees it confirmed'); -- Checks: family sees it confirmed.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Testimonial permission needs feedback; a change needs what and why.
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery, -- Adds another confirmed booking:
                             first_date, last_date, status, confirmed_at) -- (with its dates and status)
select :'sam', '00000000-0000-0000-0000-000000000013', :'sam_family', 'General Maths', -- (for Sam with tutor T3, General Maths)
       extract(isodow from current_date + 2)::smallint, '19:00', 60, 'online', -- the weekday in two days, 7pm, online,
       current_date + 2, current_date + 9, 'confirmed', now() -- for a week, confirmed now,
-- and keeps its id as other.
returning id as other \gset
select private.queue_renewals(); -- Queues the questions.
-- Keeps the new question's id as renewal2.
select id as renewal2 from public.term_renewals where booking_id = :'other' \gset
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((public.answer_renewal(:'renewal2', false, true, 'time', 'Netball on that day', null, true) is null)::int, 1, 'a change sends no request'); -- Checks: a change sends no request.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.term_renewals where id = :'renewal2' and change_what = 'time' -- Checks the change is recorded, and no testimonial without feedback:
  and change_reason = 'Netball on that day' and not testimonial_ok), 1, 'change recorded; no testimonial without feedback'); -- (wants a different time, because of netball).

-- Leave the extra sessions and bookings out of the later tests.
delete from public.sessions where booking_id in (:'ending', :'next_booking', :'other'); -- Removes the test sessions.
delete from public.bookings where id in (:'next_booking', :'ending', :'other'); -- Removes the test bookings.

-- Prints that every check in this file passed.
\echo '  scheduling terms and renewals: all checks passed'
