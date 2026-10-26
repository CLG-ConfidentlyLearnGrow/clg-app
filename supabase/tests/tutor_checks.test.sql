-- Tutors adding their own checks. Runs after access_rules.test.sql and reuses
-- its helpers, staff admin (...b0), tutors T1 (...11) and T2 (...12), and
-- parent P1 (...01).

-- Two-step login is required.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1');
set role authenticated;
select tests.fails($$insert into public.tutor_checks (tutor_id, kind, reference, expires_on) values ('00000000-0000-0000-0000-000000000011', 'wwcc_nsw', 'N1', current_date + 400)$$, 'tutor without two-step login');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
-- Own check: saved, logged, but not confirmed even if the tutor tries.
insert into public.tutor_checks (tutor_id, kind, reference, completed_on, expires_on, verified_at, verified_by)
values ('00000000-0000-0000-0000-000000000011', 'wwcc_nsw', 'NSW-1', current_date - 10, current_date + 1000, now(), '00000000-0000-0000-0000-000000000011');
select tests.eq((select count(*) from public.tutor_checks where reference = 'NSW-1' and verified_at is null and verified_by is null and submitted_by = '00000000-0000-0000-0000-000000000011' and submitted_at is not null), 1, 'tutor entry waits for an admin');
-- Not for someone else, not expired, not in the future, no edits.
select tests.fails($$insert into public.tutor_checks (tutor_id, kind, reference, expires_on) values ('00000000-0000-0000-0000-000000000012', 'wwcc_nsw', 'X', current_date + 400)$$, 'tutor adds check for another tutor');
select tests.fails($$insert into public.tutor_checks (tutor_id, kind, reference, expires_on) values ('00000000-0000-0000-0000-000000000011', 'wwcc_nsw', 'OLD', current_date - 1)$$, 'expired check');
select tests.fails($$insert into public.tutor_checks (tutor_id, kind, reference, completed_on, expires_on) values ('00000000-0000-0000-0000-000000000011', 'wwcc_nsw', 'F', current_date + 5, current_date + 400)$$, 'date done in the future');
update public.tutor_checks set expires_on = current_date + 5000 where reference = 'NSW-1';
select tests.eq((select count(*) from public.tutor_checks where expires_on = current_date + 5000), 0, 'tutor cannot edit a check');
select tests.fails($$select public.confirm_tutor_check((select id from public.tutor_checks where reference = 'NSW-1'))$$, 'tutor confirms own check');
-- Police check expiry still worked out from the issue date.
insert into public.tutor_checks (tutor_id, kind, reference, completed_on, expires_on)
values ('00000000-0000-0000-0000-000000000011', 'police_check', 'PC-T1', current_date - 30, current_date);
select tests.eq((select count(*) from public.tutor_checks where reference = 'PC-T1' and expires_on = (current_date - 30 + interval '5 years')::date), 1, 'police check expiry from issue date');
-- Unconfirmed entries don't count.
select tests.eq((select count(*) from public.tutor_check_status where kind = 'wwcc_nsw' and expires_on = current_date + 1000), 0, 'unconfirmed check not counted');
reset role;

-- Parents can't confirm.
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2');
set role authenticated;
select tests.fails($$select public.confirm_tutor_check(gen_random_uuid())$$, 'parent confirms a check');
reset role;

-- Admin confirms one and declines another.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select public.confirm_tutor_check(id)::int from public.tutor_checks where reference = 'NSW-1'), 1, 'admin confirms');
select tests.eq((select count(*) from public.tutor_checks where reference = 'NSW-1' and verified_by = '00000000-0000-0000-0000-0000000000b0'), 1, 'confirmation stamped');
select tests.eq((select count(*) from public.tutor_check_status where tutor_id = '00000000-0000-0000-0000-000000000011' and kind = 'wwcc_nsw' and expires_on = current_date + 1000), 1, 'confirmed check counts');
select tests.fails($$select public.decline_tutor_check((select id from public.tutor_checks where reference = 'PC-T1'), '')$$, 'decline needs a reason');
select tests.eq((select public.decline_tutor_check(id, 'Number does not match the certificate')::int from public.tutor_checks where reference = 'PC-T1'), 1, 'admin declines');
select tests.eq((select public.confirm_tutor_check(id)::int from public.tutor_checks where reference = 'PC-T1'), 0, 'declined check cannot then be confirmed');
reset role;

-- The tutor sees the reason.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.tutor_checks where reference = 'PC-T1' and declined_reason is not null and verified_at is null), 1, 'tutor sees why it was declined');
reset role;

-- The other tutor can't see it.
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.tutor_checks where tutor_id = '00000000-0000-0000-0000-000000000011'), 0, 'tutors see only their own checks');
reset role;
select tests.claims(null);

\echo '  tutor checks: all checks passed'
