-- Why families and tutors leave, and admin hours due by the day after the
-- pay week (2 Nov 2026). Reuses owner admin (...a0), parent P1 (...01) and
-- tutor T1 (...11).

select tests.claims(null);
select family_id as fam from public.students where full_name = 'Cara One' \gset

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails(format($$select public.record_leaving('family', %L, null, current_date, 'bored')$$, :'fam'), 'unknown reason');
select tests.fails($$select public.record_leaving('family', null, null, current_date, 'cost')$$, 'no family chosen');
select public.record_leaving('family', :'fam', null, current_date, 'goals_met', 'Reached their goals for Year 6.', true, true);
select public.record_leaving('tutor', null, '00000000-0000-0000-0000-000000000011', current_date, 'own_study_or_work', 'Started full-time work.');
select tests.eq((select count(*) from public.list_leaving_records()), 2, 'admin sees both');
select tests.eq((select count(*) from public.list_leaving_records() where who = 'family' and left_happy and review_asked), 1, 'happy family asked for a review');
select tests.fails($$delete from public.leaving_records$$, 'records changed directly');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.leaving_records), 0, 'families see none');
select tests.fails(format($$select public.record_leaving('family', %L, null, current_date, 'cost')$$, :'fam'), 'family records a reason');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.list_leaving_records()), 0, 'tutors see none');
reset role;
select tests.claims(null);
delete from public.leaving_records;

-- Admin hours: due the day after the pay period ends; late ones flagged.
select tests.eq((select (public.billing_hours_due_by(p.period_start) = p.period_end + 1)::int
  from public.billing_pay_period(current_date) p), 1, 'due the day after the pay period ends');
insert into public.billing_hour_logs (account_id, work_date, minutes, note) values
  ('00000000-0000-0000-0000-0000000000a0', current_date - 40, 60, 'Old hours'),
  ('00000000-0000-0000-0000-0000000000a0', current_date, 60, 'Today');
select tests.eq((select count(*) from public.billing_hour_logs where note = 'Old hours' and logged_late), 1, 'late entry flagged');
select tests.eq((select count(*) from public.billing_hour_logs where note = 'Today' and not logged_late), 1, 'on-time entry not flagged');
delete from public.billing_hour_logs where note in ('Old hours', 'Today');

\echo '  leaving records and hours due: all checks passed'
