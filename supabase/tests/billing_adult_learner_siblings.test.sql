-- Summary: an adult learner sees and manages family billing only when they
-- are the family's only learner (Carla, 16 Nov 2026). In a family with
-- siblings, billing stays with the parents, or with whoever CLG names as
-- bill payer or extra payer on Admin > Billing. Being named bill payer never
-- lets them see their siblings' profiles. Runs after billing.test.sql.
-- Everything is rolled back at the end so later tests see the people as
-- they were.
--
-- People made here: adult learner Ari (...d1, 25 years old), Ari's younger
-- brother Ben (no login, 12), and their parent Pam (...d2).

-- Keeps psql quiet so only problems are printed.
\set QUIET on
begin; -- Starts a transaction, so everything below can be undone at the end.
-- Earlier tests re-run older billing files, which put back the old payer rule, so apply this change again (it must be safe to run twice).
\ir ../migrations/20261118300200_billing_adult_learner_only_learner.sql
-- Runs it a second time, to show running it twice is safe.
\ir ../migrations/20261118300200_billing_adult_learner_only_learner.sql

-- ---------------------------------------------------------------------------
-- People and a family
-- ---------------------------------------------------------------------------
select tests.claims(null); -- Signs out, so no one is signed in.
insert into auth.users (id, email, raw_user_meta_data) values -- Adds two people through sign-up:
  ('00000000-0000-0000-0000-0000000000d1', 'ari@example.com', -- Ari (adult learner ...d1),
   json_build_object('signup_as', 'learner', 'full_name', 'Ari Four', 'state', 'SA', 'year_level', 'University or TAFE', 'school', 'TAFE SA', -- at TAFE in SA,
                     'date_of_birth', (current_date - interval '25 years')::date)), -- born 25 years ago,
  ('00000000-0000-0000-0000-0000000000d2', 'pam@example.com', '{"signup_as":"parent","full_name":"Pam Four"}'); -- and Pam (parent ...d2).
insert into public.families (name) values ('Four family') returning id as fam \gset
-- (the line above adds the Four family and keeps its id as fam)
update public.students set family_id = :'fam' -- Puts Ari's student record in the Four family
where account_id = '00000000-0000-0000-0000-0000000000d1' returning id as ari \gset
-- (and keeps Ari's student id as ari).
insert into public.billing_accounts (family_id, plan) values (:'fam', 'monthly'); -- Sets up the family's billing account, with no bill payer named yet.
insert into public.billing_credits (family_id, kind, amount_cents, note) values (:'fam', 'goodwill', 500, 'Test credit'); -- Gives the family $5 credit, so there is something to see.

-- ---------------------------------------------------------------------------
-- Ari is the only learner: Ari looks after billing
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000d1'); -- Signs in as Ari.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam'), 1, 'only learner: adult learner sees the billing account'); -- Checks Ari sees the family's billing account.
select tests.eq((select count(*) from public.billing_credits where family_id = :'fam'), 1, 'only learner: adult learner sees credit'); -- Checks Ari sees the family's credit.
select tests.eq(public.billing_credit_balance(:'fam'), 500, 'only learner: adult learner sees the credit balance'); -- Checks Ari sees the $5 balance.
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam'), 1, 'only learner: adult learner can choose the plan'); -- Checks the plan choice is offered to Ari.
select tests.eq(public.billing_paid_by_others()::int, 0, 'only learner: billing is not looked after by others'); -- Checks the page won't tell Ari someone else pays.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- A younger brother joins the family: billing moves to the parent
-- ---------------------------------------------------------------------------
insert into public.students (family_id, full_name, date_of_birth, state, year_level, school) -- Adds Ari's brother Ben to the same family:
values (:'fam', 'Ben Four', current_date - interval '12 years', 'SA', 'Year 7', 'Park PS') returning id as ben \gset
-- (aged 12, Year 7, no login of his own; his id is kept as ben)
insert into public.parent_student_links (parent_id, student_id, verified_at) values ('00000000-0000-0000-0000-0000000000d2', :'ben', now()); -- Links Ben to his parent Pam.

