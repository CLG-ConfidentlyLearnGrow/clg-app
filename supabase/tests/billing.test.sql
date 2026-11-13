-- Billing: prices, family accounts, invoices built from sessions, credits,
-- payments and automatic pauses. Runs after access_rules.test.sql and
-- reuses its people: owner (...a0), staff admin (...b0), tutor T1 (...11),
-- parents P1 (...01, Cara's family) and P2 (...02, Cal's family).

-- The billing migration must be safe to run twice.
-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the database change 20261027230100_billing.sql first, as this test needs it.
\ir ../migrations/20261027230100_billing.sql
-- Re-running an older billing file resets its rules, so apply admin levels again.
-- Runs the database change 20261029900200_admin_levels.sql first, as this test needs it.
\ir ../migrations/20261029900200_admin_levels.sql

-- Keeps Cara's student id as cara and her family id as fam1.
select id as cara, family_id as fam1 from public.students where full_name = 'Cara One' \gset
-- Keeps Cal's student id as cal and his family id as fam2.
select id as cal, family_id as fam2 from public.students where full_name = 'Cal Two' \gset
-- Monday of the week two weeks from now, and the next Monday after it.
select date_trunc('week', private.billing_today() + 14)::date as mon1, -- Keeps the Monday two weeks away as mon1,
       -- and the Monday three weeks away as mon2.
       date_trunc('week', private.billing_today() + 21)::date as mon2 \gset

-- A session for tests, written straight in as the server would.
create function tests.session(p_student uuid, p_day date, p_start time, p_minutes int, p_level text default 'school') -- A test helper that adds a session with tutor T1 and gives back its id. It takes the student, day, start, minutes and level:
returns uuid language sql as $$ -- (gives back the new session's id)
  insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) -- Adds the session:
  select p_student, '00000000-0000-0000-0000-000000000011', s.family_id, 'General Maths', p_level, 'online', -- for this student with tutor T1, General Maths, online,
         (p_day + p_start) at time zone 'Australia/Adelaide', -- starting at the given time in Adelaide,
         (p_day + p_start + make_interval(mins => p_minutes)) at time zone 'Australia/Adelaide' -- ending the given minutes later,
  from public.students s where s.id = p_student -- (using the student's family),
  returning id -- and hands back its id.
$$; -- (end of the helper)
grant execute on function tests.session(uuid, date, time, int, text) to authenticated; -- Lets signed-in test users run it.

-- ---------------------------------------------------------------------------
-- Money rules
-- ---------------------------------------------------------------------------
select tests.eq(private.billing_minutes(45), 60, '45 min charged as 1 hr'); -- Checks: 45 min charged as 1 hr.
select tests.eq(private.billing_minutes(61), 90, 'half-hour steps'); -- Checks: half-hour steps.
select tests.eq(private.billing_minutes(120), 120, '2 hr stays 2 hr'); -- Checks: 2 hr stays 2 hr.
select tests.eq(private.billing_fee_cents(38000, 'card'), 657, 'card fee on $380'); -- Checks: card fee on $380.
select tests.eq(private.billing_fee_cents(38000, 'bank_debit'), 350, 'bank debit fee capped at $3.50'); -- Checks: bank debit fee capped at $3.50.
select tests.eq(private.billing_debit_discount(38000), 154, 'bank debit discount is half the saving'); -- Checks: bank debit discount is half the saving.
select tests.eq(private.billing_debit_discount(9500), 31, 'discount on $95'); -- Checks: discount on $95.
select tests.eq(private.billing_cancel_credit_percent(now() + interval '30 hours', now(), 'family', 'cancelled'), 100, 'more than 24hr notice'); -- Checks: more than 24hr notice.
select tests.eq(private.billing_cancel_credit_percent(now() + interval '24 hours', now(), 'family', 'cancelled'), 50, 'exactly 24hr notice'); -- Checks: exactly 24hr notice.
select tests.eq(private.billing_cancel_credit_percent(now() + interval '2 hours', now(), 'family', 'cancelled'), 50, '2hr notice'); -- Checks: 2hr notice.
select tests.eq(private.billing_cancel_credit_percent(now() + interval '1 hour', now(), 'family', 'cancelled'), 0, 'under 2hr notice'); -- Checks: under 2hr notice.
select tests.eq(private.billing_cancel_credit_percent(now() + interval '1 hour', now(), 'tutor', 'cancelled'), 100, 'tutor cancels: full credit'); -- Checks: tutor cancels: full credit.
select tests.eq(private.billing_cancel_credit_percent(now() + interval '1 hour', now(), 'admin', 'cancelled'), 100, 'CLG cancels: full credit'); -- Checks: CLG cancels: full credit.
select tests.eq(private.billing_cancel_credit_percent(now() - interval '1 hour', null, null, 'no_show'), 0, 'no-show: no credit'); -- Checks: no-show: no credit.
-- Monday 7 Dec 2026: 4 business days before is Tuesday 1 Dec.
select tests.eq((private.business_days_before('2026-12-07', 4) = '2026-12-01')::int, 1, 'business days skip weekends'); -- Checks: business days skip weekends.
select tests.eq(((select due_on from private.billing_dates('weekly', 'card', '2026-12-07')) = '2026-12-03')::int, 1, 'weekly due 4 days before'); -- Checks: weekly due 4 days before.
select tests.eq(((select send_on from private.billing_dates('weekly', 'card', '2026-12-07')) = '2026-11-26')::int, 1, 'weekly sent 1 week before due'); -- Checks: weekly sent 1 week before due.
select tests.eq(((select due_on from private.billing_dates('term', 'card', '2027-01-27')) = '2027-01-20')::int, 1, 'term due 1 week before'); -- Checks: term due 1 week before.
select tests.eq(((select send_on from private.billing_dates('term', 'card', '2027-01-27')) = '2027-01-06')::int, 1, 'term sent 2 weeks before due'); -- Checks: term sent 2 weeks before due.
-- Monthly bank debit, first session Monday 7 Dec: due Thu 3 Dec, but taken
-- Tue 1 Dec so it clears in time.
select tests.eq(((select charge_on from private.billing_dates('monthly', 'bank_debit', '2026-12-07')) = '2026-12-01')::int, 1, 'bank debit taken 4 business days ahead'); -- Checks: bank debit taken 4 business days ahead.

-- ---------------------------------------------------------------------------
-- Prices and settings
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_price_items), 4, 'parent sees active prices only (tutoring and drafting, school and tertiary)'); -- Checks: parent sees active prices only (tutoring and drafting, school and tertiary).
select tests.eq((select count(*) from public.billing_price_items where code like 'drafting_%' and not gst_applies -- Checks the drafting prices: 90 dollars school, 110 tertiary, GST-free:
  and amount_cents in (9000, 11000)), 2, 'drafting $90 school, $110 tertiary, GST-free'); -- (two price items).
