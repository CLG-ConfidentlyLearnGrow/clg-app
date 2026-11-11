-- Access rule tests. Run with scripts/test-db.sh.
-- Each check raises an error (and stops the run) if a rule is broken.

create schema tests; -- A separate area for the test helpers.
grant usage on schema tests to anon, authenticated, service_role; -- Lets all three roles use it.

-- Sign in as someone for the following statements (claims as Supabase sets them).
create function tests.claims(p_user uuid, p_aal text default 'aal1') returns void -- Test helper: signs in as someone (one-step sign-in unless told otherwise).
language sql as $$ -- (written in SQL)
  select set_config('request.jwt.claims', -- Sets the "who is signed in" details:
    json_build_object('sub', p_user, 'role', 'authenticated', 'aal', p_aal)::text, false) -- their id, the signed-in role, and how they signed in.
$$; -- (end of the helper)

-- Asserts that a statement fails.
create function tests.fails(p_sql text, p_label text) returns void -- Test helper: checks that a statement is refused.
language plpgsql as $$ -- (written in PL/pgSQL)
begin -- Starts the helper.
  begin -- Starts an inner block, so a refusal can be caught.
    execute p_sql; -- Runs the statement.
  exception when others then -- If it was refused:
    return; -- that's a pass, so stop here.
  end; -- End of the inner block.
  raise exception 'Expected failure but it succeeded: %', p_label; -- It worked, which is a failure: stops with the label.
end; -- End of the helper.
$$; -- (end of its code)

create function tests.eq(p_actual bigint, p_expected bigint, p_label text) returns void -- Test helper: checks a number is what's expected.
language plpgsql as $$ -- (written in PL/pgSQL)
begin -- Starts the helper.
  if p_actual is distinct from p_expected then -- If the numbers differ,
    raise exception 'FAIL %: expected %, got %', p_label, p_expected, p_actual; -- stops, showing both numbers and the label.
  end if; -- End of the comparison.
end; -- End of the helper.
$$; -- (end of its code)
grant execute on all functions in schema tests to anon, authenticated, service_role; -- Lets all three roles use the helpers.

-- Ids used below
--   owner  ...a0   staff admin ...b0   tutor T1 ...11   tutor T2 ...12
--   parent P1 ...01  parent P2 ...02  adult learner ...21

-- ===========================================================================
-- Sign-up rules
-- ===========================================================================

-- Owner bootstrap through an invitation.
select private.create_owner_invitation('Owner@CLG.example'); -- Makes the one-off owner invite (with capitals, to be tidied).
insert into auth.users (id, email, invited_at, raw_user_meta_data) -- The owner signs up from the invite:
values ('00000000-0000-0000-0000-0000000000a0', 'owner@clg.example', now(), '{"full_name":"Olive Owner"}'); -- (Olive Owner).
select tests.eq((select count(*) from public.admin_profiles), 0, 'no admin role before email confirmed'); -- Checks: no admin role before email confirmed.
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-0000000000a0'; -- The owner confirms their email.
select tests.eq((select count(*) from public.admin_profiles where level = 'owner'), 1, 'owner created on confirmation'); -- Checks: owner created on confirmation.
select tests.fails($$select private.create_owner_invitation('second@clg.example')$$, 'only one owner bootstrap'); -- Checks this is refused: only one owner bootstrap.

-- Parents sign up openly.
insert into auth.users (id, email, raw_user_meta_data) values -- Adds two parents:
  ('00000000-0000-0000-0000-000000000001', 'p1@example.com', '{"signup_as":"parent","full_name":"Pat One","accepted_policies_version":"2026-10"}'), -- Pat (parent P1), who agreed to the policies at sign-up,
  ('00000000-0000-0000-0000-000000000002', 'p2@example.com', '{"signup_as":"parent","full_name":"Pip Two"}'); -- and Pip (parent P2).
select tests.eq((select count(*) from public.parent_profiles), 2, 'two parents'); -- Checks: two parents.
select tests.eq((select count(*) from public.consent_records where account_id = '00000000-0000-0000-0000-000000000001'), 2, 'sign-up consent recorded'); -- Checks: sign-up consent recorded.

