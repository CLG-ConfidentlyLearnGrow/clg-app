-- Summary: checks the change that goes with renaming the "Parent" profile to
-- "Family" (Carla, 20 Nov 2026). An adult learner who pays for themselves
-- does everything from their Student profile, with no Family profile: they
-- are in a family of their own, get a Billing tab, choose how often to pay,
-- agree to the payment terms, become the bill payer and see their own
-- invoices. A parent who becomes a learner joins their children's family, a
-- student saved with no family is given one when the change runs, and the
-- database's messages that name the profile say "Family". Reuses
-- access_rules.test.sql people: parent P1 (...01, Cara's parent) and the
-- adult learner (...21). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the change again (checks it can run twice).
\ir ../migrations/20261122870100_family_profile_adult_learner_billing.sql

select tests.claims(null); -- acts as the database itself while setting up
\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)
\set adult '00000000-0000-0000-0000-000000000021'
-- (the adult learner's account id)
select family_id as cara_fam from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's family as cara_fam; P1 is Cara's parent)

-- 1. The adult learner who signed up on their own is in a family of their own.
select tests.eq((select count(*) from public.students where account_id = :'adult' and family_id is not null), 1::bigint, 'an adult learner who signed up alone is in a family'); -- has a family
select family_id as ada_fam from public.students where account_id = :'adult' \gset
-- (keeps the adult learner's family as ada_fam)
select tests.eq((select count(*) from public.students where family_id = :'ada_fam'), 1::bigint, 'and is the only learner in it'); -- nobody else in it

-- 2. Signed in on their Student profile, they can start and run their own payments.
select tests.claims(:'adult'); -- signs in as the adult learner
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq(public.billing_i_pay()::int, 1, 'the adult learner gets a Billing tab'); -- yes
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'ada_fam'), 1::bigint, 'and is asked how often to pay'); -- sees the choice
select public.billing_choose_plan(:'ada_fam', 'monthly'); -- chooses monthly
select public.billing_accept_terms(:'ada_fam', 'test-terms'); -- agrees to the payment terms
reset role; -- back to the database itself
select tests.eq((select count(*) from public.billing_accounts where family_id = :'ada_fam' and bill_payer_id = :'adult' and plan = 'monthly' and terms_accepted_at is not null), 1::bigint, 'choosing a plan and agreeing makes the adult learner the bill payer'); -- saved, with them paying

-- 3. They see their own invoice and what they owe on it.
insert into public.billing_invoices (family_id, family_name, plan, method, status, period_start, period_end, first_session_on, send_on, due_on, charge_on) -- an open invoice for their family:
select :'ada_fam', 'Ada family', 'monthly', 'card', 'open', d, d + 30, d + 7, d, d + 3, d + 3 from (select private.billing_today() as d) t returning id as ada_inv \gset
-- (keeps the invoice as ada_inv)
select tests.claims(:'adult'); -- signs in as the adult learner
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.billing_invoices where id = :'ada_inv'), 1::bigint, 'the adult learner sees their own invoice'); -- visible
select tests.eq((select count(*) from public.billing_invoice_payers(:'ada_inv')), 1::bigint, 'and what is owed on it, so they can pay it'); -- one payer row
reset role; -- back to the database itself

-- 4. Someone else cannot see that billing.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.billing_invoices where id = :'ada_inv'), 0::bigint, 'another family cannot see the adult learner''s invoice'); -- hidden
reset role; -- back to the database itself

-- 5. A parent who becomes a learner joins their children's family (one bill for the household).
select tests.claims(null); -- acts as the database itself
insert into public.students (full_name, account_id, date_of_birth, state, year_level, school) values ('Pat Parent', :'p1', current_date - interval '40 years', 'SA', 'University or TAFE', 'Test University'); -- P1 adds a student profile for themselves
select tests.eq((select count(*) from public.students where account_id = :'p1' and family_id = :'cara_fam'), 1::bigint, 'a parent who becomes a learner joins their children''s family'); -- same family as Cara

-- 6. A student with their own login saved with no family is given one when the change runs.
alter table public.students disable trigger students_own_family; -- switches off the new step for a moment, to copy an older record
insert into public.students (full_name, account_id, date_of_birth, state, year_level, school) values ('Old Learner', '00000000-0000-0000-0000-000000000011', current_date - interval '25 years', 'SA', 'University or TAFE', 'Test University'); -- an older-style record with no family (T1's login reused)
alter table public.students enable trigger students_own_family; -- switches it back on
\ir ../migrations/20261122870100_family_profile_adult_learner_billing.sql
select tests.eq((select count(*) from public.students where full_name = 'Old Learner' and family_id is not null), 1::bigint, 'an existing learner with no family is given one'); -- fixed
select tests.eq((select count(*) from public.students where account_id is not null and family_id is null), 0::bigint, 'no student with their own login is left without a family'); -- none left

-- 7. A child added by a parent keeps the family they were given.
select tests.eq((select count(*) from public.students where full_name = 'Cara One' and family_id = :'cara_fam'), 1::bigint, 'children added by a parent keep their family'); -- unchanged

-- 8. The database's messages that name the profile say "Family".
select tests.eq((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'private') and (p.prosrc like '%Only parents can add a child%' or p.prosrc like '%That account is not a parent account%' or p.prosrc like '%Only parents and students can make a family calendar link%' or p.prosrc like '%Choose tutor, admin or parent.%')), 0::bigint, 'no database message names the old Parent profile'); -- none left

-- Throws everything away.
rollback;
\echo '  family_profile_adult_learner_billing: all checks passed'
