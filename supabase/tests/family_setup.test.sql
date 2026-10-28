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
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', ' ',
  null, null, null, null, null)$$, 'child without a name');
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Bad Date',
  (current_date + 1), null, null, null, null)$$, 'child born in the future');
select tests.fails($$select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Bad Year',
  null, null, 'Grade 4', null, null)$$, 'unknown year level');
-- Only the name: the family fills in the rest.
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Gus Two', null, null, null, null, null) as gus \gset
select tests.eq((select count(*) from public.students where id = :'gus' and date_of_birth is null and state is null and year_level is null and school is null), 1, 'child with only a name');
select tests.eq(private.student_details_complete(:'gus')::int, 0, 'details not finished');
select tests.eq(private.student_details_complete(:'dana')::int, 1, 'full details are finished');
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

-- ---------------------------------------------------------------------------
-- The family finishes the details; no tutor until they do
-- ---------------------------------------------------------------------------
create or replace function tests.fails_with(p_sql text, p_words text, p_label text) returns void
language plpgsql as $f$
begin
  execute p_sql;
  raise exception 'Expected failure but it succeeded: %', p_label;
exception when others then
  if sqlerrm like 'Expected failure%' then raise; end if;
  if position(p_words in sqlerrm) = 0 then
    raise exception 'FAIL %: wrong error: %', p_label, sqlerrm;
  end if;
end;
$f$;
select tests.fails_with(format($$insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-000000000011', %L, 'English')$$, :'gus'),
  'details aren''t finished', 'no tutor before details are finished');
select tests.fails_with(format($$insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date)
  values (%L, '00000000-0000-0000-0000-000000000011', 'English', 1, '16:00', 60, 'online', current_date, current_date + 7)$$, :'gus'),
  'details aren''t finished', 'no booking before details are finished');

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.fails(format($$update public.students set date_of_birth = current_date + 1 where id = %L$$, :'gus'), 'parent gives a future birthday');
update public.students set date_of_birth = (current_date - interval '8 years')::date, state = 'SA', year_level = 'Year 3', school = 'Hill PS' where id = :'gus';
select tests.eq((select count(*) from public.students where id = :'gus' and state = 'SA' and date_of_birth is not null), 1, 'parent fills in birthday and state');
select tests.fails(format($$update public.students set date_of_birth = (current_date - interval '9 years')::date where id = %L$$, :'gus'), 'parent changes birthday once given');
select tests.fails(format($$update public.students set state = 'VIC' where id = %L$$, :'gus'), 'parent changes state once given');
select tests.fails(format($$update public.students set year_level = null where id = %L$$, :'gus'), 'parent clears the year level');
reset role;
select tests.eq(private.student_details_complete(:'gus')::int, 1, 'details finished by the family');

-- Clean up so later test files see the original fixtures.
delete from public.students where id in (:'dana', :'eli', :'fay', :'gus');
delete from public.consent_records where document_version = 'test-v9';
