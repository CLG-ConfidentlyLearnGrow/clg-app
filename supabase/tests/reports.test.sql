-- Reports: the figures in a report, who can see and make reports, and the
-- automatic monthly, quarterly and yearly runs. Reuses access_rules.test.sql
-- people: owner (...a0), operations admin (...b0), tutor T1 (...11).
-- Uses March 2025, a month no other test touches. Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the reports database change again (checks it can run twice).
\ir ../migrations/20261113000100_reports.sql

-- Keeps Cara's family id as fam (the new student joins Cara's family).
select family_id as fam from public.students where full_name = 'Cara One' \gset

-- A new student, added on 1 March 2025 at 10am Adelaide time.
insert into public.students (family_id, full_name, date_of_birth, state, year_level, school, goals, created_at) -- adds the student
values (:'fam', 'Rae Report', '2012-05-05', 'SA', 'Year 8', 'Hills High', 'Read more widely', timestamp '2025-03-01 10:00' at time zone 'Australia/Adelaide') -- Rae, Year 8, in SA
returning id as rae \gset
-- Rae asks for English the same morning.
insert into public.student_subjects (student_id, subject) values (:'rae', 'English'); -- adds English (the app stamps it with now)
update public.student_subjects set added_at = timestamp '2025-03-01 10:00' at time zone 'Australia/Adelaide' where student_id = :'rae'; -- moves it back to 10am on 1 March

-- Tutor T1 is confirmed for Rae 10 days later (1 hour a week).
insert into public.bookings (student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, -- adds the booking
                             status, requested_at, confirmed_at)
values (:'rae', '00000000-0000-0000-0000-000000000011', :'fam', 'English', 3, '16:00', 60, 'online', '2025-03-12', '2025-06-30', -- Wednesdays 4pm, online
        'confirmed', timestamp '2025-03-05 10:00' at time zone 'Australia/Adelaide', timestamp '2025-03-11 10:00' at time zone 'Australia/Adelaide') -- asked for on 5 March, confirmed 11 March
returning id as booking \gset

-- Two one-hour sessions that went ahead in March, and one cancelled.
insert into public.sessions (booking_id, student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at, status, completed_at) -- adds the sessions
select :'booking', :'rae', '00000000-0000-0000-0000-000000000011', :'fam', 'English', 'school', 'online', -- Rae with T1, school English, online
       (d + time '16:00') at time zone 'Australia/Adelaide', (d + time '17:00') at time zone 'Australia/Adelaide', -- 4pm to 5pm Adelaide time
       'completed', (d + time '17:00') at time zone 'Australia/Adelaide' -- went ahead
from unnest(array[date '2025-03-12', date '2025-03-19']) d; -- on 12 and 19 March
insert into public.sessions (booking_id, student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at, status, cancelled_at, cancelled_by_role) -- adds a cancelled session
values (:'booking', :'rae', '00000000-0000-0000-0000-000000000011', :'fam', 'English', 'school', 'online', -- the same booking
        timestamp '2025-03-26 16:00' at time zone 'Australia/Adelaide', timestamp '2025-03-26 17:00' at time zone 'Australia/Adelaide', -- 26 March, 4pm to 5pm
        'cancelled', timestamp '2025-03-20 09:00' at time zone 'Australia/Adelaide', 'family'); -- cancelled by the family days ahead

-- An invoice with both sessions at $95 an hour.
insert into public.billing_invoices (family_id, family_name, plan, method, status, period_start, period_end, first_session_on, send_on, due_on, charge_on) -- adds the invoice
values (:'fam', 'One family', 'term', 'none', 'paid', '2025-03-12', '2025-03-19', '2025-03-12', '2025-03-01', '2025-03-05', '2025-03-05') -- paid, for March
returning id as inv \gset
insert into public.billing_invoice_lines (invoice_id, session_id, student_id, line_date, description, minutes, billed_minutes, hourly_cents, amount_cents) -- adds a line per session
select :'inv', se.id, :'rae', (se.starts_at at time zone 'Australia/Adelaide')::date, 'English', 60, 60, 9500, 9500 -- one hour at $95
from public.sessions se where se.booking_id = :'booking' and se.status = 'completed'; -- both completed sessions
-- A voided invoice line that must not count.
insert into public.billing_invoices (family_id, family_name, plan, method, status, period_start, period_end, first_session_on, send_on, due_on, charge_on, voided_at) -- adds a voided invoice
values (:'fam', 'One family', 'term', 'none', 'void', '2025-03-12', '2025-03-12', '2025-03-12', '2025-03-01', '2025-03-05', '2025-03-05', now()) -- voided
returning id as void_inv \gset
insert into public.billing_invoice_lines (invoice_id, line_date, description, minutes, billed_minutes, hourly_cents, amount_cents) -- adds a line to it
values (:'void_inv', '2025-03-12', 'Voided', 60, 60, 9500, 9500); -- $95 that must be left out