-- Typed metadata cannot make someone a tutor or admin.
select tests.fails($$insert into auth.users (email, raw_user_meta_data) values ('x@example.com', '{"signup_as":"tutor"}')$$, 'self sign-up as tutor'); -- Checks this is refused: self sign-up as tutor.
select tests.fails($$insert into auth.users (email, raw_user_meta_data) values ('x@example.com', '{"signup_as":"admin"}')$$, 'self sign-up as admin'); -- Checks this is refused: self sign-up as admin.
select tests.fails($$insert into auth.users (email) values ('x@example.com')$$, 'sign-up with no type'); -- Checks this is refused: sign-up with no type.
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data) values -- Someone tries to make themselves an admin at sign-up:
  ('00000000-0000-0000-0000-000000000099', 'sneaky@example.com', '{"role":"admin","invited_role":"admin"}', '{"signup_as":"parent","role":"admin","invited_role":"admin"}'); -- (by adding admin to their sign-up details).
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-000000000099' and role <> 'parent'), 0, 'role smuggled in metadata is ignored'); -- Checks: role smuggled in metadata is ignored.

-- Students 16 or over sign up alone; under-16s cannot.
select tests.fails($$insert into auth.users (email, raw_user_meta_data) values ('teen@example.com', json_build_object('signup_as','learner','state','SA','year_level','Year 10','school','Unley High','date_of_birth', (current_date - interval '16 years' + interval '1 day')::date))$$, 'learner under 16'); -- Checks this is refused: learner under 16.
insert into auth.users (id, email, raw_user_meta_data) values -- A 16-year-old signs up as a learner:
  ('00000000-0000-0000-0000-000000000022', 'sixteen@example.com', -- (account ...22),
   json_build_object('signup_as', 'learner', 'full_name', 'Sam Sixteen', 'state', 'SA', 'year_level', 'Year 11', 'school', 'Unley High', -- Sam, Year 11 in SA,
                     'date_of_birth', (current_date - interval '16 years')::date)); -- born 16 years ago.
select tests.eq((select count(*) from public.students where account_id = '00000000-0000-0000-0000-000000000022'), 1, 'student aged 16 can sign up alone'); -- Checks: student aged 16 can sign up alone.
delete from public.students where account_id = '00000000-0000-0000-0000-000000000022'; -- Removes Sam's student record.
select tests.fails($$insert into auth.users (email, raw_user_meta_data) values ('nostate@example.com', json_build_object('signup_as','learner','date_of_birth', (current_date - interval '30 years')::date))$$, 'learner without state'); -- Checks this is refused: learner without state.
select tests.fails($$insert into auth.users (email, raw_user_meta_data) values ('bad@example.com', '{"signup_as":"learner","date_of_birth":"not a date"}')$$, 'learner bad date'); -- Checks this is refused: learner bad date.
select tests.fails($$insert into auth.users (email, raw_user_meta_data) values ('noyear@example.com', json_build_object('signup_as','learner','state','SA','school','Uni SA','date_of_birth', (current_date - interval '30 years')::date))$$, 'learner without year level'); -- Checks this is refused: learner without year level.
select tests.fails($$insert into auth.users (email, raw_user_meta_data) values ('noschool@example.com', json_build_object('signup_as','learner','state','SA','year_level','Adult learner','date_of_birth', (current_date - interval '30 years')::date))$$, 'learner without school'); -- Checks this is refused: learner without school.
insert into auth.users (id, email, raw_user_meta_data) values -- A 30-year-old signs up as a learner:
  ('00000000-0000-0000-0000-000000000021', 'adult@example.com', -- (account ...21),
   json_build_object('signup_as', 'learner', 'full_name', 'Ada Learner', 'state', 'SA', 'year_level', 'University or TAFE', 'school', 'TAFE SA', -- Ada, at TAFE in SA,
                     'date_of_birth', (current_date - interval '30 years')::date)); -- born 30 years ago.
select tests.eq((select count(*) from public.students where account_id = '00000000-0000-0000-0000-000000000021'), 1, 'adult learner has a student record'); -- Checks: adult learner has a student record.

-- ===========================================================================
-- Admin invitations
-- ===========================================================================

-- Without two-step login the owner has no admin powers.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal1'); -- Signs in as test account ...a0.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$insert into public.invitations (email, role, invited_by) values ('t1@clg.example', 'tutor', '00000000-0000-0000-0000-0000000000a0')$$, 'invite without aal2'); -- Checks this is refused: invite without aal2.
select tests.eq((select count(*) from public.students), 0, 'admin without aal2 sees no students'); -- Checks: admin without aal2 sees no students.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.invitations (email, role, invited_by) values -- The owner invites three staff:
  ('t1@clg.example', 'tutor', '00000000-0000-0000-0000-0000000000a0'), -- tutor T1,
  ('t2@clg.example', 'tutor', '00000000-0000-0000-0000-0000000000a0'), -- tutor T2,
  ('staff@clg.example', 'admin', '00000000-0000-0000-0000-0000000000a0'); -- and a staff admin.
