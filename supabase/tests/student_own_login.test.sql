-- Giving a student on a parent's account their own login.
-- Reuses access_rules.test.sql helpers: admin (...b0), tutor T1 (...11),
-- parents P1 (...01) and P2 (...02), and family_setup's tests.fails_with.

-- Two children on P2's account: one aged 17, one aged 12, one with no birthday.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Kim Two', -- Adds Kim, 17, Year 11, to parent P2's family:
  -- and keeps her id as kim.
  (current_date - interval '17 years')::date, 'SA', 'Year 11', 'Hill HS', '[]') as kim \gset
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Lou Two', -- Adds Lou, 12, Year 7:
  -- and keeps the id as lou.
  (current_date - interval '12 years')::date, 'SA', 'Year 7', 'Hill HS', '[]') as lou \gset
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Max Two', -- Adds Max, with no details yet:
  -- and keeps the id as max.
  null, null, null, null, null) as max \gset

-- Refusals, with plain messages.
select tests.fails_with(format($$select public.admin_offer_student_login(%L, 'lou@example.com')$$, :'lou'), -- Checks under 16 is refused:
  'under 16', 'under 16 refused'); -- (Lou is 12).
select tests.fails_with(format($$select public.admin_offer_student_login(%L, 'max@example.com')$$, :'max'), -- Checks no birthday is refused:
  'date of birth first', 'no birthday refused'); -- (Max has none).
select tests.fails_with(format($$select public.admin_offer_student_login(%L, 'not an email')$$, :'kim'), -- Checks a bad email is refused:
  'check the email', 'bad email refused'); -- (the message asks to check it).
select tests.fails_with(format($$select public.admin_offer_student_login(%L, 'P1@example.com')$$, :'kim'), -- Checks the email of an existing account is refused:
  'already has a CLG account', 'email of an existing account refused'); -- (parent P1's email).

-- A first offer, then a second one that replaces it.
select public.admin_offer_student_login(:'kim', 'old-kim@example.com'); -- Offers Kim a login at an old email.
select public.admin_offer_student_login(:'kim', ' Kim@Example.com '); -- Offers it again at a new email (with untidy spacing and capitals).
select tests.eq((select count(*) from public.student_login_offers where student_id = :'kim'), 1, 'new offer replaces the old one'); -- Checks: new offer replaces the old one.
select tests.eq((select count(*) from public.student_login_offers where student_id = :'kim' and email = 'kim@example.com'), 1, 'email stored in lower case'); -- Checks: email stored in lower case.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Nobody else can make offers or see them.
select tests.claims('00000000-0000-0000-0000-0000000000b0'); -- Signs in as test account ...b0.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.admin_offer_student_login(%L, 'x@example.com')$$, :'kim'), 'admin without two-step login'); -- Checks this is refused: admin without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.admin_offer_student_login(%L, 'x@example.com')$$, :'kim'), 'the parent'); -- Checks this is refused: the parent.
select tests.eq((select count(*) from public.student_login_offers), 0, 'parent sees no offers'); -- Checks: parent sees no offers.
select tests.fails(format($$insert into public.student_login_offers (student_id, email) values (%L, 'x@example.com')$$, :'kim'), 'parent writes an offer'); -- Checks this is refused: parent writes an offer.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.admin_offer_student_login(%L, 'x@example.com')$$, :'kim'), 'a tutor'); -- Checks this is refused: a tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails(format($$select public.admin_offer_student_login(%L, 'x@example.com')$$, :'kim'), 'anon'); -- Checks this is refused: anon.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The account is made; nothing is handed over until the email is confirmed.
insert into auth.users (id, email, invited_at, raw_user_meta_data) -- Kim signs up from the offer:
values ('00000000-0000-0000-0000-0000000000c1', 'kim@example.com', now(), '{"full_name":"Kim"}'); -- (invited, named Kim).
select tests.eq((select count(*) from public.students where id = :'kim' and account_id is not null), 0, 'not linked before the email is confirmed'); -- Checks: not linked before the email is confirmed.
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000c1'), 0, 'no role before the email is confirmed'); -- Checks: no role before the email is confirmed.
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-0000000000c1'; -- Kim confirms her email.
select tests.eq((select count(*) from public.students where id = :'kim' and account_id = '00000000-0000-0000-0000-0000000000c1'), 1, 'student record handed over'); -- Checks: student record handed over.
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000c1' and role = 'student'), 1, 'student role given'); -- Checks: student role given.
select tests.eq((select count(*) from public.student_login_offers where student_id = :'kim' and accepted_at is not null), 1, 'offer marked used'); -- Checks: offer marked used.
select tests.eq((select count(*) from public.parent_student_links where student_id = :'kim'), 1, 'parent link kept'); -- Checks: parent link kept.

