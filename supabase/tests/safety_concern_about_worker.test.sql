-- Summary: checks the confidential flag about a CLG worker (Carla, 15 Nov
-- 2026): who each person can name, that the person named never sees the
-- concern, that a concern about the officer goes to the deputy (and the other
-- way round), that one naming both goes to both, that a concern can't be
-- passed to the person it names but can be shared with them, the reader
-- alert emails (no details), and the to-do number for readers. Reuses
-- access_rules.test.sql people: owner Olive (...a0, officer), operations
-- admin Sam Staff (...b0, deputy), tutor T1 (...11, teaches Cara), tutor T2
-- (...12), parent P1 (...01, Cara's parent). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this database change again (checks it can run twice).
\ir ../migrations/20261117100100_safety_concern_about_worker.sql

select tests.claims(null); -- acts as the database itself while setting up
select id as cara from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's student id as cara)
update public.child_safety_contacts set officer_id = '00000000-0000-0000-0000-0000000000a0', deputy_id = '00000000-0000-0000-0000-0000000000b0' where id; -- Olive is officer, Sam Staff is deputy
\set olive '00000000-0000-0000-0000-0000000000a0'
-- (Olive's account id, the officer)
\set sam '00000000-0000-0000-0000-0000000000b0'
-- (Sam Staff's account id, the deputy)
\set t1 '00000000-0000-0000-0000-000000000011'
-- (tutor T1's account id)
\set t2 '00000000-0000-0000-0000-000000000012'
-- (tutor T2's account id)

-- 1. Who each person can name.
select tests.eq((select count(*) from public.tutor_assignments where tutor_id = :'t2' and student_id = :'cara'), 0::bigint, 'set-up: T2 has never tutored Cara'); -- checks the starting point
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq((select count(*) from public.safety_concern_people_choices() where account_id = :'t1'), 1::bigint, 'a parent can name their child''s tutor'); -- T1 listed
select tests.eq((select count(*) from public.safety_concern_people_choices() where account_id in (:'olive', :'sam')), 2::bigint, 'a parent can name CLG''s admins'); -- Olive and Sam listed
select tests.eq((select count(*) from public.safety_concern_people_choices() where account_id = :'t2'), 0::bigint, 'a parent cannot see other tutors in the list'); -- T2 hidden
reset role; -- back to the database itself
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concern_people_choices() where account_id = :'t2'), 1::bigint, 'staff can name any other staff member'); -- T2 listed
select tests.eq((select count(*) from public.safety_concern_people_choices() where account_id = :'t1'), 0::bigint, 'nobody can name themselves'); -- T1 not listed
select tests.fails(format($q$select public.raise_safety_concern(%L, null, null, 'officer', false, false, 'no', null, null, 'Naming myself should be refused.', array[%L]::uuid[])$q$, :'cara', :'t1'), 'naming yourself is refused'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.raise_safety_concern(%L, null, null, 'officer', false, false, 'no', null, null, 'Naming a tutor I have never met.', array[%L]::uuid[])$q$, :'cara', :'t2'), 'a parent cannot name someone not on their list'); -- refused

-- 2. A concern about a tutor goes to the officer and is hidden from the tutor.
select public.raise_safety_concern(:'cara', null, null, 'officer', false, false, 'no', null, null, 'The tutor messaged Cara privately late at night.', array[:'t1']::uuid[]) as c_tutor \gset
-- (P1 raises a concern naming tutor T1; keeps its id as c_tutor)
select tests.eq((select count(*) from public.safety_concern_people where concern_id = :'c_tutor'), 1::bigint, 'the person who raised it can see who they named'); -- visible to the raiser
reset role; -- back to the database itself
select tests.eq((select count(*) from public.safety_concerns where id = :'c_tutor' and recipient_id = :'olive'), 1::bigint, 'it went to the officer'); -- routed to Olive
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1 (the person named)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concerns where id = :'c_tutor'), 0::bigint, 'the tutor named cannot see the concern'); -- hidden
select tests.eq((select count(*) from public.safety_concern_people where account_id = :'t1'), 0::bigint, 'the tutor cannot see that they were named'); -- hidden
select tests.eq((select n from public.to_do_counts() where area = 'safety' and section = 'concerns'), 0, 'the tutor gets no to-do number'); -- nothing shows
reset role; -- back to the database itself
select tests.claims(:'olive', 'aal2'); -- signs in as the officer
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concern_people where concern_id = :'c_tutor' and full_name = 'Tess Tutor'), 1::bigint, 'the officer sees who it is about'); -- visible to the officer
reset role; -- back to the database itself