select tests.eq((select count(*) from public.students), 1, 'admin with aal2 sees all students'); -- Checks: admin with aal2 sees all students.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Someone self-signing-up with an invited email gets no role until that
-- inbox confirms; their parent or admin request in the metadata is ignored.
insert into auth.users (id, email, raw_user_meta_data) values -- Tutor T1 signs up, choosing "parent" by mistake:
  ('00000000-0000-0000-0000-000000000011', 't1@clg.example', '{"signup_as":"parent","full_name":"Tess Tutor"}'); -- (Tess Tutor).
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-000000000011'), 0, 'no role before confirmation'); -- Checks: no role before confirmation.

-- Admin invites (Supabase sets invited_at after the insert).
insert into auth.users (id, email, raw_user_meta_data) values -- Tutor T2 and the staff admin sign up from their invites:
  ('00000000-0000-0000-0000-000000000012', 't2@clg.example', '{"full_name":"Tom Tutor"}'), -- Tom (tutor T2),
  ('00000000-0000-0000-0000-0000000000b0', 'staff@clg.example', '{"full_name":"Sam Staff"}'); -- Sam (staff admin).
update auth.users set invited_at = now() where email in ('t2@clg.example', 'staff@clg.example'); -- Marks them as invited.
select tests.eq((select count(*) from public.tutor_profiles), 0, 'no tutor role before invite accepted'); -- Checks: no tutor role before invite accepted.
update auth.users set email_confirmed_at = now() -- All three confirm their emails:
  where email in ('t1@clg.example', 't2@clg.example', 'staff@clg.example'); -- (the three staff emails).
select tests.eq((select count(*) from public.tutor_profiles), 2, 'tutors created when invitations accepted'); -- Checks: tutors created when invitations accepted.
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-000000000011'), 1, 'invited tutor has only the tutor role'); -- Checks: invited tutor has only the tutor role.
select tests.eq((select count(*) from public.admin_profiles where level = 'operations'), 1, 'staff admin created as operations'); -- Checks: staff admin created as operations.
select tests.eq((select count(*) from public.invitations where accepted_at is null and email like 't%'), 0, 'invitations marked accepted'); -- Checks: invitations marked accepted.
select tests.fails($$insert into auth.users (email, invited_at) values ('nobody@clg.example', now())$$, 'invite with no invitation'); -- Checks this is refused: invite with no invitation.
-- Confirming an email later does not re-use an accepted invitation.
insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-000000000098', 'later@example.com', '{"signup_as":"parent"}'); -- Someone signs up as a parent with no name.
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-000000000098'; -- They confirm their email.
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-000000000098'), 1, 'ordinary confirmation grants nothing extra'); -- Checks: ordinary confirmation grants nothing extra.

