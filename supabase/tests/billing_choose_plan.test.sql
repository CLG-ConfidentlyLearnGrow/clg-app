-- Families choose how often they pay. Cal's family; P1 (...01) is linked
-- here as Cal's parent. Tutor T1 (...11) is not in the family.
-- Runs after billing.test.sql. Rolled back at the end.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
begin; -- Starts a transaction, so everything below can be undone at the end.
-- Runs the database change 20261103230100_billing_choose_plan.sql first, as this test needs it.
\ir ../migrations/20261103230100_billing_choose_plan.sql

-- Keeps Cal's student id as cal and his family id as fam.
select id as cal, family_id as fam from public.students where full_name = 'Cal Two' \gset
insert into public.parent_student_links (parent_id, student_id) values ('00000000-0000-0000-0000-000000000001', :'cal') -- Links parent P1 to Cal:
on conflict do nothing; -- (unless already linked).
delete from public.billing_invoices where family_id = :'fam'; -- Clears Cal's family's invoices.
delete from public.billing_accounts where family_id = :'fam'; -- Clears their billing set-up.

-- Someone outside the family can't choose or see it.
select tests.claims('00000000-0000-0000-0000-000000000011'); -- Signs in as test account ...11.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_choose_plan(%L, 'monthly')$$, :'fam'), 'tutor chooses a family''s plan'); -- Checks this is refused: tutor chooses a family's plan.
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam'), 0, 'tutor does not see the choice'); -- Checks: tutor does not see the choice.
select tests.fails(format($$select private.billing_family_invoiced(%L)$$, :'fam'), 'browser calls the private helper'); -- Checks this is refused: browser calls the private helper.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The parent sees the question before any billing is set up, then chooses.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam' and not chosen and can_change), 1, 'parent is asked how often to pay'); -- Checks: parent is asked how often to pay.
select public.billing_choose_plan(:'fam', 'monthly'); -- The parent chooses monthly.
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam' and chosen and plan = 'monthly'), 1, 'parent chose monthly'); -- Checks: parent chose monthly.
update public.billing_accounts set plan = 'upfront'; -- Tries to change the plan directly.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and plan = 'monthly'), 1, 'parent can''t change the plan directly'); -- Checks: parent can't change the plan directly.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.billing_choose_plan(:'fam', 'term'); -- The parent changes to per term.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and plan = 'term' -- Checks the parent can change their mind before the first invoice, and becomes the bill payer:
  and bill_payer_id = '00000000-0000-0000-0000-000000000001' and plan_chosen_by = '00000000-0000-0000-0000-000000000001'), 1, -- (per term, with parent P1 as payer and chooser),
  'parent changes their mind before the first invoice; becomes bill payer'); -- (the label).

-- Weekly needs a card.
update public.billing_accounts set method = 'bank_debit', stripe_payment_method_id = 'pm_x' where family_id = :'fam'; -- Gives the family a saved bank debit.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_choose_plan(%L, 'weekly')$$, :'fam'), 'weekly with bank debit'); -- Checks this is refused: weekly with bank debit.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Once an invoice is sent, the family asks CLG instead.
insert into public.billing_invoices (family_id, family_name, plan, method, status, period_start, period_end, first_session_on, send_on, due_on, charge_on) -- Adds a sent invoice for the family:
select :'fam', 'Test family', 'term', 'card', 'open', d, d + 30, d + 7, d, d + 3, d + 3 from (select private.billing_today() as d) t; -- (per term, by card, starting today).
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_choose_plan(%L, 'monthly')$$, :'fam'), 'changing plan after the first invoice'); -- Checks this is refused: changing plan after the first invoice.
select public.billing_choose_plan(:'fam', 'term'); -- Chooses per term again (no change, so it's allowed).
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam' and not can_change), 1, 'plan locked after the first invoice'); -- Checks: plan locked after the first invoice.
reset role; -- Goes back to the all-powerful test user (access rules off).

rollback; -- Undoes everything this file did, leaving the test database as it was.
-- Prints that every check in this file passed.
\echo '  billing choose plan: all checks passed'
