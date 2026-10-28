-- Split payments: Cal's family (bill payer P2, ...02, monthly by bank
-- debit) shares invoices with P1 (...01), who becomes Cal's second parent
-- here. Runs after billing.test.sql. Everything is rolled back at the end
-- so later tests see the people as they were.

\set QUIET on
begin;
-- Runs the split migration again: it must be safe to run twice (and
-- billing.test.sql re-ran the first billing file, which this one updates).
\ir ../migrations/20261028230400_billing_split_payments.sql

select id as cal, family_id as fam2 from public.students where full_name = 'Cal Two' \gset
select date_trunc('month', private.billing_today() + 120)::date as m \gset
create function tests.session(p_student uuid, p_day date, p_start time, p_minutes int)
returns uuid language sql as $$
  insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at)
  select p_student, '00000000-0000-0000-0000-000000000011', s.family_id, 'General Maths', 'school', 'online',
         (p_day + p_start) at time zone 'Australia/Adelaide',
         (p_day + p_start + make_interval(mins => p_minutes)) at time zone 'Australia/Adelaide'
  from public.students s where s.id = p_student
  returning id
$$;
insert into public.parent_student_links (parent_id, student_id) values ('00000000-0000-0000-0000-000000000001', :'cal');
-- billing.test.sql clears billing accounts when it finishes.
insert into public.billing_accounts (family_id, bill_payer_id, plan) values (:'fam2', '00000000-0000-0000-0000-000000000002', 'monthly')
on conflict (family_id) do update set bill_payer_id = excluded.bill_payer_id, plan = excluded.plan;

-- ---------------------------------------------------------------------------
-- Setting a split
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.fails(format($$select public.billing_set_split(%L, '00000000-0000-0000-0000-000000000001', 40)$$, :'fam2'), 'parent sets a split');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.fails(format($$select public.billing_set_split(%L, '00000000-0000-0000-0000-000000000002', 40)$$, :'fam2'), 'main payer added as an extra payer');
select tests.fails(format($$select public.billing_set_split(%L, '00000000-0000-0000-0000-000000000011', 40)$$, :'fam2'), 'tutor added as a payer');
select tests.fails(format($$select public.billing_set_split(%L, '00000000-0000-0000-0000-000000000001', 100)$$, :'fam2'), 'share of 100%');
select tests.fails(format($$insert into public.billing_payers (family_id, account_id, share_percent) values (%L, '00000000-0000-0000-0000-000000000001', 40)$$, :'fam2'), 'payer added by hand');
select public.billing_set_split(:'fam2', '00000000-0000-0000-0000-000000000001', 30);
select public.billing_set_split(:'fam2', '00000000-0000-0000-0000-000000000001', 40);
select tests.eq((select count(*) from public.billing_payers where share_percent = 40), 1, 'admin sets and changes a split');
reset role;

-- ---------------------------------------------------------------------------
-- An invoice split 40 / 60
-- ---------------------------------------------------------------------------
select tests.claims(null);
select tests.session(:'cal', :'m'::date + 8, '15:00', 60) as s1 \gset
select tests.session(:'cal', :'m'::date + 15, '15:00', 90) as s2 \gset
select public.billing_build_invoice(:'fam2', :'m', (:'m'::date + interval '1 month - 1 day')::date) as inv \gset
select total_cents as total from public.billing_invoices where id = :'inv' \gset
select tests.eq((select count(*) from public.billing_invoice_shares where invoice_id = :'inv'), 2, 'two shares');
select tests.eq((select sum(amount_cents) from public.billing_invoice_shares where invoice_id = :'inv'), :total, 'shares add up to the total');
select tests.eq((select amount_cents from public.billing_invoice_shares where invoice_id = :'inv' and payer_id = '00000000-0000-0000-0000-000000000001'),
  floor(:total * 0.4)::int, 'second parent pays 40%');
select amount_cents as p1_owes from public.billing_invoice_shares where invoice_id = :'inv' and payer_id = '00000000-0000-0000-0000-000000000001' \gset
select amount_cents as p2_owes from public.billing_invoice_shares where invoice_id = :'inv' and payer_id = '00000000-0000-0000-0000-000000000002' \gset
select public.billing_approve_invoice(:'inv');