-- 3. A concern about the officer goes to the deputy, even if the officer was picked.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select public.raise_safety_concern(:'cara', null, null, 'officer', false, false, 'no', null, null, 'Something about the Child Safety Officer worried me.', array[:'olive']::uuid[]) as c_officer \gset
-- (P1 picks the officer, but names her; keeps its id as c_officer)
reset role; -- back to the database itself
select tests.eq((select count(*) from public.safety_concerns where id = :'c_officer' and recipient_id = :'sam' and sent_to = 'deputy'), 1::bigint, 'a concern about the officer goes to the deputy'); -- routed to Sam
select tests.claims(:'olive', 'aal2'); -- signs in as the officer (also the owner)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concerns where id = :'c_officer'), 0::bigint, 'the officer, even as owner, cannot see a concern about herself'); -- hidden
select tests.fails(format($q$select public.safety_concern_add_note(%L, 'Trying to add a note')$q$, :'c_officer'), 'the officer cannot add notes to it'); -- refused
reset role; -- back to the database itself

-- 4. A concern about the deputy goes to the officer, even if the deputy was picked.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select public.raise_safety_concern(:'cara', null, null, 'deputy', false, false, 'no', null, null, 'Something about the deputy worried me.', array[:'sam']::uuid[]) as c_deputy \gset
-- (P1 picks the deputy, but names him; keeps its id as c_deputy)
reset role; -- back to the database itself
select tests.eq((select count(*) from public.safety_concerns where id = :'c_deputy' and recipient_id = :'olive' and sent_to = 'officer'), 1::bigint, 'a concern about the deputy goes to the officer'); -- routed to Olive
select tests.claims(:'sam', 'aal2'); -- signs in as the deputy
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concerns where id = :'c_deputy'), 0::bigint, 'the deputy cannot see a concern about himself'); -- hidden
reset role; -- back to the database itself

-- 5. A concern naming both goes to both.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select public.raise_safety_concern(:'cara', null, null, 'officer', false, false, 'no', null, null, 'Something about both child safety contacts.', array[:'olive', :'sam']::uuid[]) as c_both \gset
-- (P1 names both; keeps its id as c_both)
reset role; -- back to the database itself
select tests.eq((select count(*) from public.safety_concern_readers where concern_id = :'c_both' and account_id = :'sam' and reason = 'names_both'), 1::bigint, 'the deputy is added as a reader'); -- reader row
select tests.claims(:'sam', 'aal2'); -- signs in as the deputy
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concerns where id = :'c_both'), 1::bigint, 'the deputy can read it'); -- visible
select public.safety_concern_add_note(:'c_both', 'Read by the deputy.'); -- a reader can add a note
select tests.fails(format($q$select public.safety_concern_pass_on(%L, 'Reader trying to pass on')$q$, :'c_both'), 'a reader cannot pass it on'); -- refused
reset role; -- back to the database itself
select tests.claims(:'olive', 'aal2'); -- signs in as the officer
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concerns where id = :'c_both'), 1::bigint, 'the officer can read it'); -- visible
select tests.eq((select count(*) from public.safety_concern_notes where concern_id = :'c_both'), 1::bigint, 'the officer sees the deputy''s note'); -- shared notes
reset role; -- back to the database itself