select tests.claims('00000000-0000-0000-0000-0000000000d1'); -- Signs in as Ari again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam'), 0, 'with a sibling: adult learner no longer sees the billing account'); -- Checks Ari no longer sees the billing account.
select tests.eq((select count(*) from public.billing_credits where family_id = :'fam'), 0, 'with a sibling: adult learner no longer sees credit'); -- Checks Ari no longer sees the credit.
select tests.eq(public.billing_credit_balance(:'fam'), null, 'with a sibling: adult learner gets no credit balance'); -- Checks the balance is withheld from Ari.
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam'), 0, 'with a sibling: adult learner is not offered the plan choice'); -- Checks Ari isn't offered the plan choice.
select tests.fails(format($$select public.billing_choose_plan(%L, 'term')$$, :'fam'), 'with a sibling: adult learner chooses the plan'); -- Checks this is refused: Ari chooses how often the family pays.
select tests.fails(format($$select public.billing_accept_terms(%L, '2026-10')$$, :'fam'), 'with a sibling: adult learner accepts the terms'); -- Checks this is refused: Ari accepts the family terms.
select tests.eq(public.billing_paid_by_others()::int, 1, 'with a sibling: the page tells the adult learner someone else looks after billing'); -- Checks the page can tell Ari someone else pays.
select tests.eq((select count(*) from public.students where id = :'ben'), 0, 'with a sibling: adult learner cannot see the sibling'); -- Checks Ari still can't see Ben's profile.
select tests.eq((select n from public.to_do_counts() where area = 'family' and section = 'billing'), 0, 'with a sibling: no billing count on the adult learner''s menu'); -- Checks Ari's menu has no billing count.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000d2'); -- Signs in as Pam, the parent.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam'), 1, 'with a sibling: the parent sees the billing account'); -- Checks Pam sees the family's billing account.
select tests.eq(public.billing_credit_balance(:'fam'), 500, 'with a sibling: the parent sees the credit balance'); -- Checks Pam sees the $5 balance.
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam'), 1, 'with a sibling: the parent can choose the plan'); -- Checks the plan choice is offered to Pam.
select tests.eq(public.billing_paid_by_others()::int, 0, 'parent: not told someone else pays'); -- Checks Pam isn't told someone else pays (she's not a learner).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- CLG names Ari as the bill payer: Ari looks after billing again
-- ---------------------------------------------------------------------------
update public.billing_accounts set bill_payer_id = '00000000-0000-0000-0000-0000000000d1' where family_id = :'fam'; -- CLG names Ari as the family's bill payer (as Admin > Billing does).

select tests.claims('00000000-0000-0000-0000-0000000000d1'); -- Signs in as Ari again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam'), 1, 'named bill payer: adult learner sees the billing account'); -- Checks Ari sees the billing account again.
select tests.eq(public.billing_credit_balance(:'fam'), 500, 'named bill payer: adult learner sees the credit balance'); -- Checks Ari sees the $5 balance again.
select public.billing_choose_plan(:'fam', 'term'); -- Ari chooses to pay per term (this must now work).
select tests.eq(public.billing_paid_by_others()::int, 0, 'named bill payer: not told someone else pays'); -- Checks the page won't tell Ari someone else pays.
select tests.eq((select count(*) from public.students where id = :'ben'), 0, 'named bill payer: adult learner still cannot see the sibling'); -- Checks Ari still can't see Ben's profile.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam' and plan = 'term'), 1, 'named bill payer: the plan choice saved'); -- Checks Ari's plan choice was saved.

-- ---------------------------------------------------------------------------
-- CLG adds Ari as an extra payer instead: Ari looks after their share
-- ---------------------------------------------------------------------------
update public.billing_accounts set bill_payer_id = '00000000-0000-0000-0000-0000000000d2' where family_id = :'fam'; -- CLG makes Pam the bill payer instead.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.billing_set_split(:'fam', '00000000-0000-0000-0000-0000000000d1', 50); -- The owner splits the family's invoices 50/50 with Ari.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000d1'); -- Signs in as Ari again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam'), 1, 'extra payer: adult learner sees the billing account'); -- Checks Ari, as an extra payer, sees the billing account.
select tests.eq((select count(*) from public.students where id = :'ben'), 0, 'extra payer: adult learner still cannot see the sibling'); -- Checks Ari still can't see Ben's profile.
reset role; -- Goes back to the all-powerful test user (access rules off).

\echo '  adult learner billing with siblings: all checks passed'
rollback; -- Undoes everything above, so later tests start clean.