-- Staff admins cannot invite or create admins.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$insert into public.invitations (email, role, invited_by) values ('a2@clg.example', 'admin', '00000000-0000-0000-0000-0000000000b0')$$, 'staff invites admin'); -- Checks this is refused: staff invites admin.
select tests.fails($$insert into public.account_roles (account_id, role) values ('00000000-0000-0000-0000-000000000001', 'admin')$$, 'staff grants admin'); -- Checks this is refused: staff grants admin.
insert into public.invitations (email, role, invited_by) values ('t3@clg.example', 'tutor', '00000000-0000-0000-0000-0000000000b0'); -- Tries to invite another tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Parents and children
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.add_my_child('Cara One', (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Hill PS', '[{"subject": "General Maths", "level": "Year 5"}]'); -- Parent P1 adds a child, Cara, 10, Year 5, General Maths.
select tests.eq((select count(*) from public.students), 1, 'P1 sees own child'); -- Checks: P1 sees own child.
select tests.eq((select count(*) from public.families), 1, 'P1 sees own family'); -- Checks: P1 sees own family.
-- Escalation attempts
select tests.fails($$insert into public.account_roles (account_id, role) values ('00000000-0000-0000-0000-000000000001', 'admin')$$, 'parent grants self admin'); -- Checks this is refused: parent grants self admin.
select tests.fails($$insert into public.students (full_name, date_of_birth) values ('X', '2015-01-01')$$, 'parent inserts student directly'); -- Checks this is refused: parent inserts student directly.
select tests.fails($$update public.students set account_id = '00000000-0000-0000-0000-000000000001'$$, 'parent attaches login to child'); -- Checks this is refused: parent attaches login to child.
select tests.fails($$update public.students set date_of_birth = current_date - interval '20 years'$$, 'parent changes child date of birth'); -- Checks this is refused: parent changes child date of birth.
select tests.fails($$insert into public.parent_student_links (parent_id, student_id) select '00000000-0000-0000-0000-000000000001', id from public.students$$, 'parent creates own link'); -- Checks this is refused: parent creates own link.
select tests.eq((select count(*) from public.audit_log), 0, 'parent sees no audit rows'); -- Checks: parent sees no audit rows.
select tests.fails($$update public.students set state = 'VIC'$$, 'parent changes child state'); -- Checks this is refused: parent changes child state.
update public.students set year_level = 'Year 6'; -- Tries to change the year level.
select tests.fails($$update public.students set year_level = null$$, 'parent clears year level'); -- Checks this is refused: parent clears year level.
select tests.fails($$update public.students set school = ''$$, 'parent clears school'); -- Checks this is refused: parent clears school.
select tests.fails($$update public.students set year_level = 'Grade 6'$$, 'parent sets unknown year level'); -- Checks this is refused: parent sets unknown year level.
select tests.eq((select count(*) from public.students where year_level = 'Year 6'), 1, 'parent edits child details'); -- Checks: parent edits child details.
-- Consent for own child only
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset
insert into public.consent_records (account_id, student_id, kind, document_version) -- Records parent P1's consent for Cara:
select '00000000-0000-0000-0000-000000000001', id, 'parental_consent', '2026-10' from public.students; -- (for each student).
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.add_my_child('No Year', (current_date - interval '12 years')::date, 'SA')$$, 'child without year level'); -- Checks this is refused: child without year level.
select tests.fails($$select public.add_my_child('Bad Year', (current_date - interval '12 years')::date, 'SA', 'Grade 7', 'Hill PS')$$, 'child with unknown year level'); -- Checks this is refused: child with unknown year level.
select tests.fails($$select public.add_my_child('No School', (current_date - interval '12 years')::date, 'SA', 'Year 7', '  ')$$, 'child without school'); -- Checks this is refused: child without school.
select public.add_my_child('Cal Two', (current_date - interval '12 years')::date, 'SA', 'Year 7', 'Hill PS', '[{"subject": "English"}]'); -- Parent P2 adds Cal, 12, Year 7, English.
select public.add_my_child('Vic Two', (current_date - interval '9 years')::date, 'VIC', 'Year 4', 'Bay PS', '[{"subject": "English"}]'); -- Parent P2 adds Vic, 9, Year 4 in Victoria.
select tests.eq((select count(*) from public.students), 2, 'P2 sees only own children'); -- Checks: P2 sees only own children.
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-000000000001'), 0, 'P2 cannot see P1'); -- Checks: P2 cannot see P1.
select tests.eq((select count(*) from public.account_private), 1, 'P2 sees only own contact details'); -- Checks: P2 sees only own contact details.
select tests.fails(format($$insert into public.consent_records (account_id, student_id, kind, document_version) -- Checks parent P2 can't consent for parent P1's child:
  values ('00000000-0000-0000-0000-000000000002', %L, 'parental_consent', 'x')$$, :'cara'), 'P2 consents for P1 child'); -- (the label).
update public.students set full_name = 'Hacked' where id = :'cara'; -- Tries to rename Cara.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.eq((select count(*) from public.students where full_name = 'Hacked'), 0, 'P2 cannot edit P1 child'); -- Checks: P2 cannot edit P1 child.

-- Under-16s cannot have their own login; 16 and over can.
select tests.claims(null); -- Signs out, so no one is signed in.
insert into auth.users (id, email, raw_user_meta_data) values -- Adds a test account for a teenager:
  ('00000000-0000-0000-0000-000000000031', 'teen@example.com', '{"signup_as":"parent"}'); -- (account ...31).
select tests.fails($$update public.students set account_id = '00000000-0000-0000-0000-000000000031', date_of_birth = current_date - interval '15 years 11 months' where full_name = 'Cara One'$$, 'login for a 15-year-old'); -- Checks this is refused: login for a 15-year-old.
update public.students set account_id = '00000000-0000-0000-0000-000000000031', date_of_birth = current_date - interval '16 years 1 month' where full_name = 'Cal Two'; -- Gives Cal that login and makes him 16.
update public.students set account_id = null, date_of_birth = current_date - interval '12 years' where full_name = 'Cal Two'; -- Takes it away and makes him 12 again.


-- ===========================================================================
-- Tutor assignment and clearance
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- No checks yet: assignment refused.
select tests.fails($$insert into public.tutor_assignments (tutor_id, student_id, subject) -- Checks a tutor with no checks can't be assigned:
  select '00000000-0000-0000-0000-000000000011', id, 'General Maths' from public.students where full_name = 'Cara One'$$, 'assign uncleared tutor'); -- (tutor T1 to Cara).
-- What the tutors teach (see tutor_teaching.test.sql for the rules).
insert into public.tutor_teaching (tutor_id, subject, from_level, to_level) values -- Adds what the tutors teach:
  ('00000000-0000-0000-0000-000000000011', 'General Maths', 'Year 3', 'Year 6'), -- tutor T1, General Maths, Years 3 to 6,
  ('00000000-0000-0000-0000-000000000011', 'English', 'University or TAFE', 'Adult learner'), -- tutor T1, English, university to adult,
  ('00000000-0000-0000-0000-000000000012', 'Science', 'Year 1', 'Year 6'), -- tutor T2, Science, Years 1 to 6,
  ('00000000-0000-0000-0000-000000000012', 'General Maths', 'Year 1', 'Year 12'); -- tutor T2, General Maths, Years 1 to 12.
insert into public.tutor_checks (tutor_id, kind, reference, expires_on) values -- Adds tutor T1's checks:
  ('00000000-0000-0000-0000-000000000011', 'wwcc_sa', 'WWCC-123', current_date + 365), -- SA WWCC,
  ('00000000-0000-0000-0000-000000000011', 'rrhan_ec_fundamentals', null, current_date + 365), -- RRHAN-EC Fundamentals,
  ('00000000-0000-0000-0000-000000000011', 'rrhan_ec_masterclass', null, current_date + 365); -- and Masterclass, each for a year.
select tests.eq((select count(*) from public.tutor_checks where verified_by = '00000000-0000-0000-0000-0000000000a0'), 3, 'checks stamped with verifier'); -- Checks: checks stamped with verifier.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq(private.tutor_cleared_for_state('00000000-0000-0000-0000-000000000011', 'SA')::int, 1, 'cleared without a police check (no longer required)'); -- Checks: cleared without a police check (no longer required).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- A police check is optional. If recorded, it needs its issue date and
-- counts for 5 years from it.
select tests.fails($$insert into public.tutor_checks (tutor_id, kind, reference, expires_on) values -- Checks a police check without an issue date is refused:
  ('00000000-0000-0000-0000-000000000011', 'police_check', 'NPC-1', current_date + 365)$$, 'police check without issue date'); -- (the label).
insert into public.tutor_checks (tutor_id, kind, reference, completed_on, expires_on) values -- Adds an old police check:
  ('00000000-0000-0000-0000-000000000011', 'police_check', 'NPC-OLD', current_date - 365 * 6, current_date + 999); -- (issued 6 years ago).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq(private.tutor_cleared_for_state('00000000-0000-0000-0000-000000000011', 'SA')::int, 1, 'an old police check does not block clearance'); -- Checks: an old police check does not block clearance.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.tutor_checks (tutor_id, kind, reference, completed_on, expires_on) values -- Adds a newer police check:
  ('00000000-0000-0000-0000-000000000011', 'police_check', 'NPC-2', current_date - 365 * 4, current_date + 999); -- (issued 4 years ago).
select tests.eq((select count(*) from public.tutor_checks where reference = 'NPC-2' and expires_on = completed_on + interval '5 years'), 1, 'police check expiry set from issue date'); -- Checks: police check expiry set from issue date.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq(private.tutor_cleared_for_state('00000000-0000-0000-0000-000000000011', 'SA')::int, 1, 'still cleared with a recent police check'); -- Checks: still cleared with a recent police check.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Cleared, but the parent link is not verified (parents' own links are now
-- confirmed straight away, so undo that here to test the rule).
update public.parent_student_links set verified_at = null -- Makes Cara's parent link unconfirmed:
  where student_id = (select id from public.students where full_name = 'Cara One'); -- (for Cara).
select tests.fails($$insert into public.tutor_assignments (tutor_id, student_id, subject) -- Checks a tutor can't be assigned before the parent link is confirmed:
  select '00000000-0000-0000-0000-000000000011', id, 'General Maths' from public.students where full_name = 'Cara One'$$, 'assign before parent link verified'); -- (the label).
update public.parent_student_links set verified_at = now() -- Confirms the link again:
  where student_id = (select id from public.students where full_name = 'Cara One'); -- (for Cara).
select tests.eq((select count(*) from public.parent_student_links where verified_by = '00000000-0000-0000-0000-0000000000a0'), 1, 'link verification stamped'); -- Checks: link verification stamped.
insert into public.tutor_assignments (tutor_id, student_id, subject) -- Assigns tutor T1 to Cara:
  select '00000000-0000-0000-0000-000000000011', id, 'General Maths' from public.students where full_name = 'Cara One'; -- (General Maths).
-- An adult learner needs no parent link.
insert into public.tutor_assignments (tutor_id, student_id, subject) -- Assigns tutor T1 to Ada:
  select '00000000-0000-0000-0000-000000000011', id, 'English' from public.students where full_name = 'Ada Learner'; -- (English).
select tests.eq((select count(*) from public.tutor_check_status where status = 'current'), 4, 'check status view'); -- Checks: check status view.
-- T2 works from Victoria: the Victorian check is needed and missing.
update public.tutor_work_settings set work_state = 'VIC' where tutor_id = '00000000-0000-0000-0000-000000000012'; -- Tutor T2 works in Victoria.
select tests.eq((select count(*) from public.tutor_check_status where tutor_id = '00000000-0000-0000-0000-000000000012' and status = 'missing'), 1, 'T2 VIC check missing (police check not required)'); -- Checks: T2 VIC check missing (police check not required).
-- State matching: T1 holds SA checks only, so cannot take a Victorian student.
update public.parent_student_links set verified_at = now(); -- Confirms all parent links.
select tests.fails($$insert into public.tutor_assignments (tutor_id, student_id, subject) -- Checks an SA-only tutor can't teach a Victorian student:
  select '00000000-0000-0000-0000-000000000011', id, 'General Maths' from public.students where full_name = 'Vic Two'$$, 'SA-only tutor for VIC student'); -- (tutor T1 and Vic).
insert into public.tutor_checks (tutor_id, kind, reference, completed_on, expires_on) values -- Adds tutor T2's checks:
  ('00000000-0000-0000-0000-000000000012', 'wwc_vic', 'VIC-9', null, current_date + 365), -- Victorian WWC,
  ('00000000-0000-0000-0000-000000000012', 'police_check', 'NPC-3', current_date - 30, null), -- a police check,
  -- RRHAN-EC is needed for students in every state (2 Nov 2026).
  ('00000000-0000-0000-0000-000000000012', 'rrhan_ec_fundamentals', null, current_date - 30, null), -- RRHAN-EC Fundamentals,
  ('00000000-0000-0000-0000-000000000012', 'rrhan_ec_masterclass', null, current_date - 30, null); -- and Masterclass.
insert into public.tutor_assignments (tutor_id, student_id, subject) -- Assigns tutor T2 to Vic:
  select '00000000-0000-0000-0000-000000000012', id, 'Science' from public.students where full_name = 'Vic Two'; -- (Science).
select tests.fails($$insert into public.tutor_assignments (tutor_id, student_id, subject) -- Checks a Victoria-only tutor can't teach an SA student:
  select '00000000-0000-0000-0000-000000000012', id, 'General Maths' from public.students where full_name = 'Cal Two'$$, 'VIC-only tutor for SA student'); -- (tutor T2 and Cal).
select tests.eq((select count(*) from public.eligible_tutors((select id from public.students where full_name = 'Vic Two'))), 1, 'eligible tutors for VIC student'); -- Checks: eligible tutors for VIC student.
select tests.eq((select count(*) from public.eligible_tutors((select id from public.students where full_name = 'Cara One'))), 1, 'eligible tutors for SA student'); -- Checks: eligible tutors for SA student.
select tests.eq((select count(*) from public.tutor_cleared_states where tutor_id = '00000000-0000-0000-0000-000000000011'), 1, 'T1 cleared for SA only'); -- Checks: T1 cleared for SA only.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Tutor without two-step login sees no students.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- Signs in as test account ...11.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students), 0, 'tutor aal1 sees nothing'); -- Checks: tutor aal1 sees nothing.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students), 2, 'tutor sees assigned students only'); -- Checks: tutor sees assigned students only.
select tests.eq((select count(*) from public.students where full_name = 'Cal Two'), 0, 'tutor cannot see unassigned child'); -- Checks: tutor cannot see unassigned child.
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-000000000001'), 1, 'tutor sees parent name'); -- Checks: tutor sees parent name.
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-000000000002'), 0, 'tutor cannot see other parent'); -- Checks: tutor cannot see other parent.
select tests.eq((select count(*) from public.account_private), 1, 'tutor sees no family contact details'); -- Checks: tutor sees no family contact details.
select tests.eq((select count(*) from public.parent_profiles), 0, 'tutor sees no parent profiles'); -- Checks: tutor sees no parent profiles.
select tests.fails($$update public.tutor_profiles set active = false where account_id = '00000000-0000-0000-0000-000000000011'$$, 'tutor changes own active flag'); -- Checks this is refused: tutor changes own active flag.
update public.tutor_profiles set bio = 'Maths specialist' where account_id = '00000000-0000-0000-0000-000000000011'; -- Tries to change tutor T1's bio.
-- Availability and weekly hours are the tutor's own, and separate.
update public.tutor_work_settings set max_weekly_hours = 12 where tutor_id = '00000000-0000-0000-0000-000000000011'; -- Sets tutor T1's weekly maximum to 12 hr.
insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at) -- Adds tutor T1's Monday availability:
  values ('00000000-0000-0000-0000-000000000011', 1, '15:30', '19:00'); -- 3:30pm to 7pm.
