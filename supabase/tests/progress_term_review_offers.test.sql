-- Summary: paid term reviews (Carla, 12 Nov 2026). Checks that families are
-- offered a review near the end of a term, or near the end of their booked
-- sessions when those don't line up with a term; that only the family
-- member who answers (and CLG admins) can see and answer offers; that a
-- "yes" makes an invoice at the offered price and a draft for the tutor;
-- and that monthly summaries stay off. Runs after progress_roadmaps.test.sql
-- and reuses its people: owner ...a0 (admin), tutor T1 ...11 (teaches Cara
-- One), parent P1 ...01 (Cara's parent), parent P2 ...02.

-- The migration is safe to run twice.
\ir ../migrations/20261113900100_paid_term_reviews.sql

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara and her family as fam.
select id as cara, family_id as fam from public.students where full_name = 'Cara One' \gset
-- Keeps today's date in Adelaide as today.
select (now() at time zone 'Australia/Adelaide')::date as today \gset

-- Set-up: saves the SA terms and Cara's future sessions so they can be put
-- back, and gives Cara's family a billing account if it has none.
create temp table saved_terms as select * from public.school_terms where state = 'SA'; -- Keeps a copy of the SA term dates.
delete from public.school_terms where state = 'SA'; -- Clears the SA term dates, so the test controls them.
create temp table saved_sessions as -- Keeps a list of Cara's sessions still to come
  select id, status from public.sessions where student_id = :'cara' and status = 'scheduled' and starts_at > now(); -- (with their status).
update public.sessions set status = 'cancelled', cancelled_at = now() where id in (select id from saved_sessions); -- Sets them aside for the test (put back at the end).
create temp table had_billing as select family_id from public.billing_accounts where family_id = :'fam'; -- Notes whether the family already had billing.
insert into public.billing_accounts (family_id, bill_payer_id, plan) -- Gives the family weekly billing,
  values (:'fam', '00000000-0000-0000-0000-000000000001', 'weekly') on conflict (family_id) do nothing; -- paid by parent P1, if they had none.

-- A school term that started 40 days ago and ends in 20 days, and one
-- future session for Cara 25 days from now (so her booking reaches the end of term).
insert into public.school_terms (state, year, term, starts_on, ends_on) -- Adds a test term:
  values ('SA', extract(year from :'today'::date - 40)::int, 4, :'today'::date - 40, :'today'::date + 20); -- started 40 days ago, ends in 20 days.
insert into public.sessions (id, student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status) values -- Adds a booked session:
  ('00000000-0000-0000-0000-0000000f0001', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', -- Cara with tutor T1, online,
   now() + interval '25 days', now() + interval '25 days 1 hour', 'scheduled'); -- in 25 days, for 1 hr.

-- ===========================================================================
-- Which end a review is for
-- ===========================================================================
select tests.eq((select count(*) from private.term_review_next_end(:'cara', :'today') where period_kind = 'term'), 1, 'booking reaches the end of term: offered for the term'); -- Checks: the term is used when the booking reaches it.
select tests.eq((select count(*) from private.term_review_next_end(:'cara', :'today') where period_ends_on = :'today'::date + 20), 1, 'offer is for the term''s last day'); -- Checks: the end date is the term's last day.
update public.sessions set starts_at = now() + interval '10 days', ends_at = now() + interval '10 days 1 hour' where id = '00000000-0000-0000-0000-0000000f0001'; -- Moves the last session to 10 days from now.
select tests.eq((select count(*) from private.term_review_next_end(:'cara', :'today') where period_kind = 'term'), 1, 'booking stops within 2 weeks of term end: still the term'); -- Checks: close to the end of term still counts as the term.
update public.school_terms set ends_on = :'today'::date + 60 where state = 'SA'; -- Moves the term's end to 60 days away.
select tests.eq((select count(*) from private.term_review_next_end(:'cara', :'today') where period_kind = 'booking_end'), 1, 'booking stops well before term end: offered for the booking'); -- Checks: a booking that doesn't line up with the term uses its last session.
select tests.eq((select count(*) from private.term_review_next_end(:'cara', :'today') where period_ends_on = :'today'::date + 10), 1, 'offer is for the last booked session'); -- Checks: the end date is the last booked session.
update public.sessions set status = 'cancelled', cancelled_at = now() where id = '00000000-0000-0000-0000-0000000f0001'; -- Cancels the session (nothing booked).
select tests.eq((select count(*) from private.term_review_next_end(:'cara', :'today')), 0, 'nothing booked: no offer'); -- Checks: no booked sessions means no offer.
update public.sessions set status = 'scheduled', cancelled_at = null, starts_at = now() + interval '25 days', ends_at = now() + interval '25 days 1 hour' -- Books the session again,
  where id = '00000000-0000-0000-0000-0000000f0001'; -- 25 days from now.
update public.school_terms set ends_on = :'today'::date + 20 where state = 'SA'; -- And puts the term's end back to 20 days away.

-- ===========================================================================
-- Offers go out only once the price is set and in use
-- ===========================================================================
select tests.eq((select count(*) from public.add_ons where code = 'term_reviews'), 0, 'old term reviews add-on removed'); -- Checks: the old add-on is gone (the price item replaces it).
select tests.eq((select count(*) from public.billing_price_items where code = 'term_review' and unit = 'once' and not active), 1, 'term review price item starts off'); -- Checks: the price item is there and off.
select tests.eq(private.queue_term_reviews(), 0, 'no offers while the price is off'); -- Checks: no offers until the price is in use.
update public.billing_price_items set amount_cents = 4000, active = true where code = 'term_review'; -- The owner sets $40 and turns it on.
select tests.eq(private.queue_term_reviews(), 1, 'one offer made'); -- Checks: Cara's family gets an offer.
select tests.eq(private.queue_term_reviews(), 0, 'not offered twice'); -- Checks: running again makes no new offer.
-- Keeps the offer's id as offer.
select id as offer from public.term_review_offers where student_id = :'cara' \gset
select tests.eq((select count(*) from public.term_review_offers where id = :'offer' and price_cents = 4000 and answer = 'waiting' and period_kind = 'term'), 1, 'offer keeps the price and waits for an answer'); -- Checks the offer's details.
select tests.eq((select count(*) from public.progress_notices where offer_id = :'offer' and kind = 'review_offer' -- Checks parent P1 is told,
  and account_id = '00000000-0000-0000-0000-000000000001' and body like '%$40.00%'), 1, 'parent told, with the price'); -- with the price.
select tests.eq((select count(*) from public.progress_notices where offer_id = :'offer' and account_id = '00000000-0000-0000-0000-000000000011'), 0, 'tutor is not told about the offer'); -- Checks: the tutor gets nothing (no prices for tutors).
select tests.eq((select count(*) from public.term_reviews where offer_id = :'offer'), 0, 'no review before the family says yes'); -- Checks: no draft yet.

-- ===========================================================================
-- Who can see and answer
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.term_review_offers), 0, 'tutor sees no offers'); -- Checks: tutors can't see offers or prices.
select tests.fails(format($$select public.answer_term_review_offer(%L, true)$$, :'offer'), 'tutor answers for the family'); -- Checks this is refused: the tutor answers.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as parent P2 (not Cara's parent).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.term_review_offers), 0, 'other parent sees no offers'); -- Checks: another family can't see it.
select tests.fails(format($$select public.answer_term_review_offer(%L, true)$$, :'offer'), 'other parent answers'); -- Checks this is refused: another parent answers.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as parent P1 (Cara's parent).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.term_review_offers where id = :'offer'), 1, 'parent sees the offer'); -- Checks: the parent sees it.
select tests.fails(format($$update public.term_review_offers set answer = 'yes' where id = %L$$, :'offer'), 'parent says yes by editing the table directly'); -- Checks this is refused: direct edits (answers go through the function).
select tests.fails(format($$select public.answer_term_review_offer(%L, true, true)$$, :'offer'), 'parent gives themselves a free review'); -- Checks this is refused: "no charge" from a parent.
select public.answer_term_review_offer(:'offer', false); -- The parent says no.
select tests.eq((select count(*) from public.term_review_offers where id = :'offer' and answer = 'no' and invoice_id is null), 1, 'no: recorded, nothing charged'); -- Checks: a "no" charges nothing.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.term_reviews where offer_id = :'offer'), 0, 'no: no review made'); -- Checks: a "no" makes no draft.