-- T1's pay: $40 an hour for each session, and an hour of admin at $30.
insert into public.billing_pay_lines (account_id, staff_name, work_date, kind, work_kind, session_id, minutes, rate_cents, amount_cents, status) -- adds the session pay
select '00000000-0000-0000-0000-000000000011', 'T1', (se.starts_at at time zone 'Australia/Adelaide')::date, 'session', 'school', se.id, 60, 4000, 4000, 'sent' -- one hour at $40
from public.sessions se where se.booking_id = :'booking' and se.status = 'completed'; -- both completed sessions
insert into public.billing_pay_lines (account_id, staff_name, work_date, kind, work_kind, minutes, rate_cents, amount_cents, status) -- adds admin pay
values ('00000000-0000-0000-0000-0000000000a0', 'Owner', '2025-03-15', 'admin', 'admin', 60, 3000, 3000, 'sent'); -- one hour at $30

-- A family left in March because of cost.
insert into public.leaving_records (who, family_id, left_on, reason, left_happy) values ('family', :'fam', '2025-03-28', 'cost', true); -- left happy

-- ---------------------------------------------------------------------------
-- Who can make and see reports.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.fails($$select public.report_make('2025-03-01', '2025-03-31')$$, 'operations makes a report'); -- checks this is refused
select tests.fails($$select public.report_save_settings(12, 0)$$, 'operations changes settings'); -- checks this is refused
reset role; -- back to the test user (access rules off)

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails($$select public.report_make('2025-03-01', '2025-03-31')$$, 'tutor makes a report'); -- checks this is refused
select tests.fails($$select public.reports_make_due()$$, 'tutor runs the timer'); -- checks this is refused
reset role; -- back to the test user (access rules off)

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.fails($$select public.report_make('2025-03-31', '2025-03-01')$$, 'dates backwards'); -- checks this is refused
select tests.fails($$select public.report_save_settings(80, 0)$$, 'super too high'); -- checks this is refused
select public.report_save_settings(12, 0); -- 12% super, no other costs
select public.report_make('2025-03-01', '2025-03-31') as rep \gset
select tests.eq((select count(*) from public.reports where id = :'rep'), 1, 'owner sees their report'); -- checks the owner can read it
select tests.fails($$insert into public.reports (kind, period_start, period_end, figures) values ('custom', current_date, current_date, '{}')$$, 'report written directly'); -- checks this is refused
reset role; -- back to the test user (access rules off)

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.reports), 0, 'operations sees no reports'); -- checks operations can't read reports
select tests.eq((select count(*) from public.report_settings), 0, 'operations sees no settings'); -- checks operations can't read settings
reset role; -- back to the test user (access rules off)
select tests.claims(null); -- signs out

