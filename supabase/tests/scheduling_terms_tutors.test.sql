-- Tutors check their availability each term. Runs after
-- scheduling_terms.test.sql, which leaves made-up SA terms in place: this
-- term ends in 10 days (term 2, so tutors are asked from 21 days before),
-- and next term starts in 24 days.

select tests.claims(null); -- Signs out, so no one is signed in.
select private.queue_availability_checks(); -- Queues the "is your availability right?" checks.
select tests.eq((select count(*) from public.availability_checks where tutor_id = '00000000-0000-0000-0000-000000000013'), 1, 'tutor asked'); -- Checks: tutor asked.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000013' -- Checks tutor T3 gets a notice:
  and kind = 'availability_check'), 1, 'tutor gets a notice'); -- (one availability check notice).
select private.queue_availability_checks(); -- Queues the checks again (should not repeat).
select tests.eq((select count(*) from public.availability_checks where tutor_id = '00000000-0000-0000-0000-000000000013'), 1, 'asked only once a term'); -- Checks: asked only once a term.
-- Keeps tutor T3's check id as t3_check.
select id as t3_check from public.availability_checks where tutor_id = '00000000-0000-0000-0000-000000000013' \gset

-- Who can see and answer.
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as test account ...14 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.availability_checks where tutor_id = '00000000-0000-0000-0000-000000000013'), 0, 'other tutor can''t see it'); -- Checks: other tutor can't see it.
select tests.fails(format($$select public.confirm_availability(%L, false)$$, :'t3_check'), 'other tutor confirms'); -- Checks this is refused: other tutor confirms.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_availability_checks()), 0, 'families see none'); -- Checks: families see none.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.availability_checks$$, 'anon'); -- Checks this is refused: anon.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal1'); -- Signs in as test account ...13.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.confirm_availability(%L, false)$$, :'t3_check'), 'tutor without two-step login'); -- Checks this is refused: tutor without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The tutor taps "No changes": a copy of their availability is kept.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$update public.availability_checks set changed = true where id = %L$$, :'t3_check'), 'tutor edits the table directly'); -- Checks this is refused: tutor edits the table directly.
select public.confirm_availability(:'t3_check', false); -- Tutor T3 says their availability has changed.
select tests.eq((select count(*) from public.list_availability_checks() where confirmed_at is not null and not changed), 1, 'confirmed with no changes'); -- Checks: confirmed with no changes.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select jsonb_array_length(snapshot->'slots') from public.availability_checks where id = :'t3_check'), -- Checks their availability is copied into the check:
  (select count(*)::int from public.tutor_availability where tutor_id = '00000000-0000-0000-0000-000000000013'), 'availability copied'); -- (same number of times as they have).

-- Next term: the tutor has removed a weekly time, and a booking now falls
-- outside their availability.
select a.id as gone_id, a.weekday as gone_day, a.starts_at as gone_from, a.ends_at as gone_to -- Keeps one of tutor T3's available times:
from public.tutor_availability a where a.tutor_id = '00000000-0000-0000-0000-000000000013' -- (its id, day, start and end),
-- the earliest one.
order by a.weekday, a.starts_at limit 1 \gset
select tests.claims(null); -- Signs out, so no one is signed in.
update public.availability_checks set asked_at = now() - interval '3 months' where id = :'t3_check'; -- Makes the check three months old.
insert into public.availability_checks (tutor_id, term_id) -- Adds a new check for next term:
select '00000000-0000-0000-0000-000000000013', id from public.school_terms where state = 'SA' and starts_on = current_date + 24; -- (for tutor T3, for the SA term starting in 24 days).
delete from public.tutor_availability where id = :'gone_id'; -- Removes the kept available time.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Keeps how many bookings fall outside availability, before.
select bookings_outside as outside_before from public.list_availability_checks() \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, status, confirmed_at) -- Adds a confirmed booking for Sam with tutor T3:
select id, '00000000-0000-0000-0000-000000000013', 'General Maths', 7, '06:00', 60, 'online', current_date, current_date + 5, 'confirmed', now() -- Sunday 6am online (outside their availability),
from public.students where full_name = 'Sam Three' -- (for Sam)
-- and keeps its id as outside_booking.
returning id as outside_booking \gset

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as test account ...13 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select cardinality(removed_slots) from public.list_availability_checks()), 1, 'removed time shown'); -- Checks: removed time shown.
select tests.eq((select bookings_outside from public.list_availability_checks()), :'outside_before'::bigint + 1, 'booking outside availability counted'); -- Checks: booking outside availability counted.
select tests.eq((select (confirmed_at is null)::int from public.list_availability_checks()), 1, 'new term''s check not answered yet'); -- Checks: new term's check not answered yet.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_availability_checks() where tutor_id = '00000000-0000-0000-0000-000000000013'), 1, 'admin sees the latest check'); -- Checks: admin sees the latest check.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Put things back for the later tests.
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.bookings where id = :'outside_booking'; -- Removes that booking.
insert into public.tutor_availability (id, tutor_id, weekday, starts_at, ends_at) -- Puts the removed available time back:
values (:'gone_id', '00000000-0000-0000-0000-000000000013', :'gone_day', :'gone_from', :'gone_to'); -- (with the same id, day and times).

-- Prints that every check in this file passed.
\echo '  scheduling tutor availability checks: all checks passed'
