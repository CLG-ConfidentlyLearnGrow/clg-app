-- Billing: prices, family accounts, invoices built from sessions, credits,
-- payments and automatic pauses. Runs after access_rules.test.sql and
-- reuses its people: owner (...a0), staff admin (...b0), tutor T1 (...11),
-- parents P1 (...01, Cara's family) and P2 (...02, Cal's family).

-- The billing migration must be safe to run twice.
\set QUIET on
\ir ../migrations/20261027230100_billing.sql

select id as cara, family_id as fam1 from public.students where full_name = 'Cara One' \gset
select id as cal, family_id as fam2 from public.students where full_name = 'Cal Two' \gset
-- Monday of the week two weeks from now, and the next Monday after it.
select date_trunc('week', private.billing_today() + 14)::date as mon1,
       date_trunc('week', private.billing_today() + 21)::date as mon2 \gset

-- A session for tests, written straight in as the server would.
create function tests.session(p_student uuid, p_day date, p_start time, p_minutes int, p_level text default 'school')
returns uuid language sql as $$
  insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at)
  select p_student, '00000000-0000-0000-0000-000000000011', s.family_id, 'General Maths', p_level, 'online',
         (p_day + p_start) at time zone 'Australia/Adelaide',
         (p_day + p_start + make_interval(mins => p_minutes)) at time zone 'Australia/Adelaide'
  from public.students s where s.id = p_student
  returning id
$$;
grant execute on function tests.session(uuid, date, time, int, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Money rules
-- ---------------------------------------------------------------------------
select tests.eq(private.billing_minutes(45), 60, '45 min charged as 1 hr');
select tests.eq(private.billing_minutes(61), 90, 'half-hour steps');
select tests.eq(private.billing_minutes(120), 120, '2 hr stays 2 hr');
select tests.eq(private.billing_fee_cents(38000, 'card'), 657, 'card fee on $380');
select tests.eq(private.billing_fee_cents(38000, 'bank_debit'), 350, 'bank debit fee capped at $3.50');
select tests.eq(private.billing_debit_discount(38000), 154, 'bank debit discount is half the saving');
select tests.eq(private.billing_debit_discount(9500), 31, 'discount on $95');
select tests.eq(private.billing_cancel_credit_percent(now() + interval '30 hours', now(), 'family', 'cancelled'), 100, 'more than 24hr notice');
select tests.eq(private.billing_cancel_credit_percent(now() + interval '24 hours', now(), 'family', 'cancelled'), 50, 'exactly 24hr notice');
select tests.eq(private.billing_cancel_credit_percent(now() + interval '2 hours', now(), 'family', 'cancelled'), 50, '2hr notice');
select tests.eq(private.billing_cancel_credit_percent(now() + interval '1 hour', now(), 'family', 'cancelled'), 0, 'under 2hr notice');
select tests.eq(private.billing_cancel_credit_percent(now() + interval '1 hour', now(), 'tutor', 'cancelled'), 100, 'tutor cancels: full credit');
select tests.eq(private.billing_cancel_credit_percent(now() + interval '1 hour', now(), 'admin', 'cancelled'), 100, 'CLG cancels: full credit');
select tests.eq(private.billing_cancel_credit_percent(now() - interval '1 hour', null, null, 'no_show'), 0, 'no-show: no credit');
-- Monday 7 Dec 2026: 4 business days before is Tuesday 1 Dec.
select tests.eq((private.business_days_before('2026-12-07', 4) = '2026-12-01')::int, 1, 'business days skip weekends');
select tests.eq(((select due_on from private.billing_dates('weekly', 'card', '2026-12-07')) = '2026-12-03')::int, 1, 'weekly due 4 days before');
select tests.eq(((select send_on from private.billing_dates('weekly', 'card', '2026-12-07')) = '2026-11-26')::int, 1, 'weekly sent 1 week before due');
select tests.eq(((select due_on from private.billing_dates('term', 'card', '2027-01-27')) = '2027-01-20')::int, 1, 'term due 1 week before');
select tests.eq(((select send_on from private.billing_dates('term', 'card', '2027-01-27')) = '2027-01-06')::int, 1, 'term sent 2 weeks before due');
-- Monthly bank debit, first session Monday 7 Dec: due Thu 3 Dec, but taken
-- Tue 1 Dec so it clears in time.
select tests.eq(((select charge_on from private.billing_dates('monthly', 'bank_debit', '2026-12-07')) = '2026-12-01')::int, 1, 'bank debit taken 4 business days ahead');

-- ---------------------------------------------------------------------------
-- Prices and settings
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.billing_price_items), 2, 'parent sees active prices only');
update public.billing_price_items set amount_cents = 1 where code = 'school_tutoring';
select tests.eq((select count(*) from public.billing_price_items where amount_cents = 1), 0, 'price unchanged');
select tests.eq((select count(*) from public.billing_settings), 0, 'parent cannot see settings');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal1');
set role authenticated;
select tests.eq((select count(*) from public.billing_price_items), 2, 'admin without two-step login gets parent-level view');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.billing_price_items), 3, 'admin sees all prices');
update public.billing_price_items set description = 'Updated' where code = 'school_tutoring';
select tests.eq((select count(*) from public.billing_price_items where description = 'Updated'), 1, 'admin edits a price');
select tests.fails($$insert into public.billing_price_items (code, name, amount_cents, session_level) values ('second_school', 'Second', 100, 'school')$$, 'two active prices for one level');
select tests.fails($$delete from public.billing_price_items where code = 'other_support'$$, 'prices are turned off, not deleted');
update public.billing_settings set override_by = 'admin';
select tests.eq((select count(*) from public.billing_settings where override_by = 'admin'), 0, 'staff admin cannot change settings');
reset role;

