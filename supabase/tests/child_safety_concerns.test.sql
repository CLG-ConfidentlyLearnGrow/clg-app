-- Summary: checks the child safety concern flag (Carla, 12 Nov 2026):
-- who receives concerns and who may change that, who can raise a concern
-- about which child, that only the person it was sent to can read it (with
-- two-step sign-in), follow-up notes, passing a concern on, the to-do
-- number, the alert email (no details in it), and that records survive a
-- student or account being deleted. Reuses access_rules.test.sql people:
-- owner Olive (...a0), operations admin Sam Staff (...b0), tutor T1 (...11,
-- teaches Cara), tutor T2 (...12), parent P1 (...01, Cara's parent) and
-- parent P2 (...02, Vic's parent). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the concern flag database change again (checks it can run twice).
\ir ../migrations/20261113700100_child_safety_concerns.sql

select tests.claims(null); -- acts as the database itself while setting up
select id as cara from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's student id as cara)
select id as vic from public.students where full_name = 'Vic Two' \gset
-- (keeps Vic's student id as vic)
update public.child_safety_contacts set officer_id = '00000000-0000-0000-0000-0000000000a0', deputy_id = null where id; -- the owner starts as officer (as the file does on the live site)

-- 1. Who receives concerns, and who may change that.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.fails($q$select public.set_child_safety_contacts('00000000-0000-0000-0000-000000000011', null)$q$, 'a tutor can''t name the officer'); -- refused for a tutor
select tests.fails($q$select * from public.child_safety_contacts$q$, 'nobody reads the settings row directly'); -- refused: only through the list
select tests.eq((select count(*) from public.child_safety_contact_choices()), 0::bigint, 'a tutor gets no list of staff to choose from'); -- empty for non-owners
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal1'); -- signs in as the owner WITHOUT two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.fails($q$select public.set_child_safety_contacts('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000b0')$q$, 'the owner needs two-step sign-in to change it'); -- refused without two-step
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner with two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.fails($q$select public.set_child_safety_contacts('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a0')$q$, 'officer and deputy must differ'); -- refused: the same person twice
select tests.fails($q$select public.set_child_safety_contacts('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-000000000001')$q$, 'a parent can''t be the deputy'); -- refused: not staff
select tests.fails($q$select public.set_child_safety_contacts(null, '00000000-0000-0000-0000-0000000000b0')$q$, 'an officer is required'); -- refused: no officer
select tests.eq(((select count(*) from public.child_safety_contact_choices()) >= 3)::int, 1, 'the owner sees the staff to choose from'); -- owner, operations admin and tutors
select public.set_child_safety_contacts('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000b0'); -- names Olive officer and Sam Staff deputy
reset role; -- back to the database itself
select tests.eq((select count(*) from public.audit_log where action = 'set_child_safety_contacts'), 1::bigint, 'the change is in the activity log'); -- logged

select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.child_safety_contacts_list()), 2::bigint, 'a parent can see who receives concerns'); -- officer and deputy
select tests.eq((select count(*) from public.child_safety_contacts_list() where role = 'deputy' and full_name = 'Sam Staff'), 1::bigint, 'the deputy is named'); -- by name
reset role; -- back to the database itself
select tests.claims(null); -- signs out
set role anon; -- acts as someone not signed in
select tests.fails($q$select * from public.child_safety_contacts_list()$q$, 'signed-out visitors can''t see the list'); -- refused for anon
reset role; -- back to the database itself

-- 2. Raising concerns.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select public.raise_safety_concern(:'cara', null, null, 'officer', false, false, 'no', null, current_date, 'Cara said something worrying about home.') as c_parent \gset
-- (P1 raises a concern about their own child Cara, sent to the officer; keeps its id as c_parent)
select tests.fails(format($q$select public.raise_safety_concern(%L, null, null, 'officer', false, false, 'no', null, null, 'A concern about another family''s child.')$q$, :'vic'), 'a parent can''t pick another family''s child'); -- refused: Vic isn't theirs
select tests.fails($q$select public.raise_safety_concern(null, 'A neighbour''s child', null, 'officer', false, false, 'no', null, null, 'Something I saw at the park.')$q$, 'a child not listed needs a state'); -- refused: no state
select tests.fails($q$select public.raise_safety_concern(null, '', 'SA', 'officer', false, false, 'no', null, null, 'Something I saw at the park.')$q$, 'a child not listed needs a name'); -- refused: no name
select tests.fails($q$select public.raise_safety_concern(null, 'A child', 'SA', 'officer', false, false, 'maybe', null, null, 'Something I saw at the park.')$q$, 'the reporting-line answer must be one of the choices'); -- refused: bad answer
select tests.fails($q$select public.raise_safety_concern(null, 'A child', 'SA', 'officer', false, false, 'no', null, null, 'short')$q$, 'what happened needs a sentence'); -- refused: too short
select public.raise_safety_concern(null, 'A child at the park', 'SA', 'officer', true, true, 'yes', 'CARL-123', null, 'A child was left alone and hurt; I called 000 and CARL.') as c_other \gset
-- (P1 raises a concern about a child who isn't a CLG student; keeps its id as c_other)
select tests.fails($q$insert into public.safety_concerns (raised_by_name, child_name, child_state, sent_to, immediate_danger, reported_to_line, what_happened) values ('x', 'y', 'SA', 'officer', false, 'no', 'Direct insert attempt')$q$, 'nobody adds concerns directly'); -- refused: only through the function
select tests.fails(format($q$update public.safety_concerns set status = 'closed' where id = %L$q$, :'c_parent'), 'the person who raised it can''t change it'); -- refused: no direct changes
reset role; -- back to the database itself
select tests.eq((select count(*) from public.safety_concerns where id = :'c_parent' and child_name = 'Cara One' and child_state = 'SA' -- the parent's concern
  and recipient_id = '00000000-0000-0000-0000-0000000000a0' and raised_by_roles = 'parent'), 1::bigint, 'name and state come from the student record, sent to the officer'); -- filled in correctly

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select public.raise_safety_concern(:'cara', null, null, 'deputy', false, false, 'not_sure', null, null, 'A concern about the Child Safety Officer, so sent to the deputy.') as c_tutor \gset
-- (T1 raises a concern about Cara and sends it to the deputy; keeps its id as c_tutor)
select tests.fails(format($q$select public.raise_safety_concern(%L, null, null, 'officer', false, false, 'no', null, null, 'Not my student at all, so refused.')$q$, :'vic'), 'a tutor can''t pick a student they don''t teach'); -- refused: Vic isn't T1's
reset role; -- back to the database itself

-- 3. Who can read what.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the officer (the owner) with two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concerns), 2::bigint, 'the officer sees the two concerns sent to them'); -- the parent's two
select tests.eq((select count(*) from public.safety_concerns where id = :'c_tutor'), 0::bigint, 'the officer (even as owner) can''t see a concern sent to the deputy'); -- hidden
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal1'); -- the officer WITHOUT two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concerns), 0::bigint, 'without two-step sign-in the officer sees nothing'); -- hidden
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- signs in as the deputy
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concerns), 1::bigint, 'the deputy sees only the one sent to them'); -- the tutor's
select tests.eq((select n from public.to_do_counts() where area = 'safety' and section = 'concerns'), 1, 'the deputy has one new concern to read'); -- the to-do number
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- signs in as tutor T2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concerns), 0::bigint, 'another tutor sees no concerns'); -- hidden
select tests.eq((select n from public.to_do_counts() where area = 'safety' and section = 'concerns'), 0, 'another tutor has no number'); -- zero
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concerns), 2::bigint, 'a parent sees the concerns they raised'); -- their own two
select tests.eq((select count(*) from public.safety_concerns where id = :'c_tutor'), 0::bigint, 'a parent can''t see the tutor''s concern about their child'); -- hidden
reset role; -- back to the database itself

