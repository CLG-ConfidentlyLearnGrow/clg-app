-- Learning needs: the family writes them; only people linked to the
-- student can read them. Reuses access_rules.test.sql helpers: admin
-- (...b0), tutor T1 (...11), parents P1 (...01) and P2 (...02).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Nia Two', -- Adds a test child, Nia, to parent P2's family:
  -- born ten years ago, in Year 5 in SA, and keeps her id as nia.
  (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Hill PS', '[]') as nia \gset
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
update public.students set learning_needs = 'Dyslexia; prefers short tasks' where id = :'nia'; -- Writes Nia's learning needs.
select tests.eq((select count(*) from public.students where id = :'nia' and learning_needs like 'Dyslexia%'), 1, 'parent writes learning needs'); -- Checks: parent writes learning needs.
select tests.fails(format($$update public.students set learning_needs = repeat('x', 2001) where id = %L$$, :'nia'), 'too long'); -- Checks this is refused: too long.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = :'nia'), 0, 'another parent cannot see them'); -- Checks: another parent cannot see them.
update public.students set learning_needs = 'changed' where id = :'nia'; -- Tries to change them.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.students where id = :'nia' and learning_needs = 'changed'), 0, 'another parent cannot change them'); -- Checks: another parent cannot change them.

select tests.claims('00000000-0000-0000-0000-000000000011'); -- Signs in as test account ...11.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = :'nia'), 0, 'an unassigned tutor cannot see them'); -- Checks: an unassigned tutor cannot see them.
reset role; -- Goes back to the all-powerful test user (access rules off).

delete from public.students where id = :'nia'; -- Removes Nia again.

-- Prints that every check in this file passed.
\echo '  learning needs: all checks passed'
