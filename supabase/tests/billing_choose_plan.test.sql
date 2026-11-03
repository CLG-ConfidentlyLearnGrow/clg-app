-- Families choose how often they pay. Cal's family; P1 (...01) is linked
-- here as Cal's parent. Tutor T1 (...11) is not in the family.
-- Runs after billing.test.sql. Rolled back at the end.

\set QUIET on
begin;
\ir ../migrations/20261103230100_billing_choose_plan.sql

select id as cal, family_id as fam from public.students where full_name = 'Cal Two' \gset
insert into public.parent_student_links (parent_id, student_id) values ('00000000-0000-0000-0000-000000000001', :'cal')
on conflict do nothing;
delete from public.billing_invoices where family_id = :'fam';
delete from public.billing_accounts where family_id = :'fam';

-- Someone outside the family can't choose or see it.
select tests.claims('00000000-0000-0000-0000-000000000011');
set role authenticated;
select tests.fails(format($$select public.billing_choose_plan(%L, 'monthly')$$, :'fam'), 'tutor chooses a family''s plan');
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam'), 0, 'tutor does not see the choice');
select tests.fails(format($$select private.billing_family_invoiced(%L)$$, :'fam'), 'browser calls the private helper');
reset role;

-- The parent sees the question before any billing is set up, then chooses.
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam' and not chosen and can_change), 1, 'parent is asked how often to pay');
select public.billing_choose_plan(:'fam', 'monthly');
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam' and chosen and plan = 'monthly'), 1, 'parent chose monthly');
update public.billing_accounts set plan = 'upfront';
reset role;
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and plan = 'monthly'), 1, 'parent can''t change the plan directly');
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select public.billing_choose_plan(:'fam', 'term');
reset role;
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and plan = 'term'
  and bill_payer_id = '00000000-0000-0000-0000-000000000001' and plan_chosen_by = '00000000-0000-0000-0000-000000000001'), 1,
  'parent changes their mind before the first invoice; becomes bill payer');

-- Weekly needs a card.
update public.billing_accounts set method = 'bank_debit', stripe_payment_method_id = 'pm_x' where family_id = :'fam';
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails(format($$select public.billing_choose_plan(%L, 'weekly')$$, :'fam'), 'weekly with bank debit');
reset role;

-- Once an invoice is sent, the family asks CLG instead.
insert into public.billing_invoices (family_id, family_name, plan, method, status, period_start, period_end, first_session_on, send_on, due_on, charge_on)
select :'fam', 'Test family', 'term', 'card', 'open', d, d + 30, d + 7, d, d + 3, d + 3 from (select private.billing_today() as d) t;
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails(format($$select public.billing_choose_plan(%L, 'monthly')$$, :'fam'), 'changing plan after the first invoice');
select public.billing_choose_plan(:'fam', 'term');
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam' and not can_change), 1, 'plan locked after the first invoice');
reset role;

rollback;
\echo '  billing choose plan: all checks passed'