update public.billing_price_items set amount_cents = 1 where code = 'school_tutoring'; -- Tries to change the school tutoring price.
select tests.eq((select count(*) from public.billing_price_items where amount_cents = 1), 0, 'price unchanged'); -- Checks: price unchanged.
select tests.eq((select count(*) from public.billing_settings), 0, 'parent cannot see settings'); -- Checks: parent cannot see settings.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal1'); -- Signs in as test account ...b0.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_price_items), 4, 'admin without two-step login gets parent-level view'); -- Checks: admin without two-step login gets parent-level view.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_price_items), 6, 'admin sees all prices'); -- Checks: admin sees all prices (including the term review price, off until set).
-- Prices are a billing rule: only the owner changes them.
update public.billing_price_items set description = 'Updated' where code = 'school_tutoring'; -- Tries to change its description.
select tests.eq((select count(*) from public.billing_price_items where description = 'Updated'), 0, 'operations admin cannot edit a price'); -- Checks: operations admin cannot edit a price.
update public.billing_settings set override_by = 'admin'; -- Lets any admin override a pause.
select tests.eq((select count(*) from public.billing_settings where override_by = 'admin'), 0, 'staff admin cannot change settings'); -- Checks: staff admin cannot change settings.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
update public.billing_price_items set description = 'Updated' where code = 'school_tutoring'; -- Tries to change the description again.
select tests.eq((select count(*) from public.billing_price_items where description = 'Updated'), 1, 'owner edits a price'); -- Checks: owner edits a price.
select tests.fails($$insert into public.billing_price_items (code, name, amount_cents, session_level) values ('second_school', 'Second', 100, 'school')$$, 'two active prices for one level'); -- Checks this is refused: two active prices for one level.
select tests.fails($$delete from public.billing_price_items where code = 'other_support'$$, 'prices are turned off, not deleted'); -- Checks this is refused: prices are turned off, not deleted.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Family billing accounts and kept rates
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$insert into public.billing_accounts (family_id, plan) values (%L, 'weekly')$$, :'fam1'), 'parent creates own billing account'); -- Checks this is refused: parent creates own billing account.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
insert into public.billing_accounts (family_id, bill_payer_id, plan) values -- Sets up billing for both families:
  (:'fam1', '00000000-0000-0000-0000-000000000001', 'weekly'), -- Cara's family pays weekly (parent P1),
  (:'fam2', '00000000-0000-0000-0000-000000000002', 'monthly'); -- Cal's family pays monthly (parent P2).
