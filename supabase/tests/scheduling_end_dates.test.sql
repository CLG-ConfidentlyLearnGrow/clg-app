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

-- The parent sets "book until".
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
insert into public.student_places (student_id, online, book_until) values (:'sam', true, current_date + 60)
on conflict (student_id) do update set book_until = excluded.book_until;
select tests.eq((select count(*) from public.student_places where student_id = :'sam' and book_until = current_date + 60), 1::bigint,
  'the parent can set how long to book for');
select tests.fails(format($$update public.student_places set book_until = current_date - 1 where student_id = %L$$, :'sam'), 'not in the past');
select tests.fails(format($$update public.student_places set book_until = current_date + 400 where student_id = %L$$, :'sam'), 'not more than a year ahead');
select tests.eq((select (count(*) >= 1 and bool_and(ends_on >= current_date))::int from public.student_term_dates(:'sam')), 1,
  'the parent sees the student''s term dates that haven''t finished');
reset role;

-- CLG admins see the term dates; another family and tutors don't.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select (count(*) >= 1)::int from public.student_term_dates(:'sam')), 1, 'admins see the term dates');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.fails(format($$select * from public.student_term_dates(%L)$$, :'sam'), 'another family can''t');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails(format($$select * from public.student_term_dates(%L)$$, :'sam'), 'tutors can''t');
reset role;

select tests.claims(null);
delete from public.student_places where student_id = :'sam';

\echo '  scheduling end dates: all checks passed'
