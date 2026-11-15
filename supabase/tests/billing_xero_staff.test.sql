-- Keeping Xero's employee records in step: the Xero to-do list. Reuses
-- people from access_rules.test.sql: owner (...a0), operations admin
-- (...b0), tutor T1 (...11), parent P1 (...01). Rolled back at the end.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this feature's database change (also checks it can run twice).
\ir ../migrations/20261117230100_billing_xero_staff.sql

-- Starts from a clean list for T1.
delete from public.billing_xero_tasks where account_id = '00000000-0000-0000-0000-000000000011'; -- clears T1's to-dos
delete from public.billing_staff_pay where account_id = '00000000-0000-0000-0000-000000000011'; -- clears T1's pay details

-- Linking to Xero alone adds no to-do.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.eq(public.billing_link_xero_employees('[{"account_id":"00000000-0000-0000-0000-000000000011","xero_employee_id":"emp-1"},{"account_id":"00000000-0000-0000-0000-000000000001","xero_employee_id":"emp-2"}]'), 1, 'only the staff member is linked'); -- links T1; skips the parent, who isn't staff
select tests.eq(public.billing_link_xero_employees('[{"account_id":"00000000-0000-0000-0000-000000000011","xero_employee_id":"emp-9"}]'), 0, 'an existing link is never replaced'); -- tries to change T1's link
reset role; -- back to the test runner
select tests.eq((select count(*) from public.billing_staff_pay where account_id = '00000000-0000-0000-0000-000000000011' and xero_employee_id = 'emp-1'), 1, 'T1 linked to emp-1'); -- checks the link kept
select tests.eq((select count(*) from public.billing_xero_tasks where account_id = '00000000-0000-0000-0000-000000000011'), 0, 'linking adds no to-do'); -- checks no to-do

-- Changing a rate and employment type adds one to-do saying what changed.
update public.billing_staff_pay set employment = 'part_time', school_rate_cents = 3312 where account_id = '00000000-0000-0000-0000-000000000011'; -- T1 goes part-time at $33.12
select tests.eq((select count(*) from public.billing_xero_tasks where account_id = '00000000-0000-0000-0000-000000000011' and kind = 'pay_details' -- checks one to-do,
  and details like '%Casual to Part-time%' and details like '%$33.12/hr%'), 1, 'pay change gives a to-do with the details'); -- naming both changes

-- Changing only a Xero link adds nothing.
update public.billing_staff_pay set xero_school_rate_id = 'rate-1' where account_id = '00000000-0000-0000-0000-000000000011'; -- picks a Xero earnings rate
select tests.eq((select count(*) from public.billing_xero_tasks where account_id = '00000000-0000-0000-0000-000000000011'), 1, 'Xero link change adds nothing'); -- still one to-do

-- Removing someone from the team adds one "left" to-do.
insert into public.staff_departures (account_id, full_name, left_on, reason) values ('00000000-0000-0000-0000-000000000011', 'Tutor One', current_date, 'moved'); -- T1 leaves
select tests.eq((select count(*) from public.billing_xero_tasks where account_id = '00000000-0000-0000-0000-000000000011' and kind = 'left' and left_on = current_date), 1, 'leaving gives a to-do'); -- checks the to-do

-- Who can see and tick off the list.
select id as task from public.billing_xero_tasks where account_id = '00000000-0000-0000-0000-000000000011' and kind = 'left' \gset
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.billing_xero_tasks), 0, 'operations admin sees no Xero to-dos'); -- pay is for the owner and Finance
select tests.fails(format($$select public.billing_xero_task_done(%L)$$, :'task'), 'operations ticks off a to-do'); -- checks this is refused
select tests.fails($$select public.billing_link_xero_employees('[]')$$, 'operations links staff to Xero'); -- checks this is refused
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.billing_xero_tasks), 0, 'tutor sees no Xero to-dos'); -- not even their own
select tests.fails($$insert into public.billing_xero_tasks (account_id, kind, details) values (auth.uid(), 'left', 'x')$$, 'tutor writes a to-do'); -- checks this is refused
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.billing_xero_tasks where account_id = '00000000-0000-0000-0000-000000000011'), 2, 'owner sees the to-dos'); -- both to-dos
select tests.fails(format($$select public.billing_xero_task_done(%L, 'magic')$$, :'task'), 'unknown way of doing it'); -- checks a wrong value is refused
select public.billing_xero_task_done(:'task'); -- the owner ticks it off
select tests.eq((select count(*) from public.billing_xero_tasks where id = :'task' and done_how = 'by_hand' and done_by = auth.uid()), 1, 'ticked off by the owner'); -- checks who and how
reset role; -- back to the test runner

rollback; -- Undoes everything this file did, leaving the test database as it was.
-- Prints that every check in this file passed.
\echo '  billing xero staff: all checks passed'