-- ---------------------------------------------------------------------------
-- Family billing accounts and kept rates
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails(format($$insert into public.billing_accounts (family_id, plan) values (%L, 'weekly')$$, :'fam1'), 'parent creates own billing account');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
insert into public.billing_accounts (family_id, bill_payer_id, plan) values
  (:'fam1', '00000000-0000-0000-0000-000000000001', 'weekly'),
  (:'fam2', '00000000-0000-0000-0000-000000000002', 'monthly');
select tests.fails(format($$update public.billing_accounts set paused = true where family_id = %L$$, :'fam1'), 'admin sets pause by hand');
select tests.fails(format($$update public.billing_accounts set stripe_payment_method_id = 'pm_x' where family_id = %L$$, :'fam1'), 'admin types a payment reference');
-- Pat's family keeps their old $80/hr rate.
insert into public.billing_family_rates (family_id, price_item_id, amount_cents, note)
select :'fam1', id, 8000, 'Kept rate' from public.billing_price_items where code = 'school_tutoring';
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.billing_accounts), 1, 'parent sees own billing account only');
select tests.fails($$select stripe_customer_id from public.billing_accounts$$, 'parent reads Stripe reference');
update public.billing_accounts set plan = 'term';
select tests.eq((select count(*) from public.billing_accounts where plan = 'term'), 0, 'parent cannot change plan');
select tests.eq((select count(*) from public.billing_family_rates), 0, 'parent cannot see kept rates');
select public.billing_accept_terms(:'fam1', '2026-10');
select tests.eq((select count(*) from public.billing_accounts where terms_version = '2026-10'), 1, 'parent accepts terms');
select tests.fails(format($$select public.billing_accept_terms(%L, '2026-10')$$, :'fam2'), 'parent accepts terms for another family');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.billing_accounts), 0, 'tutor sees no billing');
reset role;

select tests.claims(null);
-- Weekly families can't use bank debit (too slow); the method stays as it was.
select public.billing_save_payment_method(:'fam1', 'cus_1', 'pm_1', 'bank_debit');
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam1' and method = 'none' and payment_ready), 1, 'weekly stays off bank debit');
select public.billing_save_payment_method(:'fam1', 'cus_1', 'pm_card', 'card');
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam1' and method = 'card'), 1, 'card saved');
select public.billing_save_payment_method(:'fam2', 'cus_2', 'pm_becs', 'bank_debit', 'mandate_2');
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.fails(format($$select public.billing_save_payment_method(%L, 'cus_x', 'pm_x', 'card')$$, :'fam2'), 'browser saves a payment method');
reset role;
select tests.claims(null);