-- 4. Dealing with a concern.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.safety_concern_set_status(%L, 'closed')$q$, :'c_parent'), 'the person who raised it can''t close it'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- signs in as the deputy
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.safety_concern_add_note(%L, 'Trying to add a note')$q$, :'c_parent'), 'the deputy can''t add notes to the officer''s concern'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the officer
set role authenticated; -- acts as a signed-in person
select public.safety_concern_add_note(:'c_parent', 'Phoned CARL 13 14 78, reference 456.'); -- adds a follow-up note
select tests.eq((select count(*) from public.safety_concerns where id = :'c_parent' and status = 'in_progress'), 1::bigint, 'a note moves a new concern to being dealt with'); -- moved on
select tests.eq((select count(*) from public.safety_concern_notes where concern_id = :'c_parent'), 1::bigint, 'the officer sees the note'); -- visible
select tests.fails(format($q$update public.safety_concern_notes set note = 'changed' where concern_id = %L$q$, :'c_parent'), 'notes can''t be edited'); -- refused
select tests.fails(format($q$delete from public.safety_concern_notes where concern_id = %L$q$, :'c_parent'), 'notes can''t be deleted'); -- refused
select public.safety_concern_set_status(:'c_other', 'closed'); -- closes the other concern
select tests.eq((select count(*) from public.safety_concerns where id = :'c_other' and status = 'closed' and closed_at is not null), 1::bigint, 'closing records when'); -- closed with a time
select tests.fails(format($q$select public.safety_concern_pass_on(%L, '')$q$, :'c_parent'), 'passing on needs a reason'); -- refused: no reason
select public.safety_concern_pass_on(:'c_parent', 'It turns out to involve me.'); -- passes the parent's concern to the deputy
select tests.eq((select count(*) from public.safety_concerns where id = :'c_parent'), 0::bigint, 'after passing it on, the officer can''t see it'); -- hidden now
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concern_notes), 0::bigint, 'the person who raised it can''t read the notes'); -- hidden
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- signs in as the deputy
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_concerns where id = :'c_parent' and status = 'new' and sent_to = 'deputy'), 1::bigint, 'the deputy now has it, as new'); -- moved to them
select tests.eq((select count(*) from public.safety_concern_notes where concern_id = :'c_parent'), 2::bigint, 'the deputy sees its notes, including the hand-over'); -- both notes
reset role; -- back to the database itself