-- 6. Passing on and sharing a concern about the other contact.
select tests.claims(:'sam', 'aal2'); -- signs in as the deputy
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.safety_concern_pass_on(%L, 'Passing it to the officer')$q$, :'c_officer'), 'a concern about the officer cannot be passed to her'); -- refused
select tests.fails(format($q$select public.safety_concern_share(%L, '')$q$, :'c_officer'), 'sharing needs a reason'); -- refused: no reason
select public.safety_concern_share(:'c_officer', 'Carla needs to know so we can sort out a misunderstanding.'); -- the deputy chooses to share it
select tests.fails(format($q$select public.safety_concern_share(%L, 'Again')$q$, :'c_officer'), 'cannot share with someone who can already read it'); -- refused: already shared
select tests.eq((select n from public.to_do_counts() where area = 'safety' and section = 'concerns'), (select count(*)::int from public.safety_concerns where status = 'new'), 'the deputy''s number counts every new concern they handle'); -- to-do number includes the both-named one
reset role; -- back to the database itself
select tests.claims(:'olive', 'aal2'); -- signs in as the officer
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concerns where id = :'c_officer'), 1::bigint, 'once shared, the officer can read it'); -- visible now
select tests.eq((select count(*) from public.safety_concern_notes where concern_id = :'c_officer' and note like 'Shared with Olive%'), 1::bigint, 'the sharing is recorded as a note'); -- note kept
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concern_notes), 0::bigint, 'the person who raised it still cannot read notes'); -- hidden
select tests.eq((select count(*) from public.safety_concern_readers), 0::bigint, 'the person who raised it cannot see who else reads it'); -- hidden
reset role; -- back to the database itself

-- 7. Lauren's emergency owner access (or any owner) doesn't open concerns. An
-- owner who isn't a contact sees nothing.
update public.child_safety_contacts set officer_id = :'sam', deputy_id = null where id; -- for a moment, Sam is officer and there's no deputy
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.raise_safety_concern(%L, null, null, 'officer', false, false, 'no', null, null, 'About the officer with no deputy named.', array[%L]::uuid[])$q$, :'cara', :'sam'), 'a concern about the officer is refused when there is no deputy (the person is told to phone the line)'); -- refused with a plain message
reset role; -- back to the database itself
update public.child_safety_contacts set officer_id = :'olive', deputy_id = :'sam' where id; -- puts the contacts back

-- 8. Reader alert emails: one per reader, no names or details.
select tests.claims(null); -- acts as the database itself
select tests.eq(private.safety_reader_emails_waiting()::int, 1, 'reader alert emails are waiting'); -- waiting
create temp table reader_claimed as select * from public.safety_reader_emails_claim(50); -- takes the waiting emails
select tests.eq((select count(*) from reader_claimed), 2::bigint, 'one email per reader (named both, and shared)'); -- two readers
select tests.eq((select count(*) from reader_claimed where body like '%Cara%' or body like '%Owner%' or body like '%worried%'), 0::bigint, 'reader emails hold no names or details'); -- confidential
select tests.eq(private.safety_reader_emails_waiting()::int, 0, 'nothing waiting once taken'); -- all taken
select public.safety_reader_emails_release(array(select id from reader_claimed)); -- puts them back (as if sending failed)
select tests.eq(private.emails_waiting()::int, 1, 'the shared email check sees them'); -- the sender would wake

-- 9. The activity log never holds names or details.
select tests.eq((select count(*) from public.audit_log where details::text like '%Tess%' or details::text like '%worried%' or details::text like '%misunderstanding%'), 0::bigint, 'no names or details in the activity log'); -- nothing leaked

-- 10. Nobody writes these tables directly.
select tests.claims(:'olive', 'aal2'); -- signs in as the officer
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$insert into public.safety_concern_readers (concern_id, account_id, reason) values (%L, %L, 'shared')$q$, :'c_tutor', :'t1'), 'nobody adds readers directly'); -- refused
select tests.fails(format($q$delete from public.safety_concern_people where concern_id = %L$q$, :'c_tutor'), 'nobody removes who a concern names'); -- refused
reset role; -- back to the database itself

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  safety concern about a worker: all checks passed'
