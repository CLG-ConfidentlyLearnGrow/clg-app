-- Summary: checks start times every 15 minutes and the session summary time
-- kept free after each of a tutor's sessions (Carla, 12 Nov 2026), and that
-- only owner and operations admins can change the summary time. Reuses the
-- earlier scheduling tests' people: owner admin (...a0), tutor T3 (...13)
-- and Sam Three.

select tests.claims(null); -- acts as the database itself while setting up
select id as sam from public.students where full_name = 'Sam Three' \gset
select id as other from public.students where full_name <> 'Sam Three' order by full_name limit 1 \gset
select max_weekly_hours as t3_max from public.tutor_work_settings where tutor_id = '00000000-0000-0000-0000-000000000013' \gset
update public.tutor_work_settings set max_weekly_hours = null where tutor_id = '00000000-0000-0000-0000-000000000013'; -- no weekly limit during this test
delete from public.bookings where tutor_id = '00000000-0000-0000-0000-000000000013' and weekday = 7; -- clear Sunday bookings from earlier tests
-- T3 is available Sundays 8am to 1pm, online.
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at, online, in_person) -- the columns being filled
values ('00000000-0000-0000-0000-000000000013', 7, '08:00', '13:00', true, false) returning id as sun \gset
-- T3 already has another student 10 to 11am on Sundays (a request, which holds the time).
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by) -- the columns being filled
values (:'other', '00000000-0000-0000-0000-000000000013', 'General Maths', 7, '10:00', 60, 'online', current_date + 7, current_date + 70, -- Sunday 10am online
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0') returning id as held \gset

-- The setting starts at 15 minutes.
select tests.eq((select summary_minutes from public.scheduling_settings), 15, 'summary time starts at 15 min');

-- With 15 min: one-hour starts 8:00 to 8:45 (finished by 9:45, 15 min before 10am)
-- and 11:15 to 12:00 (15 min after 11am), every 15 minutes: 8 in all.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', null, array[7]::smallint[]) -- Sunday times for Sam
  where tutor_id = '00000000-0000-0000-0000-000000000013'), 8::bigint, 'times leave 15 min after the other session for the summary');
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', null, array[7]::smallint[]) -- Sunday times for Sam
  where tutor_id = '00000000-0000-0000-0000-000000000013' and start_time = '08:15'), 1::bigint, 'start times every 15 minutes (8:15 is offered)');
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', null, array[7]::smallint[]) -- Sunday times for Sam
  where tutor_id = '00000000-0000-0000-0000-000000000013' and start_time in ('09:30', '10:30', '11:00')), 0::bigint, 'nothing inside the other session or its summary time');
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', null, array[7]::smallint[]) -- Sunday times for Sam
  where tutor_id = '00000000-0000-0000-0000-000000000013' and joins_other_sessions), 2::bigint, '8:45 and 11:15 are marked as next to the other session');

-- Offering another time inside the summary time is refused.
select tests.fails(format($$select public.offer_other_time(%L, 'General Maths', '00000000-0000-0000-0000-000000000013', 7::smallint, '11:05', 60, 'online', null, current_date + 7, current_date + 70, 'test')$$, :'sam'),
  'an offered time can''t start inside the tutor''s summary time');
-- 11:15, straight after the summary time, is accepted (proves the refusal above was about the gap).
select public.offer_other_time(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000013', 7::smallint, '11:15', 60, 'online', null, current_date + 7, current_date + 70, 'test') as offered \gset
select tests.eq((select count(*) from public.bookings where id = :'offered'), 1::bigint, 'a time straight after the summary time can be offered');
reset role; -- back to the database itself
select tests.claims(null); -- acts as the database itself
delete from public.session_notices where booking_id = :'offered'; -- removes that offer's notices
delete from public.bookings where id = :'offered'; -- removes that offer, so Sam is free again
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin again
set role authenticated; -- acts as a signed-in person

-- Tutors and families can't change the summary time.
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- signs in as tutor T3
set role authenticated; -- acts as a signed-in person
select tests.fails($q$select public.set_summary_minutes(5)$q$, 'tutors can''t change the summary time');
reset role; -- back to the database itself

-- The owner changes it: 31 is refused, 0 means back-to-back times are allowed.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner admin
set role authenticated; -- acts as a signed-in person
select tests.fails($q$select public.set_summary_minutes(31)$q$, 'over 30 minutes is refused');
select public.set_summary_minutes(0); -- no summary time
select tests.eq((select count(*) from public.find_session_times(:'sam', 'General Maths', 60, true, '{}', null, array[7]::smallint[]) -- Sunday times for Sam
  where tutor_id = '00000000-0000-0000-0000-000000000013'), 10::bigint, 'with 0 min, 9am and 11am are offered too');
select public.set_summary_minutes(15); -- back to 15 min
reset role; -- back to the database itself

-- Put things back.
select tests.claims(null); -- acts as the database itself
delete from public.session_notices where booking_id = :'held'; -- removes the test notices
delete from public.bookings where id = :'held'; -- removes the test booking
delete from public.tutor_availability where id = :'sun'; -- removes the Sunday time
update public.tutor_work_settings set max_weekly_hours = nullif(:'t3_max', '')::numeric where tutor_id = '00000000-0000-0000-0000-000000000013'; -- puts the weekly limit back

\echo '  scheduling summary time: all checks passed'
