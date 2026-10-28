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

- **Credits in Xero.** Each credit (cancellation, tutor's day off, goodwill) becomes a credit note on the family's Xero contact. When an invoice uses credit, the app applies those credit notes to it in Xero once it is approved, so the invoice shows the full sessions and the credit sits beside it for the accountant.

## Tutor and staff pay (added 2026-10-28)

- **Rates.** Admins enter up to three hourly rates per person (school tutoring, tertiary and other tutoring, admin) and their employment type (casual, part-time, full-time).
- **Pay lines.** Pay comes from the confirmed worked time on each session (scheduling's sign on and sign off). A tutor who starts late is paid the time worked; a student who is late doesn't change the tutor's pay.
- **Late cancels and no-shows.** Before the tutor has signed on: 50% of the session or 1 hr, whichever is less (CLG's own rule). After the tutor has signed on: the time they had to be there. A tutor's own cancellation is unpaid.
- **Casual minimum (switched off for now).** Carla asked on 2026-10-28 to turn this off for now and back on next year; it is a setting (Pay period and casual minimum, owner only), and the pay screen warns while it is off. When on: casual staff get at least 2 hr pay for each day they attend work, online included (Miscellaneous Award MA000104 cl 11.2; Post-Secondary Award MA000075 cl 11.4). The app adds a top-up line for a short day. Admin hours count towards the 2 hr. Late-cancel pay alone isn't a day at work.
- **Award check.** Award minimum rates (from 1 July 2026) are settings, updated each 1 July. Any line paying under the minimum for that person's employment type is flagged in red. The seeded levels (Miscellaneous L1, MA000075 tutor/instructor, Clerks L1 Y1) need an employment adviser's confirmation.
- **Xero Payroll.** Each pay period (weekly by default; must match Xero's pay calendar), admins send each person's lines to Xero Payroll as a draft timesheet, one earnings rate per kind of work. Carla checks and approves in Xero, which handles super (Payday Super from 1 July 2026) and Single Touch Payroll. Part-time staff paid a fixed weekly pattern still need their pattern hours entered in Xero.
- **Privacy.** Staff see only their own rates and pay (with two-step login); only admins see everyone's. Families never see pay.

## Split payments between payers (added 2026-10-28)

- **What.** An admin can split a family's invoices between the bill payer and another parent or adult learner in the family, as whole percentages (for example 50/50 or 60/40). The bill payer pays what is left. Each invoice keeps the split it was made with, so changing the split only affects new invoices.
- **Paying.** Each payer saves their own card or bank debit in the app and is charged only their share on the charge date. A payer who hasn't set up automatic payment pays their share by link. If any payer uses bank debit, the charge date allows for it to clear in time. The bank-debit discount still depends on the bill payer's saved method, as before, and is shared in the same proportion.
- **One invoice.** The invoice stays one invoice, with one set of session lines and one Xero invoice addressed to the bill payer. Each payer's payment is recorded against it in Xero. The invoice is paid when the shares add up to the total.
- **Pauses.** CLG's rule is unchanged: an overdue invoice puts the whole family on hold, even if one payer has paid their share. A failed payment pauses the family until that payer pays.

### Why (research and practice)

- Regular sessions are what make tuition work (EEF Toolkit: one-to-one tuition, small group tuition; Evidence for Learning). A family where one parent pays for everything and the other is meant to pay them back is a common cause of late payment and gaps. Letting each payer pay their own share directly keeps sessions regular.
- Parental engagement works best when it is easy and specific for each parent (EEF guidance report, *Working with Parents to Support Children's Learning*). Each payer sees their own share and their own action, and nothing more.

### Privacy and legal notes

- **Separated parents.** Each payer sees only their own share, their own saved method and their own payments. They never see the other payer's card or bank details, contact details or payment history (Privacy Act APP 6 and APP 11). This matters where there are family violence concerns or parenting orders. The bill payer sees the split percentages; the second payer sees only that "another payer" pays the rest. Admins see both.
- **Who may share.** Only a parent linked to a child in the family, or an adult (18+) learner in it, can be added. The database checks this (`billing_set_split`), and writes to the split tables are admin or server only. Tested in `supabase/tests/billing_split.test.sql`.
- **Tax invoice.** The Xero tax invoice is addressed to the bill payer. A second payer who needs a tax invoice in their own name (for example for a claim) needs a separate invoice, done by hand for now.
- **Terms.** The family terms are accepted once per family. A second payer should also read them; the terms should say that each payer is responsible for their own share and that an overdue share pauses the family's sessions. The lawyer review should cover this.

Not built yet (next steps): email and text messages (tutor notices and reminders are queued in the app, ready for when email sending is set up), NDIS and school funding.

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
