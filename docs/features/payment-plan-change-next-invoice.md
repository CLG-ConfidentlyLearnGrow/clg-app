# Change payment plan, starting from the next invoice

Requested by Carla, 20 Nov 2026: "Families need to have the ability to pre
change the payment plan type (can change the payment plan type at any time,
and it only comes into effect for the next invoice)."

## What it does

- The person who pays (the bill payer, or a sole adult learner) can change
  how often they pay (weekly, monthly, per term or all upfront) at any time
  on their Billing page.
- Before the family's first invoice, the choice is saved straight away,
  because nothing has been billed yet.
- After that, the change is **booked**. The family stays on their current
  plan until that plan's next invoice is due to be built. On that day the
  daily billing run switches the plan, so that invoice, and every later one,
  follows the new plan. Invoices already built (draft, waiting, sent or paid)
  stay as they are.
- The Billing page shows the booked change and the day the next invoice is
  expected, with a **Cancel this change** button. Choosing the current plan
  again also cancels it.
- The person who pays and the owner and Operations admins get a notice when
  a change is booked, cancelled and made.
- Weekly still needs a card. If the family moves to bank debit before a
  booked weekly change starts, the change is not made and the payer is told
  why.
- Admins can still set a plan on Admin > Billing. That applies straight away
  and clears any booked change. The admin page shows a booked change.
- "All upfront" has no automatic invoices (CLG builds them by hand), so a
  change away from it applies straight away.

## Why (education research)

- Regular, uninterrupted one to one sessions are what make tuition work
  (EEF Teaching and Learning Toolkit, one to one tuition: about five months'
  extra progress, strongest when sessions are frequent and sustained;
  Evidence for Learning carries the same Toolkit for Australia).
- Payment trouble is a common reason sessions pause or stop. Letting a
  family pick a plan that suits their budget, without waiting on CLG and
  without a surprise bill, keeps sessions going. Starting the change at the
  next invoice means a family is never billed twice and never gets an
  unexpected lump-sum invoice the day they switch (for example the rest of
  a term all at once).
- AERO's guidance on partnering with families stresses clear, predictable
  communication; the booked change and its expected start day give that.

## Legal notes

- **Australian Consumer Law**: the change is made by the customer, takes
  effect only for services not yet invoiced, and the date it starts is shown
  before it starts, so there are no surprise or unilateral price changes.
  Invoices already issued keep their agreed terms. The family can cancel a
  booked change before it starts.
- **Family payment terms**: the terms say a family may change how often they
  pay at any time, starting from their next invoice. The in-app terms
  version is not changed, because this widens what the family may do and
  takes nothing away.
- **Privacy Act and APPs**: no new personal information. The booked change
  is visible only to the people who pay for the family and to admins (the
  existing billing row rule). Tutors see nothing.
- **Children's data**: students under 18 who do not pay see nothing new.
- UK and EU (later): same approach meets the Consumer Rights Act 2015 and
  EU consumer rules on clear pricing before charging.

## How it works (for developers)

- `billing_accounts.pending_plan`, `pending_plan_at`, `pending_plan_by`.
- `billing_choose_plan` saves straight away before the first invoice, books
  the change after it, and cancels a booked change when the current plan is
  chosen again.
- `billing_cancel_plan_change(family)` for the payer or an admin.
- `billing_plan_change_starts(family)`: the current plan's next invoice day.
- `private.billing_next_send_on(...)` mirrors how `billing_build_due_invoices`
  picks periods and send days.
- `private.billing_apply_plan_changes(day)` runs at the start of
  `billing_build_due_invoices` (edited in place), so the daily run and an
  admin's "run billing now" both make due changes before building invoices.
  It only reads accounts with a booked change (partial index), so it stays
  fast.
- Migration `20261123500100_payment_plan_change_next_invoice.sql` (run after
  `20261123400500_payment_plan_required.sql`). Tests:
  `supabase/tests/billing_plan_change_next_invoice.test.sql` and
  `supabase/tests/billing_choose_plan_change.test.sql`.