select tests.fails($$update public.tutor_work_settings set work_state = 'NSW' where tutor_id = '00000000-0000-0000-0000-000000000011'$$, 'tutor changes own work state'); -- Checks this is refused: tutor changes own work state.
select tests.fails($$insert into public.tutor_availability (tutor_id, weekday, starts_at, ends_at) values ('00000000-0000-0000-0000-000000000012', 1, '09:00', '10:00')$$, 'tutor edits another tutor availability'); -- Checks this is refused: tutor edits another tutor availability.
select tests.fails($$select public.eligible_tutors(gen_random_uuid())$$, 'tutor lists eligible tutors'); -- Checks this is refused: tutor lists eligible tutors.
-- A tutor may add their own check, but it waits for an admin (see tutor_checks.test.sql).
insert into storage.objects (bucket_id, name) values ('check-documents', '00000000-0000-0000-0000-000000000011/self.pdf'); -- Adds a file to storage, as if uploaded.
insert into public.tutor_checks (tutor_id, kind, reference, expires_on, document_path) values ('00000000-0000-0000-0000-000000000011', 'wwcc_sa', 'SELF', current_date + 999, '00000000-0000-0000-0000-000000000011/self.pdf'); -- Adds a check pointing at that file.
select tests.eq((select count(*) from public.tutor_checks where reference = 'SELF' and verified_at is not null), 0, 'tutor cannot verify own check'); -- Checks: tutor cannot verify own check.
select tests.fails($$insert into public.tutor_assignments (tutor_id, student_id, subject) select '00000000-0000-0000-0000-000000000011', id, 'x' from public.students limit 1$$, 'tutor assigns self'); -- Checks this is refused: tutor assigns self.
reset role; -- Goes back to the all-powerful test user (access rules off).
delete from public.tutor_checks where reference = 'SELF'; -- Removes the check.
delete from storage.objects where name = '00000000-0000-0000-0000-000000000011/self.pdf'; -- Removes the file.

