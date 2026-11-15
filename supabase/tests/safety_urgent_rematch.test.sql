-- Summary: checks urgent re-matching after a match is ended from a concern
-- (Carla, 15 Nov 2026): ending a match when the child has upcoming sessions
-- with that tutor raises an "Urgent: needs a new tutor" flag, counting the
-- sessions already on an invoice; matching admins see it (with no reason)
-- and can mark it sorted; tutors and families can't see it. Reuses
-- access_rules.test.sql people: owner Olive (...a0, officer), operations
-- admin Sam Staff (...b0), tutor T1 (...11, teaches Cara), parent P1 (...01,
-- Cara's parent). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this database change again (checks it can run twice).
\ir ../migrations/20261117500100_safety_urgent_rematch.sql

select tests.claims(null); -- acts as the database itself while setting up
select id as cara, family_id as fam from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's student id as cara and her family as fam)
update public.child_safety_contacts set officer_id = '00000000-0000-0000-0000-0000000000a0', deputy_id = '00000000-0000-0000-0000-0000000000b0' where id; -- Olive is officer, Sam Staff is deputy
\set olive '00000000-0000-0000-0000-0000000000a0'
-- (Olive's account id, the officer)
\set sam '00000000-0000-0000-0000-0000000000b0'
-- (Sam Staff's account id, an operations admin)
\set t1 '00000000-0000-0000-0000-000000000011'
-- (tutor T1's account id)
update public.tutor_assignments set starts_on = current_date - 30 where tutor_id = :'t1' and student_id = :'cara'; -- makes T1's match with Cara clearly current
insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) -- three upcoming sessions for T1 and Cara:
select :'cara', :'t1', :'fam', 'English', 'school', 'online', now() + (d || ' days')::interval, now() + (d || ' days')::interval + interval '1 hour' -- an hour of English each,
from unnest(array[3, 10, 17]) d; -- in 3, 10 and 17 days
insert into public.billing_invoices (family_id, family_name, plan, method, status, period_start, period_end, first_session_on, send_on, due_on, charge_on) -- a paid invoice:
values (:'fam', 'Test family', 'term', 'card', 'paid', current_date, current_date + 30, current_date + 3, current_date, current_date, current_date) -- for this term
returning id as inv \gset
-- (keeps the invoice's id as inv)
insert into public.billing_invoice_lines (invoice_id, session_id, student_id, line_date, description, minutes, billed_minutes, hourly_cents, amount_cents) -- puts two of the sessions on it:
select :'inv', s.id, :'cara', (s.starts_at at time zone 'Australia/Adelaide')::date, 'English', 60, 60, 9500, 9500 -- one line each,
from public.sessions s where s.tutor_id = :'t1' and s.student_id = :'cara' and s.starts_at < now() + interval '12 days'; -- the first two

-- P1 raises a concern about T1 and Cara; the officer ends the match.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person, so access rules apply
select public.raise_safety_concern(:'cara', null, null, 'officer', false, false, 'no', null, null, 'Something the tutor said worried us.', array[:'t1']::uuid[]) as c1 \gset
-- (keeps the concern's id as c1)
reset role; -- back to the database itself
select tests.claims(:'olive', 'aal2'); -- signs in as the officer
set role authenticated; -- acts as a signed-in person
select public.safety_end_match(:'c1', :'t1', 'Keeping Cara safe while we look into it.'); -- ends the match
select tests.eq((select count(*) from public.safety_concern_rematch(:'c1') where paid_sessions = 2 and upcoming_sessions = 3), 1::bigint, 'the officer sees the urgent flag on the concern'); -- shown on the concern
reset role; -- back to the database itself

-- 1. The flag counts the sessions.
select tests.eq((select count(*) from public.safety_rematch_flags where student_id = :'cara' and upcoming_sessions = 3 and paid_sessions = 2 and subjects = 'English' and sorted_at is null), 1::bigint, 'the flag counts 3 upcoming sessions, 2 already paid for'); -- counted

-- 2. Matching admins see it, without a reason.
select tests.claims(:'sam', 'aal2'); -- signs in as Sam (operations, not handling the concern)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.urgent_rematches() where student_name = 'Cara One' and paid_sessions = 2), 1::bigint, 'a matching admin sees the urgent flag'); -- visible
select tests.fails($q$select * from public.safety_rematch_flags$q$, 'nobody reads the flags table directly'); -- refused
select tests.eq((select count(*) from public.safety_concern_rematch(:'c1')), 0::bigint, 'but can''t see it on the concern (not handling it)'); -- hidden
reset role; -- back to the database itself

-- 3. Tutors and families don't see it.
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.urgent_rematches()), 0::bigint, 'the tutor sees no flags'); -- hidden
select tests.fails(format($q$select public.urgent_rematch_sorted(%L, 'Trying')$q$, (select id from public.urgent_rematches() limit 1)), 'the tutor can''t mark it sorted'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.urgent_rematches()), 0::bigint, 'families see no flags'); -- hidden
reset role; -- back to the database itself

-- 4. Marking it sorted.
select id as flag from public.safety_rematch_flags where student_id = :'cara' \gset
-- (keeps the flag's id as flag)
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.urgent_rematch_sorted(%L, '')$q$, :'flag'), 'marking sorted needs a note'); -- refused
select public.urgent_rematch_sorted(:'flag', 'Moved Cara to a new tutor from next week.'); -- marks it sorted
select tests.eq((select count(*) from public.urgent_rematches()), 0::bigint, 'once sorted, it leaves the list'); -- gone
reset role; -- back to the database itself

-- 5. No flag when nothing is booked.
delete from public.safety_holds where concern_id = :'c1'; -- clears the step (and its flag) for a fresh try
update public.sessions set status = 'cancelled', cancelled_at = now() where tutor_id = :'t1' and student_id = :'cara'; -- cancels the sessions
select tests.claims(:'olive', 'aal2'); -- signs in as the officer
set role authenticated; -- acts as a signed-in person
select public.safety_end_match(:'c1', :'t1', 'Ending again with nothing booked.'); -- ends the match again
reset role; -- back to the database itself
select tests.eq((select count(*) from public.safety_rematch_flags), 0::bigint, 'no flag when nothing is booked'); -- none

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  safety urgent re-matching: all checks passed'
