-- CLG hears when a session time is declined (Carla, 11 Nov 2026). Reuses
-- the earlier scheduling tests' people: owner admin (...a0), tutor T3 (...13)
-- and Sam Three.

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by) -- Adds an offer for Sam with tutor T3:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 6, '10:00', 60, 'online', current_date + 14, current_date + 42, -- Saturday 10am online, starting in two weeks,
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0') -- the tutor has two days to reply, offered by the owner,
-- and keeps its id as offer.
returning id as offer \gset

-- The tutor must give a reason to decline.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.respond_to_booking(%L, false, '  ')$$, :'offer'), 'a tutor can''t decline without a reason'); -- Checks this is refused: a tutor can't decline without a reason.
select public.respond_to_booking(:'offer', false, 'Saturday mornings are taken'); -- The tutor declines, with a reason.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.session_notices -- Checks the CLG admin is told, with the reason:
  where account_id = '00000000-0000-0000-0000-0000000000a0' and booking_id = :'offer' and title = 'Session declined' -- (a "Session declined" notice for this offer),
    and body like '%Reason: Saturday mornings are taken%'), 1::bigint, 'CLG admin is told when a tutor declines, with the reason'); -- (that includes the reason).
select tests.eq((select count(*) from public.session_notices -- Checks the tutor who declined isn't sent the CLG notice:
  where account_id = '00000000-0000-0000-0000-000000000013' and booking_id = :'offer' and title = 'Session declined'), 0::bigint, -- (none for tutor T3),
  'the tutor who declined isn''t sent the CLG notice'); -- (the label).

delete from public.session_notices where booking_id = :'offer'; -- Removes the offer's notices.
delete from public.bookings where id = :'offer'; -- Removes the offer.

-- A family must give a reason to decline a time CLG offered.
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by, needs_family_ok) -- Adds an offer that also needs the family's OK:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 6, '10:00', 60, 'online', current_date + 14, current_date + 42, -- (the same time),
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0', true) -- (needs the family's OK),
-- and keeps its id as fam.
returning id as fam \gset
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.approve_booking(%L, false, null)$$, :'fam'), 'a family can''t decline without a reason'); -- Checks this is refused: a family can't decline without a reason.
select public.approve_booking(:'fam', false, 'Saturdays are sport'); -- The family declines, with a reason.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.session_notices -- Checks the CLG admin is told, with the reason:
  where account_id = '00000000-0000-0000-0000-0000000000a0' and booking_id = :'fam' and body like '%Reason: Saturdays are sport%'), 1::bigint, -- (a notice that includes the reason),
  'CLG admin is told when a family declines, with the reason'); -- (the label).
delete from public.session_notices where booking_id = :'fam'; -- Removes the offer's notices.
delete from public.bookings where id = :'fam'; -- Removes the offer.

-- A declined offer doesn't restart a waiting student's count.
insert into public.student_subjects (student_id, subject) values (:'sam', 'Chemistry'); -- Adds Chemistry to Sam's subjects.
update public.student_subjects set added_at = now() - interval '10 days' where student_id = :'sam' and subject = 'Chemistry'; -- Makes it look added 10 days ago.
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, tutor_reply_by, requested_by) -- Adds a Chemistry offer:
values (:'sam', '00000000-0000-0000-0000-000000000013', 'Chemistry', 6, '10:00', 60, 'online', current_date + 14, current_date + 42, -- (the same time),
        now() + interval '2 days', '00000000-0000-0000-0000-0000000000a0') -- (offered by the owner),
-- and keeps its id as chem.
returning id as chem \gset
update public.bookings set status = 'declined', declined_by_role = 'tutor' where id = :'chem'; -- Marks it declined by the tutor.
select tests.eq((select (stage = 'needs_tutor' and since < now() - interval '9 days')::int from private.matching_rows() -- Checks the wait still counts from when the subject was added:
  where student_id = :'sam' and subject = 'Chemistry'), 1, 'still waiting since the subject was added after a decline'); -- (still needs a tutor, waiting more than 9 days).
delete from public.session_notices where booking_id = :'chem'; -- Removes the offer's notices.
delete from public.bookings where id = :'chem'; -- Removes the offer.
delete from public.student_subjects where student_id = :'sam' and subject = 'Chemistry'; -- Removes Chemistry.

-- Prints that every check in this file passed.
\echo '  scheduling decline notice: all checks passed'
