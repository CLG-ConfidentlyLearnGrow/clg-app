-- CLG hears when a session time is declined (Carla, 11 Nov 2026). Reuses
-- the earlier scheduling tests' people: owner admin (...a0), tutor T3 (...13)
-- and Sam Three.

select tests.claims(null);
select id as sam from public.students where full_name = 'Sam Three' \gset
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by)
values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 6, '10:00', 60, 'online', current_date + 14, current_date + 42,
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0')
returning id as offer \gset

-- The tutor must give a reason to decline.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails(format($$select public.respond_to_booking(%L, false, '  ')$$, :'offer'), 'a tutor can''t decline without a reason');
select public.respond_to_booking(:'offer', false, 'Saturday mornings are taken');
reset role;

select tests.claims(null);
select tests.eq((select count(*) from public.session_notices
  where account_id = '00000000-0000-0000-0000-0000000000a0' and booking_id = :'offer' and title = 'Session declined'
    and body like '%Reason: Saturday mornings are taken%'), 1::bigint, 'CLG admin is told when a tutor declines, with the reason');
select tests.eq((select count(*) from public.session_notices
  where account_id = '00000000-0000-0000-0000-000000000013' and booking_id = :'offer' and title = 'Session declined'), 0::bigint,
  'the tutor who declined isn''t sent the CLG notice');

delete from public.session_notices where booking_id = :'offer';
delete from public.bookings where id = :'offer';

-- A family must give a reason to decline a time CLG offered.
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by, needs_family_ok)
values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 6, '10:00', 60, 'online', current_date + 14, current_date + 42,
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0', true)
returning id as fam \gset
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.approve_booking(%L, false, null)$$, :'fam'), 'a family can''t decline without a reason');
select public.approve_booking(:'fam', false, 'Saturdays are sport');
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.session_notices
  where account_id = '00000000-0000-0000-0000-0000000000a0' and booking_id = :'fam' and body like '%Reason: Saturdays are sport%'), 1::bigint,
  'CLG admin is told when a family declines, with the reason');
delete from public.session_notices where booking_id = :'fam';
delete from public.bookings where id = :'fam';

-- A declined offer doesn't restart a waiting student's count.
insert into public.student_subjects (student_id, subject) values (:'sam', 'Chemistry');
update public.student_subjects set added_at = now() - interval '10 days' where student_id = :'sam' and subject = 'Chemistry';
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by)
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Chemistry', 6, '10:00', 60, 'online', current_date + 14, current_date + 42,
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0')
returning id as chem \gset
update public.bookings set status = 'declined', declined_by_role = 'tutor' where id = :'chem';
select tests.eq((select (stage = 'needs_tutor' and since < now() - interval '9 days')::int from private.matching_rows()
  where student_id = :'sam' and subject = 'Chemistry'), 1, 'still waiting since the subject was added after a decline');
delete from public.session_notices where booking_id = :'chem';
delete from public.bookings where id = :'chem';
delete from public.student_subjects where student_id = :'sam' and subject = 'Chemistry';

\echo '  scheduling decline notice: all checks passed'