select tests.fails(format($$update public.billing_accounts set paused = true where family_id = %L$$, :'fam1'), 'admin sets pause by hand'); -- Checks this is refused: admin sets pause by hand.
select tests.fails(format($$update public.billing_accounts set stripe_payment_method_id = 'pm_x' where family_id = %L$$, :'fam1'), 'admin types a payment reference'); -- Checks this is refused: admin types a payment reference.
-- Kept rates are prices: operations can't set them, the owner can.
select tests.fails($$insert into public.billing_family_rates (family_id, price_item_id, amount_cents, note) -- Checks an operations admin can't set a kept rate:
  select (select id from public.families order by name limit 1), id, 8000, 'Kept rate' from public.billing_price_items where code = 'school_tutoring'$$, 'operations sets a kept rate'); -- (an 80 dollar school rate for a family).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Pat's family keeps their old $80/hr rate.
insert into public.billing_family_rates (family_id, price_item_id, amount_cents, note) -- Gives Cara's family a kept rate:
select :'fam1', id, 8000, 'Kept rate' from public.billing_price_items where code = 'school_tutoring'; -- (80 dollars an hour for school tutoring).
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_accounts), 1, 'parent sees own billing account only'); -- Checks: parent sees own billing account only.
select tests.fails($$select stripe_customer_id from public.billing_accounts$$, 'parent reads Stripe reference'); -- Checks this is refused: parent reads Stripe reference.
update public.billing_accounts set plan = 'term'; -- Tries to change the plan.
select tests.eq((select count(*) from public.billing_accounts where plan = 'term'), 0, 'parent cannot change plan'); -- Checks: parent cannot change plan.
select tests.eq((select count(*) from public.billing_family_rates), 0, 'parent cannot see kept rates'); -- Checks: parent cannot see kept rates.
select public.billing_accept_terms(:'fam1', '2026-10'); -- Accepts the billing terms for Cara's family.
select tests.eq((select count(*) from public.billing_accounts where terms_version = '2026-10'), 1, 'parent accepts terms'); -- Checks: parent accepts terms.
select tests.fails(format($$select public.billing_accept_terms(%L, '2026-10')$$, :'fam2'), 'parent accepts terms for another family'); -- Checks this is refused: parent accepts terms for another family.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_accounts), 0, 'tutor sees no billing'); -- Checks: tutor sees no billing.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
-- Weekly families can't use bank debit (too slow); the method stays as it was.
select public.billing_save_payment_method(:'fam1', 'cus_1', 'pm_1', 'bank_debit'); -- Saves a bank debit for Cara's family.
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam1' and method = 'none' and payment_ready), 1, 'weekly stays off bank debit'); -- Checks: weekly stays off bank debit.
select public.billing_save_payment_method(:'fam1', 'cus_1', 'pm_card', 'card'); -- Swaps it for a card.
select tests.eq((select count(*) from public.billing_accounts where family_id = :'fam1' and method = 'card'), 1, 'card saved'); -- Checks: card saved.
select public.billing_save_payment_method(:'fam2', 'cus_2', 'pm_becs', 'bank_debit', 'mandate_2'); -- Saves a bank debit for Cal's family, with its mandate.
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_save_payment_method(%L, 'cus_x', 'pm_x', 'card')$$, :'fam2'), 'browser saves a payment method'); -- Checks this is refused: browser saves a payment method.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- ---------------------------------------------------------------------------
-- Building an invoice: one line per session
-- ---------------------------------------------------------------------------
-- A 1-hr session on mon1, kept as s1.
select tests.session(:'cara', :'mon1'::date, '16:00', 60) as s1 \gset
-- A 45-minute session two days later, kept as s2.
select tests.session(:'cara', :'mon1'::date + 2, '16:00', 45) as s2 \gset
-- A 1.5-hr session four days later, kept as s3.
select tests.session(:'cara', :'mon1'::date + 4, '16:00', 90) as s3 \gset
-- A session five days later, kept as s_gone.
select tests.session(:'cara', :'mon1'::date + 5, '10:00', 60) as s_gone \gset
update public.sessions set status = 'cancelled', cancelled_at = now(), cancelled_by_role = 'family' where id = :'s_gone'; -- The family cancels it.

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_build_invoice(%L, %L, %L)$$, :'fam1', :'mon1', :'mon1'::date + 6), 'parent builds an invoice'); -- Checks this is refused: parent builds an invoice.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- Builds Cara's family's invoice for that week, kept as inv1.
select public.billing_build_invoice(:'fam1', :'mon1', :'mon1'::date + 6) as inv1 \gset
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv1'), 3, 'one line per session, cancelled left off'); -- Checks: one line per session, cancelled left off.
-- $80 kept rate: 1 hr + 1 hr (45 min minimum) + 1.5 hr.
select tests.eq((select subtotal_cents from public.billing_invoices where id = :'inv1'), 28000, 'kept rate and minimums'); -- Checks: kept rate and minimums.
select tests.eq((select total_cents from public.billing_invoices where id = :'inv1'), 28000, 'no credit, no discount for card'); -- Checks: no credit, no discount for card.
select tests.eq((select gst_cents from public.billing_invoices where id = :'inv1'), 0, 'curriculum tutoring GST-free'); -- Checks: curriculum tutoring GST-free.
select tests.eq(((select due_on from public.billing_invoices where id = :'inv1') = :'mon1'::date - 4)::int, 1, 'due 4 days before first session'); -- Checks: due 4 days before first session.
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv1' and description like '%, Cara, General Maths' and description like '%4:00pm to 5:00pm%'), 1, 'line shows day, date, time, first name and subject'); -- Checks: line shows day, date, time, first name and subject.
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv1' and description like '%One%'), 0, 'no surname on invoice'); -- Checks: no surname on invoice.
select tests.eq((select count(*) from public.billing_build_invoice(:'fam1', :'mon1', :'mon1'::date + 6) x where x is not null), 0, 'a session is never billed twice'); -- Checks: a session is never billed twice.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_invoices), 0, 'parent does not see a draft'); -- Checks: parent does not see a draft.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.billing_approve_invoice(:'inv1'); -- Approves the invoice.
select tests.fails(format($$select public.billing_approve_invoice(%L)$$, :'inv1'), 'approve twice'); -- Checks this is refused: approve twice.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_invoices), 1, 'parent sees the sent invoice'); -- Checks: parent sees the sent invoice.
select tests.eq((select count(*) from public.billing_invoice_lines), 3, 'parent sees its lines'); -- Checks: parent sees its lines.
select tests.fails(format($$update public.billing_invoices set total_cents = 0 where id = %L$$, :'inv1'), 'parent changes an invoice'); -- Checks this is refused: parent changes an invoice.
select tests.fails(format($$select public.billing_void_invoice(%L, 'Do not want it')$$, :'inv1'), 'parent cancels an invoice'); -- Checks this is refused: parent cancels an invoice.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_invoices), 0, 'other parent sees no invoices'); -- Checks: other parent sees no invoices.
select tests.eq((select count(*) from public.billing_invoice_lines), 0, 'other parent sees no lines'); -- Checks: other parent sees no lines.
select tests.eq((select count(*) from public.billing_credit_balance(:'fam1') x where x is not null), 0, 'other parent cannot read credit balance'); -- Checks: other parent cannot read credit balance.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_invoices), 0, 'tutor sees no invoices'); -- Checks: tutor sees no invoices.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Cancellation credits
-- ---------------------------------------------------------------------------
select tests.claims(null); -- Signs out, so no one is signed in.
update public.sessions set status = 'cancelled', cancelled_by_role = 'family', -- The family cancels the first session:
  cancelled_at = starts_at - interval '48 hours' where id = :'s1'; -- 2 days before.
