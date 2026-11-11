-- More than one parent per student, and possible duplicate children.
-- Reuses access_rules.test.sql helpers: admin (...b0), tutor T1 (...11),
-- parents P1 (...01) and P2 (...02). tests.fails_with comes from earlier files.

-- ---------------------------------------------------------------------------
-- A parent always sees a child they added, before CLG confirms the link
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.add_my_child('Sall Yoodle', (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Hill PS', -- Parent P1 adds a child, Sall:
  -- (with English) and keeps her id as sall.
  '[{"subject": "English"}]') as sall \gset
select tests.eq((select count(*) from public.students where id = :'sall'), 1, 'parent sees a child they just added'); -- Checks: parent sees a child they just added.
select tests.eq((select count(*) from public.parent_student_links where student_id = :'sall' -- Checks the link is confirmed straight away (no admin step):
  and verified_at is not null and verified_by is null), 1, 'link confirmed straight away (no admin step)'); -- (confirmed, by nobody).
select tests.eq((select count(*) from public.student_subjects where student_id = :'sall'), 1, 'parent sees the subjects'); -- Checks: parent sees the subjects.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- P2 can't see it yet.
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = :'sall'), 0, 'another parent can''t see the child'); -- Checks: another parent can't see the child.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- CLG links a second parent
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_link_parent('00000000-0000-0000-0000-000000000002', :'sall', 'Guardian', true); -- The admin links parent P2 to Sall as a guardian who can manage.
select tests.eq((select count(*) from public.parent_student_links -- Checks the second parent is linked and already confirmed:
  where parent_id = '00000000-0000-0000-0000-000000000002' and student_id = :'sall' -- (parent P2 and Sall),
    and relationship = 'guardian' and verified_at is not null), 1, 'second parent linked and already confirmed'); -- (as guardian, confirmed).
select tests.eq((select count(*) from public.admin_student_parents() where student_id = :'sall'), 2, 'admin sees both parents'); -- Checks: admin sees both parents.
-- Running it again just updates the link.
select public.admin_link_parent('00000000-0000-0000-0000-000000000002', :'sall', 'parent', false); -- Links parent P2 again as a parent who can't manage.
select tests.eq((select count(*) from public.parent_student_links -- Checks linking again updates the relationship:
  where parent_id = '00000000-0000-0000-0000-000000000002' and student_id = :'sall' and relationship = 'parent' and not can_manage), 1, -- (now "parent", can't manage),
  'linking again updates the relationship'); -- (the label).
select tests.fails_with(format($$select public.admin_link_parent('00000000-0000-0000-0000-000000000002', %L, 'neighbour')$$, :'sall'), -- Checks an unknown relationship is refused:
  'Choose parent, guardian', 'unknown relationship'); -- (the message lists the allowed ones).
select tests.fails_with($$select public.admin_link_parent('00000000-0000-0000-0000-000000000002', gen_random_uuid())$$, -- Checks an unknown student is refused:
  'student could not be found', 'unknown student'); -- (the message says the student couldn't be found).
select tests.fails_with(format($$select public.admin_link_parent(gen_random_uuid(), %L)$$, :'sall'), -- Checks an unknown account is refused:
  'account could not be found', 'unknown account'); -- (the message says the account couldn't be found).
-- A tutor account can be linked as a parent too, and gets the parent role.
select public.admin_link_parent('00000000-0000-0000-0000-000000000011', :'sall', 'carer'); -- Links tutor T1 to Sall as a carer.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.account_roles -- Checks the tutor gets the parent role:
  where account_id = '00000000-0000-0000-0000-000000000011' and role = 'parent'), 1, 'tutor gets the parent role'); -- (one parent role).
select tests.eq((select count(*) from public.parent_profiles -- Checks the tutor gets a parent profile:
  where account_id = '00000000-0000-0000-0000-000000000011'), 1, 'tutor gets a parent profile'); -- (one profile).

-- The second parent now sees the child, but can't change details (not managing).
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = :'sall'), 1, 'second parent sees the child'); -- Checks: second parent sees the child.
update public.students set school = 'Changed PS' where id = :'sall'; -- Tries to change Sall's school.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.students where id = :'sall' and school = 'Hill PS'), 1, -- Checks a parent who can't manage can't change details:
  'a parent who can''t manage can''t change details'); -- (the label).

