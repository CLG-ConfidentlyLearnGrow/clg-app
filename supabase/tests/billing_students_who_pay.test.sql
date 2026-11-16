-- Summary: checks that only students who pay for their own lessons get
-- billing (Carla, 16 Nov 2026). An adult learner with no parent linked pays
-- for themselves; a student aged 18+ with their own login in a family where
-- a parent pays does not (no plan choice, no invoices, no Billing tab),
-- unless they are made the bill payer. Reuses access_rules.test.sql people:
-- parent P1 (...01, Cara's parent), adult learner (...21) and tutor T2
-- (...12, used here as the login of an 18+ student in Cara's family).
-- Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this database change again (checks it can run twice).
\ir ../migrations/20261118900200_billing_students_who_pay.sql

select tests.claims(null); -- acts as the database itself while setting up
\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)
\set adult '00000000-0000-0000-0000-000000000021'
-- (the adult learner's account id)
\set older '00000000-0000-0000-0000-000000000012'
-- (the login used for the older student below)
select family_id as fam from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's family as fam; P1 is Cara's parent)
insert into public.students (family_id, full_name, account_id, date_of_birth, state, year_level, school) values (:'fam', 'Olly One', :'older', current_date - interval '19 years', 'SA', 'University or TAFE', 'Test University'); -- Cara's older sibling, 19, with their own login
insert into public.billing_accounts (family_id, bill_payer_id, plan) values (:'fam', :'p1', 'monthly') on conflict (family_id) do update set bill_payer_id = excluded.bill_payer_id; -- P1 is the family's bill payer
insert into public.billing_invoices (family_id, family_name, plan, method, status, period_start, period_end, first_session_on, send_on, due_on, charge_on) -- an open invoice for the family:
select :'fam', 'Test family', 'monthly', 'card', 'open', d, d + 30, d + 7, d, d + 3, d + 3 from (select private.billing_today() as d) t; -- (monthly, by card, starting today)

-- 1. The parent pays: they get billing.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq(public.billing_i_pay()::int, 1, 'the paying parent gets a Billing tab'); -- yes
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam'), 1::bigint, 'the paying parent sees the plan choice'); -- sees it
reset role; -- back to the database itself

-- 2. The 19-year-old student whose parent pays: no billing at all.
select tests.claims(:'older'); -- signs in as the older student
set role authenticated; -- acts as a signed-in person
select tests.eq(public.billing_i_pay()::int, 0, 'a student whose parent pays gets no Billing tab'); -- no
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam'), 0::bigint, 'and isn''t asked how often to pay'); -- hidden
select tests.eq((select count(*) from public.billing_invoices where family_id = :'fam'), 0::bigint, 'and can''t see the family''s invoices'); -- hidden
select tests.fails(format($q$select public.billing_choose_plan(%L, 'weekly')$q$, :'fam'), 'and can''t change how the family pays'); -- refused
reset role; -- back to the database itself

-- 3. If CLG makes that student the bill payer, they get billing.
update public.billing_accounts set bill_payer_id = :'older' where family_id = :'fam'; -- the older student now pays
select tests.claims(:'older'); -- signs in as the older student
set role authenticated; -- acts as a signed-in person
select tests.eq(public.billing_i_pay()::int, 1, 'a student who is the bill payer gets a Billing tab'); -- yes
reset role; -- back to the database itself

-- 3b. A 19-year-old who is the family's ONLY learner, but whose parent pays,
-- still gets no billing (the gap sibling privacy left open).
select tests.claims(null); -- acts as the database itself while setting up
insert into public.families (name) values ('Solo family') returning id as solo_fam \gset
-- (a new family, kept as solo_fam)
insert into public.students (family_id, full_name, account_id, date_of_birth, state, year_level, school) values (:'solo_fam', 'Solo Student', '00000000-0000-0000-0000-000000000011', current_date - interval '19 years', 'SA', 'University or TAFE', 'Test University') returning id as solo \gset
-- (a 19-year-old with their own login, the only learner; T1's login is reused for them)
insert into public.parent_student_links (parent_id, student_id, verified_at) values (:'p1', :'solo', now()); -- P1 is their parent
select tests.claims('00000000-0000-0000-0000-000000000011'); -- signs in as that student
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'solo_fam'), 0::bigint, 'an only learner whose parent pays isn''t asked how often to pay'); -- hidden
reset role; -- back to the database itself

-- 4. An adult learner with no parent linked pays for themselves.
select tests.claims(null); -- acts as the database itself while setting up
insert into public.families (name) values ('Ada Learner family') returning id as ada_fam \gset
-- (gives the adult learner a family of their own, kept as ada_fam, as billing works per family)
update public.students set family_id = :'ada_fam' where account_id = :'adult'; -- puts the adult learner in it
select tests.claims(:'adult'); -- signs in as the adult learner
set role authenticated; -- acts as a signed-in person
select tests.eq(public.billing_i_pay()::int, 1, 'an adult learner who pays for themselves gets a Billing tab'); -- yes
select tests.eq((select count(*) from public.billing_my_plan_choices()), 1::bigint, 'and is asked how often to pay'); -- sees their own family
reset role; -- back to the database itself

-- 5. Nobody signed in gets nothing.
select tests.claims(null); -- signed out
select tests.eq(public.billing_i_pay()::int, 0, 'nobody signed in pays for anything'); -- no

-- Throws everything away.
rollback;
\echo '  billing_students_who_pay: all checks passed'
