-- Staff invite links. Runs after access_rules.test.sql and reuses its
-- helpers, owner (...a0), staff admin (...b0) and parent P1 (...01).

create temporary table tokens (label text primary key, token text);
grant all on tokens to authenticated, anon;

-- Only admins with two-step login can make a link.
select tests.claims(null);
set role anon;
select tests.fails($$select public.create_staff_invite_link('join.one@example.com', 'tutor')$$, 'anon makes a link');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2');
set role authenticated;
select tests.fails($$select public.create_staff_invite_link('join.one@example.com', 'tutor')$$, 'parent makes a link');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal1');
set role authenticated;
select tests.fails($$select public.create_staff_invite_link('join.one@example.com', 'tutor')$$, 'admin without two-step login');
reset role;

-- Staff admin: tutor links yes, admin links no.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
insert into tokens values ('tutor1', public.create_staff_invite_link(' Join.One@Example.com ', 'tutor'));
select tests.fails($$select public.create_staff_invite_link('join.admin@example.com', 'admin')$$, 'staff admin makes an admin link');
select tests.fails($$select public.create_staff_invite_link('not-an-email', 'tutor')$$, 'bad email');
select tests.fails($$select public.create_staff_invite_link('join.two@example.com', 'parent')$$, 'parent role link');
-- Someone who already has a confirmed account gets the role directly instead.
select tests.fails($$select public.create_staff_invite_link('owner@clg.example', 'tutor')$$, 'existing account');
reset role;

select tests.eq((select length(token) from tokens where label = 'tutor1'), 64, 'link secret is 64 characters');
select tests.eq((select count(*) from public.invitations where email = 'join.one@example.com' and accepted_at is null and role = 'tutor'), 1, 'invitation recorded, email tidied');
select tests.eq((select count(*) from public.invitations i join tokens t on t.label = 'tutor1' where i.link_hash = t.token), 0, 'link itself is not stored');
select tests.eq((select count(*) from public.invitations where email = 'join.one@example.com' and expires_at between now() + interval '6 days 23 hours' and now() + interval '7 days 1 minute'), 1, 'link lasts 7 days');

-- Anyone holding the link can see what it's for; a wrong or short link shows nothing.
select tests.claims(null);
set role anon;
select tests.eq((select count(*) from public.staff_invite_link_details((select token from tokens where label = 'tutor1')) where status = 'open' and role = 'tutor' and email = 'join.one@example.com'), 1, 'link details for the holder');
select tests.eq((select count(*) from public.staff_invite_link_details(repeat('a', 64))), 0, 'wrong link');
select tests.eq((select count(*) from public.staff_invite_link_details('abc')), 0, 'short link');
select tests.eq((select count(*) from public.staff_invite_link_details(null)), 0, 'no link');
select tests.fails($$select * from public.invitations$$, 'anon reads invitations');
reset role;

-- Sending a new link cancels the old one.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
insert into tokens values ('tutor1b', public.create_staff_invite_link('join.one@example.com', 'tutor'));
reset role;
select tests.eq((select count(*) from public.staff_invite_link_details((select token from tokens where label = 'tutor1'))), 0, 'old link stops working');
select tests.eq((select count(*) from public.staff_invite_link_details((select token from tokens where label = 'tutor1b')) where status = 'open'), 1, 'new link works');
select tests.eq((select count(*) from public.invitations where email = 'join.one@example.com' and accepted_at is null), 1, 'still one invitation per email');

-- Owner: admin links. A staff admin can't replace the owner's admin invitation.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
insert into tokens values ('admin1', public.create_staff_invite_link('join.admin@example.com', 'admin'));
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.fails($$select public.create_staff_invite_link('join.admin@example.com', 'tutor')$$, 'staff admin replaces an admin invitation');
reset role;

-- Joining through the link (the app makes the account with the email
-- already confirmed): the role is given straight away, no approval.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000a1de1', 'join.one@example.com', now(), '{"full_name":"Jo Join"}'),
  ('00000000-0000-0000-0000-0000000a1de2', 'join.admin@example.com', now(), '{"full_name":"Ada Join"}');
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000a1de1' and role = 'tutor'), 1, 'tutor role given on joining');
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000a1de1'), 1, 'only the invited role');
select tests.eq((select count(*) from public.tutor_profiles where account_id = '00000000-0000-0000-0000-0000000a1de1'), 1, 'tutor profile made');
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000a1de2' and role = 'admin'), 1, 'admin role given on joining');
select tests.eq((select count(*) from public.admin_profiles where account_id = '00000000-0000-0000-0000-0000000a1de2' and level = 'operations'), 1, 'new admin is operations level');
select tests.eq((select count(*) from public.staff_invite_link_details((select token from tokens where label = 'tutor1b')) where status = 'used'), 1, 'link used once');

-- A new tutor is not cleared to teach until CLG confirms their checks.
select tests.eq((select count(*) from public.tutor_cleared_states where tutor_id = '00000000-0000-0000-0000-0000000a1de1'), 0, 'new tutor not cleared before checks');

-- An expired link gives nothing.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
insert into tokens values ('late', public.create_staff_invite_link('join.late@example.com', 'tutor'));
reset role;
update public.invitations set expires_at = now() - interval '1 minute' where email = 'join.late@example.com';
select tests.eq((select count(*) from public.staff_invite_link_details((select token from tokens where label = 'late')) where status = 'expired'), 1, 'expired link shows as expired');
select tests.fails($$insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000a1de3', 'join.late@example.com', now(), '{"full_name":"Lee Late"}')$$, 'joining on an expired link');
-- An expired invitation can be replaced with a fresh link.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select length(public.create_staff_invite_link('join.late@example.com', 'tutor'))), 64, 'fresh link after expiry');
reset role;

-- Parents and students still sign up without anyone approving them.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000a1de4', 'join.parent@example.com', '{"signup_as":"parent","full_name":"Pam Open"}');
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000a1de4' and role = 'parent'), 1, 'parent signs up without approval');

select tests.claims(null);
drop table tokens;

\echo '  staff invite links: all checks passed'