-- Parents see their child's tutor; other parents do not.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-000000000011'), 1, 'P1 sees tutor name'); -- Checks: P1 sees tutor name.
select tests.eq((select count(*) from public.tutor_profiles where bio = 'Maths specialist'), 1, 'P1 sees tutor bio'); -- Checks: P1 sees tutor bio.
select tests.eq((select count(*) from public.tutor_assignments), 1, 'P1 sees own child assignment only'); -- Checks: P1 sees own child assignment only.
select tests.eq((select count(*) from public.tutor_checks), 0, 'P1 cannot see tutor checks'); -- Checks: P1 cannot see tutor checks.
select tests.eq((select count(*) from public.tutor_work_settings), 0, 'P1 cannot see tutor hours'); -- Checks: P1 cannot see tutor hours.
select tests.eq((select count(*) from public.tutor_availability), 0, 'P1 cannot see tutor availability'); -- Checks: P1 cannot see tutor availability.
select tests.fails($$insert into public.check_requirements values ('SA', 'wwc_vic', 'student_state')$$, 'parent edits check rules'); -- Checks this is refused: parent edits check rules.
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-000000000012'), 0, 'P1 cannot see unrelated tutor'); -- Checks: P1 cannot see unrelated tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-000000000011'), 0, 'P2 cannot see T1'); -- Checks: P2 cannot see T1.
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-0000000000a0'), 1, 'P2 sees admin name'); -- Checks: P2 sees admin name.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Sensitive records
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.save_student_sensitive((select id from public.students where full_name = 'Cara One'), 'Dyslexia', 'Coloured overlays'); -- Saves Cara's learning needs and adjustments.
select tests.fails($$select * from public.student_sensitive$$, 'direct read of sensitive table'); -- Checks this is refused: direct read of sensitive table.
select tests.eq((select count(*) from public.read_student_sensitive((select id from public.students where full_name = 'Cara One'))), 1, 'parent reads sensitive via function'); -- Checks: parent reads sensitive via function.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.read_student_sensitive((select id from public.students where full_name = 'Cara One'))), 1, 'tutor reads sensitive via function'); -- Checks: tutor reads sensitive via function.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format('select * from public.read_student_sensitive(%L)', :'cara'), 'P2 reads P1 child sensitive'); -- Checks this is refused: P2 reads P1 child sensitive.
select tests.fails(format('select public.save_student_sensitive(%L, %L, %L)', :'cara', 'x', 'x'), 'P2 writes P1 child sensitive'); -- Checks this is refused: P2 writes P1 child sensitive.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.eq((select count(*) from public.audit_log where table_name = 'student_sensitive' and action = 'view'), 2, 'sensitive views logged'); -- Checks: sensitive views logged.
select tests.eq((select count(*) from public.audit_log where details::text ilike '%dyslexia%'), 0, 'audit log holds no sensitive content'); -- Checks: audit log holds no sensitive content.

