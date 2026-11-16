-- Summary: tests that the "book again?" question follows each student's own
-- book-till date (20261119700200_renewals_book_till.sql), not the end of the
-- school term. Runs after scheduling_terms.test.sql, which leaves made-up SA
-- terms in place (this term ends in 10 days, next term runs from day 24 to
-- day 80). Reuses tutor T3 (...13), parents P3 (...03, Sam Three's parent)
-- and P4 (...04), and admin A (...a0).

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam and his family id as sam_family.
select id as sam, family_id as sam_family from public.students where full_name = 'Sam Three' \gset
delete from public.away_dates where tutor_id = '00000000-0000-0000-0000-000000000013' or student_id = :'sam'; -- Clears away dates left by earlier tests, so no session is dropped by them.

-- A booking that runs to Sam's book-till date, 45 days away.
update public.student_places set book_until = current_date + 45 where student_id = :'sam'; -- Sets Sam's book-till date to 45 days from today.
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery, -- Adds a confirmed booking:
                             first_date, last_date, status, confirmed_at) -- (with its dates and status)
select :'sam', '00000000-0000-0000-0000-000000000013', :'sam_family', 'General Maths', -- (for Sam with tutor T3, General Maths)
       extract(isodow from current_date + 1)::smallint, '06:15', 60, 'online', -- tomorrow's weekday, 6:15am (a time no other test uses), online,
       current_date + 1, current_date + 45, 'confirmed', now() -- up to the book-till date, confirmed now,
-- and keeps its id as till.
returning id as till \gset

-- More than 3 weeks before the book-till date: not asked yet.
select private.queue_renewals(); -- Runs the daily question.
select tests.eq((select count(*) from public.term_renewals where booking_id = :'till'), 0, 'not asked more than 3 weeks before the book-till date'); -- Checks: not asked yet.

-- The family moves the book-till date to the middle of this term (7 days
-- away). The question now goes out, even though the term does not end then.
update public.student_places set book_until = current_date + 7 where student_id = :'sam'; -- Moves Sam's book-till date to 7 days from today.
select private.queue_renewals(); -- Runs the daily question.
select tests.eq((select count(*) from public.term_renewals where booking_id = :'till' and book_until = current_date + 7 -- Checks the question is about the book-till date:
  and term_id is null and own_term_id is null), 1, 'asked 3 weeks before a mid-term book-till date'); -- (not about a term).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003' -- Checks the parent gets a "Book again?" notice:
  and booking_id = :'till' and kind = 'renewal_due' and title = 'Book again?'), 1, 'parent gets a Book again notice'); -- (one notice).
select private.queue_renewals(); -- Runs it again (should not repeat).
select tests.eq((select count(*) from public.term_renewals where booking_id = :'till'), 1, 'asked only once'); -- Checks: asked only once.
-- Keeps the question's id as renewal.
select id as renewal from public.term_renewals where booking_id = :'till' \gset

-- Who can see it.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_renewals() where booking_id = :'till'), 0, 'tutor does not see the question'); -- Checks: the tutor does not see it.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as another parent, P4.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_renewals() where booking_id = :'till'), 0, 'another parent does not see the question'); -- Checks: another parent does not see it.
select tests.fails(format($$select public.answer_book_again(%L, true, current_date + 100, true, false)$$, :'renewal'), 'another parent answers'); -- Checks this is refused: another parent answers.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The family answers.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as Sam's parent, P3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_renewals() where booking_id = :'till' and book_until = current_date + 7), 1, 'family sees the book-till date'); -- Checks: the family sees the date.
select tests.fails(format($$select public.answer_book_again(%L, true, current_date + 400, true, false)$$, :'renewal'), 'a new date more than a year away'); -- Checks this is refused: a date more than a year away.
select tests.fails(format($$select public.answer_book_again(%L, true, current_date + 40, true, false)$$, :'renewal'), 'a new date before the last booked session'); -- Checks this is refused: a date before the booking's last session.
-- Same again until day 100, sessions in the school holidays, none on public holidays; keeps the new booking's id.
select public.answer_book_again(:'renewal', true, current_date + 100, true, false) as next_booking \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.bookings where id = :'next_booking' and status = 'requested' and renews_booking = :'till' -- Checks the tutor gets a request:
  and first_date = current_date + 50 and last_date = current_date + 100 -- (from the next session day after the last one, to the new date),
  and not skip_holidays and skip_public_holidays -- (school holidays go ahead, public holidays do not),
  and family_note like 'Same again, booked until %'), 1, 'request runs to the new book-till date with both holiday ticks'); -- (with a note naming the new date).
select tests.eq((select count(*) from public.student_places where student_id = :'sam' and book_until = current_date + 100 -- Checks the student's "How long to book" answers are updated:
  and include_school_holidays and not include_public_holidays), 1, 'student book-till date and holiday ticks updated'); -- (new date and both ticks).

-- CLG admins see the answer with both dates.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as admin A with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_renewals() where booking_id = :'till' and book_until = current_date + 7 -- Checks the admin sees the answer:
  and new_book_until = current_date + 100 and holidays and not public_holidays and same_again), 1, 'admin sees the new date and both ticks'); -- (old date, new date, both ticks).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Leave the extra bookings out of the later tests.
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.bookings where id in (:'next_booking', :'till'); -- Removes both test bookings (their questions go with them).

-- Prints that every check in this file passed.
\echo '  renewals by book-till date: all checks passed'