-- 5. The activity log has ids only, never the details.
select tests.eq((select count(*) from public.audit_log where details::text like '%worrying%' or details::text like '%CARL%'), 0::bigint, 'no concern details in the activity log'); -- nothing leaked

-- 6. Alert emails: one per concern, no names or details.
select tests.claims(null); -- acts as the database itself
select tests.eq(private.safety_concern_emails_waiting()::int, 1, 'alert emails are waiting'); -- waiting
create temp table claimed as select * from public.safety_concern_emails_claim(50); -- takes the waiting emails
select tests.eq((select count(*) from claimed), 3::bigint, 'one email per concern'); -- three concerns
select tests.eq((select count(*) from claimed where body like '%Cara%' or body like '%worrying%' or subject like '%Cara%'), 0::bigint, 'emails hold no names or details'); -- confidential
select tests.eq((select count(*) from claimed where subject like 'Urgent:%'), 1::bigint, 'the immediate-danger concern is marked urgent'); -- urgent subject
select tests.eq(private.safety_concern_emails_waiting()::int, 0, 'nothing waiting once taken'); -- all taken
select public.safety_concern_emails_release(array(select id from claimed)); -- puts them back (as if sending failed)
select tests.eq(private.safety_concern_emails_waiting()::int, 1, 'put back to try again'); -- waiting again
select tests.eq(private.emails_waiting()::int, 1, 'the shared email check sees them'); -- the sender would wake

-- 7. Records survive deletion.
delete from public.students where id = :'cara'; -- Cara's record is deleted (for example, a family asks)
select tests.eq((select count(*) from public.safety_concerns where child_name = 'Cara One' and student_id is null), 2::bigint, 'concerns keep the child''s name after the student is deleted'); -- kept
update public.child_safety_contacts set deputy_id = null where id; -- what deleting the deputy's account does to the settings row (the real delete is blocked here by a security alert check)
update public.safety_concerns set recipient_id = null where recipient_id = '00000000-0000-0000-0000-0000000000b0'; -- and to their concerns (the database clears the link)
select tests.eq((select count(*) from public.safety_concerns where recipient_id = '00000000-0000-0000-0000-0000000000a0' and sent_to = 'officer' and status = 'new'), 2::bigint, 'the deputy''s concerns move to the officer'); -- moved, not lost

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  child safety concerns: all checks passed'
