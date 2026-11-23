# Plan fees, family hourly rate changes and 24 hour payment reminders

Requested by Carla, 22 Nov 2026:

1. "Invoice total ... when it is usual bookings, the app works it out from the
   session planned (and the family hour rate can be edited by admin, even after
   the invoice is sent, if the family hour rate is edited after an invoice is
   sent, the amended invoice is sent to the family)."
2. "Payment plans can be; pay in full, monthly, or weekly. ... For per month
   invoices, there is a $10 additional cost to each invoice. For per week
   invoices, there is a $5 additional cost to each invoice."
3. "Everyone gets a reminder 24 hours prior to any payment being required."
4. "All payments should come off their saved card automatically."

The Student Success Program parts of the same message (program invoice
totals, instalments, forfeiting a place) are built in the Student Success
Program thread. This brief covers normal tutoring billing.

## What it does

### Payment plan fees

- Each monthly invoice gets one "Monthly payment plan fee" line ($10) and each
  weekly invoice one "Weekly payment plan fee" line ($5). Per term and all
  upfront invoices have no fee.
- Both are prices on Admin > Billing > Prices and settings, so the owner can
  change them (or switch one off). The Student Success Program uses the same
  two prices.
- The fee is the same whether the family pays by card or bank debit.
- Families see the fee next to each plan before choosing, in the payment terms
  card, and as its own line on each invoice.
- A setting, **Plan fees start from** (30 Nov 2026 to begin with), means only
  invoices whose first session is on or after that date get the fee.
- The fee line is dated the first session's day, so if an invoice is only
  partly paid, the payment covers the fee first and the hold starts from the
  first session not paid for (as before).
- Carla asked whether the two fees should be the same. Recommendation: keep
  them different. A weekly family gets about four invoices a month, so $5 a
  week is about $21.65 a month against $10 for monthly. That fairly covers four
  times the card fees and admin, and nudges families towards fewer, larger
  payments. Both amounts can be changed later.

### Changing a family's hourly rate

- The owner or a Finance admin sets a family's own hourly rate (school or
  tertiary tutoring) on Admin > Billing > Family billing > Family hourly rate,
  with the first session date it applies to. Leaving the rate empty goes back
  to the price list. Operations admins can see it but not change it (they
  have view-only billing since 20 Nov 2026).