-- ---------------------------------------------------------------------------
-- Building an invoice: one line per session
-- ---------------------------------------------------------------------------
select tests.session(:'cara', :'mon1'::date, '16:00', 60) as s1 \gset
select tests.session(:'cara', :'mon1'::date + 2, '16:00', 45) as s2 \gset
select tests.session(:'cara', :'mon1'::date + 4, '16:00', 90) as s3 \gset
select tests.session(:'cara', :'mon1'::date + 5, '10:00', 60) as s_gone \gset
update public.sessions set status = 'cancelled', cancelled_at = now(), cancelled_by_role = 'family' where id = :'s_gone';

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails(format($$select public.billing_build_invoice(%L, %L, %L)$$, :'fam1', :'mon1', :'mon1'::date + 6), 'parent builds an invoice');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.billing_build_invoice(:'fam1', :'mon1', :'mon1'::date + 6) as inv1 \gset
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv1'), 3, 'one line per session, cancelled left off');
-- $80 kept rate: 1 hr + 1 hr (45 min minimum) + 1.5 hr.
select tests.eq((select subtotal_cents from public.billing_invoices where id = :'inv1'), 28000, 'kept rate and minimums');
select tests.eq((select total_cents from public.billing_invoices where id = :'inv1'), 28000, 'no credit, no discount for card');
select tests.eq((select gst_cents from public.billing_invoices where id = :'inv1'), 0, 'curriculum tutoring GST-free');
select tests.eq(((select due_on from public.billing_invoices where id = :'inv1') = :'mon1'::date - 4)::int, 1, 'due 4 days before first session');
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv1' and description like '%, Cara, General Maths' and description like '%4:00pm to 5:00pm%'), 1, 'line shows day, date, time, first name and subject');
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv1' and description like '%One%'), 0, 'no surname on invoice');
select tests.eq((select count(*) from public.billing_build_invoice(:'fam1', :'mon1', :'mon1'::date + 6) x where x is not null), 0, 'a session is never billed twice');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.billing_invoices), 0, 'parent does not see a draft');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.billing_approve_invoice(:'inv1');
select tests.fails(format($$select public.billing_approve_invoice(%L)$$, :'inv1'), 'approve twice');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.billing_invoices), 1, 'parent sees the sent invoice');
select tests.eq((select count(*) from public.billing_invoice_lines), 3, 'parent sees its lines');
select tests.fails(format($$update public.billing_invoices set total_cents = 0 where id = %L$$, :'inv1'), 'parent changes an invoice');
select tests.fails(format($$select public.billing_void_invoice(%L, 'Do not want it')$$, :'inv1'), 'parent cancels an invoice');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.billing_invoices), 0, 'other parent sees no invoices');
select tests.eq((select count(*) from public.billing_invoice_lines), 0, 'other parent sees no lines');
select tests.eq((select count(*) from public.billing_credit_balance(:'fam1') x where x is not null), 0, 'other parent cannot read credit balance');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.billing_invoices), 0, 'tutor sees no invoices');
reset role;

-- ---------------------------------------------------------------------------
-- Cancellation credits
-- ---------------------------------------------------------------------------
select tests.claims(null);
update public.sessions set status = 'cancelled', cancelled_by_role = 'family',
  cancelled_at = starts_at - interval '48 hours' where id = :'s1';
update public.sessions set status = 'cancelled', cancelled_by_role = 'family',
  cancelled_at = starts_at - interval '10 hours' where id = :'s2';
update public.sessions set status = 'no_show' where id = :'s3';
select tests.eq(public.billing_credit_cancellations(), 3, 'three sessions checked');
select tests.eq(public.billing_credit_cancellations(), 0, 'never credited twice');
-- $80 full + $40 half + nothing for the no-show.
select tests.eq(public.billing_credit_balance(:'fam1'), 12000, 'credit balance');