update public.sessions set status = 'cancelled', cancelled_by_role = 'family', -- The family cancels the second session:
  cancelled_at = starts_at - interval '10 hours' where id = :'s2'; -- 10 hours before.
update public.sessions set status = 'no_show' where id = :'s3'; -- The third session is a no-show.
select tests.eq(public.billing_credit_cancellations(), 3, 'three sessions checked'); -- Checks: three sessions checked.
select tests.eq(public.billing_credit_cancellations(), 0, 'never credited twice'); -- Checks: never credited twice.
-- $80 full + $40 half + nothing for the no-show.
select tests.eq(public.billing_credit_balance(:'fam1'), 12000, 'credit balance'); -- Checks: credit balance.

-- The next invoice uses the credit first.
-- A 1-hr session on mon2, kept as s4.
select tests.session(:'cara', :'mon2'::date, '16:00', 60) as s4 \gset
-- Builds the invoice for that week, kept as inv2.
select public.billing_build_invoice(:'fam1', :'mon2', :'mon2'::date + 6) as inv2 \gset
select tests.eq((select credit_applied_cents from public.billing_invoices where id = :'inv2'), 8000, 'credit used'); -- Checks: credit used.
select tests.eq((select total_cents from public.billing_invoices where id = :'inv2'), 0, 'nothing left to pay'); -- Checks: nothing left to pay.
select tests.eq(public.billing_credit_balance(:'fam1'), 4000, 'credit left over'); -- Checks: credit left over.
-- Cancelling the invoice returns the credit and frees the session.
select public.billing_void_invoice(:'inv2', 'Built by mistake'); -- Voids it (built by mistake).
select tests.eq(public.billing_credit_balance(:'fam1'), 12000, 'credit returned'); -- Checks: credit returned.
select tests.eq((select count(*) from public.billing_build_invoice(:'fam1', :'mon2', :'mon2'::date + 6) x where x is not null), 1, 'session billable again after cancel'); -- Checks: session billable again after cancel.

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_add_credit(%L, 1000, 'x')$$, :'fam1'), 'credit needs a reason'); -- Checks this is refused: credit needs a reason.
select public.billing_add_credit(:'fam1', 1000, 'Sorry about the room change'); -- Adds a 10 dollar credit.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_add_credit(%L, 1000, 'Free money please')$$, :'fam1'), 'parent adds credit'); -- Checks this is refused: parent adds credit.
select tests.eq((select count(*) from public.billing_credits where kind = 'goodwill'), 1, 'parent sees own credits'); -- Checks: parent sees own credits.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- ---------------------------------------------------------------------------
-- Pauses
-- ---------------------------------------------------------------------------
-- Keeps the first invoice's due date as due1.
select due_on as due1 from public.billing_invoices where id = :'inv1' \gset
select tests.eq(private.billing_refresh_pause(:'fam1', :'due1')::int, 0, 'not paused on the due date'); -- Checks: not paused on the due date.
select tests.eq(private.billing_refresh_pause(:'fam1', :'due1'::date + 1)::int, 1, 'paused the day after'); -- Checks: paused the day after.
select tests.eq(private.billing_family_paused(:'fam1')::int, 1, 'scheduling sees the pause'); -- Checks: scheduling sees the pause.
select tests.eq((select count(*) from public.billing_tutor_notices where kind = 'on_hold' and student_id = :'cara'), 1, 'tutor told sessions are on hold'); -- Checks: tutor told sessions are on hold.
select tests.eq((select count(*) from public.billing_pause_events where family_id = :'fam1' and kind = 'paused'), 1, 'pause recorded'); -- Checks: pause recorded.
select tests.eq((select count(*) from public.audit_log where action = 'billing_paused'), 1, 'pause in activity log'); -- Checks: pause in activity log.

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(public.my_support_on_hold()::int, 1, 'parent sees on hold'); -- Checks: parent sees on hold.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.billing_tutor_notices), 1, 'tutor sees own notice'); -- Checks: tutor sees own notice.
select tests.fails($$update public.billing_tutor_notices set sent_at = now()$$, 'tutor changes a notice'); -- Checks this is refused: tutor changes a notice.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq(public.my_support_on_hold()::int, 0, 'other family not on hold'); -- Checks: other family not on hold.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Override: owner only, needs a reason and a date.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_override_pause(%L, 'Family asked nicely', private.billing_today() + 30)$$, :'fam1'), 'staff admin overrides'); -- Checks this is refused: staff admin overrides.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_override_pause(%L, '', private.billing_today() + 30)$$, :'fam1'), 'override without reason'); -- Checks this is refused: override without reason.
select tests.fails(format($$select public.billing_override_pause(%L, 'Paying Friday', null)$$, :'fam1'), 'override without a date'); -- Checks this is refused: override without a date.
select tests.fails(format($$select public.billing_override_pause(%L, 'Paying Friday', private.billing_today() + 200)$$, :'fam1'), 'override too far ahead'); -- Checks this is refused: override too far ahead.
select public.billing_override_pause(:'fam1', 'Payment plan agreed', private.billing_today() + 30, '$100 a week from Friday'); -- The owner overrides the pause with a payment plan for 30 days.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq(private.billing_refresh_pause(:'fam1', :'due1'::date + 1)::int, 0, 'override lifts the pause'); -- Checks: override lifts the pause.
select tests.eq((select count(*) from public.billing_tutor_notices where kind = 'back_on' and student_id = :'cara'), 1, 'tutor told sessions are back on'); -- Checks: tutor told sessions are back on.
select tests.eq(private.billing_refresh_pause(:'fam1', private.billing_today() + 31)::int, 1, 'pause returns when the override date passes'); -- Checks: pause returns when the override date passes.
update public.billing_pause_overrides set ended_at = now() where family_id = :'fam1'; -- Ends the override.

