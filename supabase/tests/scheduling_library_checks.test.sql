-- Library opening hours when needed, re-checks and the first-booking
-- holiday reminder (Carla, 11 Nov 2026). Reuses the earlier scheduling
-- tests' people: owner admin (...a0), tutor T3 (...13), Sam Three.

select tests.claims(null);
select id as sam from public.students where full_name = 'Sam Three' \gset
insert into public.libraries (name, suburb) values ('Hours Test Library', 'Glenelg') returning id as lib \gset
delete from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0'
  and title in ('Library opening hours needed', 'First sessions at a library');

-- Loaded but unused: nothing asked.
select tests.eq((select count(*) from public.session_notices where title = 'Library opening hours needed' and body like 'Hours Test Library%'), 0::bigint, 'no request while unused');

-- A tutor adds it: admins are asked once.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
insert into public.tutor_places (tutor_id, library_id) values ('00000000-0000-0000-0000-000000000013', :'lib');
reset role;
select tests.claims(null);
insert into public.student_places (student_id, online, library_ids) values (:'sam', true, array[:'lib']::uuid[])
on conflict (student_id) do update set library_ids = excluded.library_ids;
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0'
  and title = 'Library opening hours needed' and body like 'Hours Test Library%'), 1::bigint, 'admins are asked for hours once');

-- It shows on the to-do list until hours are added, then again after 6 months.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.library_checks() where library_id = :'lib' and problem = 'Opening hours needed'), 1::bigint, 'to-do: hours needed');
select tests.fails(format($$select public.mark_library_hours_checked(%L)$$, :'lib'), 'can''t say hours are right with none entered');
insert into public.library_hours (library_id, weekday, opens, closes) values (:'lib', 1, '09:00', '17:00');
select tests.eq((select count(*) from public.library_checks() where library_id = :'lib'), 0::bigint, 'off the list once hours are in');
reset role;
select tests.claims(null);
update public.libraries set hours_checked_at = now() - interval '7 months' where id = :'lib';
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.library_checks() where library_id = :'lib' and problem like 'Check%'), 1::bigint, 'back on the list after 6 months');
select public.mark_library_hours_checked(:'lib');
select tests.eq((select count(*) from public.library_checks() where library_id = :'lib'), 0::bigint, 'marked as still right');
reset role;

-- Families and tutors can't see the list.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails($q$select * from public.library_checks()$q$, 'tutors can''t see library checks');
reset role;

-- First sessions at the library: one holiday reminder.
select tests.claims(null);
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, library_id, first_date, last_date, tutor_reply_by, requested_by)
values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 1, '10:00', 60, 'library', :'lib', current_date + 14, current_date + 42,
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0'),
       (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 1, '12:00', 60, 'library', :'lib', current_date + 14, current_date + 42,
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0');
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0'
  and title = 'First sessions at a library' and body like '%Hours Test Library%'), 1::bigint, 'one holiday reminder for the first booking');

-- Put things back.
delete from public.session_notices where booking_id in (select id from public.bookings where library_id = :'lib');
delete from public.bookings where library_id = :'lib';
delete from public.student_places where student_id = :'sam';
delete from public.tutor_places where library_id = :'lib';
delete from public.libraries where id = :'lib';
delete from public.session_notices where title in ('Library opening hours needed', 'First sessions at a library');

\echo '  scheduling library checks: all checks passed'

-- Numbers on tabs (Carla, 11 Nov 2026).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.scheduling_counts() where key in ('matching', 'libraries')), 2::bigint, 'admins get matching and library counts');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select n from public.scheduling_counts() where key = 'booking-length'), 1, 'a family with an unanswered "How long to book" sees 1');
select tests.eq((select count(*) from public.scheduling_counts() where key = 'matching'), 0::bigint, 'families don''t get the matching count');
select public.set_booking_length(:'sam', current_date + 30, true, true);
select tests.eq((select n from public.scheduling_counts() where key = 'booking-length'), 0, 'answered: 0');
reset role;
select tests.claims(null);
delete from public.student_places where student_id = :'sam';

\echo '  scheduling tab counts: all checks passed'
