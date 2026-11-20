-- Summary: a family can book a change of payment plan at any time, and it
-- starts from their next invoice (Carla, 20 Nov 2026). Uses Cal's family,
-- with parent P1 (...01) linked as Cal's parent, the owner (...a0) and
-- tutor T1 (...11). Checks:
--   * before the first invoice, a plan is saved straight away;
--   * after that, a change is booked and the current plan stays;
--   * the booked change and its expected start day can be read;
--   * the change is made only when the current plan's next invoice is due,
--     and that invoice is built on the new plan;
--   * the person who pays and admins are told;
--   * the change can be cancelled (by button, or by choosing the current
--     plan again), but not by someone outside the family;
--   * a booked weekly change is not made if the family moved to bank debit.
-- Rolled back at the end.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction, so everything below can be undone at the end.
begin;
-- Runs the change again (and twice), to check it is safe to run more than once.
\ir ../migrations/20261123500100_payment_plan_change_next_invoice.sql
\ir ../migrations/20261123500100_payment_plan_change_next_invoice.sql

-- A session for this test, written straight in as the server would.
create function tests.plan_session(p_student uuid, p_day date) returns uuid language sql as $$ -- takes the student and day, gives back the new session's id
  insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) -- adds the session:
  select p_student, '00000000-0000-0000-0000-000000000011', s.family_id, 'General Maths', 'school', 'online', -- for this student with tutor T1, online,
         (p_day + time '16:00') at time zone 'Australia/Adelaide', -- from 4pm Adelaide time,
         (p_day + time '17:00') at time zone 'Australia/Adelaide' -- to 5pm,
  from public.students s where s.id = p_student -- (using the student's family),
  returning id -- and gives back its id
$$; -- end of the helper

-- Keeps Cal's student id as cal and his family id as fam.
select id as cal, family_id as fam from public.students where full_name = 'Cal Two' \gset
insert into public.parent_student_links (parent_id, student_id) values ('00000000-0000-0000-0000-000000000001', :'cal') -- links parent P1 to Cal,
on conflict do nothing; -- (unless already linked).
delete from public.billing_invoices where family_id = :'fam'; -- clears Cal's family's invoices,
delete from public.billing_accounts where family_id = :'fam'; -- and their billing set-up.
-- A Monday four weeks away, well past the next weekly invoice day.
select date_trunc('week', private.billing_today() + 28)::date as mon \gset
-- Takes Cal's family's sessions from that week out of the way, so only the test session counts.
delete from public.sessions where family_id = :'fam' and starts_at >= (:'mon'::date) at time zone 'Australia/Adelaide'; -- removes later sessions for the family

-- Before the first invoice: weekly is saved straight away.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set local role authenticated; -- acts as a signed-in user
select public.billing_choose_plan(:'fam', 'weekly'); -- chooses weekly
reset role; -- back to the test user
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and plan = 'weekly' and pending_plan is null), 1::bigint, 'first choice saved straight away'); -- checks the plan

-- An invoice is sent on the weekly plan.
insert into public.billing_invoices (family_id, family_name, plan, method, status, period_start, period_end, first_session_on, send_on, due_on, charge_on) -- adds a sent invoice:
select :'fam', 'Test family', 'weekly', 'card', 'open', d, d + 6, d + 2, d, d + 1, d + 1 from (select private.billing_today() as d) t; -- (weekly, by card, this week).

-- A session four weeks away, not yet on an invoice.
-- Adds it and keeps its id as sess.
select tests.plan_session(:'cal', :'mon') as sess \gset

-- After the first invoice: changing to monthly is booked, and weekly stays.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set local role authenticated; -- acts as a signed-in user
select public.billing_choose_plan(:'fam', 'monthly'); -- asks for monthly
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and plan = 'weekly' and pending_plan = 'monthly'), 1::bigint, 'the payer sees the booked change, current plan kept'); -- checks what the payer can read
select tests.eq((select case when public.billing_plan_change_starts(:'fam') = :'mon'::date - 11 then 1 else 0 end)::bigint, 1::bigint, 'expected start is the next weekly invoice day'); -- checks the start day (weekly invoices go out 11 days before the first session)
reset role; -- back to the test user
select tests.eq((select case when count(*) > 0 then 1 else 0 end from public.session_notices where title = 'Payment plan change booked' and body like '%from weekly to monthly%')::bigint, 1::bigint, 'admins are told about the booked change'); -- checks the notice
select tests.eq((select count(*) from public.billing_invoices where family_id = :'fam' and plan = 'weekly' and status = 'open'), 1::bigint, 'the invoice already sent keeps its plan'); -- checks the sent invoice is untouched