-- Audit log cannot be altered, even by an admin.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$delete from public.audit_log$$, 'admin deletes audit log'); -- Checks this is refused: admin deletes audit log.
select tests.fails($$update public.audit_log set action = 'x'$$, 'admin edits audit log'); -- Checks this is refused: admin edits audit log.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- ===========================================================================
-- Check expiry removes tutor access
-- ===========================================================================

update public.tutor_checks set expires_on = current_date - 1 -- Makes tutor T1's SA WWCC expired:
  where tutor_id = '00000000-0000-0000-0000-000000000011' and kind = 'wwcc_sa'; -- (for tutor T1).
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students), 0, 'expired WWCC removes access'); -- Checks: expired WWCC removes access.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.accounts where id = '00000000-0000-0000-0000-000000000011'), 0, 'parent no longer sees uncleared tutor'); -- Checks: parent no longer sees uncleared tutor.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- A tutor working from another state also needs that state's check.
update public.tutor_checks set expires_on = current_date + 365 -- Renews it:
  where tutor_id = '00000000-0000-0000-0000-000000000011' and kind = 'wwcc_sa'; -- (for tutor T1).
update public.tutor_work_settings set work_state = 'VIC' where tutor_id = '00000000-0000-0000-0000-000000000011'; -- Tutor T1 now works in Victoria.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students), 0, 'interstate tutor needs own state check too'); -- Checks: interstate tutor needs own state check too.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
insert into public.tutor_checks (tutor_id, kind, reference, expires_on, verified_at) values -- Adds a confirmed Victorian WWC for tutor T1:
  ('00000000-0000-0000-0000-000000000011', 'wwc_vic', 'VIC-1', current_date + 365, now()); -- (for a year).
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students), 2, 'access back once both checks held'); -- Checks: access back once both checks held.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- ===========================================================================
-- Signed-out visitors and account lock
-- ===========================================================================