-- Payments. A bank debit still processing doesn't count as overdue; a
-- failure pauses straight away; a success lifts it.
select public.billing_record_payment(:'inv1', 'stripe', 'pi_1', 'card', 28000, 'processing'); -- A card payment starts.
select tests.eq(private.billing_refresh_pause(:'fam1', :'due1'::date + 1)::int, 0, 'processing payment is not overdue'); -- Checks: processing payment is not overdue.
select public.billing_record_payment(:'inv1', 'stripe', 'pi_1', 'card', 28000, 'failed', 'Card declined'); -- It fails (card declined).
select tests.eq(private.billing_family_paused(:'fam1')::int, 1, 'failed payment pauses'); -- Checks: failed payment pauses.
select public.billing_record_payment(:'inv1', 'stripe', 'pi_1', 'card', 28000, 'processing'); -- It starts again.
select tests.eq((select count(*) from public.billing_payments where provider_ref = 'pi_1' and status = 'failed'), 1, 'a late message never undoes a result'); -- Checks: a late message never undoes a result.
select public.billing_record_payment(:'inv1', 'stripe', 'pi_2', 'card', 28000, 'succeeded'); -- A new payment succeeds.
select tests.eq((select count(*) from public.billing_invoices where id = :'inv1' and status = 'paid'), 1, 'invoice paid'); -- Checks: invoice paid.
select tests.eq(private.billing_family_paused(:'fam1')::int, 0, 'payment lifts the pause'); -- Checks: payment lifts the pause.
select tests.fails(format($$select public.billing_void_invoice(%L, 'Too late now')$$, :'inv1'), 'paid invoice cannot be cancelled'); -- Checks this is refused: paid invoice cannot be cancelled.

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.billing_record_payment(%L, 'stripe', 'pi_fake', 'card', 28000, 'succeeded')$$, :'inv1'), 'browser records a payment'); -- Checks this is refused: browser records a payment.
select tests.eq((select count(*) from public.billing_payments), 2, 'parent sees own payments'); -- Checks: parent sees own payments.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

