-- Summary: checks the quiet steps on a concern about a tutor (Carla, 15 Nov
-- 2026): only the person handling the concern can take them, only for a
-- tutor it names; "stop new students" blocks new pairings but keeps current
-- students; "end match" ends the tutor's match with the concern's child and
-- stops them being paired again; steps can be lifted; the tutor can't see
-- any of it. Reuses access_rules.test.sql people: owner Olive (...a0,
-- officer), operations admin Sam Staff (...b0, deputy), tutor T1 (...11,
-- teaches Cara), parent P1 (...01, Cara's parent). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this database change again (checks it can run twice).
\ir ../migrations/20261117400100_safety_quiet_steps.sql

select tests.claims(null); -- acts as the database itself while setting up
select id as cara from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's student id as cara)
select id as vic from public.students where full_name = 'Vic Two' \gset
-- (keeps Vic's student id as vic, a child T1 doesn't teach)
update public.child_safety_contacts set officer_id = '00000000-0000-0000-0000-0000000000a0', deputy_id = '00000000-0000-0000-0000-0000000000b0' where id; -- Olive is officer, Sam Staff is deputy
\set olive '00000000-0000-0000-0000-0000000000a0'
-- (Olive's account id, the officer)
\set sam '00000000-0000-0000-0000-0000000000b0'
-- (Sam Staff's account id, the deputy)
\set t1 '00000000-0000-0000-0000-000000000011'
-- (tutor T1's account id)
update public.tutor_assignments set starts_on = current_date - 30 where tutor_id = :'t1' and student_id = :'cara'; -- makes T1's match with Cara clearly current (started a month ago)
select tests.eq(private.blocked_pair(:'t1', :'cara')::int, 0, 'set-up: T1 and Cara are not blocked'); -- starting point
select tests.eq(private.blocked_pair(:'t1', :'vic')::int, 0, 'set-up: T1 and Vic are not blocked'); -- starting point

-- P1 raises a concern about T1, about Cara. It goes to the officer.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person, so access rules apply
select public.raise_safety_concern(:'cara', null, null, 'officer', false, false, 'no', null, null, 'The tutor asked Cara to keep a secret from us.', array[:'t1']::uuid[]) as c1 \gset
-- (keeps the concern's id as c1)
reset role; -- back to the database itself

-- 1. Only the person handling the concern can take steps.
select tests.claims(:'sam', 'aal2'); -- signs in as Sam (an admin, but not handling this concern)
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.safety_stop_new_students(%L, %L, 'Trying without handling it')$q$, :'c1', :'t1'), 'someone not handling the concern cannot take a step'); -- refused
select tests.eq((select count(*) from public.safety_concern_quiet_steps(:'c1')), 0::bigint, 'and gets no options'); -- empty
reset role; -- back to the database itself
select tests.claims(:'olive', 'aal2'); -- signs in as the officer
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concern_quiet_steps(:'c1') where tutor_id = :'t1' and matched_now), 1::bigint, 'the officer sees T1, matched with Cara now'); -- the options
select tests.fails(format($q$select public.safety_stop_new_students(%L, %L, 'Not named in this concern')$q$, :'c1', :'sam'), 'steps are only for a tutor the concern names'); -- refused
select tests.fails(format($q$select public.safety_stop_new_students(%L, %L, '')$q$, :'c1', :'t1'), 'a step needs a reason'); -- refused

-- 2. Stop new students: current students stay, new ones are blocked.
select public.safety_stop_new_students(:'c1', :'t1', 'While we look into the concern.'); -- takes the step
select tests.fails(format($q$select public.safety_stop_new_students(%L, %L, 'Again')$q$, :'c1', :'t1'), 'cannot stop new students twice'); -- refused
reset role; -- back to the database itself
select tests.eq(private.blocked_pair(:'t1', :'vic')::int, 1, 'T1 cannot be paired with a new student'); -- blocked
select tests.eq(private.blocked_pair(:'t1', :'cara')::int, 0, 'T1 keeps their current student'); -- still allowed

-- 3. The tutor sees nothing.
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_holds), 0::bigint, 'the tutor cannot see the steps'); -- hidden
select tests.eq((select count(*) from public.safety_concern_quiet_steps(:'c1')), 0::bigint, 'the tutor gets no options'); -- empty
select tests.eq((select count(*) from public.students where id = :'cara'), 1::bigint, 'the tutor can still open Cara''s record (match not ended yet)'); -- still current
reset role; -- back to the database itself

-- 4. End the match with Cara.
select tests.claims(:'olive', 'aal2'); -- signs in as the officer
set role authenticated; -- acts as a signed-in person
select public.safety_end_match(:'c1', :'t1', 'Keeping Cara safe while we look into it.') as bookings_left \gset
-- (ends the match; keeps the number of bookings left as bookings_left)
select tests.fails(format($q$select public.safety_end_match(%L, %L, 'Again')$q$, :'c1', :'t1'), 'cannot end the same match twice'); -- refused
select tests.eq((select count(*) from public.safety_concern_notes where concern_id = :'c1' and note like 'Ended %'), 1::bigint, 'ending the match is recorded on the concern'); -- note kept
reset role; -- back to the database itself
select tests.eq((select count(*) from public.tutor_assignments where tutor_id = :'t1' and student_id = :'cara' and private.assignment_is_current(starts_on, ends_on)), 0::bigint, 'T1''s match with Cara has ended'); -- ended
select tests.eq(private.blocked_pair(:'t1', :'cara')::int, 1, 'T1 and Cara cannot be paired again'); -- blocked
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.students where id = :'cara'), 0::bigint, 'the tutor can no longer open Cara''s record'); -- access gone
reset role; -- back to the database itself

-- 5. Lifting steps.
select tests.claims(:'olive', 'aal2'); -- signs in as the officer
set role authenticated; -- acts as a signed-in person
select no_new_students_id as hold_new from public.safety_concern_quiet_steps(:'c1') where tutor_id = :'t1' \gset
-- (keeps the "stop new students" step's id as hold_new)
select tests.fails(format($q$select public.safety_lift_hold(%L, '')$q$, :'hold_new'), 'lifting needs a reason'); -- refused
select public.safety_lift_hold(:'hold_new', 'Looked into it; no concern found.'); -- lifts it
reset role; -- back to the database itself
select tests.eq(private.blocked_pair(:'t1', :'vic')::int, 0, 'after lifting, T1 can be paired with new students again'); -- allowed
select tests.eq(private.blocked_pair(:'t1', :'cara')::int, 1, 'the ended match stays blocked until it is lifted too'); -- still blocked

-- 6. The activity log holds ids only.
select tests.eq((select count(*) from public.audit_log where details::text like '%secret%' or details::text like '%look into%'), 0::bigint, 'no reasons or details in the activity log'); -- nothing leaked

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  safety quiet steps: all checks passed'
