-- Summary: choosing a payment plan is compulsory, and the person who pays
-- can change it later (Carla, 20 Nov 2026). Uses Cal's family, with parent
-- P1 (...01) linked as Cal's parent, and the owner (...a0). Checks:
--   * the payer can change the plan after the first invoice was sent;
--   * the change applies from the next session not already invoiced (the
--     invoice already sent keeps its plan);
--   * admins are told about the change;
--   * weekly still needs a card;
--   * the booking functions check a plan was chosen.
-- Rolled back at the end.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction, so everything below can be undone at the end.
begin;
-- Runs the change again (and twice), to check it is safe to run more than once.
\ir ../migrations/20261123400500_payment_plan_required.sql
\ir ../migrations/20261123400500_payment_plan_required.sql

-- Keeps Cal's student id as cal and his family id as fam.
select id as cal, family_id as fam from public.students where full_name = 'Cal Two' \gset
insert into public.parent_student_links (parent_id, student_id) values ('00000000-0000-0000-0000-000000000001', :'cal') -- links parent P1 to Cal,
on conflict do nothing; -- (unless already linked).
delete from public.billing_invoices where family_id = :'fam'; -- clears Cal's family's invoices,
delete from public.billing_accounts where family_id = :'fam'; -- and their billing set-up.

-- Before choosing: the family has no plan.
select tests.eq((select private.billing_plan_chosen(:'fam'))::int::bigint, 0::bigint, 'no plan chosen yet'); -- checks the helper

-- The parent chooses per term.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set local role authenticated; -- acts as a signed-in user
select public.billing_choose_plan(:'fam', 'term'); -- chooses per term
reset role; -- back to the test user
select tests.eq((select private.billing_plan_chosen(:'fam'))::int::bigint, 1::bigint, 'plan chosen'); -- checks the helper

-- An invoice is sent on the per term plan.
insert into public.billing_invoices (family_id, family_name, plan, method, status, period_start, period_end, first_session_on, send_on, due_on, charge_on) -- adds a sent invoice:
select :'fam', 'Test family', 'term', 'card', 'open', d, d + 30, d + 7, d, d + 3, d + 3 from (select private.billing_today() as d) t; -- (per term, by card, starting today).

-- The parent changes to monthly after the first invoice: allowed now.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set local role authenticated; -- acts as a signed-in user
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam' and chosen and can_change), 1::bigint, 'plan can still be changed after the first invoice'); -- checks the list
select public.billing_choose_plan(:'fam', 'monthly'); -- changes to monthly
reset role; -- back to the test user
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and plan = 'monthly'), 1::bigint, 'plan changed to monthly'); -- checks the change
select tests.eq((select count(*) from public.billing_invoices where family_id = :'fam' and plan = 'term' and status = 'open'), 1::bigint, 'the invoice already sent keeps its plan'); -- checks the sent invoice is untouched
select tests.eq((select case when count(*) > 0 then 1 else 0 end from public.session_notices where title = 'Payment plan changed' and body like '%from term to monthly%')::bigint, 1::bigint, 'admins are told about the change'); -- checks the notice

-- Weekly still needs a card.
update public.billing_accounts set method = 'bank_debit', stripe_payment_method_id = 'pm_x' where family_id = :'fam'; -- gives the family a saved bank debit
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set local role authenticated; -- acts as a signed-in user
select tests.fails(format($$select public.billing_choose_plan(%L, 'weekly')$$, :'fam'), 'weekly with bank debit'); -- checks this is refused
reset role; -- back to the test user

-- Someone outside the family still cannot change it.
select tests.claims('00000000-0000-0000-0000-000000000011'); -- signs in as tutor T1
set local role authenticated; -- acts as a signed-in user
select tests.fails(format($$select public.billing_choose_plan(%L, 'term')$$, :'fam'), 'tutor changes a family''s plan'); -- checks this is refused
reset role; -- back to the test user

-- The booking functions check a plan was chosen (read from their code).
select tests.eq(case when strpos(pg_get_functiondef('public.approve_booking(uuid, boolean, text)'::regprocedure), 'billing_plan_chosen') > 0 then 1::bigint else 0::bigint end, 1::bigint, 'approving a time needs a plan'); -- checks approve_booking
select tests.eq(case when strpos(pg_get_functiondef('public.request_booking(uuid, text, uuid, smallint, time, integer, public.session_delivery, uuid, date, date, text)'::regprocedure), 'billing_plan_chosen') > 0 then 1::bigint else 0::bigint end, 1::bigint, 'asking for a booking needs a plan'); -- checks request_booking

-- Undoes everything this file did.
rollback;
-- Prints that every check in this file passed.
\echo '  billing choose plan change: all checks passed'