-- ---------------------------------------------------------------------------
-- Monthly bank debit with discount, and GST where it applies
-- ---------------------------------------------------------------------------
update public.billing_price_items set gst_applies = true where code = 'tertiary_tutoring'; -- Makes tertiary tutoring charge GST, for this test.
-- Keeps the first of the month after next as month1.
select date_trunc('month', private.billing_today() + 45)::date as month1 \gset
-- A Cal session in month1, kept as c1.
select tests.session(:'cal', :'month1'::date + 7, '15:00', 60) as c1 \gset
-- Another a week later, kept as c2.
select tests.session(:'cal', :'month1'::date + 14, '15:00', 60) as c2 \gset
-- A tertiary session the next day, kept as c3.
select tests.session(:'cal', :'month1'::date + 15, '15:00', 60, 'tertiary') as c3 \gset
-- Builds Cal's family's monthly invoice, kept as inv3.
select public.billing_build_invoice(:'fam2', :'month1', (:'month1'::date + interval '1 month - 1 day')::date) as inv3 \gset
select tests.eq((select subtotal_cents from public.billing_invoices where id = :'inv3'), 30500, 'new family pays $95 and $115'); -- Checks: new family pays $95 and $115.
select tests.eq((select gst_cents from public.billing_invoices where id = :'inv3'), 1045, 'GST only on the price that carries it'); -- Checks: GST only on the price that carries it.
select tests.eq((select discount_cents from public.billing_invoices where id = :'inv3'), private.billing_debit_discount(30500), 'bank debit discount applied'); -- Checks: bank debit discount applied.
select tests.eq((select (charge_on <= due_on)::int from public.billing_invoices where id = :'inv3'), 1, 'bank debit taken by the due date'); -- Checks: bank debit taken by the due date.
update public.billing_price_items set gst_applies = false where code = 'tertiary_tutoring'; -- Makes tertiary tutoring GST-free again.