-- ---------------------------------------------------------------------------
-- Removing links
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_unlink_parent('00000000-0000-0000-0000-000000000011', :'sall'); -- Unlinks tutor T1.
select public.admin_unlink_parent('00000000-0000-0000-0000-000000000002', :'sall'); -- Unlinks parent P2.
select tests.eq((select count(*) from public.parent_student_links where student_id = :'sall'), 1, 'links removed'); -- Checks: links removed.
select tests.fails_with(format($$select public.admin_unlink_parent('00000000-0000-0000-0000-000000000001', %L)$$, :'sall'), -- Checks the last parent who can manage can't be removed:
  'only parent who can manage', 'can''t remove the last parent'); -- (the message says so).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Possible duplicates: P2 adds the same child again
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.add_my_child('  sall   yoodle ', (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Hill PS', -- Parent P1 adds Sall again (with untidy spacing):
  -- (with English and Science) and keeps the id as sall2.
  '[{"subject": "English"}, {"subject": "Science"}]') as sall2 \gset
select tests.eq((select count(*) from public.parent_student_links where student_id = :'sall2' and verified_at is null), 1, -- Checks a possible double-up waits for CLG:
  'a possible double-up waits for CLG'); -- (the link isn't confirmed yet).
select tests.fails('select * from public.admin_possible_duplicate_children()', 'parent lists duplicates'); -- Checks this is refused: parent lists duplicates.
select tests.fails(format($$select public.admin_merge_students(%L, %L)$$, :'sall2', :'sall'), 'parent merges records'); -- Checks this is refused: parent merges records.
reset role; -- Goes back to the all-powerful test user (access rules off).
-- Parental consent given for the double-up.
insert into public.consent_records (account_id, student_id, kind, document_version) -- Copies a consent record onto the second Sall:
select '00000000-0000-0000-0000-000000000002', :'sall2', kind, 'test-merge' -- (for parent P2, marked test-merge)
from public.consent_records where student_id is not null limit 1; -- (from any student's consent).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.admin_possible_duplicate_children() -- Checks the same name and birthday are flagged for CLG:
  where (student_id, other_student_id) in ((least(:'sall'::uuid, :'sall2'::uuid), greatest(:'sall'::uuid, :'sall2'::uuid)))), 1, -- (the pair of records),
  'same name and birthday flagged for CLG'); -- (the label).
select tests.fails_with(format($$select public.admin_merge_students(%L, %L)$$, :'sall', :'sall'), -- Checks a record can't be merged into itself:
  'two different', 'merge a record into itself'); -- (the message asks for two different records).
select public.admin_merge_students(:'sall', :'sall2'); -- Merges the second Sall into the first.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.students where id = :'sall2'), 0, 'double-up removed'); -- Checks: double-up removed.
select tests.eq((select count(*) from public.parent_student_links where student_id = :'sall' and verified_at is not null), 2, -- Checks both parents are now on the kept record, confirmed:
  'both parents now on the kept record, confirmed'); -- (the label).
select tests.eq((select count(*) from public.student_subjects where student_id = :'sall'), 2, 'subjects combined'); -- Checks: subjects combined.
select tests.eq((select count(*) from public.consent_records where student_id = :'sall' and document_version = 'test-merge'), 1, -- Checks the consent moved to the kept record:
  'consent moved to the kept record'); -- (the label).

-- A record with history can't be merged away.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.add_my_child('Sall Yoodle', (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Hill PS', -- Parent P1 adds Sall a third time:
  -- and keeps the id as sall3.
  '[{"subject": "English"}]') as sall3 \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
insert into public.family_notes (student_id, kind, body, written_by) -- Adds a family note for the third Sall:
values (:'sall3', 'feedback', 'Loves reading', '00000000-0000-0000-0000-000000000001'); -- (so the record has history).
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with(format($$select public.admin_merge_students(%L, %L)$$, :'sall', :'sall3'), -- Checks a record with history can't be merged:
  'already has history', 'record with history'); -- (the message says it already has history).
-- CLG decides they're different children: the pair stops showing.
select public.admin_dismiss_duplicate(:'sall3', :'sall'); -- CLG says they're different children.
select tests.eq((select count(*) from public.admin_possible_duplicate_children() -- Checks the dismissed pair stops showing:
  where :'sall3'::uuid in (student_id, other_student_id)), 0, 'dismissed pair stops showing'); -- (none for the third Sall).
select tests.eq((select count(*) from public.parent_student_links where student_id = :'sall3' and verified_at is not null), 1, -- Checks the held link is confirmed:
  'held link confirmed once CLG says they are different children'); -- (the label).
reset role; -- Goes back to the all-powerful test user (access rules off).
-- Points sall2 at the third Sall from here on.
\set sall2 :sall3

-- ---------------------------------------------------------------------------
-- Nobody else can do this
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0'); -- Signs in as test account ...b0.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.admin_link_parent('00000000-0000-0000-0000-000000000002', %L)$$, :'sall'), -- Checks an admin without two-step login is refused:
  'admin without two-step login'); -- (the label).
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.admin_link_parent('00000000-0000-0000-0000-000000000011', %L)$$, :'sall2'), 'tutor links themselves'); -- Checks this is refused: tutor links themselves.
select tests.fails('select * from public.admin_student_parents()', 'tutor lists parent links'); -- Checks this is refused: tutor lists parent links.
select tests.fails('select * from public.student_duplicate_dismissals', 'tutor reads dismissals'); -- Checks this is refused: tutor reads dismissals.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.admin_link_parent('00000000-0000-0000-0000-000000000001', %L)$$, :'sall2'), -- Checks a parent can't link themselves to another child:
  'parent links themselves to another child'); -- (the label).
select tests.fails(format($$select public.admin_unlink_parent('00000000-0000-0000-0000-000000000002', %L)$$, :'sall2'), -- Checks a parent can't remove another parent:
  'parent removes another parent'); -- (the label).
select tests.fails(format($$select public.admin_dismiss_duplicate(%L, %L)$$, :'sall', :'sall2'), 'parent dismisses a duplicate'); -- Checks this is refused: parent dismisses a duplicate.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Clean up so later test files see the original fixtures.
delete from public.students where id in (:'sall', :'sall3'); -- Removes the test children.
delete from public.consent_records where document_version = 'test-merge'; -- Removes the copied consent.
delete from public.account_roles where account_id = '00000000-0000-0000-0000-000000000011' and role = 'parent'; -- Removes tutor T1's parent role.
delete from public.parent_profiles where account_id = '00000000-0000-0000-0000-000000000011'; -- Removes tutor T1's parent profile.

-- Prints that every check in this file passed.
\echo '  link parents: all checks passed'
