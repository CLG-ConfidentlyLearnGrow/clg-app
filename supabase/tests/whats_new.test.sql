-- Summary: checks the "What's new" pop-up (Carla, 15 Nov 2026): only full
-- admins write and publish updates, drafts are hidden from everyone else,
-- each person only sees changes for their own dashboards, the pop-up only
-- shows updates they haven't closed (and none from before they got the
-- role), published updates can't be edited, and a later start day holds an
-- update back. Reuses access_rules.test.sql people: owner Olive (...a0),
-- operations admin Sam Staff (...b0), tutor T1 (...11), parent P1 (...01),
-- adult learner (...21, a student). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the "What's new" database change again (checks it can run twice).
\ir ../migrations/20261117600100_whats_new.sql

\set olive '00000000-0000-0000-0000-0000000000a0'
-- (Olive's account id: owner)
\set sam '00000000-0000-0000-0000-0000000000b0'
-- (Sam Staff's account id: operations admin)
\set t1 '00000000-0000-0000-0000-000000000011'
-- (tutor T1's account id)
\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)
\set adult '00000000-0000-0000-0000-000000000021'
-- (the adult learner's account id: a student)

select tests.claims(null); -- acts as the database itself while setting up
update public.account_roles set granted_at = now() - interval '30 days' where account_id in (:'olive', :'sam', :'t1', :'p1', :'adult'); -- everyone has had their roles for a month, so new updates count as "after they joined"

-- 1. Only full admins with two-step sign-in write updates.
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.fails($q$select public.whats_new_save_note(null, 'A tutor update')$q$, 'a tutor cannot write updates'); -- refused
reset role; -- back to the database itself
select tests.claims(:'sam', 'aal1'); -- Sam WITHOUT two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.fails($q$select public.whats_new_save_note(null, 'No two-step')$q$, 'an admin without two-step sign-in cannot write updates'); -- refused
reset role; -- back to the database itself
select tests.claims(:'sam', 'aal2'); -- Sam with two-step sign-in (operations)
set role authenticated; -- acts as a signed-in person
select public.whats_new_save_note(null, 'Booking is quicker') as n1 \gset
-- (Sam starts an update; keeps its id as n1)
select public.whats_new_save_item(:'n1', null, 'added', array['parent', 'student'], 'You can now book a session in two taps.') as i_family \gset
-- (a change for parents and students; keeps its id as i_family)
select public.whats_new_save_item(:'n1', null, 'updated', array['tutor'], 'Your weekly calendar now shows travel time.') as i_tutor \gset
-- (a change for tutors; keeps its id as i_tutor)
select public.whats_new_save_item(:'n1', null, 'removed', array['admin'], 'The old bookings report is gone. Use Reports instead.') as i_admin \gset
-- (a change for admins; keeps its id as i_admin)
select tests.fails(format($q$select public.whats_new_save_item(%L, null, 'moved', array['tutor'], 'Not a real kind.')$q$, :'n1'), 'the kind must be added, updated or removed'); -- refused
select tests.fails(format($q$select public.whats_new_save_item(%L, null, 'added', array[]::text[], 'No dashboard chosen.')$q$, :'n1'), 'at least one dashboard is needed'); -- refused
select tests.fails(format($q$select public.whats_new_save_item(%L, null, 'added', array['robot'], 'Not a real dashboard.')$q$, :'n1'), 'dashboards must be real'); -- refused
select tests.fails(format($q$select public.whats_new_save_item(%L, null, 'added', array['tutor'], repeat('x', 501))$q$, :'n1'), 'changes must be short'); -- refused
select tests.fails($q$insert into public.whats_new_notes (title) values ('Direct insert')$q$, 'nobody adds updates directly'); -- refused
select tests.fails(format($q$select public.whats_new_publish(%L, current_date + 400)$q$, :'n1'), 'a start day more than a year ahead is refused'); -- refused
select public.whats_new_save_note(null, 'Empty update') as n_empty \gset
-- (an update with no changes; keeps its id as n_empty)
select tests.fails(format($q$select public.whats_new_publish(%L)$q$, :'n_empty'), 'an update with no changes cannot be published'); -- refused
select public.whats_new_delete_note(:'n_empty'); -- a draft can be deleted
reset role; -- back to the database itself
select tests.eq((select count(*) from public.whats_new_notes where id = :'n_empty'), 0::bigint, 'the empty draft was deleted'); -- gone

-- 2. Drafts are hidden from everyone but full admins.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.whats_new_notes), 0::bigint, 'a parent cannot see a draft'); -- hidden
select tests.eq((select count(*) from public.whats_new_items), 0::bigint, 'a parent cannot see a draft''s changes'); -- hidden
select tests.eq((select count(*) from public.whats_new_for_me('parent')), 0::bigint, 'no pop-up for a draft'); -- nothing
reset role; -- back to the database itself

-- 3. Once published, each person only sees changes for their own dashboards.
select tests.claims(:'olive', 'aal2'); -- signs in as the owner
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.whats_new_items where note_id = :'n1'), 3::bigint, 'the owner sees every change in a draft'); -- all three
select public.whats_new_publish(:'n1'); -- publishes it now
select tests.fails(format($q$select public.whats_new_save_item(%L, null, 'added', array['tutor'], 'Sneaking in a change.')$q$, :'n1'), 'a published update cannot get new changes'); -- refused
select tests.fails(format($q$select public.whats_new_delete_item(%L)$q$, :'i_tutor'), 'a published update''s changes cannot be removed'); -- refused
select tests.fails(format($q$select public.whats_new_save_note(%L, 'Renamed')$q$, :'n1'), 'a published update cannot be renamed'); -- refused
select tests.fails(format($q$select public.whats_new_delete_note(%L)$q$, :'n1'), 'a published update cannot be deleted'); -- refused
reset role; -- back to the database itself
update public.whats_new_notes set show_from = now() - interval '1 hour' where id = :'n1'; -- moves its start back an hour (everything here happens in one instant otherwise)

