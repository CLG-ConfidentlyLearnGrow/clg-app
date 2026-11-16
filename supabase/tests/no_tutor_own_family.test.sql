-- Summary: checks that a tutor can never be matched with their own child or
-- family member (Carla, 16 Nov 2026). Covers: a tutor who is a linked parent
-- of a student, another student in that same family, and a tutor who is the
-- student themselves. Checks the shared pairing check (blocked_pair) says
-- "blocked", that a new match is refused with a plain message, and that
-- other pairs and ending an old match still work. Reuses access_rules.test.sql
-- people: tutor T1 (...11, teaches Cara), tutor T2 (...12), parent P2 (...02,
-- Vic's parent). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this database change again (checks it can run twice).
\ir ../migrations/20261118100400_no_tutor_own_family.sql
-- Writes out the short forms in the database's messages again (the file above put back the old wording).
\ir ../migrations/20261119500200_messages_no_contractions.sql

select tests.claims(null); -- acts as the database itself while setting up
\set t1 '00000000-0000-0000-0000-000000000011'
-- (tutor T1's account id)
\set t2 '00000000-0000-0000-0000-000000000012'
-- (tutor T2's account id)
select id as cara from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's student id as cara)
select id as vic, family_id as vic_family from public.students where full_name = 'Vic Two' \gset
-- (keeps Vic's student id as vic, and Vic's family as vic_family)

-- Starting point: T2 isn't family of anyone yet.
select tests.eq(private.tutor_is_family(:'t2', :'vic')::int, 0, 'set-up: T2 is not Vic''s family'); -- not family
select tests.eq(private.blocked_pair(:'t2', :'vic')::int, 0, 'set-up: T2 and Vic are not blocked'); -- not blocked

-- T2 also becomes a parent, linked to Vic (like a tutor who is also a CLG parent).
insert into public.account_roles (account_id, role) values (:'t2', 'parent') on conflict do nothing; -- gives T2 the parent role
insert into public.parent_profiles (account_id) values (:'t2') on conflict do nothing; -- and a parent profile
insert into public.parent_student_links (parent_id, student_id, verified_at) values (:'t2', :'vic', now()); -- links T2 to Vic as a parent (confirmed)
-- Vic gets a sibling in the same family that T2 isn't directly linked to (for example a stepchild).
insert into public.students (family_id, full_name, date_of_birth, state, year_level, school) values (:'vic_family', 'Sib Two', current_date - interval '9 years', 'SA', 'Year 4', 'Test School') returning id as sib \gset
-- (keeps the sibling's id as sib)

-- 1. The shared pairing check blocks the tutor's own family.
select tests.eq(private.tutor_is_family(:'t2', :'vic')::int, 1, 'T2 is Vic''s family (linked parent)'); -- family
select tests.eq(private.blocked_pair(:'t2', :'vic')::int, 1, 'T2 cannot be paired with their own child'); -- blocked
select tests.eq(private.blocked_pair(:'t2', :'sib')::int, 1, 'T2 cannot be paired with another child in the same family'); -- blocked
select tests.eq(private.blocked_pair(:'t2', :'cara')::int, 0, 'T2 can still be paired with someone else''s child'); -- not blocked
select tests.eq(private.blocked_pair(:'t1', :'vic')::int, 0, 'another tutor can still be paired with Vic'); -- not blocked

-- 2. A new match with their own child is refused, with the plain reason first.
do $$ -- a small block that checks the refusal and its words
declare -- the working values:
  v_message text; -- the refusal message
begin -- starts the block
  begin -- an inner block, so the refusal can be caught
    insert into public.tutor_assignments (tutor_id, student_id, subject) -- tries to match T2 with Vic
    select '00000000-0000-0000-0000-000000000012', id, 'Mathematics' from public.students where full_name = 'Vic Two'; -- (T2 and Vic, Mathematics)
  exception when others then -- refused:
    v_message := sqlerrm; -- keeps the message
  end; -- end of the inner block
  if v_message is null or v_message not like 'A tutor cannot be matched with their own child%' then -- not refused, or refused for another reason
    raise exception 'FAIL: matching a tutor with their own child should be refused with the plain message, got: %', coalesce(v_message, 'no refusal'); -- stops the run
  end if; -- end of the check
end; -- end of the block
$$; -- end of the code

-- 3. Moving an existing match onto the tutor's own child is refused too.
do $$ -- a small block that checks the refusal and its words
declare -- the working values:
  v_message text; -- the refusal message
begin -- starts the block
  begin -- an inner block, so the refusal can be caught
    update public.tutor_assignments -- tries to change T1's match with Cara
    set tutor_id = '00000000-0000-0000-0000-000000000012', -- to tutor T2
        student_id = (select id from public.students where full_name = 'Vic Two') -- and T2's own child Vic
    where tutor_id = '00000000-0000-0000-0000-000000000011' -- (T1's match)
      and student_id = (select id from public.students where full_name = 'Cara One'); -- (with Cara)
  exception when others then -- refused:
    v_message := sqlerrm; -- keeps the message
  end; -- end of the inner block
  if v_message is null or v_message not like 'A tutor cannot be matched with their own child%' then -- not refused, or refused for another reason
    raise exception 'FAIL: moving a match onto a tutor''s own child should be refused, got: %', coalesce(v_message, 'no refusal'); -- stops the run
  end if; -- end of the check
end; -- end of the block
$$; -- end of the code
update public.tutor_assignments set ends_on = current_date where tutor_id = :'t1' and student_id = :'cara'; -- ending a match (same tutor and student) still works
select tests.eq((select count(*) from public.tutor_assignments where tutor_id = :'t1' and student_id = :'cara' and ends_on = current_date), 1::bigint, 'ending a match still works'); -- ended

-- 4. A tutor who is the student themselves (learning with CLG) can't tutor themselves.
insert into public.students (full_name, account_id, date_of_birth, state, year_level, school) values ('Tutor Two Learner', :'t2', current_date - interval '30 years', 'SA', 'Adult learner', 'Not studying') returning id as self \gset
-- (keeps T2's own learner record as self)
select tests.eq(private.blocked_pair(:'t2', :'self')::int, 1, 'a tutor cannot be paired with themselves as a learner'); -- blocked
select tests.eq(private.blocked_pair(:'t1', :'self')::int, 0, 'another tutor can teach that learner'); -- not blocked

-- Throws everything away.
rollback;
\echo '  no_tutor_own_family: all checks passed'