-- ===========================================================================
-- Changing to yes: an invoice and a draft for the tutor
-- ===========================================================================
update public.billing_price_items set amount_cents = 5000 where code = 'term_review'; -- The owner raises the price to $50 after the offer went out.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as parent P1 again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.answer_term_review_offer(:'offer', true) as invoice_number \gset
select tests.eq((select (:'invoice_number' like 'CLG-%')::int), 1, 'yes: invoice number given back'); -- Checks: the parent gets an invoice number.
select tests.fails(format($$select public.answer_term_review_offer(%L, false)$$, :'offer'), 'changing a yes back to no'); -- Checks this is refused: undoing a "yes" in the app.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Keeps the invoice's id as invoice.
select invoice_id as invoice from public.term_review_offers where id = :'offer' \gset
select tests.eq((select count(*) from public.billing_invoice_lines l join public.billing_price_items p on p.id = l.price_item_id -- Checks the invoice has one term review line
  where l.invoice_id = :'invoice' and p.code = 'term_review' and l.amount_cents = 4000 and l.session_id is null), 1, 'one line at the offered price ($40, not $50)'); -- at the price the family was shown.
select tests.eq((select count(*) from public.billing_invoices where id = :'invoice' and family_id = :'fam' and subtotal_cents = 4000), 1, 'invoice is for Cara''s family'); -- Checks the invoice's family and amount.
select tests.eq((select count(*) from public.term_reviews where offer_id = :'offer' and tutor_id = '00000000-0000-0000-0000-000000000011' -- Checks the tutor has a draft,
  and status = 'draft' and due_on = :'today'::date + 6), 1, 'yes: draft for the tutor, due 2 weeks before term ends'); -- due 14 days before the end (day 20), which is day 6.