- Unpaid invoices with sessions from that date are re-priced straight away:
  the lines, GST, bank debit discount and each payer's share of a split
  invoice. Credit already used stays, unless the invoice is now smaller than
  it (the rest goes back to the family's credit).
- A draft, or an invoice still waiting for approval in Xero, is re-priced
  quietly. An invoice the family already has is marked **Amended**, the people
  who pay get a notice with the new and old totals, and the next billing run
  updates it in Xero and emails the amended invoice from Xero.
- Paid (or partly paid) invoices never change. A lower rate gives the family
  credit for the difference (a credit note in Xero). A higher rate only applies
  to invoices that are not paid yet.
- A higher rate cannot start before today, because sessions already given were
  agreed at the old rate.
- Any payment reminder already sent for a re-priced invoice is replaced, so the
  family is reminded of the new amount a day before it is taken.

### 24 hour payment reminders

- The daily billing run (7am Adelaide in summer, 6am in winter, outside quiet
  hours) reminds each person who pays the day before their saved card or bank
  account is charged, or the day before an invoice they pay themselves is due.
  With split payments, each payer is reminded of their own share.
- The reminder is an app notice (with a pop-up notification for anyone who
  turned them on) and an email. Day-to-day notices are app only, but a payment
  reminder is emailed too because money is about to leave the family's account.
- A saved card or bank account is only charged once its reminder is at least
  20 hours old. An invoice approved on its charge day is therefore charged the
  next morning. The hold check runs after the charge, so a family is not put on
  hold by this one-day wait.
- No "due tomorrow" reminder is sent once an invoice is overdue (the overdue
  and hold notices already cover that).
- Student Success Program invoices send their own reminders with program
  wording, so this reminder only covers session invoices.

### Automatic payment (Carla's question 7)

Payments come off the saved card or bank account automatically. No "pay some
other way" option is needed: card scheme and bank debit rules only require
that a family can change their card or bank account (the existing **Change card
or bank account** button) and can cancel the automatic payment authority. The
family terms should say how to do that (contact CLG, or their bank for a bank
debit) and that cancelling means paying each invoice by its due date.

## Why (education research)

- Regular, uninterrupted one to one tuition is what makes it work: about five
  months' extra progress on average, strongest when sessions are frequent and
  sustained (EEF Teaching and Learning Toolkit, one to one tuition; Evidence for
  Learning publishes the same Toolkit for Australia). A failed or forgotten
  payment puts sessions on hold, so a clear reminder the day before keeps
  sessions running.
- AERO's guidance on partnering with families stresses clear, predictable,
  two-way communication. Telling a family the exact amount, invoice and day
  before money is taken, and telling them straight away when an invoice
  changes, is that kind of communication.
- Showing the plan fee before a family chooses lets them pick the plan that
  suits their budget, which supports the EEF finding that engagement works best
  when it is easy and specific for parents (EEF, Working with Parents to
  Support Children's Learning).

## Legal notes (Australia first)

- **Card surcharges.** Card surcharges are not allowed (see `billing.md`). The
  plan fee is a fee for the invoicing frequency, charged the same whether the
  family pays by card or bank debit, so it is not a surcharge. Because the
  weekly plan is card only, the lawyer should confirm the weekly fee cannot be
  read as a card surcharge.
- **Australian Consumer Law: clear prices (s 48, component pricing).** The fee is
  shown before the family chooses a plan, in the payment terms, and as its own
  line on each invoice. The family terms must mention the fee, and the "Plan
  fees start from" date should not be earlier than when families agree to
  those terms.
- **Unfair contract terms (ACL Part 2-3, penalties since 9 Nov 2023).** A term
  letting CLG change prices with no notice could be unfair. The terms should
  say CLG gives written notice before a higher hourly rate starts and that the
  family can end their bookings before it starts. The app already stops a
  higher rate being backdated, and never changes a paid invoice.
- **Recurring card and bank debit payments.** Stripe's BECS direct debit
  agreement and card scheme rules require the family to be able to change or
  cancel the authority; the app's Change card button and the family terms cover
  this. The 24 hour reminder goes beyond what Stripe sends.
- **Tax invoices.** An invoice the family already has is updated in Xero and
  re-sent, so the family holds the current version. Credit for a paid invoice
  is a credit note (adjustment note) in Xero. Records are kept as before (at
  least 5 years).
- **Privacy Act and APPs.** Reminder emails and notices name the amount, the
  invoice number and the day only, never the child or session details (APP 3
  and APP 11). Only the people who pay get them. Reminder rows are readable only
  by billing admins and written only by the server. Tested in
  `supabase/tests/billing_plan_fees_rate_reminders.test.sql`.
- **Children's Online Privacy Code.** No child data is added or shared.
- **UK and EU later.** The UK and EU allow surcharge-free plan fees in the same
  way; strong customer authentication for saved cards is handled by Stripe.

## How we will know it works

From the pilot: failed automatic payments per month (aim close to none), holds
caused by payment (aim close to none), amended invoices that still show
**Xero update waiting** after a day (aim none), and family questions about
unexpected charges (aim none).

## Files

- Migration: `supabase/migrations/20261125300100_plan_fees_rate_changes_payment_reminders.sql`
- Tests: `supabase/tests/billing_plan_fees_rate_reminders.test.sql`
- Billing run: `src/lib/billing/run.ts` (reminders, charge check, Xero amend)
- Xero: `src/lib/billing/xero.ts` (amend and email an invoice)
