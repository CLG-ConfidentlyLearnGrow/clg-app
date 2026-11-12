-- Summary: parents only ever see their own children (Carla, 12 Nov 2026).
-- A parent sees the students they added, plus any student CLG has linked to
-- them, and nobody else's. Someone who is also an admin sees every student
-- (that's needed for admin work), so the Parent dashboard and family Billing
-- page read only the person's own links and families. These checks prove the
-- database gives the pages what they need to do that.
-- Reuses access_rules.test.sql helpers (tests.claims, tests.eq) and its
-- accounts: admin (...b0), parents P1 (...01) and P2 (...02).

-- ---------------------------------------------------------------------------
-- Every parent-only account: no student outside their own links
-- ---------------------------------------------------------------------------
-- Lists every account whose only role is parent (no admin, tutor or student role).
create temp table parent_only as -- A scratch list of parent-only accounts:
  select distinct r.account_id as id -- each account once,
  from public.account_roles r -- from the roles table,
  where r.role = 'parent' -- holding the parent role,
    and not exists ( -- and no other role:
      select 1 from public.account_roles o where o.account_id = r.account_id and o.role <> 'parent' -- (any role that isn't parent rules them out).
    ); -- End of the list.
-- A scratch table to note anything a parent can see that isn't theirs.
create temp table parent_leaks (parent_id uuid, what text, n bigint); -- Each row: the parent, what kind of record, and how many they shouldn't see.
grant select on parent_only to authenticated; -- Lets the signed-in role read the list (it's only used in this test).
grant insert, select on parent_leaks to authenticated; -- Lets the signed-in role note leaks (only used in this test).
select tests.eq((select count(*) >= 2 from parent_only)::int, 1, 'there are parent-only accounts to check'); -- Makes sure the sweep below really checks someone.

set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Signs in as each parent-only account in turn and counts what they can see
-- that belongs to a student they aren't linked to. Every count must be 0.
do $$ -- (a block of steps)
declare -- The block's working values:
  p uuid; -- the parent being checked.
begin -- Starts the steps.
  for p in select id from parent_only loop -- For each parent-only account:
    perform set_config('request.jwt.claims', -- signs in as them,
      json_build_object('sub', p, 'role', 'authenticated', 'aal', 'aal1')::text, true); -- (their id, the signed-in role, one-step sign-in).
    insert into parent_leaks -- Notes students they can see but aren't linked to:
      select p, 'students', count(*) from public.students s -- (each student they can see)
      where not exists (select 1 from public.parent_student_links l where l.parent_id = p and l.student_id = s.id); -- (with no link to this parent).
    insert into parent_leaks -- Notes other children's subjects they can see:
      select p, 'student_subjects', count(*) from public.student_subjects x -- (each subject row they can see)
      where not exists (select 1 from public.parent_student_links l where l.parent_id = p and l.student_id = x.student_id); -- (for a child not linked to them).
    insert into parent_leaks -- Notes other children's tutor matches they can see:
      select p, 'tutor_assignments', count(*) from public.tutor_assignments x -- (each tutor match they can see)
      where not exists (select 1 from public.parent_student_links l where l.parent_id = p and l.student_id = x.student_id); -- (for a child not linked to them).
    insert into parent_leaks -- Notes other children's parent links they can see:
      select p, 'parent_student_links', count(*) from public.parent_student_links x -- (each parent link they can see)
      where not exists (select 1 from public.parent_student_links l where l.parent_id = p and l.student_id = x.student_id); -- (for a child not linked to them).
    insert into parent_leaks -- Notes families they can see with none of their children in them:
      select p, 'families', count(*) from public.families f -- (each family they can see)
      where not exists ( -- (with no child of theirs in it:)
        select 1 from public.students s join public.parent_student_links l on l.student_id = s.id -- (their children)
        where s.family_id = f.id and l.parent_id = p -- (in this family).
      ); -- (end of the family check)
  end loop; -- Next parent.
end; -- End of the steps.
$$; -- (end of the block)
reset role; -- Goes back to the all-powerful test user (access rules off).
-- Shows exactly what leaked, if anything, so a failure is easy to read.
select tests.eq((select coalesce(sum(n), 0) from parent_leaks)::bigint, 0, -- Checks nobody saw anything that isn't theirs:
  'parent-only accounts see only their own children: ' || coalesce((select string_agg(what || ' x' || n, ', ') from parent_leaks where n > 0), 'none')); -- (the label names any leak).

-- ---------------------------------------------------------------------------
-- An admin who is also a parent: the database marks which children are theirs
-- ---------------------------------------------------------------------------
-- Sets up the admin (...b0) as a parent of one child of their own.
insert into public.families (id, name) values ('00000000-0000-0000-0000-00000000f0b0', 'Admin own family'); -- A family for the admin's own child.
insert into public.students (id, family_id, full_name, date_of_birth, state, year_level, school) values -- The admin's own child:
  ('00000000-0000-0000-0000-00000000c0b0', '00000000-0000-0000-0000-00000000f0b0', 'Own Kid', (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Own PS'); -- (a 9-year-old in SA).
insert into public.account_roles (account_id, role) values ('00000000-0000-0000-0000-0000000000b0', 'parent') on conflict do nothing; -- Gives the admin the parent role too.
insert into public.parent_profiles (account_id) values ('00000000-0000-0000-0000-0000000000b0') on conflict do nothing; -- And a parent profile.
insert into public.parent_student_links (parent_id, student_id) values ('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-00000000c0b0'); -- Links the admin to their own child.

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the admin, with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- As an admin they can see other students too (this is why the page must filter).
select tests.eq((select count(*) > 1 from public.students)::int, 1, 'admin sees more students than their own child'); -- Checks the admin sees other students.
-- Their own parent links name only their own child: this is what the Parent dashboard uses.
select tests.eq((select count(*) from public.parent_student_links where parent_id = auth.uid()), 1, 'admin-parent has one link of their own'); -- Checks: exactly one link of their own.
select tests.eq((select count(*) from public.parent_student_links where parent_id = auth.uid() -- Checks that link is to their own child:
  and student_id = '00000000-0000-0000-0000-00000000c0b0'), 1, 'admin-parent''s own link is to their own child'); -- (Own Kid).
-- The families they pay for: only their own, even though they can see all families as an admin.
select tests.eq((select count(*) > 1 from public.families)::int, 1, 'admin sees more families than their own'); -- Checks the admin sees other families.
select tests.eq((select count(*) from public.billing_my_plan_choices()), 1, 'admin-parent pays for one family only'); -- Checks the family Billing page's list has just one family,
select tests.eq((select count(*) from public.billing_my_plan_choices() -- and that it's their own:
  where family_id = '00000000-0000-0000-0000-00000000f0b0'), 1, 'admin-parent''s billing family is their own'); -- (Admin own family).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- An admin links another parent, then unlinks them
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as parent P2.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = '00000000-0000-0000-0000-00000000c0b0'), 0, 'P2 can''t see the child before being linked'); -- Checks: P2 can't see the child yet.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the admin, with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_link_parent('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000c0b0', 'guardian', true); -- The admin links P2 to the child as a guardian.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as parent P2.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = '00000000-0000-0000-0000-00000000c0b0'), 1, 'P2 sees the child once linked'); -- Checks: P2 now sees the child.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the admin, with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_unlink_parent('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000c0b0'); -- The admin removes P2's link.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as parent P2.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = '00000000-0000-0000-0000-00000000c0b0'), 0, 'P2 can''t see the child once unlinked'); -- Checks: P2 can't see the child after unlinking.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Tidy up, so later test files start from the same place
-- ---------------------------------------------------------------------------
delete from public.students where id = '00000000-0000-0000-0000-00000000c0b0'; -- Removes the admin's test child (its links go with it).
delete from public.families where id = '00000000-0000-0000-0000-00000000f0b0'; -- Removes the test family.
delete from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000b0' and role = 'parent'; -- Takes the parent role back off the admin.
delete from public.parent_profiles where account_id = '00000000-0000-0000-0000-0000000000b0'; -- Removes the admin's parent profile.
select tests.claims(null); -- Signs out, so no one is signed in.

-- Prints that every check in this file passed.
\echo '  parents see only their own children: all checks passed'