-- The next invoice uses the credit first.
select tests.session(:'cara', :'mon2'::date, '16:00', 60) as s4 \gset
select public.billing_build_invoice(:'fam1', :'mon2', :'mon2'::date + 6) as inv2 \gset
select tests.eq((select credit_applied_cents from public.billing_invoices where id = :'inv2'), 8000, 'credit used');
select tests.eq((select total_cents from public.billing_invoices where id = :'inv2'), 0, 'nothing left to pay');
select tests.eq(public.billing_credit_balance(:'fam1'), 4000, 'credit left over');
-- Cancelling the invoice returns the credit and frees the session.
select public.billing_void_invoice(:'inv2', 'Built by mistake');
select tests.eq(public.billing_credit_balance(:'fam1'), 12000, 'credit returned');
select tests.eq((select count(*) from public.billing_build_invoice(:'fam1', :'mon2', :'mon2'::date + 6) x where x is not null), 1, 'session billable again after cancel');

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.fails(format($$select public.billing_add_credit(%L, 1000, 'x')$$, :'fam1'), 'credit needs a reason');
select public.billing_add_credit(:'fam1', 1000, 'Sorry about the room change');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails(format($$select public.billing_add_credit(%L, 1000, 'Free money please')$$, :'fam1'), 'parent adds credit');
select tests.eq((select count(*) from public.billing_credits where kind = 'goodwill'), 1, 'parent sees own credits');
reset role;
select tests.claims(null);

-- ---------------------------------------------------------------------------
-- Pauses
-- ---------------------------------------------------------------------------
select due_on as due1 from public.billing_invoices where id = :'inv1' \gset
select tests.eq(private.billing_refresh_pause(:'fam1', :'due1')::int, 0, 'not paused on the due date');
select tests.eq(private.billing_refresh_pause(:'fam1', :'due1'::date + 1)::int, 1, 'paused the day after');
select tests.eq(private.billing_family_paused(:'fam1')::int, 1, 'scheduling sees the pause');
select tests.eq((select count(*) from public.billing_tutor_notices where kind = 'on_hold' and student_id = :'cara'), 1, 'tutor told sessions are on hold');
select tests.eq((select count(*) from public.billing_pause_events where family_id = :'fam1' and kind = 'paused'), 1, 'pause recorded');
select tests.eq((select count(*) from public.audit_log where action = 'billing_paused'), 1, 'pause in activity log');

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq(public.my_support_on_hold()::int, 1, 'parent sees on hold');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.billing_tutor_notices), 1, 'tutor sees own notice');
select tests.fails($$update public.billing_tutor_notices set sent_at = now()$$, 'tutor changes a notice');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq(public.my_support_on_hold()::int, 0, 'other family not on hold');
reset role;

-- Override: owner only, needs a reason and a date.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.fails(format($$select public.billing_override_pause(%L, 'Family asked nicely', private.billing_today() + 30)$$, :'fam1'), 'staff admin overrides');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails(format($$select public.billing_override_pause(%L, '', private.billing_today() + 30)$$, :'fam1'), 'override without reason');
select tests.fails(format($$select public.billing_override_pause(%L, 'Paying Friday', null)$$, :'fam1'), 'override without a date');
select tests.fails(format($$select public.billing_override_pause(%L, 'Paying Friday', private.billing_today() + 200)$$, :'fam1'), 'override too far ahead');
select public.billing_override_pause(:'fam1', 'Payment plan agreed', private.billing_today() + 30, '$100 a week from Friday');
reset role;
select tests.claims(null);
select tests.eq(private.billing_refresh_pause(:'fam1', :'due1'::date + 1)::int, 0, 'override lifts the pause');
select tests.eq((select count(*) from public.billing_tutor_notices where kind = 'back_on' and student_id = :'cara'), 1, 'tutor told sessions are back on');
select tests.eq(private.billing_refresh_pause(:'fam1', private.billing_today() + 31)::int, 1, 'pause returns when the override date passes');
update public.billing_pause_overrides set ended_at = now() where family_id = :'fam1';