-- ---------------------------------------------------------------------------
-- The figures in the March 2025 report.
-- ---------------------------------------------------------------------------
select figures as f from public.reports where id = :'rep' \gset
-- Matching: Rae waited 10 days (1 to 11 March).
select tests.eq((:'f'::jsonb #>> '{matching,matched}')::bigint, 1, 'one new match'); -- checks one match
select tests.eq((:'f'::jsonb #>> '{matching,average_days}')::numeric::bigint, 10, 'waited 10 days'); -- checks the wait
select tests.eq((:'f'::jsonb #>> '{matching,within_14_days}')::bigint, 1, 'matched within two weeks'); -- checks the two-week count
-- Enquiries: Rae was added and booked.
select tests.eq((:'f'::jsonb #>> '{enquiries,new_students}')::bigint, 1, 'one new student'); -- checks the new students
select tests.eq((:'f'::jsonb #>> '{enquiries,booked}')::bigint, 1, 'one booked'); -- checks the booked count
select tests.eq((:'f'::jsonb #>> '{enquiries,booked_percent}')::numeric::bigint, 100, 'all booked'); -- checks the booked share
-- Tutor weeks: T1 had 2 hours over 31 days (about 0.5 hours a week; the cancelled session doesn't count).
select tests.eq((select round((t ->> 'period_weekly')::numeric * 10)::bigint from jsonb_array_elements(:'f'::jsonb -> 'tutors') t -- T1's hours a week, times 10
                 where t ->> 'name' = (select full_name from public.accounts where id = '00000000-0000-0000-0000-000000000011')), 5, 'tutor average hours a week'); -- checks 0.5
-- Leaving: one family, for cost, and happy.
select tests.eq((:'f'::jsonb #>> '{leaving,families}')::bigint, 1, 'one family left'); -- checks families left
select tests.eq((:'f'::jsonb #>> '{leaving,families_happy}')::bigint, 1, 'left happy'); -- checks left happy
select tests.eq((select (r ->> 'count')::bigint from jsonb_array_elements(:'f'::jsonb #> '{leaving,reasons}') r where r ->> 'reason' = 'cost'), 1, 'reason is cost'); -- checks the reason
-- Money: $190 income (the voided $95 left out); tutor wages $80 + 12% = $89.60.
select tests.eq((:'f'::jsonb #>> '{money,income_cents}')::bigint, 19000, 'income'); -- checks income
select tests.eq((:'f'::jsonb #>> '{money,tutor_wages_cents}')::bigint, 8960, 'tutor wages with super'); -- checks tutor wages
select tests.eq((:'f'::jsonb #>> '{money,admin_wages_cents}')::bigint, 3360, 'admin wages with super'); -- checks admin wages ($30 + 12%)
select tests.eq((:'f'::jsonb #>> '{money,profit_per_hour_after_tutors_cents}')::bigint, 5020, 'profit per hour after tutors'); -- checks ($190 - $89.60) / 2 hours
select tests.eq((:'f'::jsonb #>> '{money,profit_per_hour_after_all_cents}')::bigint, 3340, 'profit per hour after all costs'); -- checks ($190 - $89.60 - $33.60) / 2 hours
select tests.eq((select (l ->> 'profit_per_hour_cents')::bigint from jsonb_array_elements(:'f'::jsonb #> '{money,levels}') l where l ->> 'kind' = 'school'), 5020, 'school profit per hour'); -- checks the school figure
select tests.eq((:'f'::jsonb #>> '{money,sessions_without_pay}')::bigint, 0, 'every session has pay'); -- checks no missing pay
select tests.eq((:'f'::jsonb #>> '{money,sessions_not_billed}')::bigint, 0, 'every session is billed'); -- checks nothing missing from invoices

-- Other costs of $3,043.75 a month ($100 a day) reduce profit after all costs.
update public.report_settings set monthly_other_costs_cents = 304375 where id; -- sets other costs
select tests.eq((private.report_figures('2025-03-01', '2025-03-31') #>> '{money,other_costs_cents}')::bigint, 310000, 'other costs spread over 31 days'); -- checks $3,100 for March
update public.report_settings set monthly_other_costs_cents = 0 where id; -- back to none

-- ---------------------------------------------------------------------------
-- Automatic reports: which periods are due on a given day.
-- ---------------------------------------------------------------------------
select tests.eq((select count(*) from private.report_due_periods('2026-12-01') where kind = 'monthly' and period_start = '2026-11-01' and period_end = '2026-11-30'), 1, 'November report on 1 December'); -- checks the month
select tests.eq((select count(*) from private.report_due_periods('2027-01-05') where kind = 'quarterly' and period_start = '2026-10-01' and period_end = '2026-12-31'), 1, 'October to December quarter in January'); -- checks the quarter
select tests.eq((select count(*) from private.report_due_periods('2027-07-01') where kind = 'yearly' and period_start = '2026-07-01' and period_end = '2027-06-30'), 1, 'financial year in July'); -- checks the year
select tests.eq((select count(*) from private.report_due_periods('2027-03-01') where kind = 'yearly' and period_start = '2025-07-01' and period_end = '2026-06-30'), 1, 'last financial year mid-year'); -- checks the year mid-year

-- The timer makes the three due reports once, then nothing more.
update public.report_settings set automatic_from = '2000-01-01' where id; -- lets every due period count
select tests.eq(public.reports_make_due(), 3, 'timer makes monthly, quarterly and yearly reports'); -- checks three were made
select tests.eq(public.reports_make_due(), 0, 'running again makes none'); -- checks nothing doubles up

-- The owner sees new reports on the to-do numbers, and opening one clears it.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.eq((select n from public.to_do_counts() where area = 'admin' and section = 'reports'), 3, 'three new reports to read'); -- checks the number
select id as monthly from public.reports where kind = 'monthly' \gset
select public.report_mark_read(:'monthly'); -- opens the monthly report
select tests.eq((select n from public.to_do_counts() where area = 'admin' and section = 'reports'), 2, 'two left to read'); -- checks the number went down
select tests.fails(format($$select public.report_delete(%L)$$, :'monthly'), 'automatic report deleted'); -- checks automatic reports can't be deleted
select public.report_delete(:'rep'); -- deletes the custom report
select tests.eq((select count(*) from public.reports where id = :'rep'), 0, 'custom report deleted'); -- checks it's gone
reset role; -- back to the test user (access rules off)

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.to_do_counts() where section = 'reports'), 0, 'operations has no reports number'); -- checks operations doesn't get the number
reset role; -- back to the test user (access rules off)
select tests.claims(null); -- signs out

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  reports: all checks passed'
