-- Away dates and the waitlist. Runs after scheduling.test.sql and reuses its
-- people: owner admin (...a0), tutors T3 (...13) and T4 (...14), parents P3
-- (...03, Sam Three's parent) and P4 (...04), and the two libraries.

select id as sam from public.students where full_name = 'Sam Three' \gset
select (current_date + 7 + ((8 - extract(isodow from current_date)::int) % 7)) as first_day \gset

-- ---------------------------------------------------------------------------
-- Away dates
-- ---------------------------------------------------------------------------

-- The family will be away on the second Monday.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq(public.add_away_dates(null, :'sam', :'first_day'::date + 6, :'first_day'::date + 8, 'Camp'), 0, 'family adds away dates (nothing booked yet)');
select tests.fails(format($$select public.add_away_dates(null, %L, %L::date + 9, %L::date + 8)$$, :'sam', :'first_day', :'first_day'), 'dates out of order');
select tests.fails(format($$select public.add_away_dates(null, %L, current_date - 10, current_date - 5)$$, :'sam'), 'dates in the past');
select tests.fails($$select public.add_away_dates('00000000-0000-0000-0000-000000000013', null, current_date + 1, current_date + 2)$$, 'family adds a tutor''s away dates');
select tests.fails($$insert into public.away_dates (student_id, from_date, to_date) select id, current_date, current_date from public.students$$, 'family writes the table directly');
select tests.eq(c.sessions, 4, 'booking shows 4 sessions') from public.count_booking_sessions(:'sam', '00000000-0000-0000-0000-000000000013', 1::smallint, :'first_day'::date, :'first_day'::date + 28) c;
select tests.eq(c.skipped, 1, 'and 1 away date skipped') from public.count_booking_sessions(:'sam', '00000000-0000-0000-0000-000000000013', 1::smallint, :'first_day'::date, :'first_day'::date + 28) c;
select public.request_booking(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000013', 1::smallint, '16:00', 60, 'online', null, :'first_day'::date, :'first_day'::date + 28) as booking \gset
reset role;

select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.fails(format($$select public.add_away_dates(null, %L, current_date + 1, current_date + 2)$$, :'sam'), 'other parent adds away dates');
select tests.fails(format($$select * from public.count_booking_sessions(%L, '00000000-0000-0000-0000-000000000013', 1::smallint, current_date, current_date + 7)$$, :'sam'), 'other parent counts sessions');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select public.respond_to_booking(:'booking', true);
select tests.eq((select count(*) from public.sessions where booking_id = :'booking'), 4, 'away week skipped when sessions are made');
reset role;

-- The tutor is away the first Monday: that session is cancelled by the tutor.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal1');
set role authenticated;
select tests.fails(format($$select public.add_away_dates('00000000-0000-0000-0000-000000000013', null, %L::date, %L::date)$$, :'first_day', :'first_day'), 'tutor without two-step login');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2');
set role authenticated;
select tests.fails(format($$select public.add_away_dates('00000000-0000-0000-0000-000000000013', null, %L::date, %L::date)$$, :'first_day', :'first_day'), 'tutor adds another tutor''s away dates');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.eq(public.add_away_dates('00000000-0000-0000-0000-000000000013', null, :'first_day'::date, :'first_day'::date, 'Exam'), 1, 'tutor away cancels one session');
select tests.eq((select count(*) from public.sessions where booking_id = :'booking' and status = 'cancelled' and cancelled_by_role = 'tutor' and cancel_reason = 'Away: Exam'), 1, 'cancelled by the tutor');
select tests.eq((select count(*) from public.away_dates where student_id = :'sam'), 1, 'tutor sees their student''s away dates');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.away_dates), 0, 'other tutor sees none');
reset role;
select tests.claims(null);
select id as sam_away from public.away_dates where student_id = :'sam' \gset
select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.eq((select count(*) from public.away_dates), 0, 'other parent sees none');
select tests.fails(format($$select public.remove_away_dates(%L)$$, :'sam_away'), 'other parent removes');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.away_dates), 1, 'family sees only their child''s');
select public.remove_away_dates(id) from public.away_dates where student_id = :'sam';
select tests.eq((select count(*) from public.away_dates), 0, 'family removes away dates');
reset role;
select tests.claims(null);
set role anon;
select tests.fails($$select * from public.away_dates$$, 'anon');
reset role;

-- ---------------------------------------------------------------------------
-- Waitlist
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', null, array[2]::smallint[])), 0, 'nobody free on Tuesdays');
select public.join_waitlist(:'sam', 'General Maths', 60, true, '{}', array[2]::smallint[], null, null, null, 'Any Tuesday') as wait \gset
select tests.fails(format($$select public.join_waitlist(%L, 'general maths', 60, true)$$, :'sam'), 'same subject twice');
select tests.fails(format($$select public.join_waitlist(%L, 'Science', 60, false, '{}')$$, :'sam'), 'no place chosen');
select tests.fails($$insert into public.waitlist (student_id, subject, minutes) select id, 'x', 60 from public.students$$, 'family writes the table directly');
select tests.eq((select count(*) from public.list_waitlist()), 1, 'family sees their place');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.eq((select count(*) from public.waitlist), 0, 'other parent sees no places');
select tests.eq((select count(*) from public.list_waitlist()), 0, 'other parent list is empty');
select tests.fails(format($$select public.join_waitlist(%L, 'English', 60, true)$$, :'sam'), 'other parent joins for Sam');
select tests.fails(format($$select public.leave_waitlist(%L)$$, :'wait'), 'other parent removes Sam''s place');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select times_now_free from public.list_waitlist() where id = :'wait'), 0, 'no times free yet');
select tests.eq((select count(*) from public.list_waitlist() where waited_4_weeks), 0, 'not waiting 4 weeks yet');
reset role;

-- T3 adds Tuesday availability: the admin list now shows free times.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at)
  values ('00000000-0000-0000-0000-000000000013', 2, '15:00', '17:00');
reset role;
select tests.claims(null);
update public.waitlist set created_at = now() - interval '30 days' where id = :'wait';
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select times_now_free from public.list_waitlist() where id = :'wait'), 3, 'three Tuesday times now free');
select tests.eq((select count(*) from public.list_waitlist() where waited_4_weeks), 1, 'waited 4 weeks');
reset role;

-- Booking that subject closes the place.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select public.request_booking(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000013', 2::smallint, '15:00', 60, 'online', null, :'first_day'::date, :'first_day'::date + 14);
select tests.eq((select count(*) from public.waitlist where id = :'wait' and closed_reason = 'booked'), 1, 'place closed when booked');
select tests.eq((select count(*) from public.list_waitlist()), 0, 'no open places left');
select public.join_waitlist(:'sam', 'General Maths', 90, false, array[(select id from public.libraries where name = 'Beta Library')]);
select public.leave_waitlist(id) from public.waitlist where closed_at is null;
select tests.eq((select count(*) from public.waitlist where closed_reason = 'withdrawn'), 1, 'family leaves the waitlist');
reset role;
select tests.claims(null);

\echo '  scheduling away dates and waitlist: all checks passed'
