-- More than one parent per student, and possible duplicate children.
-- Reuses access_rules.test.sql helpers: admin (...b0), tutor T1 (...11),
-- parents P1 (...01) and P2 (...02). tests.fails_with comes from earlier files.

-- ---------------------------------------------------------------------------
-- A parent always sees a child they added, before CLG confirms the link
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select public.add_my_child('Sall Yoodle', (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Hill PS',
  '[{"subject": "English"}]') as sall \gset
select tests.eq((select count(*) from public.students where id = :'sall'), 1, 'parent sees a child they just added');
select tests.eq((select count(*) from public.parent_student_links where student_id = :'sall'
  and verified_at is not null and verified_by is null), 1, 'link confirmed straight away (no admin step)');
select tests.eq((select count(*) from public.student_subjects where student_id = :'sall'), 1, 'parent sees the subjects');
reset role;

-- P2 can't see it yet.
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.students where id = :'sall'), 0, 'another parent can''t see the child');
reset role;

-- ---------------------------------------------------------------------------
-- CLG links a second parent
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.admin_link_parent('00000000-0000-0000-0000-000000000002', :'sall', 'Guardian', true);
select tests.eq((select count(*) from public.parent_student_links
  where parent_id = '00000000-0000-0000-0000-000000000002' and student_id = :'sall'
    and relationship = 'guardian' and verified_at is not null), 1, 'second parent linked and already confirmed');
select tests.eq((select count(*) from public.admin_student_parents() where student_id = :'sall'), 2, 'admin sees both parents');
-- Running it again just updates the link.
select public.admin_link_parent('00000000-0000-0000-0000-000000000002', :'sall', 'parent', false);
select tests.eq((select count(*) from public.parent_student_links
  where parent_id = '00000000-0000-0000-0000-000000000002' and student_id = :'sall' and relationship = 'parent' and not can_manage), 1,
  'linking again updates the relationship');
select tests.fails_with(format($$select public.admin_link_parent('00000000-0000-0000-0000-000000000002', %L, 'neighbour')$$, :'sall'),
  'Choose parent, guardian', 'unknown relationship');
select tests.fails_with($$select public.admin_link_parent('00000000-0000-0000-0000-000000000002', gen_random_uuid())$$,
  'student could not be found', 'unknown student');
select tests.fails_with(format($$select public.admin_link_parent(gen_random_uuid(), %L)$$, :'sall'),
  'account could not be found', 'unknown account');
-- A tutor account can be linked as a parent too, and gets the parent role.
select public.admin_link_parent('00000000-0000-0000-0000-000000000011', :'sall', 'carer');
reset role;
select tests.eq((select count(*) from public.account_roles
  where account_id = '00000000-0000-0000-0000-000000000011' and role = 'parent'), 1, 'tutor gets the parent role');
select tests.eq((select count(*) from public.parent_profiles
  where account_id = '00000000-0000-0000-0000-000000000011'), 1, 'tutor gets a parent profile');

-- The second parent now sees the child, but can't change details (not managing).
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.students where id = :'sall'), 1, 'second parent sees the child');
update public.students set school = 'Changed PS' where id = :'sall';
reset role;
select tests.eq((select count(*) from public.students where id = :'sall' and school = 'Hill PS'), 1,
  'a parent who can''t manage can''t change details');

-- ---------------------------------------------------------------------------
-- Removing links
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.admin_unlink_parent('00000000-0000-0000-0000-000000000011', :'sall');
select public.admin_unlink_parent('00000000-0000-0000-0000-000000000002', :'sall');
select tests.eq((select count(*) from public.parent_student_links where student_id = :'sall'), 1, 'links removed');
select tests.fails_with(format($$select public.admin_unlink_parent('00000000-0000-0000-0000-000000000001', %L)$$, :'sall'),
  'only parent who can manage', 'can''t remove the last parent');
reset role;

