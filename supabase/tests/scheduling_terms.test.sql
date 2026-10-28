-- School terms and renewing each term. Runs after the other scheduling tests
-- and reuses their people: tutors T3 (...13) and T4 (...14), parents P3
-- (...03, Sam Three's parent) and P4 (...04).

select tests.claims(null);
select id as sam, family_id as sam_family from public.students where full_name = 'Sam Three' \gset

-- The real SA dates are loaded by the migration.
select tests.eq((select count(*) from public.school_terms where state = 'SA' and year = 2027), 4, 'SA 2027 terms loaded');

-- Swap in made-up terms around today: this term ends in 10 days, next term
-- starts in 24 days.
delete from public.school_terms where state = 'SA';
insert into public.school_terms (state, year, term, starts_on, ends_on)
select 'SA', extract(year from current_date - 50)::int, 2, current_date - 50, current_date + 10;
insert into public.school_terms (state, year, term, starts_on, ends_on)
select 'SA', extract(year from current_date + 24)::int, 3, current_date + 24, current_date + 80;

select tests.eq(private.in_school_holidays('SA', current_date + 15)::int, 1, 'between terms is holidays');
select tests.eq(private.in_school_holidays('SA', current_date)::int, 0, 'term time is not holidays');
select tests.eq(private.in_school_holidays('VIC', current_date + 15)::int, 0, 'no terms for the state: not holidays');

-- Only admins change terms.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.school_terms where state = 'SA'), 2, 'families can read terms');
select tests.fails($$insert into public.school_terms (state, year, term, starts_on, ends_on) values ('NSW', 2027, 1, '2027-02-01', '2027-04-09')$$, 'family adds a term');
reset role;
select tests.claims(null);
set role anon;
select tests.fails($$select * from public.school_terms$$, 'anon reads terms');
reset role;

-- A booking that skips the holidays gets no sessions between terms.
select tests.claims(null);
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery,
                             first_date, last_date, status, confirmed_at, skip_holidays)
select :'sam', '00000000-0000-0000-0000-000000000013', :'sam_family', 'General Maths',
       extract(isodow from current_date + 1)::smallint, '20:00', 60, 'online',
       current_date + 1, current_date + 36, 'confirmed', now(), true
returning id as skipper \gset
select private.make_sessions(:'skipper');
select tests.eq((select count(*) from public.sessions where booking_id = :'skipper'), 4, 'sessions only in term time (2 this term, 2 next)');
delete from public.sessions where booking_id = :'skipper';
delete from public.bookings where id = :'skipper';

-- A booking that ends this term.
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery,
                             first_date, last_date, status, confirmed_at)
select :'sam', '00000000-0000-0000-0000-000000000013', :'sam_family', 'General Maths',
       extract(isodow from current_date + 1)::smallint, '19:00', 60, 'online',
       current_date + 1, current_date + 8, 'confirmed', now()
returning id as ending \gset

select private.queue_renewals();
select tests.eq((select count(*) from public.term_renewals where booking_id = :'ending'), 1, 'family asked about next term');
select id as renewal from public.term_renewals where booking_id = :'ending' \gset
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003'
  and booking_id = :'ending' and kind = 'renewal_due'), 1, 'parent gets a notice');
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000013'
  and booking_id = :'ending' and kind = 'renewal_due'), 0, 'tutor isn''t asked');
select private.queue_renewals();
select tests.eq((select count(*) from public.term_renewals where booking_id = :'ending'), 1, 'asked only once');

-- Who can see and answer.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.term_renewals), 0, 'tutor can''t see renewal answers');
select tests.fails(format($$select public.answer_renewal(%L, true, false)$$, :'renewal'), 'tutor answers');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.eq((select count(*) from public.list_renewals()), 0, 'other parent sees none');
select tests.fails(format($$select public.answer_renewal(%L, true, false)$$, :'renewal'), 'other parent answers');
reset role;
select tests.claims(null);
set role anon;
select tests.fails($$select * from public.term_renewals$$, 'anon');
reset role;

-- The family answers: same again, no holiday sessions, with feedback.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.list_renewals() where booking_id = :'ending'), 1, 'family sees the question');
select tests.fails(format($$select public.answer_renewal(%L, false, false)$$, :'renewal'), 'a change without saying what');
select tests.fails(format($$update public.term_renewals set same_again = true where id = %L$$, :'renewal'), 'family edits the table directly');
select public.answer_renewal(:'renewal', true, false, null, null, 'Sam loves it', true) as next_booking \gset
select tests.fails(format($$select public.answer_renewal(%L, true, true)$$, :'renewal'), 'answered twice');
reset role;

select tests.claims(null);
select tests.eq((select count(*) from public.bookings where id = :'next_booking' and status = 'requested'
  and renews_booking = :'ending' and skip_holidays and first_date >= current_date + 24 and last_date = current_date + 80), 1,
  'tutor gets a request for next term, skipping the holidays');
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000013'
  and booking_id = :'next_booking' and kind = 'booking_requested'), 1, 'tutor told about the request');
select tests.eq((select testimonial_ok::int from public.term_renewals where id = :'renewal'), 1, 'testimonial permission kept');

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select public.respond_to_booking(:'next_booking', true);
reset role;
select tests.claims(null);
select tests.eq((select (count(*) > 0)::int from public.sessions where booking_id = :'next_booking'), 1, 'next term''s sessions made');
select tests.eq((select count(*) from public.sessions where booking_id = :'next_booking' and starts_at < (current_date + 24)::timestamptz), 0, 'none in the holidays');

select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.list_renewals() where booking_id = :'ending' and next_status = 'confirmed'), 1, 'family sees it confirmed');
reset role;

-- Testimonial permission needs feedback; a change needs what and why.
select tests.claims(null);
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery,
                             first_date, last_date, status, confirmed_at)
select :'sam', '00000000-0000-0000-0000-000000000013', :'sam_family', 'General Maths',
       extract(isodow from current_date + 2)::smallint, '19:00', 60, 'online',
       current_date + 2, current_date + 9, 'confirmed', now()
returning id as other \gset
select private.queue_renewals();
select id as renewal2 from public.term_renewals where booking_id = :'other' \gset
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((public.answer_renewal(:'renewal2', false, true, 'time', 'Netball on that day', null, true) is null)::int, 1, 'a change sends no request');
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.term_renewals where id = :'renewal2' and change_what = 'time'
  and change_reason = 'Netball on that day' and not testimonial_ok), 1, 'change recorded; no testimonial without feedback');

-- Leave the extra sessions and bookings out of the later tests.
delete from public.sessions where booking_id in (:'ending', :'next_booking', :'other');
delete from public.bookings where id in (:'next_booking', :'ending', :'other');

\echo '  scheduling terms and renewals: all checks passed'
