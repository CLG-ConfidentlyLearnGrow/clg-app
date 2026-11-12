-- Admins setting up a family's account: adding a child to a parent's
-- account, finding an account by email, and the policy agreement check.
-- Reuses access_rules.test.sql helpers: admin (...b0), tutor T1 (...11),
-- parents P1 (...01) and P2 (...02).

-- ---------------------------------------------------------------------------
-- Admin adds a child to a parent's account
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Dana Two', -- The admin adds Dana, 9, to parent P2's family:
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', -- (Year 4 in SA),
  -- with two subjects, an end goal and a note; keeps her id as dana.
  '[{"subject": "English", "level": "Year 3"}, {"subject": "General Maths", "level": null}]', 'Enjoy reading', 'Shy at first') as dana \gset
select tests.eq((select count(*) from public.parent_student_links -- Checks an admin-made link is already checked:
  where parent_id = '00000000-0000-0000-0000-000000000002' and student_id = :'dana' -- (between parent P2 and Dana),
    and verified_at is not null and verified_by = '00000000-0000-0000-0000-0000000000b0'), 1, 'admin-made link is already checked'); -- (checked by the admin).
select tests.eq((select count(*) from public.student_subjects where student_id = :'dana'), 2, 'subjects saved'); -- Checks: subjects saved.
select tests.eq((select count(*) from public.student_subjects where student_id = :'dana' and subject = 'English' and working_level = 'Year 3'), 1, 'level saved per subject'); -- Checks: level saved per subject.
select tests.eq((select count(*) from public.students where id = :'dana' and goals = 'Enjoy reading' and extra_info = 'Shy at first'), 1, 'goal and extra information saved'); -- Checks: goal and extra information saved.
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000011', 'Not A Parent', -- Checks a child for a non-parent account is refused:
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[{"subject": "English"}]')$$, 'child for a non-parent account'); -- (tutor T1 isn't a parent).
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', ' ', -- Checks a child with no name is refused:
  null, null, null, null, null)$$, 'child without a name'); -- (blank name).
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Bad Date', -- Checks a child born in the future is refused:
  (current_date + 1), null, null, null, null)$$, 'child born in the future'); -- (tomorrow).
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Bad Year', -- Checks an unknown year level is refused:
  null, null, 'Grade 4', null, null)$$, 'unknown year level'); -- (Grade 4).
-- Only the name: the family fills in the rest.
-- Adds Gus with just a name, and keeps his id as gus.
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Gus Two', null, null, null, null, null) as gus \gset
select tests.eq((select count(*) from public.students where id = :'gus' and id in (select student_id from public.student_birth_dates() where date_of_birth is null) and state is null and year_level is null and school is null), 1, 'child with only a name'); -- Checks: child with only a name (the birth date is read through student_birth_dates, as the app does).
select tests.eq(private.student_details_complete(:'gus')::int, 0, 'details not finished'); -- Checks: details not finished.
select tests.eq(private.student_details_complete(:'dana')::int, 1, 'full details are finished'); -- Checks: full details are finished.
select tests.eq((select count(*) from public.admin_find_account('nobody@example.com')), 0, 'unknown email finds nothing'); -- Checks: unknown email finds nothing.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The parent sees the child the admin added.
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = :'dana'), 1, 'parent sees the child'); -- Checks: parent sees the child.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- A second child joins the same family.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Eli Two', -- Adds Eli, 7, Year 2:
  -- and keeps the id as eli.
  (current_date - interval '7 years')::date, 'SA', 'Year 2', 'Hill PS', '[{"subject": "English"}]') as eli \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(distinct family_id) from public.students where id in (:'dana', :'eli')), 1, 'children share one family'); -- Checks: children share one family.

