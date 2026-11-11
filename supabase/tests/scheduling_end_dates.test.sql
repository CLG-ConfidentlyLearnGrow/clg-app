-- Booking end dates (Carla, 11 Nov 2026): the family's "book until" date
-- and the student's term dates. Reuses the earlier scheduling tests' people:
-- owner admin (...a0), tutor T3 (...13), parents P3 (...03, Sam Three's
-- parent) and P4 (...04).

select tests.claims(null);
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Make sure there is at least one term ahead to list.
insert into public.school_terms (state, calendar, year, term, starts_on, ends_on)
values ('SA', 'public', extract(year from current_date)::int + 1, 4,
        make_date(extract(year from current_date)::int + 1, 10, 12), make_date(extract(year from current_date)::int + 1, 12, 11))
on conflict do nothing;

-- The parent sets how long to book for: all three answers are needed.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.set_booking_length(%L, current_date + 60, null, false)$$, :'sam'), 'both holiday questions need an answer');
select public.set_booking_length(:'sam', current_date + 60, false, true);
select tests.eq((select count(*) from public.student_places where student_id = :'sam' and book_until = current_date + 60
  and include_school_holidays = false and include_public_holidays = true), 1::bigint, 'the parent can set how long to book for');
select tests.fails(format($$select public.set_booking_length(%L, current_date - 1, false, true)$$, :'sam'), 'not in the past');
select tests.fails(format($$select public.set_booking_length(%L, current_date + 400, false, true)$$, :'sam'), 'not more than a year ahead');
select tests.eq((select (count(*) >= 1 and bool_and(ends_on >= current_date))::int from public.student_term_dates(:'sam')), 1,
  'the parent sees the student''s term dates that haven''t finished');
reset role;

-- CLG admins see the term dates and can change the booking length.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select (count(*) >= 1)::int from public.student_term_dates(:'sam')), 1, 'admins see the term dates');
select public.set_booking_length(:'sam', current_date + 90, false, true);
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.student_places where student_id = :'sam' and book_until = current_date + 90), 1::bigint,
  'an admin can change the date');

-- A new booking follows the holiday answers.
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by)
values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 6, '10:00', 60, 'online', current_date + 14, current_date + 42,
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0')
returning id as hb \gset
select tests.eq((select (skip_holidays and not skip_public_holidays)::int from public.bookings where id = :'hb'), 1,
  'no sessions in school holidays, sessions on public holidays, as the family chose');
delete from public.bookings where id = :'hb';

-- Another family and tutors can't see the term dates or change the length.
select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.fails(format($$select * from public.student_term_dates(%L)$$, :'sam'), 'another family can''t');
select tests.fails(format($$select public.set_booking_length(%L, current_date + 30, true, true)$$, :'sam'), 'another family can''t change the length');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails(format($$select * from public.student_term_dates(%L)$$, :'sam'), 'tutors can''t');
reset role;

select tests.claims(null);
delete from public.student_places where student_id = :'sam';

\echo '  scheduling end dates: all checks passed'
