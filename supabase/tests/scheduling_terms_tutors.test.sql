-- Tutors check their availability each term. Runs after
-- scheduling_terms.test.sql, which leaves made-up SA terms in place: this
-- term ends in 10 days (term 2, so tutors are asked from 21 days before),
-- and next term starts in 24 days.

select tests.claims(null);
select private.queue_availability_checks();
select tests.eq((select count(*) from public.availability_checks where tutor_id = '00000000-0000-0000-0000-000000000013'), 1, 'tutor asked');
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000013'
  and kind = 'availability_check'), 1, 'tutor gets a notice');
select private.queue_availability_checks();
select tests.eq((select count(*) from public.availability_checks where tutor_id = '00000000-0000-0000-0000-000000000013'), 1, 'asked only once a term');
select id as t3_check from public.availability_checks where tutor_id = '00000000-0000-0000-0000-000000000013' \gset

-- Who can see and answer.
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.availability_checks where tutor_id = '00000000-0000-0000-0000-000000000013'), 0, 'other tutor can''t see it');
select tests.fails(format($$select public.confirm_availability(%L, false)$$, :'t3_check'), 'other tutor confirms');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.eq((select count(*) from public.list_availability_checks()), 0, 'families see none');
reset role;
select tests.claims(null);
set role anon;
select tests.fails($$select * from public.availability_checks$$, 'anon');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal1');
set role authenticated;
select tests.fails(format($$select public.confirm_availability(%L, false)$$, :'t3_check'), 'tutor without two-step login');
reset role;

-- The tutor taps "No changes": a copy of their availability is kept.
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.fails(format($$update public.availability_checks set changed = true where id = %L$$, :'t3_check'), 'tutor edits the table directly');
select public.confirm_availability(:'t3_check', false);
select tests.eq((select count(*) from public.list_availability_checks() where confirmed_at is not null and not changed), 1, 'confirmed with no changes');
reset role;
select tests.claims(null);
select tests.eq((select jsonb_array_length(snapshot->'slots') from public.availability_checks where id = :'t3_check'),
  (select count(*)::int from public.tutor_availability where tutor_id = '00000000-0000-0000-0000-000000000013'), 'availability copied');

-- Next term: the tutor has removed a weekly time, and a booking now falls
-- outside their availability.
select a.id as gone_id, a.weekday as gone_day, a.starts_at as gone_from, a.ends_at as gone_to
from public.tutor_availability a where a.tutor_id = '00000000-0000-0000-0000-000000000013'
order by a.weekday, a.starts_at limit 1 \gset
select tests.claims(null);
update public.availability_checks set asked_at = now() - interval '3 months' where id = :'t3_check';
insert into public.availability_checks (tutor_id, term_id)
select '00000000-0000-0000-0000-000000000013', id from public.school_terms where state = 'SA' and starts_on = current_date + 24;
delete from public.tutor_availability where id = :'gone_id';
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select bookings_outside as outside_before from public.list_availability_checks() \gset
reset role;
select tests.claims(null);
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, status, confirmed_at)
select id, '00000000-0000-0000-0000-000000000013', 'General Maths', 7, '06:00', 60, 'online', current_date, current_date + 5, 'confirmed', now()
from public.students where full_name = 'Sam Three'
returning id as outside_booking \gset

select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2');
set role authenticated;
select tests.eq((select cardinality(removed_slots) from public.list_availability_checks()), 1, 'removed time shown');
select tests.eq((select bookings_outside from public.list_availability_checks()), :'outside_before'::bigint + 1, 'booking outside availability counted');
select tests.eq((select (confirmed_at is null)::int from public.list_availability_checks()), 1, 'new term''s check not answered yet');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.list_availability_checks() where tutor_id = '00000000-0000-0000-0000-000000000013'), 1, 'admin sees the latest check');
reset role;

-- Put things back for the later tests.
select tests.claims(null);
delete from public.bookings where id = :'outside_booking';
insert into public.tutor_availability (id, tutor_id, weekday, starts_at, ends_at)
values (:'gone_id', '00000000-0000-0000-0000-000000000013', :'gone_day', :'gone_from', :'gone_to');

\echo '  scheduling tutor availability checks: all checks passed'
