-- Study periods: government or private school terms, or a tertiary
-- student's own dates, and each student's last day of Term 4. Runs after
-- scheduling_terms.test.sql, which leaves made-up SA government terms in
-- place: this term ends in 10 days, next term runs from day 24 to day 80.
-- Reuses tutor T3 (...13), parents P3 (...03, Sam Three's parent) and P4
-- (...04), and admin A (...a0).

select tests.claims(null);
select id as sam, family_id as sam_family from public.students where full_name = 'Sam Three' \gset

-- Real SA private dates were loaded by the migration: Term 2 a week shorter.
-- (scheduling_terms.test.sql swapped out SA's real dates, so check the
-- rule on a copy.)
insert into public.school_terms (state, calendar, year, term, starts_on, ends_on) values
  ('NT', 'public', 2031, 2, '2031-04-20', '2031-06-27');
insert into public.school_terms (state, calendar, year, term, starts_on, ends_on)
select state, 'private', year, term, starts_on, case when term = 2 then ends_on - 7 else ends_on end
from public.school_terms where state = 'NT' and year = 2031;
select tests.eq((select count(*) from public.school_terms where state = 'NT' and year = 2031), 2, 'a state can have government and private terms');
delete from public.school_terms where state = 'NT' and year = 2031;

-- With no choice saved, a student follows the government terms.
select tests.eq((select (ends_on = current_date + 10)::int from private.student_term_for(:'sam', current_date)), 1, 'government terms by default');

-- Only the family (or an admin) sets it.
select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.fails(format($$select public.set_study_period(%L, 'private')$$, :'sam'), 'another parent sets it');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails(format($$select public.set_study_period(%L, 'private')$$, :'sam'), 'tutor sets it');
reset role;

-- Private school terms: without private dates for that year, the
-- government dates are used; once loaded, the private ones.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.set_study_period(%L, 'boarding')$$, :'sam'), 'unknown study period');
select public.set_study_period(:'sam', 'private');
select tests.fails(format($$update public.student_study_periods set calendar = 'own' where student_id = %L$$, :'sam'), 'family edits the table directly');
reset role;
select tests.claims(null);
select tests.eq((select (ends_on = current_date + 10)::int from private.student_term_for(:'sam', current_date)), 1, 'private falls back to government dates');
insert into public.school_terms (state, calendar, year, term, starts_on, ends_on)
select 'SA', 'private', extract(year from current_date - 50)::int, 2, current_date - 50, current_date + 3;
insert into public.school_terms (state, calendar, year, term, starts_on, ends_on)
select 'SA', 'private', extract(year from current_date + 24)::int, 3, current_date + 24, current_date + 80;
select tests.eq((select (ends_on = current_date + 3)::int from private.student_term_for(:'sam', current_date)), 1, 'private dates used once loaded');
select tests.eq(private.student_in_holidays(:'sam', current_date + 5)::int, 1, 'private school holidays start earlier');

-- Last day of Term 4, per student.
insert into public.school_terms (state, calendar, year, term, starts_on, ends_on) values
  ('SA', 'public', 2031, 4, '2031-10-13', '2031-12-12');
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.set_term4_last_day(%L, '2031-09-01')$$, :'sam'), 'a date outside Term 4');
select public.set_term4_last_day(:'sam', '2031-11-21');
reset role;
select tests.claims(null);
-- Sam follows private terms, which fall back to government dates for 2031.
select tests.eq((select count(*) from private.student_terms(:'sam') where term = 4 and starts_on = '2031-10-13' and ends_on = '2031-11-21'), 1, 'the student''s own last day of Term 4');
delete from public.student_term_ends where student_id = :'sam';
delete from public.school_terms where year = 2031;

-- Tertiary: own dates.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.set_study_period(:'sam', 'own');
select public.add_own_term(:'sam', current_date - 30, current_date + 6, 'Semester 2') as own1 \gset
select tests.fails(format($$select public.add_own_term(%L, current_date, current_date + 40)$$, :'sam'), 'overlapping study periods');
select tests.fails(format($$select public.add_own_term(%L, current_date + 10, current_date + 5)$$, :'sam'), 'dates out of order');
select public.add_own_term(:'sam', current_date + 40, current_date + 120, 'Semester 1') as own2 \gset
reset role;
select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.eq((select count(*) from public.student_own_terms where student_id = :'sam'), 0, 'another family can''t see them');
select tests.fails(format($$select public.remove_own_term(%L)$$, :'own2'), 'another family removes one');
reset role;
select tests.claims(null);
select tests.eq((select (own_term_id = :'own1' and ends_on = current_date + 6)::int from private.student_term_for(:'sam', current_date)), 1, 'own dates replace school terms');
select tests.eq(private.student_in_holidays(:'sam', current_date + 20)::int, 1, 'between own study periods is holidays');
select tests.eq(private.student_in_holidays(:'sam', current_date + 50)::int, 0, 'inside a study period is not');

-- The renewal question follows the own study period (3 weeks before it ends).
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery,
                             first_date, last_date, status, confirmed_at)
select :'sam', '00000000-0000-0000-0000-000000000013', :'sam_family', 'General Maths',
       extract(isodow from current_date + 1)::smallint, '19:00', 60, 'online',
       current_date + 1, current_date + 1, 'confirmed', now()
returning id as tertiary \gset
select private.queue_renewals();
select tests.eq((select count(*) from public.term_renewals where booking_id = :'tertiary' and own_term_id = :'own1' and term_id is null), 1, 'asked about the next study period');
select private.queue_renewals();
select tests.eq((select count(*) from public.term_renewals where booking_id = :'tertiary'), 1, 'asked only once');
select id as renewal from public.term_renewals where booking_id = :'tertiary' \gset

select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.list_renewals() where booking_id = :'tertiary' and term_label = 'Semester 2' and term_ends_on = current_date + 6), 1, 'family sees the study period');
select tests.fails(format($$select public.remove_own_term(%L)$$, :'own1'), 'a study period with answers can''t be removed');
select public.answer_renewal(:'renewal', true, false) as next_booking \gset
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.bookings where id = :'next_booking' and first_date >= current_date + 40
  and last_date = current_date + 120 and skip_holidays), 1, 'same again runs through the next own study period');

-- Admins see study dates to check.
delete from public.bookings where id in (:'next_booking', :'tertiary');
-- (Sam's other bookings from earlier tests were asked too.)
delete from public.term_renewals where own_term_id in (:'own1', :'own2');
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.remove_own_term(:'own1');
select public.remove_own_term(:'own2');
reset role;
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery,
                             first_date, last_date, status, confirmed_at)
select :'sam', '00000000-0000-0000-0000-000000000013', :'sam_family', 'General Maths',
       extract(isodow from current_date + 1)::smallint, '19:00', 60, 'online',
       current_date + 1, current_date + 1, 'confirmed', now()
returning id as checker \gset
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.list_study_dates_to_check() where student_id = :'sam' and problem like 'No study dates%'), 1, 'admin sees own dates missing');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.list_study_dates_to_check()), 0, 'families see none');
reset role;

-- Tidy up for the tests that follow.
select tests.claims(null);
delete from public.bookings where id = :'checker';
delete from public.student_study_periods where student_id = :'sam';
delete from public.school_terms where calendar = 'private' and state = 'SA';

\echo '  study periods: all checks passed'
