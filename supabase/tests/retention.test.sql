-- Automatic deletion tests. Runs after access_rules.test.sql and reuses its
-- helpers (tests.claims, tests.eq, tests.fails) and its owner (...a0),
-- staff admin (...b0) and tutor T1 (...11).

-- Ids used here: parents ...c1 ...c2, unused accounts ...d1 ...d2,
-- former tutors ...e1 (tutor only) ...e2 (also a parent).

insert into auth.users (id, email, raw_user_meta_data, last_sign_in_at) values
  ('00000000-0000-0000-0000-0000000000c1', 'r1@example.com', '{"signup_as":"parent","full_name":"Rae Old"}', now() - interval '3 years'),
  ('00000000-0000-0000-0000-0000000000c2', 'r2@example.com', '{"signup_as":"parent","full_name":"Ria Current"}', now()),
  ('00000000-0000-0000-0000-0000000000d1', 'u1@example.com', '{"signup_as":"parent","full_name":"Uma Unused"}', now() - interval '13 months'),
  ('00000000-0000-0000-0000-0000000000d2', 'u2@example.com', '{"signup_as":"parent","full_name":"Uli Recent"}', now() - interval '1 month'),
  ('00000000-0000-0000-0000-0000000000e1', 'e1@example.com', '{"signup_as":"parent","full_name":"Eve Former"}', now() - interval '8 years'),
  ('00000000-0000-0000-0000-0000000000e2', 'e2@example.com', '{"signup_as":"parent","full_name":"Ed Both"}', now());
update public.accounts set created_at = now() - interval '3 years'
  where id in ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d1',
               '00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000e1');

-- Former tutors: e1 is only a tutor, e2 is also a parent with a child.
delete from public.parent_profiles where account_id = '00000000-0000-0000-0000-0000000000e1';
delete from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000e1';
insert into public.account_roles (account_id, role) values
  ('00000000-0000-0000-0000-0000000000e1', 'tutor'),
  ('00000000-0000-0000-0000-0000000000e2', 'tutor');
insert into public.tutor_profiles (account_id, active, ended_on) values
  ('00000000-0000-0000-0000-0000000000e1', false, current_date - 365 * 8),
  ('00000000-0000-0000-0000-0000000000e2', false, current_date - 365 * 8);
insert into public.tutor_checks (tutor_id, kind, reference, expires_on, verified_at) values
  ('00000000-0000-0000-0000-0000000000e1', 'wwcc_sa', 'OLD-1', current_date - 365 * 7, now());

-- Students. Old = last seen 3 years ago.
insert into public.students (id, full_name, date_of_birth, state, last_activity_at, created_at) values
  ('00000000-0000-0000-0000-0000000005a1', 'Old Kid', '2012-01-01', 'SA', now() - interval '3 years', now() - interval '4 years'),
  ('00000000-0000-0000-0000-0000000005a2', 'Enrolled Kid', '2012-01-01', 'SA', now() - interval '3 years', now() - interval '4 years'),
  ('00000000-0000-0000-0000-0000000005a3', 'Held Kid', '2012-01-01', 'SA', now() - interval '3 years', now() - interval '4 years'),
  ('00000000-0000-0000-0000-0000000005a4', 'Soon Kid', '2012-01-01', 'SA', now() - interval '2 years' + interval '10 days', now() - interval '4 years'),
  ('00000000-0000-0000-0000-0000000005a5', 'Erase Kid', '2012-01-01', 'SA', now(), now()),
  ('00000000-0000-0000-0000-0000000005a6', 'Both Kid', '2012-01-01', 'SA', now(), now());
insert into public.student_sensitive (student_id, learning_needs) values
  ('00000000-0000-0000-0000-0000000005a1', 'needs');
insert into public.parent_student_links (parent_id, student_id) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000005a1'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000005a2'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000005a5'),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000005a6');
insert into public.programs (id, name) values ('00000000-0000-0000-0000-0000000006a1', 'Maths');
insert into public.enrolments (student_id, program_id, status, created_at) values
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000006a1', 'active', now() - interval '4 years');
insert into public.audit_log (at, action, table_name) values (now() - interval '8 years', 'test', 'old');

-- ===========================================================================
-- Who can see and change the rules
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-0000000000c2', 'aal2');
set role authenticated;
select tests.fails($$select * from public.upcoming_deletions()$$, 'parent sees upcoming deletions');
select tests.eq((select count(*) from public.retention_rules), 0, 'parent cannot read rules');
select tests.fails($$insert into public.retention_holds (student_id, reason) values ('00000000-0000-0000-0000-0000000005a2', 'keep it')$$, 'parent places hold');
select tests.fails($$select public.erase_student('00000000-0000-0000-0000-0000000005a5', 'Erase Kid')$$, 'parent erases');
reset role;