-- Each payer sees only their own share and payment details.
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.billing_invoice_payers(:'inv')), 1, 'second parent sees one share');
select tests.eq((select share_percent from public.billing_invoice_payers(:'inv')), 40, 'their own share');
select tests.eq((select count(*) from public.billing_invoices where id = :'inv'), 1, 'second parent sees the invoice');
select tests.eq((select count(*) from public.billing_invoice_shares), 1, 'second parent sees own share row only');
select tests.fails($$select stripe_customer_id from public.billing_payers$$, 'payer reads Stripe references');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select share_percent from public.billing_invoice_payers(:'inv')), 60, 'main payer sees their 60%');
select tests.eq((select count(*) from public.billing_payers), 1, 'main payer sees the split');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.billing_invoice_payers(:'inv')), 2, 'admin sees both shares');
reset role;

-- ---------------------------------------------------------------------------
-- Payments and pauses
-- ---------------------------------------------------------------------------
select tests.claims(null);
select due_on as due from public.billing_invoices where id = :'inv' \gset
select public.billing_record_payer_payment(:'inv', '00000000-0000-0000-0000-000000000001', 'stripe', 'pi_split_1', 'card', :p1_owes, 'succeeded');
select tests.eq((select count(*) from public.billing_invoices where id = :'inv' and status = 'open'), 1, 'one share paid: invoice still open');
select tests.eq((select paid_cents from public.billing_invoice_payers(:'inv') where payer_id = '00000000-0000-0000-0000-000000000001'), :p1_owes, 'share marked paid');
select tests.eq(private.billing_refresh_pause(:'fam2', :'due'::date + 1)::int, 1, 'whole family paused while a share is overdue');
select tests.eq(private.billing_refresh_pause(:'fam2', :'due'::date)::int, 0, 'not paused on the due date');
select public.billing_record_payer_payment(:'inv', '00000000-0000-0000-0000-000000000002', 'stripe', 'pi_split_2', 'bank_debit', :p2_owes, 'failed', 'Declined');
select tests.eq(private.billing_family_paused(:'fam2')::int, 1, 'failed share pauses');

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.billing_payments where invoice_id = :'inv'), 1, 'second parent sees only their own payment');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails(format($$select public.billing_record_payer_payment(%L, null, 'stripe', 'pi_fake', 'card', 1, 'succeeded')$$, :'inv'), 'browser records a payment');
select tests.fails(format($$select public.billing_save_payer_method(%L, '00000000-0000-0000-0000-000000000001', 'cus', 'pm', 'card')$$, :'fam2'), 'browser saves a payment method');
reset role;

select tests.claims(null);
select public.billing_record_payer_payment(:'inv', '00000000-0000-0000-0000-000000000002', 'stripe', 'pi_split_3', 'bank_debit', :p2_owes, 'processing');
select tests.eq(private.billing_refresh_pause(:'fam2', :'due'::date + 1)::int, 0, 'both shares paid or on the way: not paused');
select public.billing_record_payer_payment(:'inv', '00000000-0000-0000-0000-000000000002', 'stripe', 'pi_split_3', 'bank_debit', :p2_owes, 'succeeded');
select tests.eq((select count(*) from public.billing_invoices where id = :'inv' and status = 'paid'), 1, 'both shares paid: invoice paid');

-- Saving the second parent's card; weekly plans refuse bank debit.
select public.billing_save_payer_method(:'fam2', '00000000-0000-0000-0000-000000000001', 'cus_p1', 'pm_p1', 'bank_debit', 'mandate_p1');
select tests.eq((select count(*) from public.billing_payers where payment_ready and method = 'bank_debit'), 1, 'payer saves a bank debit');
update public.billing_accounts set plan = 'weekly', method = 'card' where family_id = :'fam2';
select public.billing_save_payer_method(:'fam2', '00000000-0000-0000-0000-000000000001', 'cus_p1', 'pm_card', 'card');
select public.billing_save_payer_method(:'fam2', '00000000-0000-0000-0000-000000000001', 'cus_p1', 'pm_p2', 'bank_debit', 'mandate_p2');
select tests.eq((select count(*) from public.billing_payers where method = 'card'), 1, 'weekly payer stays on card');

-- Removing the split: new invoices go to the main payer only.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.billing_remove_split(:'fam2', '00000000-0000-0000-0000-000000000001');
reset role;
select tests.claims(null);
select tests.session(:'cal', :'m'::date + 40, '15:00', 60) as s3 \gset
select public.billing_build_invoice(:'fam2', :'m'::date + 35, :'m'::date + 45) as inv2 \gset
select tests.eq((select count(*) from public.billing_invoice_shares where invoice_id = :'inv2'), 0, 'no split after removing it');
select tests.eq((select count(*) from public.billing_invoice_payers(:'inv2')), 1, 'main payer owes it all');

rollback;
\echo '  billing split payments: all checks passed'