set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.students$$, 'anon reads students'); -- Checks this is refused: anon reads students.
select tests.fails($$select * from public.accounts$$, 'anon reads accounts'); -- Checks this is refused: anon reads accounts.
select tests.fails($$select public.add_my_child('x', current_date, 'SA')$$, 'anon calls add_my_child'); -- Checks this is refused: anon calls add_my_child.
select tests.fails($$select public.record_login_attempt('p1@example.com', false)$$, 'anon records attempts'); -- Checks this is refused: anon records attempts.
reset role; -- Goes back to the all-powerful test user (access rules off).

set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select public.login_lock_status('p1@example.com')$$, 'browser checks lock'); -- Checks this is refused: browser checks lock.
reset role; -- Goes back to the all-powerful test user (access rules off).

set role service_role; -- Acts as the server's own key.
select public.record_login_attempt('P1@example.com', false) from generate_series(1, 4); -- Four wrong passwords for parent P1.
select tests.eq((select count(*) from public.login_lock_status('p1@example.com') x where x is not null), 0, 'not locked after 4'); -- Checks: not locked after 4.
select tests.eq((select count(*) from public.record_login_attempt('p1@example.com', false) x where x is not null), 1, 'locked on 5th'); -- Checks: locked on 5th.
select tests.eq((select count(*) from public.login_lock_status('p1@example.com') x where x is not null), 1, 'lock reported'); -- Checks: lock reported.
select public.clear_login_lock('p1@example.com'); -- Clears the lock on parent P1's sign-in.
select tests.eq((select count(*) from public.login_lock_status('p1@example.com') x where x is not null), 0, 'lock cleared'); -- Checks: lock cleared.
select tests.eq((select count(*) from public.record_login_attempt('p1@example.com', false) x where x is not null), 0, 'old failures do not re-lock after clear'); -- Checks: old failures do not re-lock after clear.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Prints that every check in this file passed.
\echo '  access rules: all checks passed'
