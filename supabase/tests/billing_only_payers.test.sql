-- Summary: checks that only the people paying see billing (Carla, 16 Nov
-- 2026). A family's bill payer and any extra payer see the plan, invoices
-- and credit; a second parent who doesn't pay sees none of it and gets no
-- Billing tab, but is still told when sessions are on hold. Until a family
-- has a bill payer, a parent can start the family's payments by choosing
-- the plan, which makes them the bill payer. Reuses access_rules.test.sql
-- people: parent P1 (...01, Cara's parent) and parent P2 (...02), linked
-- here as Cara's second parent. Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this database change again (checks it can run twice).
\ir ../migrations/20261118900300_billing_only_payers.sql

select tests.claims(null); -- acts as the database itself while setting up
\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)
\set p2 '00000000-0000-0000-0000-000000000002'
-- (parent P2's account id)
select id as cara, family_id as fam from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's id as cara and her family as fam)
insert into public.parent_student_links (parent_id, student_id, verified_at) values (:'p2', :'cara', now()) on conflict do nothing; -- P2 becomes Cara's second parent
delete from public.billing_payers where family_id = :'fam'; -- starts with no extra payers
delete from public.billing_accounts where family_id = :'fam'; -- and no billing account, so nobody pays yet
insert into public.billing_invoices (family_id, family_name, plan, method, status, period_start, period_end, first_session_on, send_on, due_on, charge_on) -- an open invoice for the family:
select :'fam', 'Test family', 'monthly', 'card', 'open', d, d + 30, d + 7, d, d + 3, d + 3 from (select private.billing_today() as d) t -- (monthly, by card, starting today)
returning id as inv \gset
-- (keeps the invoice's id as inv)

-- 1. Nobody pays yet: both parents may start, but nobody sees invoices.
select tests.claims(:'p2'); -- signs in as P2
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam'), 1::bigint, 'with no payer yet, a parent is asked how often to pay'); -- offered
select tests.eq((select count(*) from public.billing_invoices where id = :'inv'), 0::bigint, 'but sees no invoices before paying'); -- hidden
reset role; -- back to the database itself

-- 2. P1 accepts the payment terms, and so becomes the bill payer.
select tests.claims(:'p1'); -- signs in as P1
set role authenticated; -- acts as a signed-in person
select public.billing_accept_terms(:'fam', 'test'); -- accepts the payment terms (the invoice is already out, so the plan is fixed)
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and bill_payer_id = :'p1'), 1::bigint, 'accepting the terms makes P1 the bill payer'); -- payer now
select tests.eq((select count(*) from public.billing_invoices where id = :'inv'), 1::bigint, 'the bill payer sees the invoice'); -- visible
select tests.eq(public.billing_i_pay()::int, 1, 'the bill payer gets a Billing tab'); -- yes
reset role; -- back to the database itself

-- 3. P2 is a parent but doesn't pay: no billing at all.
select tests.claims(:'p2'); -- signs in as P2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam'), 0::bigint, 'a parent who doesn''t pay isn''t offered the family''s billing'); -- hidden
select tests.eq((select count(*) from public.billing_invoices where id = :'inv'), 0::bigint, 'and can''t see the invoice'); -- hidden
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam'), 0::bigint, 'and can''t see the family''s billing account'); -- hidden
select tests.eq(coalesce(public.billing_credit_balance(:'fam'), 0), 0, 'and can''t see the family''s credit'); -- hidden
select tests.fails(format($q$select public.billing_choose_plan(%L, 'weekly')$q$, :'fam'), 'and can''t change how the family pays'); -- refused
select tests.fails(format($q$select public.billing_accept_terms(%L, 'test')$q$, :'fam'), 'and can''t accept the payment terms'); -- refused
reset role; -- back to the database itself

-- 4. On hold: every parent is told, payer or not.
update public.billing_accounts set paused = true where family_id = :'fam'; -- the family is paused (overdue)
select tests.claims(:'p2'); -- signs in as P2
set role authenticated; -- acts as a signed-in person
select tests.eq(public.my_support_on_hold()::int, 1, 'a parent who doesn''t pay is still told sessions are on hold'); -- told
reset role; -- back to the database itself
update public.billing_accounts set paused = false where family_id = :'fam'; -- back to normal

-- 5. CLG names P2 as an extra payer: now P2 sees the family's billing.
insert into public.billing_payers (family_id, account_id, share_percent) values (:'fam', :'p2', 50); -- P2 pays half
select tests.claims(:'p2'); -- signs in as P2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.billing_invoices where id = :'inv'), 1::bigint, 'an extra payer sees the invoice'); -- visible
select tests.eq(public.billing_i_pay()::int, 1, 'and gets a Billing tab'); -- yes
reset role; -- back to the database itself

-- Throws everything away.
rollback;
\echo '  billing_only_payers: all checks passed'
