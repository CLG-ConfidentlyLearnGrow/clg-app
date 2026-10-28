-- Giving a student on a parent's account their own login.
-- Reuses access_rules.test.sql helpers: admin (...b0), tutor T1 (...11),
-- parents P1 (...01) and P2 (...02), and family_setup's tests.fails_with.

-- Two children on P2's account: one aged 17, one aged 12, one with no birthday.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Kim Two',
  (current_date - interval '17 years')::date, 'SA', 'Year 11', 'Hill HS', '[]') as kim \gset
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Lou Two',
  (current_date - interval '12 years')::date, 'SA', 'Year 7', 'Hill HS', '[]') as lou \gset
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Max Two',
  null, null, null, null, null) as max \gset

-- Refusals, with plain messages.
select tests.fails_with(format($$select public.admin_offer_student_login(%L, 'lou@example.com')$$, :'lou'),
  'under 16', 'under 16 refused');
select tests.fails_with(format($$select public.admin_offer_student_login(%L, 'max@example.com')$$, :'max'),
  'date of birth first', 'no birthday refused');
select tests.fails_with(format($$select public.admin_offer_student_login(%L, 'not an email')$$, :'kim'),
  'check the email', 'bad email refused');
select tests.fails_with(format($$select public.admin_offer_student_login(%L, 'P1@example.com')$$, :'kim'),
  'already has a CLG account', 'email of an existing account refused');

-- A first offer, then a second one that replaces it.
select public.admin_offer_student_login(:'kim', 'old-kim@example.com');
select public.admin_offer_student_login(:'kim', ' Kim@Example.com ');
select tests.eq((select count(*) from public.student_login_offers where student_id = :'kim'), 1, 'new offer replaces the old one');
select tests.eq((select count(*) from public.student_login_offers where student_id = :'kim' and email = 'kim@example.com'), 1, 'email stored in lower case');
reset role;

-- Nobody else can make offers or see them.
select tests.claims('00000000-0000-0000-0000-0000000000b0');
set role authenticated;
select tests.fails(format($$select public.admin_offer_student_login(%L, 'x@example.com')$$, :'kim'), 'admin without two-step login');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.fails(format($$select public.admin_offer_student_login(%L, 'x@example.com')$$, :'kim'), 'the parent');
select tests.eq((select count(*) from public.student_login_offers), 0, 'parent sees no offers');
select tests.fails(format($$insert into public.student_login_offers (student_id, email) values (%L, 'x@example.com')$$, :'kim'), 'parent writes an offer');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.fails(format($$select public.admin_offer_student_login(%L, 'x@example.com')$$, :'kim'), 'a tutor');
reset role;
select tests.claims(null);
set role anon;
select tests.fails(format($$select public.admin_offer_student_login(%L, 'x@example.com')$$, :'kim'), 'anon');
reset role;

-- The account is made; nothing is handed over until the email is confirmed.
insert into auth.users (id, email, invited_at, raw_user_meta_data)
values ('00000000-0000-0000-0000-0000000000c1', 'kim@example.com', now(), '{"full_name":"Kim"}');
select tests.eq((select count(*) from public.students where id = :'kim' and account_id is not null), 0, 'not linked before the email is confirmed');
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000c1'), 0, 'no role before the email is confirmed');
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-0000000000c1';
select tests.eq((select count(*) from public.students where id = :'kim' and account_id = '00000000-0000-0000-0000-0000000000c1'), 1, 'student record handed over');
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000c1' and role = 'student'), 1, 'student role given');
select tests.eq((select count(*) from public.student_login_offers where student_id = :'kim' and accepted_at is not null), 1, 'offer marked used');
select tests.eq((select count(*) from public.parent_student_links where student_id = :'kim'), 1, 'parent link kept');

-- The student sees their own record; the parent still does too.
select tests.claims('00000000-0000-0000-0000-0000000000c1');
set role authenticated;
select tests.eq((select count(*) from public.students where id = :'kim'), 1, 'student sees own record');
select tests.eq((select count(*) from public.students where id = :'lou'), 0, 'student does not see a sibling');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.students where id = :'kim'), 1, 'parent still sees the student');
reset role;

-- A used offer can't be used again, and a student with a login can't get another.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.fails_with(format($$select public.admin_offer_student_login(%L, 'kim2@example.com')$$, :'kim'),
  'already has their own login', 'second login refused');
reset role;

-- An offer whose time ran out does nothing.
update public.students set date_of_birth = (current_date - interval '16 years')::date where id = :'lou';
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.admin_offer_student_login(:'lou', 'lou@example.com');
reset role;
update public.student_login_offers set expires_at = now() - interval '1 minute' where student_id = :'lou';
select tests.fails($$insert into auth.users (email, raw_user_meta_data) values ('lou@example.com', '{}')$$, 'expired offer gives no account');
select tests.eq((select count(*) from public.students where id = :'lou' and account_id is null), 1, 'expired offer links nothing');

-- Clean up so later test files see the original fixtures.
delete from public.students where id in (:'kim', :'lou', :'max');
delete from public.student_login_offers;
delete from auth.users where id = '00000000-0000-0000-0000-0000000000c1';

\echo '  student own login: all checks passed'