-- ---------------------------------------------------------------------------
-- Possible duplicates: P2 adds the same child again
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select public.add_my_child('  sall   yoodle ', (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Hill PS',
  '[{"subject": "English"}, {"subject": "Science"}]') as sall2 \gset
select tests.eq((select count(*) from public.parent_student_links where student_id = :'sall2' and verified_at is null), 1,
  'a possible double-up waits for CLG');
select tests.fails('select * from public.admin_possible_duplicate_children()', 'parent lists duplicates');
select tests.fails(format($$select public.admin_merge_students(%L, %L)$$, :'sall2', :'sall'), 'parent merges records');
reset role;
-- Parental consent given for the double-up.
insert into public.consent_records (account_id, student_id, kind, document_version)
select '00000000-0000-0000-0000-000000000002', :'sall2', kind, 'test-merge'
from public.consent_records where student_id is not null limit 1;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.admin_possible_duplicate_children()
  where (student_id, other_student_id) in ((least(:'sall'::uuid, :'sall2'::uuid), greatest(:'sall'::uuid, :'sall2'::uuid)))), 1,
  'same name and birthday flagged for CLG');
select tests.fails_with(format($$select public.admin_merge_students(%L, %L)$$, :'sall', :'sall'),
  'two different', 'merge a record into itself');
select public.admin_merge_students(:'sall', :'sall2');
reset role;
select tests.eq((select count(*) from public.students where id = :'sall2'), 0, 'double-up removed');
select tests.eq((select count(*) from public.parent_student_links where student_id = :'sall' and verified_at is not null), 2,
  'both parents now on the kept record, confirmed');
select tests.eq((select count(*) from public.student_subjects where student_id = :'sall'), 2, 'subjects combined');
select tests.eq((select count(*) from public.consent_records where student_id = :'sall' and document_version = 'test-merge'), 1,
  'consent moved to the kept record');

-- A record with history can't be merged away.
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select public.add_my_child('Sall Yoodle', (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Hill PS',
  '[{"subject": "English"}]') as sall3 \gset
reset role;
insert into public.family_notes (student_id, kind, body, written_by)
values (:'sall3', 'feedback', 'Loves reading', '00000000-0000-0000-0000-000000000001');
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.fails_with(format($$select public.admin_merge_students(%L, %L)$$, :'sall', :'sall3'),
  'already has history', 'record with history');
-- CLG decides they're different children: the pair stops showing.
select public.admin_dismiss_duplicate(:'sall3', :'sall');
select tests.eq((select count(*) from public.admin_possible_duplicate_children()
  where :'sall3'::uuid in (student_id, other_student_id)), 0, 'dismissed pair stops showing');
select tests.eq((select count(*) from public.parent_student_links where student_id = :'sall3' and verified_at is not null), 1,
  'held link confirmed once CLG says they are different children');
reset role;
\set sall2 :sall3

-- ---------------------------------------------------------------------------
-- Nobody else can do this
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0');
set role authenticated;
select tests.fails(format($$select public.admin_link_parent('00000000-0000-0000-0000-000000000002', %L)$$, :'sall'),
  'admin without two-step login');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.fails(format($$select public.admin_link_parent('00000000-0000-0000-0000-000000000011', %L)$$, :'sall2'), 'tutor links themselves');
select tests.fails('select * from public.admin_student_parents()', 'tutor lists parent links');
select tests.fails('select * from public.student_duplicate_dismissals', 'tutor reads dismissals');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails(format($$select public.admin_link_parent('00000000-0000-0000-0000-000000000001', %L)$$, :'sall2'),
  'parent links themselves to another child');
select tests.fails(format($$select public.admin_unlink_parent('00000000-0000-0000-0000-000000000002', %L)$$, :'sall2'),
  'parent removes another parent');
select tests.fails(format($$select public.admin_dismiss_duplicate(%L, %L)$$, :'sall', :'sall2'), 'parent dismisses a duplicate');
reset role;

-- Clean up so later test files see the original fixtures.
delete from public.students where id in (:'sall', :'sall3');
delete from public.consent_records where document_version = 'test-merge';
delete from public.account_roles where account_id = '00000000-0000-0000-0000-000000000011' and role = 'parent';
delete from public.parent_profiles where account_id = '00000000-0000-0000-0000-000000000011';

\echo '  link parents: all checks passed'