select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.whats_new_for_me('parent')), 1::bigint, 'the parent''s pop-up has the family change'); -- one change
select tests.eq((select count(*) from public.whats_new_for_me('parent') where item_id = :'i_family'), 1::bigint, 'and it is the right one'); -- the family change
select tests.eq((select count(*) from public.whats_new_items), 1::bigint, 'a parent cannot read tutor or admin changes'); -- only theirs
select tests.eq((select count(*) from public.whats_new_notes), 1::bigint, 'a parent sees the update''s title'); -- visible
select tests.eq((select count(*) from public.whats_new_for_me('tutor')), 0::bigint, 'a parent gets nothing for a dashboard they do not have'); -- empty
reset role; -- back to the database itself

select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.whats_new_for_me('tutor') where item_id = :'i_tutor'), 1::bigint, 'the tutor''s pop-up has the tutor change'); -- theirs
select tests.eq((select count(*) from public.whats_new_items where id in (:'i_family', :'i_admin')), 0::bigint, 'a tutor cannot read family or admin changes'); -- hidden
reset role; -- back to the database itself

select tests.claims(:'adult'); -- signs in as the adult learner
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.whats_new_for_me('student') where item_id = :'i_family'), 1::bigint, 'a student sees changes tagged for students'); -- theirs
reset role; -- back to the database itself

-- 4. Closing the pop-up hides it, but the "What's new" page keeps it.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select public.whats_new_mark_seen('parent'); -- closes the pop-up on the parent dashboard
select tests.eq((select count(*) from public.whats_new_for_me('parent')), 0::bigint, 'after closing, no pop-up'); -- gone
select tests.eq((select count(*) from public.whats_new_for_me('parent', false)), 1::bigint, 'the update is still on the What is new page'); -- kept
select tests.fails($q$select public.whats_new_mark_seen('admin')$q$, 'nobody closes a dashboard they do not have'); -- refused
select tests.eq((select count(*) from public.whats_new_seen), 1::bigint, 'a person sees only their own closed times'); -- theirs only
reset role; -- back to the database itself
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.whats_new_seen), 0::bigint, 'a tutor cannot see the parent''s closed time'); -- hidden
select tests.eq((select count(*) from public.whats_new_for_me('tutor')), 1::bigint, 'the tutor still has their pop-up (closing is per person)'); -- still there
reset role; -- back to the database itself

-- 5. People who got a role after an update don't get it in the pop-up.
update public.account_roles set granted_at = now() where account_id = :'adult'; -- the learner got their role just now
select tests.claims(:'adult'); -- signs in as the adult learner
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.whats_new_for_me('student')), 0::bigint, 'no old news in the pop-up for someone new'); -- skipped
select tests.eq((select count(*) from public.whats_new_for_me('student', false)), 1::bigint, 'but it is on their What is new page'); -- kept
reset role; -- back to the database itself

-- 6. A later start day holds an update back until that day.
select tests.claims(:'olive', 'aal2'); -- signs in as the owner
set role authenticated; -- acts as a signed-in person
select public.whats_new_save_note(null, 'Welcome, trial families') as n2 \gset
-- (the owner writes a welcome; keeps its id as n2)
select public.whats_new_save_item(:'n2', null, 'added', array['parent'], 'Welcome to the CLG app!') as i_welcome \gset
-- (one change for parents; keeps its id as i_welcome)
select public.whats_new_publish(:'n2', current_date + 10); -- shows from 10 days' time
reset role; -- back to the database itself
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.whats_new_items where id = :'i_welcome'), 0::bigint, 'an update is not visible before its day'); -- hidden
reset role; -- back to the database itself
update public.whats_new_seen set seen_up_to = now() - interval '30 minutes' where account_id = :'p1'; -- P1 closed the last pop-up half an hour ago
update public.whats_new_notes set show_from = now() - interval '1 minute' where id = :'n2'; -- the day has come
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.whats_new_for_me('parent')), 1::bigint, 'on the day, the new update pops up'); -- just the welcome
select tests.eq((select count(*) from public.whats_new_for_me('parent') where item_id = :'i_welcome'), 1::bigint, 'and it is the welcome'); -- the welcome
reset role; -- back to the database itself

-- 7. Taking an update back hides it, and it can be fixed and published again.
select tests.claims(:'olive', 'aal2'); -- signs in as the owner
set role authenticated; -- acts as a signed-in person
select public.whats_new_unpublish(:'n2'); -- takes it back to a draft
select public.whats_new_save_item(:'n2', :'i_welcome', 'added', array['parent', 'student'], 'Welcome to the CLG app! Families and students start here.'); -- fixes the change
reset role; -- back to the database itself
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.whats_new_for_me('parent', false) where note_id = :'n2'), 0::bigint, 'a taken-back update disappears'); -- hidden
reset role; -- back to the database itself

-- 8. The activity log records publishing, with ids only.
select tests.eq((select count(*) from public.audit_log where action = 'whats_new_publish'), 2::bigint, 'each publish is logged'); -- two publishes
select tests.eq((select count(*) from public.audit_log where details::text like '%two taps%'), 0::bigint, 'no update words in the activity log'); -- nothing copied

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  whats_new: all checks passed'