select tests.eq((select count(*) from public.progress_notices n join public.term_reviews r on r.id = n.review_id -- Checks the tutor is told
  where r.offer_id = :'offer' and n.kind = 'review_due' and n.account_id = '00000000-0000-0000-0000-000000000011'), 1, 'tutor told to write it'); -- to write it.
select tests.eq((select count(*) from public.progress_notices where offer_id = :'offer' and kind = 'review_booked' -- Checks the owner is told it's booked,
  and account_id = '00000000-0000-0000-0000-0000000000a0' and body like '%' || :'invoice_number' || '%'), 1, 'admin told, with the invoice number'); -- with the invoice number.
select tests.eq(private.queue_term_reviews(), 0, 'daily job makes no second offer or draft'); -- Checks: the daily job doesn't repeat anything.
select tests.eq((select count(*) from public.term_reviews where offer_id = :'offer'), 1, 'still one review'); -- Checks: still one draft.

-- ===========================================================================
-- CLG gives one at no charge
-- ===========================================================================
insert into public.term_review_offers (id, student_id, period_kind, period_label, period_starts_on, period_ends_on, price_cents) -- Adds a second offer by hand:
  values ('00000000-0000-0000-0000-0000000f0002', :'cara', 'booking_end', 'Sessions to test', :'today'::date - 40, :'today'::date + 50, 4000); -- for a later end date, at $40.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.term_review_offers where student_id = :'cara'), 2, 'admin sees the offers'); -- Checks: the admin sees both offers.
select public.answer_term_review_offer('00000000-0000-0000-0000-0000000f0002', true, true); -- The owner says yes at no charge (for example on hardship).
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.term_review_offers where id = '00000000-0000-0000-0000-0000000f0002' and no_charge and invoice_id is null), 1, 'no charge: no invoice'); -- Checks: no invoice for a free review.
select tests.eq((select count(*) from public.term_reviews where offer_id = '00000000-0000-0000-0000-0000000f0002'), 1, 'no charge: tutor still gets the draft'); -- Checks: the tutor still gets a draft.

-- ===========================================================================
-- Monthly summaries stay off
-- ===========================================================================
select tests.eq(private.queue_monthly_summaries(current_date), 0, 'monthly summaries are not made'); -- Checks: no monthly summaries.

-- ===========================================================================
-- Put everything back
-- ===========================================================================
create temp table made_invoices as select invoice_id from public.term_review_offers where invoice_id is not null; -- Notes the invoices the test made.
delete from public.term_reviews where offer_id is not null; -- Removes the test drafts.
delete from public.term_review_offers where student_id = :'cara'; -- Removes the test offers (their notices go too).
delete from public.billing_credits where invoice_id in (select invoice_id from made_invoices); -- Removes any credit used on them.
delete from public.billing_invoices where id in (select invoice_id from made_invoices); -- Removes the test invoices.
delete from public.billing_accounts where family_id = :'fam' and not exists (select 1 from had_billing); -- Removes the billing account, if the test made it.
update public.billing_price_items set amount_cents = 0, active = false where code = 'term_review'; -- Turns the price item off again.
delete from public.sessions where id = '00000000-0000-0000-0000-0000000f0001'; -- Removes the test session.
update public.sessions s set status = v.status, cancelled_at = null from saved_sessions v where s.id = v.id; -- Puts Cara's other sessions back as they were.
delete from public.school_terms where state = 'SA'; -- Clears the test term.
insert into public.school_terms select * from saved_terms; -- Puts the SA term dates back.

-- Prints that every check in this file passed.
\echo '  progress term review offers: all checks passed'
