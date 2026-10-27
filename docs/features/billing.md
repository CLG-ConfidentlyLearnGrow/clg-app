# Billing: invoices, payments, credits and pauses

Requested by Carla, 2026-10-26 and 2026-10-27. Full research brief (Xero, Stripe, awards, legal): [Billing and Xero: research brief](https://claude.ai/artifact/LfkL2QsPEmcUT56gm1XJCN). This file is the short version kept with the code.

## What it's for

CLG bills families in advance for tutoring. Today that is done by hand in Xero, with payments split across Stripe, GoCardless and direct deposit. The billing module builds each family's invoice from the sessions the scheduling module books. It charges the family's saved card or bank debit on the due date. It pauses and restarts support on its own when an invoice is overdue. Xero stays the official accounts system.

## What it does

- **Prices.** A price list where each price has its own GST setting. School tutoring is $95/hr and tertiary is $115/hr, both GST-free (Carla's position: curriculum tutoring). Non-curriculum support carries GST and stays off until a price is set. Existing families keep their old rate ($80, $85 or $95) as a "kept rate" on their family.
- **Plans.** Weekly (card only), monthly, per term (with separate holiday invoices) or upfront. Automatic payment is required for weekly and monthly.
- **Invoices.** One invoice per family per period, one line per session. Each line shows the day, date, time, the student's first name and the subject; the tutor's name is off by default. Sessions are charged in half-hour steps with a 1 hr minimum. A session is never on two live invoices.
- **When.** Weekly and monthly invoices are due 4 days before the first session and go out 1 week before that. Per term and upfront invoices are due 1 week before and go out 2 weeks before that. A bank debit is taken on the due date or 4 business days before the first session, whichever is earlier, so it clears in time.
- **Pilot approval.** Invoices go to Xero as "Awaiting approval" until Carla approves them. A setting switches this to sending automatically after the pilot.
- **Bank-debit discount.** Families paying by bank debit get half of what CLG saves in fees, worked out on each invoice from fee settings.
- **Credits, not refunds.** Cancelling more than 24 hr ahead gives full credit, 24 hr to 2 hr gives 50%, and under 2 hr or a no-show gives none. When CLG or the tutor cancels, the family always gets full credit. Credit comes off the next invoice automatically, whatever the service.
- **Pauses.** A family is paused when an invoice sent to them is past its due date and unpaid, or a payment fails. A bank debit still processing doesn't count. A pause covers every child in the family. Tutors are told when sessions go on hold and when they're back on, with no money details. Paying lifts the pause straight away. Scheduling stops new bookings while a family is paused (`private.billing_family_paused`).
- **Override.** Only the owner can lift a pause without payment (a setting can extend this to admins later, for example Lauren). An override needs a reason and a date: the new due date, or the next payment of an agreed plan. If that date passes unpaid, the pause comes back.
- **Built for later.** Prices can be marked for self-signup and carry a trial (days, sessions, trial price), and can be tied to a program. Those are switched off until pricing is decided.

Not in this first version (next steps): tutor pay to Xero Payroll timesheets, credits as Xero credit notes (credits show as a line on the Xero invoice for now), email and text messages (tutor notices and reminders are queued in the app, ready for when email sending is set up), split payments between parents, NDIS and school funding.

## Why (education research)

- **Regular sessions matter.** One-to-one tuition adds about +5 months' progress on average. It works best as short, regular sessions over a set period, up to about ten weeks (EEF Teaching and Learning Toolkit; Evidence for Learning's Australian edition). A payment gap that stops sessions breaks that regularity. So the design favours automatic payment, invoices well ahead of time, and pauses that lift within minutes of payment.
- **Per term fits the evidence.** Paying per term matches the "set period" idea and has the lowest fees, so it can be offered first.
- **Parent effort stays light.** Families set up payment once and are charged automatically. That follows Carla's rule that parent support adds no work for busy parents, and the EEF's finding that parental engagement works when it is easy and specific.

## How we'll know it works

From the pilot, the app can report: sessions lost to payment pauses (aim close to none), how long pauses last (aim under 1 day), the share of families on automatic payment (aim most), invoices cancelled after sending (aim close to none), and admin time on billing each week (aim down from today).

## Privacy, security and legal notes

- **No card or bank numbers in CLG's systems.** Families enter them on Stripe's own pages and the app keeps only Stripe's reference (PCI DSS SAQ A). BECS direct debit agreements are hosted and emailed by Stripe.
- **Least child data.** Invoices show the student's first name and subject only. Xero and Stripe get the bill payer's name and email, never a child's school, needs or progress (Privacy Act APP 3 and 11; Children's Online Privacy Code, due by 10 December 2026). Stripe and Xero may hold data overseas: named in the privacy policy (APP 8).
- **Access rules in the database.** Parents (and adult learners or the named bill payer) see their own family's sent invoices, payments and credits. Students under 18 see only "on hold". Tutors see only on hold and back on notices for their own students. Only admins see billing across families. Payments, payment references and pauses are written only by the server. Tested in `supabase/tests/billing.test.sql`.
- **Signed messages only.** Stripe and Xero messages are checked against their signatures before the app acts, and each message is handled once. Each invoice has a one-off key so a retry can't charge twice.
- **Keys.** Stripe and Xero keys live in Vercel's secret settings. The app refuses a live Stripe key unless live payments are switched on, so testing can't charge real cards. The Xero sign-in is stored encrypted.
- **Tax invoices.** GST shown per line where it applies; invoices go through Xero, which adds CLG's ABN and "Tax invoice". Records kept at least 5 years (ATO); invoices stay when a family's learning records are deleted (the family name and line details are copied onto the invoice).
- **Consumer law.** No card surcharges (banned from 1 October 2026; discounts for bank debit are allowed). Families accept the terms in the app with the version and date recorded. Credits-not-refunds sits alongside the consumer guarantees: a refund is still owed where the law requires one. The family terms need a lawyer's check.
- **UK and EU later.** VAT, UK GDPR and strong customer authentication for cards (Stripe handles SCA).