-- Someone outside the family cannot read the start day or cancel it.
select tests.claims('00000000-0000-0000-0000-000000000011'); -- signs in as tutor T1
set local role authenticated; -- acts as a signed-in user
select tests.eq((select case when public.billing_plan_change_starts(:'fam') is null then 1 else 0 end)::bigint, 1::bigint, 'a tutor gets no start day'); -- checks nothing is given away
select tests.fails(format($$select public.billing_cancel_plan_change(%L)$$, :'fam'), 'tutor cancels a family''s plan change'); -- checks this is refused
reset role; -- back to the test user

-- The daily run today: the weekly invoice is not due yet, so nothing changes.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner (with the second sign-in step admins need)
set local role authenticated; -- acts as a signed-in user
-- Runs the invoice builder for today (keeps how many it made as made_today).
select public.billing_build_due_invoices(private.billing_today()) as made_today \gset
reset role; -- back to the test user
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and plan = 'weekly' and pending_plan = 'monthly'), 1::bigint, 'not changed before the next invoice day'); -- checks the plan is still weekly

-- The daily run on the next invoice day: the change is made and the invoice is monthly.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner (with the second sign-in step admins need)
set local role authenticated; -- acts as a signed-in user
-- Runs the invoice builder as if it were the next weekly invoice day (11 days before the session).
select public.billing_build_due_invoices(:'mon'::date - 11) as made_then \gset
reset role; -- back to the test user
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and plan = 'monthly' and pending_plan is null), 1::bigint, 'changed to monthly on the next invoice day'); -- checks the plan
select tests.eq((select count(*) from public.billing_invoice_lines l join public.billing_invoices i on i.id = l.invoice_id where l.session_id = :'sess' and i.plan = 'monthly'), 1::bigint, 'that invoice is built on the new plan'); -- checks the new invoice
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000001' and title = 'Payment plan changed'), 1::bigint, 'the payer is told the change was made'); -- checks the payer's notice

-- Cancelling: booked, then cancelled by the payer.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set local role authenticated; -- acts as a signed-in user
select public.billing_choose_plan(:'fam', 'term'); -- asks for per term
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and pending_plan = 'term'), 1::bigint, 'per term booked'); -- checks it is booked
select public.billing_cancel_plan_change(:'fam'); -- cancels it
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and plan = 'monthly' and pending_plan is null), 1::bigint, 'cancelled, monthly kept'); -- checks it is gone
-- Cancelling by choosing the current plan again.
select public.billing_choose_plan(:'fam', 'term'); -- asks for per term again
select public.billing_choose_plan(:'fam', 'monthly'); -- then chooses monthly, the current plan
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and pending_plan is null), 1::bigint, 'choosing the current plan cancels the booked change'); -- checks it is gone
reset role; -- back to the test user
select tests.eq((select case when count(*) > 0 then 1 else 0 end from public.session_notices where title = 'Payment plan change cancelled')::bigint, 1::bigint, 'admins are told about the cancel'); -- checks the notice

-- A booked weekly change is not made if the family moved to bank debit.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set local role authenticated; -- acts as a signed-in user
select public.billing_choose_plan(:'fam', 'weekly'); -- asks for weekly (by card, allowed)
reset role; -- back to the test user
update public.billing_accounts set method = 'bank_debit', stripe_payment_method_id = 'pm_x' where family_id = :'fam'; -- the family then saves a bank debit
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner (with the second sign-in step admins need)
set local role authenticated; -- acts as a signed-in user
-- Runs the invoice builder for today again.
select public.billing_build_due_invoices(private.billing_today()) as made_debit \gset
reset role; -- back to the test user
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and plan = 'monthly' and pending_plan is null), 1::bigint, 'weekly change dropped for bank debit'); -- checks the plan stayed monthly
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000001' and title = 'Payment plan not changed'), 1::bigint, 'the payer is told why'); -- checks the payer's notice

-- Undoes everything this file did.
rollback;
-- Prints that every check in this file passed.
\echo '  billing plan change next invoice: all checks passed'
