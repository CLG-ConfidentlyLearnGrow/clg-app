-- Admins setting up a family's account: adding a child to a parent's
-- account, finding an account by email, and the policy agreement check.
-- Reuses access_rules.test.sql helpers: admin (...b0), tutor T1 (...11),
-- parents P1 (...01) and P2 (...02).

-- ---------------------------------------------------------------------------
-- Admin adds a child to a parent's account
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Dana Two',
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS',
  '[{"subject": "English", "level": "Year 3"}, {"subject": "General Maths", "level": null}]', 'Enjoy reading', 'Shy at first') as dana \gset
select tests.eq((select count(*) from public.parent_student_links
  where parent_id = '00000000-0000-0000-0000-000000000002' and student_id = :'dana'
    and verified_at is not null and verified_by = '00000000-0000-0000-0000-0000000000b0'), 1, 'admin-made link is already checked');
select tests.eq((select count(*) from public.student_subjects where student_id = :'dana'), 2, 'subjects saved');
select tests.eq((select count(*) from public.student_subjects where student_id = :'dana' and subject = 'English' and working_level = 'Year 3'), 1, 'level saved per subject');
select tests.eq((select count(*) from public.students where id = :'dana' and goals = 'Enjoy reading' and extra_info = 'Shy at first'), 1, 'goal and extra information saved');
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000011', 'Not A Parent',
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[{"subject": "English"}]')$$, 'child for a non-parent account');
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'No Subjects',
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[]')$$, 'child without a subject');
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'No School',
  (current_date - interval '9 years')::date, 'SA', 'Year 4', ' ', '[{"subject": "English"}]')$$, 'child without a school');
select tests.eq((select count(*) from public.admin_find_account('nobody@example.com')), 0, 'unknown email finds nothing');
reset role;

-- The parent sees the child the admin added.
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.students where id = :'dana'), 1, 'parent sees the child');
reset role;

-- A second child joins the same family.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Eli Two',
  (current_date - interval '7 years')::date, 'SA', 'Year 2', 'Hill PS', '[{"subject": "English"}]') as eli \gset
reset role;
select tests.eq((select count(distinct family_id) from public.students where id in (:'dana', :'eli')), 1, 'children share one family');

-- Finding accounts by email (admins only).
select email as p2_email from public.account_private where account_id = '00000000-0000-0000-0000-000000000002' \gset
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.admin_find_account(upper(:'p2_email')) where is_parent), 1, 'admin finds a parent by email, any case');
reset role;

-- ---------------------------------------------------------------------------
-- Nobody else can do this
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0');
set role authenticated;
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'X',
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[{"subject": "English"}]')$$, 'admin without two-step login');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'X',
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[{"subject": "English"}]')$$, 'tutor');
select tests.fails(format('select * from public.admin_find_account(%L)', :'p2_email'), 'tutor looks up an email');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'X',
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[{"subject": "English"}]')$$, 'another parent');
select tests.fails($$select private.add_child_for('00000000-0000-0000-0000-000000000002', null, 'X',
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[{"subject": "English"}]', null, null)$$, 'calling the private helper');
-- Parents adding their own child still works, and stays unchecked.
select public.add_my_child('Fay One', (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Hill PS', '[{"subject": "English"}]') as fay \gset
reset role;
select tests.eq((select count(*) from public.parent_student_links where student_id = :'fay' and verified_at is null), 1, 'parent-made link waits for an admin');

select tests.claims(null);
set role anon;
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'X',
  (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Hill PS', '[{"subject": "English"}]')$$, 'anon');
reset role;

-- ---------------------------------------------------------------------------
-- Agreeing to the privacy policy and terms on first sign-in
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq(public.my_policy_consent('test-v9')::int, 0, 'not agreed yet');
insert into public.consent_records (account_id, kind, document_version)
values ('00000000-0000-0000-0000-000000000002', 'privacy_policy', 'test-v9');
select tests.eq(public.my_policy_consent('test-v9')::int, 0, 'privacy policy alone is not enough');
insert into public.consent_records (account_id, kind, document_version)
values ('00000000-0000-0000-0000-000000000002', 'terms_of_service', 'test-v9');
select tests.eq(public.my_policy_consent('test-v9')::int, 1, 'agreed to both');
select tests.fails($$insert into public.consent_records (account_id, kind, document_version)
  values ('00000000-0000-0000-0000-000000000001', 'privacy_policy', 'test-v9')$$, 'agreeing for someone else');
reset role;

-- Clean up so later test files see the original fixtures.
delete from public.students where id in (:'dana', :'eli', :'fay');
delete from public.consent_records where document_version = 'test-v9';
