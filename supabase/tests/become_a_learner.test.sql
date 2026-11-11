-- "Become a learner too": an existing account adds a student profile.
-- Reuses access_rules.test.sql helpers: tutor T1 (...11), parents P1 (...01)
-- and P2 (...02).

create or replace function tests.fails_with(p_sql text, p_words text, p_label text) returns void -- Adds a test helper: checks a statement is refused with a message containing certain words.
language plpgsql as $f$ -- (written in PL/pgSQL)
begin -- Starts the helper.
  execute p_sql; -- Runs the statement.
  raise exception 'Expected failure but it succeeded: %', p_label; -- If it worked, that's a failure.
exception when others then -- If it was refused:
  if sqlerrm like 'Expected failure%' then raise; end if; -- passes on the "it worked" failure from above,
  if position(p_words in sqlerrm) = 0 then -- and if the message doesn't contain the words,
    raise exception 'FAIL %: wrong error: %', p_label, sqlerrm; -- says the wrong error came back.
  end if; -- End of the words check.
end; -- End of the helper.
$f$; -- (end of its code)

-- A tutor becomes a learner too.
select tests.claims('00000000-0000-0000-0000-000000000011'); -- Signs in as test account ...11.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with($$select public.add_me_as_learner((current_date - interval '15 years')::date, 'SA', 'Year 10', 'Hill HS')$$, -- Checks a learner under 16 is refused:
  'under 16', 'under 16 refused'); -- (the message mentions under 16).
select tests.fails_with($$select public.add_me_as_learner((current_date - interval '30 years')::date, 'SA', 'Grade 4', 'Uni SA')$$, -- Checks an unknown year level is refused:
  'year level', 'unknown year level refused'); -- (the message mentions year level).
select tests.fails_with($$select public.add_me_as_learner((current_date - interval '30 years')::date, 'SA', 'Year 12', ' ')$$, -- Checks a blank school is refused:
  'school', 'no school refused'); -- (the message mentions school).
select public.add_me_as_learner((current_date - interval '30 years')::date, 'SA', 'Year 12', 'Open Uni', -- A 30-year-old adds themselves as a learner:
  -- with English, and keeps the student id as tl.
  '[{"subject": "English", "level": null}]', 'Brush up essay writing') as tl \gset
select tests.eq((select count(*) from public.students where id = :'tl' and account_id = '00000000-0000-0000-0000-000000000011'), 1, 'tutor sees own student profile'); -- Checks: tutor sees own student profile.
select tests.eq((select count(*) from public.student_subjects where student_id = :'tl'), 1, 'subject saved'); -- Checks: subject saved.
select tests.fails_with($$select public.add_me_as_learner((current_date - interval '30 years')::date, 'SA', 'Year 12', 'Open Uni')$$, -- Checks a second profile is refused:
  'already have a student profile', 'second profile refused'); -- (the message says they already have one).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-000000000011' and role in ('student', 'tutor')), 2, 'keeps tutor role and gains student role'); -- Checks: keeps tutor role and gains student role.

-- Other people can't see it, and nobody signed out can do this.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = :'tl'), 0, 'a parent does not see it'); -- Checks: a parent does not see it.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select public.add_me_as_learner((current_date - interval '30 years')::date, 'SA', 'Year 12', 'Open Uni')$$, 'anon'); -- Checks this is refused: anon.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Clean up so later test files see the original fixtures.
delete from public.students where id = :'tl'; -- Removes the test student.
delete from public.account_roles where account_id = '00000000-0000-0000-0000-000000000011' and role = 'student'; -- Removes tutor T1's student role.

-- Prints that every check in this file passed.
\echo '  become a learner: all checks passed'
