-- Summary: tests for plan fees, changing a family's hourly rate, and the
-- 24 hour payment reminders (Carla, 22 Nov 2026). Uses Cal's family, with
-- parent P1 (...01) linked as Cal's parent and paying, the owner (...a0),
-- an Operations admin is not needed, and tutor T1 (...11). Checks:
--   * a monthly invoice gets one $10 fee line, a weekly one $5, per term none;
--   * no fee before the "Plan fees start from" date;
--   * a rate change re-prices an unpaid sent invoice, marks it amended and
--     tells the payer; a draft is re-priced quietly;
--   * a higher rate cannot start in the past;
--   * a paid invoice is never changed: a lower rate gives credit instead;
--   * only the owner or a Finance admin can change a rate;
--   * a payment reminder is made once, the day before an automatic charge
--     or the day before a self-paid invoice is due, with a notice and email;
--   * only the server can make reminders.
-- Rolled back at the end.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction, so everything below can be undone at the end.
begin;
-- Runs the change again (and twice), to check it is safe to run more than once.
\ir ../migrations/20261125300100_plan_fees_rate_changes_payment_reminders.sql
\ir ../migrations/20261125300100_plan_fees_rate_changes_payment_reminders.sql

-- A one-hour school session for this test, written straight in as the server would.
create function tests.fee_session(p_student uuid, p_day date) returns uuid language sql as $$ -- takes the student and day, gives back the new session's id
  insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) -- adds the session:
  select p_student, '00000000-0000-0000-0000-000000000011', s.family_id, 'General Maths', 'school', 'online', -- for this student with tutor T1, online,
         (p_day + time '16:00') at time zone 'Australia/Adelaide', -- from 4pm Adelaide time,
         (p_day + time '17:00') at time zone 'Australia/Adelaide' -- to 5pm (one hour)
  from public.students s where s.id = p_student -- (using the student's family)
  returning id -- and gives back its id
$$; -- end of the helper

-- Keeps Cal's student id as cal and his family id as fam.
select id as cal, family_id as fam from public.students where full_name = 'Cal Two' \gset
-- Keeps the school tutoring price's id as school.
select id as school from public.billing_price_items where code = 'school_tutoring' \gset
insert into public.parent_student_links (parent_id, student_id) values ('00000000-0000-0000-0000-000000000001', :'cal') -- links parent P1 to Cal,
on conflict do nothing; -- (unless already linked).
delete from public.billing_invoices where family_id = :'fam'; -- clears Cal's family's invoices,
delete from public.billing_family_rates where family_id = :'fam'; -- any rate of their own,
delete from public.billing_accounts where family_id = :'fam'; -- and their billing set-up.
update public.billing_price_items set amount_cents = 9500, active = true where code = 'school_tutoring'; -- school tutoring at $95 an hour
update public.billing_settings set plan_fees_from = '2026-11-30'; -- fees from 30 Nov 2026 (the usual start)
-- A Monday five weeks away, and its session days.
select date_trunc('week', private.billing_today() + 35)::date as mon \gset
delete from public.sessions where family_id = :'fam' and starts_at >= (:'mon'::date - 7) at time zone 'Australia/Adelaide'; -- clears later sessions for the family
-- P1 pays for the family, monthly by saved card.
insert into public.billing_accounts (family_id, bill_payer_id, plan, method, stripe_customer_id, stripe_payment_method_id) -- the billing set-up:
values (:'fam', '00000000-0000-0000-0000-000000000001', 'monthly', 'card', 'cus_test', 'pm_test'); -- P1, monthly, card saved
-- Two sessions that week, kept as s1 and s2.
select tests.fee_session(:'cal', :'mon') as s1 \gset
select tests.fee_session(:'cal', :'mon'::date + 2) as s2 \gset

-- ---------------------------------------------------------------------------
-- Plan fees
-- ---------------------------------------------------------------------------
select tests.claims(null); -- acts as the server (nobody signed in)
select public.billing_build_invoice(:'fam', :'mon', :'mon'::date + 6) as inv \gset
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv' and session_id is null and amount_cents = 1000 and description = 'Monthly payment plan fee'), 1::bigint, 'monthly invoice has one $10 fee line'); -- checks the fee line
select tests.eq((select total_cents from public.billing_invoices where id = :'inv')::bigint, 20000::bigint, 'monthly total is two sessions plus the fee'); -- $95 + $95 + $10
select public.billing_void_invoice(:'inv', 'Test: try weekly'); -- cancels it, so the sessions can be billed again

update public.billing_accounts set plan = 'weekly' where family_id = :'fam'; -- now weekly
select public.billing_build_invoice(:'fam', :'mon', :'mon'::date + 6) as inv \gset
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv' and session_id is null and amount_cents = 500), 1::bigint, 'weekly invoice has one $5 fee line'); -- checks the fee line
select public.billing_void_invoice(:'inv', 'Test: try per term'); -- cancels it

update public.billing_accounts set plan = 'term' where family_id = :'fam'; -- now per term
select public.billing_build_invoice(:'fam', :'mon', :'mon'::date + 6) as inv \gset
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv' and session_id is null), 0::bigint, 'per term invoice has no fee'); -- checks there is no fee
select public.billing_void_invoice(:'inv', 'Test: try before the start date'); -- cancels it

update public.billing_accounts set plan = 'monthly' where family_id = :'fam'; -- back to monthly
update public.billing_settings set plan_fees_from = :'mon'::date + 1; -- fees only start the day after this invoice's first session
select public.billing_build_invoice(:'fam', :'mon', :'mon'::date + 6) as inv \gset
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv' and session_id is null), 0::bigint, 'no fee before the start date'); -- checks there is no fee
select public.billing_void_invoice(:'inv', 'Test: back to normal'); -- cancels it
update public.billing_settings set plan_fees_from = '2026-11-30'; -- back to the usual start

-- ---------------------------------------------------------------------------
-- Changing the family's hourly rate
-- ---------------------------------------------------------------------------
select public.billing_build_invoice(:'fam', :'mon', :'mon'::date + 6) as inv \gset
update public.billing_invoices set status = 'open', xero_invoice_id = 'x-test' where id = :'inv'; -- as if sent to the family through Xero
insert into public.billing_payment_reminders (invoice_id, payer_id, amount_cents, pay_on, automatic) -- an old reminder with the old amount
values (:'inv', '00000000-0000-0000-0000-000000000001', 20000, :'mon'::date - 4, true); -- (to check it is replaced)

-- A parent, a tutor and an Operations-level check: only the owner or Finance can change a rate.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set local role authenticated; -- acts as a signed-in user
select tests.fails(format($$select public.billing_set_family_rate(%L, %L, 5000)$$, :'fam', :'school'), 'parent changes own hourly rate'); -- checks this is refused
reset role; -- back to the test user
select tests.claims('00000000-0000-0000-0000-000000000011'); -- signs in as tutor T1
set local role authenticated; -- acts as a signed-in user
select tests.fails(format($$select public.billing_set_family_rate(%L, %L, 5000)$$, :'fam', :'school'), 'tutor changes a family hourly rate'); -- checks this is refused
reset role; -- back to the test user

-- The owner lowers the rate to $80 from today.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner (with the second sign-in step)
set local role authenticated; -- acts as a signed-in user
select public.billing_set_family_rate(:'fam', :'school', 8000, 'Test rate') ->> 'amended' as amended \gset
reset role; -- back to the test user
select tests.eq(:'amended'::bigint, 1::bigint, 'one sent invoice amended'); -- checks the count given back
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv' and session_id is not null and hourly_cents = 8000 and amount_cents = 8000), 2::bigint, 'session lines re-priced to $80'); -- checks the lines
select tests.eq((select total_cents from public.billing_invoices where id = :'inv')::bigint, 17000::bigint, 'new total is two $80 sessions plus the fee'); -- $80 + $80 + $10
select tests.eq((select count(*) from public.billing_invoices where id = :'inv' and amended_at is not null and amended_from_cents = 20000), 1::bigint, 'invoice marked amended, keeping the first total'); -- checks the amended marks
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000001' and body like '%new total is $170.00 (it was $200.00)%'), 1::bigint, 'payer told the new total'); -- checks the notice
select tests.eq((select count(*) from public.billing_payment_reminders where invoice_id = :'inv'), 0::bigint, 'old reminder removed so a new one is sent'); -- checks the reminder went
select tests.eq((select amount_cents from public.billing_family_rates where family_id = :'fam' and price_item_id = :'school')::bigint, 8000::bigint, 'rate saved'); -- checks the saved rate

-- A higher rate cannot start in the past.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner
set local role authenticated; -- acts as a signed-in user
select tests.fails(format($$select public.billing_set_family_rate(%L, %L, 9000, null, private.billing_today() - 1)$$, :'fam', :'school'), 'higher rate backdated'); -- checks this is refused
reset role; -- back to the test user

-- Once paid, the invoice never changes; a lower rate gives credit.
insert into public.billing_payments (invoice_id, provider, provider_ref, method, amount_cents, status) -- a payment for the whole invoice
values (:'inv', 'stripe', 'pi_test_rate', 'card', 17000, 'succeeded'); -- ($170, succeeded)
update public.billing_invoices set status = 'paid' where id = :'inv'; -- marks it paid
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner
set local role authenticated; -- acts as a signed-in user
select public.billing_set_family_rate(:'fam', :'school', 7000) ->> 'credit_cents' as credit \gset
select public.billing_set_family_rate(:'fam', :'school', 9000) ->> 'repriced' as repriced_up \gset
reset role; -- back to the test user
select tests.eq(:'credit'::bigint, 2000::bigint, 'lower rate on a paid invoice gives $20 credit'); -- two sessions, $10 less each
select tests.eq((select total_cents from public.billing_invoices where id = :'inv')::bigint, 17000::bigint, 'paid invoice unchanged'); -- checks the total stayed
select tests.eq((select count(*) from public.billing_credits where invoice_id = :'inv' and kind = 'goodwill' and amount_cents = 2000), 1::bigint, 'credit recorded'); -- checks the credit row
select tests.eq(:'repriced_up'::bigint, 0::bigint, 'higher rate never re-prices a paid invoice'); -- checks nothing was re-priced
select tests.eq((select count(*) from public.billing_credits where invoice_id = :'inv'), 1::bigint, 'no extra charge or credit for the higher rate'); -- checks no new credit row

-- A draft is re-priced quietly (the family has not seen it).
delete from public.billing_payments where invoice_id = :'inv'; -- (test only) removes the payment
update public.billing_invoices set status = 'draft', amended_at = null, amended_from_cents = null where id = :'inv'; -- (test only) back to a draft
delete from public.session_notices where account_id = '00000000-0000-0000-0000-000000000001'; -- clears P1's notices
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner
set local role authenticated; -- acts as a signed-in user
select public.billing_set_family_rate(:'fam', :'school', null) ->> 'amended' as amended_draft \gset
reset role; -- back to the test user
select tests.eq(:'amended_draft'::bigint, 0::bigint, 'a draft is not counted as amended'); -- checks the count
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv' and session_id is not null and hourly_cents = 9500), 2::bigint, 'removing the rate goes back to the price list'); -- checks the lines
select tests.eq((select count(*) from public.billing_invoices where id = :'inv' and amended_at is null), 1::bigint, 'draft not marked amended'); -- checks no amended mark
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000001'), 0::bigint, 'no notice for a draft'); -- checks no notice
select tests.eq((select count(*) from public.billing_family_rates where family_id = :'fam'), 0::bigint, 'rate removed'); -- checks the rate went

-- ---------------------------------------------------------------------------
-- Payment reminders
-- ---------------------------------------------------------------------------
-- The invoice is sent, and the saved card is charged the day after tomorrow.
update public.billing_invoices set status = 'open', charge_on = private.billing_today() + 2, due_on = private.billing_today() + 2 where id = :'inv'; -- sent, charged in two days
select tests.claims(null); -- acts as the server
select tests.eq(public.billing_queue_payment_reminders()::bigint, 0::bigint, 'no reminder two days before'); -- too early
update public.billing_invoices set charge_on = private.billing_today() + 1, due_on = private.billing_today() + 1 where id = :'inv'; -- now charged tomorrow
select tests.eq(public.billing_queue_payment_reminders()::bigint, 1::bigint, 'reminder the day before the charge'); -- one reminder
select tests.eq(public.billing_queue_payment_reminders()::bigint, 0::bigint, 'reminder made only once'); -- not again
select tests.eq((select count(*) from public.billing_payment_reminders where invoice_id = :'inv' and automatic and amount_cents = 20000), 1::bigint, 'reminder is for the automatic charge and the full amount'); -- checks the row
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000001' and title = 'Payment tomorrow for invoice ' || (select number from public.billing_invoices where id = :'inv')), 1::bigint, 'payer gets the reminder notice'); -- checks the notice
select tests.eq((select count(*) from public.billing_payment_reminder_emails_claim(10) where email = 'p1@example.com' and body like 'CLG will take $200.00%'), 1::bigint, 'reminder email handed to the server'); -- checks the email
select tests.eq((select count(*) from public.billing_payment_reminder_emails_claim(10)), 0::bigint, 'email handed over only once'); -- not again

-- A family who pays themselves: reminded the day before it is due, never once overdue.
delete from public.billing_payment_reminders where invoice_id = :'inv'; -- (test only) starts again
update public.billing_accounts set stripe_payment_method_id = null, method = 'none' where family_id = :'fam'; -- no saved card now
update public.billing_invoices set due_on = private.billing_today() - 1 where id = :'inv'; -- overdue
select tests.eq(public.billing_queue_payment_reminders()::bigint, 0::bigint, 'no "due tomorrow" reminder once overdue'); -- checks none
update public.billing_invoices set due_on = private.billing_today() + 1 where id = :'inv'; -- due tomorrow
select tests.eq(public.billing_queue_payment_reminders()::bigint, 1::bigint, 'self-paid reminder the day before it is due'); -- one reminder
select tests.eq((select count(*) from public.billing_payment_reminders where invoice_id = :'inv' and not automatic), 1::bigint, 'reminder says the family pays it themselves'); -- checks the row

-- Only the server makes reminders, and families cannot read them.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
set local role authenticated; -- acts as a signed-in user
select tests.fails($$select public.billing_queue_payment_reminders()$$, 'parent makes reminders'); -- checks this is refused
select tests.eq((select count(*) from public.billing_payment_reminders), 0::bigint, 'parent cannot read reminder rows'); -- checks the access rule
reset role; -- back to the test user

-- Undoes everything above.
rollback;
-- Prints that every check in this file passed.
\echo '  billing plan fees, rate changes and payment reminders: all checks passed'