-- Finding accounts by email (admins only).
-- Keeps parent P2's email as p2_email.
select email as p2_email from public.account_private where account_id = '00000000-0000-0000-0000-000000000002' \gset
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.admin_find_account(upper(:'p2_email')) where is_parent), 1, 'admin finds a parent by email, any case'); -- Checks: admin finds a parent by email, any case.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Nobody else can do this
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0'); -- Signs in as test account ...b0.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'X', -- Checks an admin without two-step login is refused:
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[{"subject": "English"}]')$$, 'admin without two-step login'); -- (the label).
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'X', -- Checks a tutor is refused:
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[{"subject": "English"}]')$$, 'tutor'); -- (the label).
select tests.fails(format('select * from public.admin_find_account(%L)', :'p2_email'), 'tutor looks up an email'); -- Checks this is refused: tutor looks up an email.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'X', -- Checks another parent is refused:
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[{"subject": "English"}]')$$, 'another parent'); -- (the label).
select tests.fails($$select private.add_child_for('00000000-0000-0000-0000-000000000002', null, 'X', -- Checks calling the private helper is refused:
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[{"subject": "English"}]', null, null)$$, 'calling the private helper'); -- (the label).
-- Parents adding their own child still works, and stays unchecked.
-- Parent P1 adds their own child, Fay, and keeps her id as fay.
select public.add_my_child('Fay One', (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Hill PS', '[{"subject": "English"}]') as fay \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.parent_student_links where student_id = :'fay' and verified_at is not null and verified_by is null), 1, 'parent-made link confirmed straight away'); -- Checks: parent-made link confirmed straight away.

select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'X', -- Checks someone not signed in is refused:
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[{"subject": "English"}]')$$, 'anon'); -- (the label).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Agreeing to the privacy policy and terms on first sign-in
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(public.my_policy_consent('test-v9')::int, 0, 'not agreed yet'); -- Checks: not agreed yet.
insert into public.consent_records (account_id, kind, document_version) -- Parent P2 agrees to the privacy policy:
values ('00000000-0000-0000-0000-000000000002', 'privacy_policy', 'test-v9'); -- (test version).
select tests.eq(public.my_policy_consent('test-v9')::int, 0, 'privacy policy alone is not enough'); -- Checks: privacy policy alone is not enough.
insert into public.consent_records (account_id, kind, document_version) -- Parent P2 agrees to the terms:
values ('00000000-0000-0000-0000-000000000002', 'terms_of_service', 'test-v9'); -- (test version).
select tests.eq(public.my_policy_consent('test-v9')::int, 1, 'agreed to both'); -- Checks: agreed to both.
select tests.fails($$insert into public.consent_records (account_id, kind, document_version) -- Checks agreeing for someone else is refused:
  values ('00000000-0000-0000-0000-000000000001', 'privacy_policy', 'test-v9')$$, 'agreeing for someone else'); -- (parent P2 agreeing for parent P1).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- The family finishes the details; no tutor until they do
-- ---------------------------------------------------------------------------
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
select tests.fails_with(format($$insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000011', %L, 'English')$$, :'gus'), -- Checks no tutor can be assigned before Gus's details are finished:
  'details aren''t finished', 'no tutor before details are finished'); -- (the message says details aren't finished).
select tests.fails_with(format($$insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date) -- Checks no booking can be made before then either:
  values (%L, '00000000-0000-0000-0000-000000000011', 'English', 1, '16:00', 60, 'online', current_date, current_date + 7)$$, :'gus'), -- (Monday 4pm online for a week),
  'details aren''t finished', 'no booking before details are finished'); -- (the message says details aren't finished).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$update public.students set date_of_birth = current_date + 1 where id = %L$$, :'gus'), 'parent gives a future birthday'); -- Checks this is refused: parent gives a future birthday.
update public.students set date_of_birth = (current_date - interval '8 years')::date, state = 'SA', year_level = 'Year 3', school = 'Hill PS' where id = :'gus'; -- Fills in Gus's details.
select tests.eq((select count(*) from public.students where id = :'gus' and state = 'SA' and id in (select student_id from public.student_birth_dates() where date_of_birth is not null)), 1, 'parent fills in birthday and state'); -- Checks: parent fills in birthday and state (birth date read through student_birth_dates).
select tests.fails(format($$update public.students set date_of_birth = (current_date - interval '9 years')::date where id = %L$$, :'gus'), 'parent changes birthday once given'); -- Checks this is refused: parent changes birthday once given.
select tests.fails(format($$update public.students set state = 'VIC' where id = %L$$, :'gus'), 'parent changes state once given'); -- Checks this is refused: parent changes state once given.
select tests.fails(format($$update public.students set year_level = null where id = %L$$, :'gus'), 'parent clears the year level'); -- Checks this is refused: parent clears the year level.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq(private.student_details_complete(:'gus')::int, 1, 'details finished by the family'); -- Checks: details finished by the family.

-- Clean up so later test files see the original fixtures.
delete from public.students where id in (:'dana', :'eli', :'fay', :'gus'); -- Removes the test children.
delete from public.consent_records where document_version = 'test-v9'; -- Removes the test agreements.