-- The student sees their own record; the parent still does too.
select tests.claims('00000000-0000-0000-0000-0000000000c1'); -- Signs in as test account ...c1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = :'kim'), 1, 'student sees own record'); -- Checks: student sees own record.
select tests.eq((select count(*) from public.students where id = :'lou'), 0, 'student does not see a sibling'); -- Checks: student does not see a sibling.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = :'kim'), 1, 'parent still sees the student'); -- Checks: parent still sees the student.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- A used offer can't be used again, and a student with a login can't get another.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with(format($$select public.admin_offer_student_login(%L, 'kim2@example.com')$$, :'kim'), -- Checks a second login is refused:
  'already has their own login', 'second login refused'); -- (Kim already has one).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- An offer whose time ran out does nothing.
update public.students set date_of_birth = (current_date - interval '16 years')::date where id = :'lou'; -- Makes Lou 16.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_offer_student_login(:'lou', 'lou@example.com'); -- Offers Lou a login.
reset role; -- Goes back to the all-powerful test user (access rules off).
update public.student_login_offers set expires_at = now() - interval '1 minute' where student_id = :'lou'; -- Makes the offer run out a minute ago.
select tests.fails($$insert into auth.users (email, raw_user_meta_data) values ('lou@example.com', '{}')$$, 'expired offer gives no account'); -- Checks this is refused: expired offer gives no account.
select tests.eq((select count(*) from public.students where id = :'lou' and account_id is null), 1, 'expired offer links nothing'); -- Checks: expired offer links nothing.


-- The link ran out before the student used it: offer again with the same
-- email, and the account made the first time is used.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_offer_student_login(:'lou', 'lou@example.com'); -- Offers it again.
reset role; -- Goes back to the all-powerful test user (access rules off).
insert into auth.users (id, email, invited_at, raw_user_meta_data) -- Someone starts signing up with Lou's email:
values ('00000000-0000-0000-0000-0000000005c2', 'lou@example.com', now(), '{}'); -- (not confirmed yet).
update public.student_login_offers set expires_at = now() - interval '1 minute' where student_id = :'lou'; -- Makes the offer run out.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_offer_student_login(:'lou', 'lou@example.com'); -- Offers it again.
-- An email that has been used (confirmed) or has a role still can't be offered.
select tests.fails_with(format($$select public.admin_offer_student_login(%L, 'kim@example.com')$$, :'lou'), -- Checks a confirmed account's email is refused:
  'already has a CLG account', 'confirmed account refused'); -- (Kim's email).
reset role; -- Goes back to the all-powerful test user (access rules off).
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-0000000005c2'; -- The sign-up for Lou's email is confirmed.
select tests.eq((select count(*) from public.students where id = :'lou' and account_id = '00000000-0000-0000-0000-0000000005c2'), 1, 'second offer hands over the record'); -- Checks: second offer hands over the record.


-- A parent can give their own child aged 16 or over a login; never under 16.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Ola Two', -- Adds Ola, exactly 16:
  -- and keeps the id as ola.
  (current_date - interval '16 years')::date, 'SA', 'Year 11', 'Hill HS', '[]') as ola \gset
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Pia Two', -- Adds Pia, one day short of 16:
  -- and keeps the id as pia.
  (current_date - interval '16 years' + interval '1 day')::date, 'SA', 'Year 10', 'Hill HS', '[]') as pia \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with(format($$select public.parent_offer_student_login(%L, 'pia@example.com')$$, :'pia'), -- Checks a parent can't offer a login one day under 16:
  'under 16', 'parent: one day under 16 refused'); -- (Pia).
select public.parent_offer_student_login(:'ola', 'ola@example.com'); -- The parent offers Ola a login.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.student_login_offers where student_id = :'ola' and offered_by = '00000000-0000-0000-0000-000000000002'), 1, 'parent made the offer'); -- Checks: parent made the offer.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with(format($$select public.parent_offer_student_login(%L, 'x@example.com')$$, :'ola'), -- Checks another parent can't offer one:
  'student''s parent', 'another parent refused'); -- (the message says only the student's parent).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.parent_offer_student_login(%L, 'x@example.com')$$, :'ola'), 'a tutor'); -- Checks this is refused: a tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select private.offer_student_login(%L, 'x@example.com')$$, :'ola'), 'calling the private helper'); -- Checks this is refused: calling the private helper.
reset role; -- Goes back to the all-powerful test user (access rules off).
delete from public.students where id in (:'ola', :'pia'); -- Removes Ola and Pia.

-- Clean up so later test files see the original fixtures.
delete from public.students where id in (:'kim', :'lou', :'max'); -- Removes Kim, Lou and Max.
delete from public.student_login_offers; -- Clears the login offers.
delete from auth.users where id in ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000005c2'); -- Removes the test accounts.

-- Prints that every check in this file passed.
\echo '  student own login: all checks passed'