-- Payments. A bank debit still processing doesn't count as overdue; a
-- failure pauses straight away; a success lifts it.
select public.billing_record_payment(:'inv1', 'stripe', 'pi_1', 'card', 28000, 'processing');
select tests.eq(private.billing_refresh_pause(:'fam1', :'due1'::date + 1)::int, 0, 'processing payment is not overdue');
select public.billing_record_payment(:'inv1', 'stripe', 'pi_1', 'card', 28000, 'failed', 'Card declined');
select tests.eq(private.billing_family_paused(:'fam1')::int, 1, 'failed payment pauses');
select public.billing_record_payment(:'inv1', 'stripe', 'pi_1', 'card', 28000, 'processing');
select tests.eq((select count(*) from public.billing_payments where provider_ref = 'pi_1' and status = 'failed'), 1, 'a late message never undoes a result');
select public.billing_record_payment(:'inv1', 'stripe', 'pi_2', 'card', 28000, 'succeeded');
select tests.eq((select count(*) from public.billing_invoices where id = :'inv1' and status = 'paid'), 1, 'invoice paid');
select tests.eq(private.billing_family_paused(:'fam1')::int, 0, 'payment lifts the pause');
select tests.fails(format($$select public.billing_void_invoice(%L, 'Too late now')$$, :'inv1'), 'paid invoice cannot be cancelled');

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.fails(format($$select public.billing_record_payment(%L, 'stripe', 'pi_fake', 'card', 28000, 'succeeded')$$, :'inv1'), 'browser records a payment');
select tests.eq((select count(*) from public.billing_payments), 2, 'parent sees own payments');
reset role;
select tests.claims(null);

-- ---------------------------------------------------------------------------
-- Monthly bank debit with discount, and GST where it applies
-- ---------------------------------------------------------------------------
update public.billing_price_items set gst_applies = true where code = 'tertiary_tutoring';
select date_trunc('month', private.billing_today() + 45)::date as month1 \gset
select tests.session(:'cal', :'month1'::date + 7, '15:00', 60) as c1 \gset
select tests.session(:'cal', :'month1'::date + 14, '15:00', 60) as c2 \gset
select tests.session(:'cal', :'month1'::date + 15, '15:00', 60, 'tertiary') as c3 \gset
select public.billing_build_invoice(:'fam2', :'month1', (:'month1'::date + interval '1 month - 1 day')::date) as inv3 \gset
select tests.eq((select subtotal_cents from public.billing_invoices where id = :'inv3'), 30500, 'new family pays $95 and $115');
select tests.eq((select gst_cents from public.billing_invoices where id = :'inv3'), 1045, 'GST only on the price that carries it');
select tests.eq((select discount_cents from public.billing_invoices where id = :'inv3'), private.billing_debit_discount(30500), 'bank debit discount applied');
select tests.eq((select (charge_on <= due_on)::int from public.billing_invoices where id = :'inv3'), 1, 'bank debit taken by the due date');
update public.billing_price_items set gst_applies = false where code = 'tertiary_tutoring';

-- The daily run finds nothing new to bill for sessions already invoiced.
select tests.eq(public.billing_build_due_invoices(:'month1'::date), 0, 'daily run skips billed sessions');
-- ...and bills a new session once its send date arrives.
select tests.session(:'cal', :'month1'::date + 20, '15:00', 60) as c4 \gset
select tests.eq(public.billing_build_due_invoices(:'month1'::date - 30), 0, 'not yet time to send');
select tests.eq(public.billing_build_due_invoices(:'month1'::date + 8), 0, 'one day before its send date');
select tests.eq(public.billing_build_due_invoices(:'month1'::date + 9), 1, 'daily run bills it on its send date');

-- ---------------------------------------------------------------------------
-- Server-only tables, settings, and signed-out visitors
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails($$select * from public.billing_webhook_events$$, 'webhook log is server-only');
select tests.fails($$select * from public.billing_xero_connection$$, 'Xero tokens are server-only');
update public.billing_settings set override_by = 'admin';
select tests.eq((select count(*) from public.billing_settings where override_by = 'admin'), 1, 'owner changes settings');
update public.billing_settings set override_by = 'owner';
select tests.eq((select count(*) from public.billing_pause_overrides), 1, 'owner sees overrides');
reset role;

select tests.claims(null);
set role anon;
select tests.fails($$select * from public.billing_invoices$$, 'anon reads invoices');
select tests.fails($$select * from public.billing_price_items$$, 'anon reads prices');
select tests.fails($$select private.billing_family_paused('00000000-0000-0000-0000-000000000000')$$, 'anon checks a pause');
reset role;

-- Leave other tests a clean slate.
delete from public.billing_payments;
delete from public.billing_credits;
delete from public.billing_invoices;
delete from public.billing_accounts;
delete from public.sessions where student_id in (:'cara', :'cal');
drop function tests.session(uuid, date, time, int, text);

\echo '  billing: all checks passed'