-- A tutor cannot mark themselves as left.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.fails($$update public.tutor_profiles set ended_on = current_date where account_id = '00000000-0000-0000-0000-000000000011'$$, 'tutor sets own end date');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.retention_rules), 4, 'staff admin reads rules');
update public.retention_rules set keep_for = interval '1 year' where kind = 'student_records';
select tests.eq((select count(*) from public.retention_rules where keep_for = interval '2 years' and kind = 'student_records'), 1, 'staff admin cannot change periods');
-- Upcoming: old, held and soon students, the former tutors, the unused account and Rae's account is not yet (still linked).
select tests.eq((select count(*) from public.upcoming_deletions() where kind = 'student'), 3, 'three students due within 30 days');
select tests.eq((select count(*) from public.upcoming_deletions() where kind = 'tutor'), 2, 'two former tutors due');
select tests.eq((select count(*) from public.upcoming_deletions() where record_id = '00000000-0000-0000-0000-0000000000d1'), 1, 'unused account listed');
select tests.eq((select count(*) from public.upcoming_deletions() where record_id = '00000000-0000-0000-0000-0000000000d2'), 0, 'recent account not listed');
insert into public.retention_holds (student_id, reason) values ('00000000-0000-0000-0000-0000000005a3', 'Open complaint');
select tests.eq((select count(*) from public.retention_holds where placed_by = '00000000-0000-0000-0000-0000000000b0'), 1, 'hold stamped with who placed it');
select tests.eq((select count(*) from public.upcoming_deletions() where record_id = '00000000-0000-0000-0000-0000000005a3'), 0, 'held student not listed');
select tests.fails($$update public.retention_holds set reason = 'changed', released_at = now()$$, 'hold reason edited');
select tests.fails($$delete from public.retention_holds$$, 'hold deleted');
select tests.fails($$select public.erase_student('00000000-0000-0000-0000-0000000005a5', 'Erase Kid')$$, 'staff admin erases');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails($$update public.retention_rules set keep_for = interval '1 day' where kind = 'student_records'$$, 'period under 30 days');
update public.retention_rules set keep_for = interval '2 years' where kind = 'student_records';
select tests.eq((select count(*) from public.retention_rules where updated_by = '00000000-0000-0000-0000-0000000000a0'), 1, 'owner change stamped');
select tests.fails($$select public.erase_student('00000000-0000-0000-0000-0000000005a5', 'Wrong Name')$$, 'erase with wrong name');
select public.erase_student('00000000-0000-0000-0000-0000000005a5', 'Erase Kid');
reset role;
select tests.claims(null);
select tests.eq((select count(*) from public.students where id = '00000000-0000-0000-0000-0000000005a5'), 0, 'erased on request');
select tests.eq((select count(*) from public.audit_log where action = 'erase_on_request'), 1, 'erasure logged');

-- ===========================================================================
-- The nightly run
-- ===========================================================================

select private.run_retention();

select tests.eq((select count(*) from public.students where id = '00000000-0000-0000-0000-0000000005a1'), 0, 'old student deleted');
select tests.eq((select count(*) from public.student_sensitive where student_id = '00000000-0000-0000-0000-0000000005a1'), 0, 'their learning needs deleted');
select tests.eq((select count(*) from auth.users where id = '00000000-0000-0000-0000-0000000000c1'), 0, 'their long-unused parent account deleted');
select tests.eq((select count(*) from public.students where id = '00000000-0000-0000-0000-0000000005a2'), 1, 'enrolled student kept');
select tests.eq((select count(*) from auth.users where id = '00000000-0000-0000-0000-0000000000c2'), 1, 'current parent kept');
select tests.eq((select count(*) from public.students where id = '00000000-0000-0000-0000-0000000005a3'), 1, 'held student kept');
select tests.eq((select count(*) from public.students where id = '00000000-0000-0000-0000-0000000005a4'), 1, 'not yet due student kept');
select tests.eq((select count(*) from auth.users where id = '00000000-0000-0000-0000-0000000000d1'), 0, 'unused account deleted');
select tests.eq((select count(*) from auth.users where id = '00000000-0000-0000-0000-0000000000d2'), 1, 'recently used account kept');
select tests.eq((select count(*) from auth.users where id = '00000000-0000-0000-0000-0000000000e1'), 0, 'former tutor deleted');
select tests.eq((select count(*) from public.tutor_checks where tutor_id = '00000000-0000-0000-0000-0000000000e1'), 0, 'their checks deleted');
select tests.eq((select count(*) from auth.users where id = '00000000-0000-0000-0000-0000000000e2'), 1, 'former tutor who is a parent keeps login');
select tests.eq((select count(*) from public.tutor_profiles where account_id = '00000000-0000-0000-0000-0000000000e2'), 0, 'but loses tutor profile');
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000e2' and role = 'tutor'), 0, 'and tutor role');
select tests.eq((select count(*) from public.audit_log where table_name = 'old'), 0, 'old activity log entry deleted');
select tests.eq((select count(*) from public.tutor_profiles where account_id = '00000000-0000-0000-0000-000000000011'), 1, 'current tutor untouched');
select tests.eq((select deleted from public.retention_log where kind = 'student_records'), 1, 'run logged as a count');

-- Releasing the hold makes the student due on the next run.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
update public.retention_holds set released_at = now() where student_id = '00000000-0000-0000-0000-0000000005a3';
select tests.eq((select count(*) from public.retention_holds where released_by = '00000000-0000-0000-0000-0000000000b0'), 1, 'release stamped');
select tests.fails($$update public.retention_holds set released_at = now() where student_id = '00000000-0000-0000-0000-0000000005a3'$$, 'hold released twice');
reset role;
select tests.claims(null);
select private.run_retention();
select tests.eq((select count(*) from public.students where id = '00000000-0000-0000-0000-0000000005a3'), 0, 'released student deleted');

-- Running again changes nothing.
select private.run_retention();
select tests.eq((select count(*) from public.students where id in ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000005a4')), 2, 'second run is safe');

\echo '  retention: all checks passed'