-- The daily run finds nothing new to bill for sessions already invoiced.
select tests.eq(public.billing_build_due_invoices(:'month1'::date), 0, 'daily run skips billed sessions'); -- Checks: daily run skips billed sessions.
-- ...and bills a new session once its send date arrives.
-- Another Cal session, kept as c4.
select tests.session(:'cal', :'month1'::date + 20, '15:00', 60) as c4 \gset
select tests.eq(public.billing_build_due_invoices(:'month1'::date - 30), 0, 'not yet time to send'); -- Checks: not yet time to send.
select tests.eq(public.billing_build_due_invoices(:'month1'::date + 8), 0, 'one day before its send date'); -- Checks: one day before its send date.
select tests.eq(public.billing_build_due_invoices(:'month1'::date + 9), 1, 'daily run bills it on its send date'); -- Checks: daily run bills it on its send date.

-- ---------------------------------------------------------------------------
-- Server-only tables, settings, and signed-out visitors
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$select * from public.billing_webhook_events$$, 'webhook log is server-only'); -- Checks this is refused: webhook log is server-only.
select tests.fails($$select * from public.billing_xero_connection$$, 'Xero tokens are server-only'); -- Checks this is refused: Xero tokens are server-only.
update public.billing_settings set override_by = 'admin'; -- Lets any admin override a pause.
select tests.eq((select count(*) from public.billing_settings where override_by = 'admin'), 1, 'owner changes settings'); -- Checks: owner changes settings.
update public.billing_settings set override_by = 'owner'; -- Only the owner again.
select tests.eq((select count(*) from public.billing_pause_overrides), 1, 'owner sees overrides'); -- Checks: owner sees overrides.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
set role anon; -- Acts as someone who is not signed in.
select tests.fails($$select * from public.billing_invoices$$, 'anon reads invoices'); -- Checks this is refused: anon reads invoices.
select tests.fails($$select * from public.billing_price_items$$, 'anon reads prices'); -- Checks this is refused: anon reads prices.
select tests.fails($$select private.billing_family_paused('00000000-0000-0000-0000-000000000000')$$, 'anon checks a pause'); -- Checks this is refused: anon checks a pause.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Leave other tests a clean slate.
delete from public.billing_payments; -- Clears the payments.
delete from public.billing_credits; -- Clears the credits.
delete from public.billing_invoices; -- Clears the invoices.
delete from public.billing_accounts; -- Clears the billing set-up.
delete from public.sessions where student_id in (:'cara', :'cal'); -- Removes Cara's and Cal's sessions.
drop function tests.session(uuid, date, time, int, text); -- Removes the session helper.

-- Prints that every check in this file passed.
\echo '  billing: all checks passed'
