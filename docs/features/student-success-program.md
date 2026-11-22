# Student Success Program

Carla, 22 Nov 2026. From her notes on Emma's job proposal: "need to have a space where can click or check off or something if a student is part of the Student Success Program ... then it sets up their student and/or family profile up accordingly." What it sets up: "Study plan, term reviews, a program label, book till date range (number of sessions) - these are top priority for matching, as they have already paid the $500 deposit to secure their place."

Carla's second note (same day): the family can tick a box to ask about it, "but ultimately an admin must qualify the student as being part of the Student Success Program, because otherwise we may run out of spaces, and need to ensure the $500 deposit has been received. Can the $500 deposit be sent through to the family, then once it is paid, they are then classified as a student in the Student Success Program?"

## What it is for

Families in the Student Success Program pay a $500 deposit to secure their child's place for a planned run of sessions. The program bundles the parts of CLG that the evidence says matter most for steady progress: a written plan, regular reviews against it, and a consistent tutor found quickly. Places are limited, because CLG can only promise priority matching to as many students as its tutors can take.

## What the evidence says

- **One to one tuition** (EEF Teaching and Learning Toolkit, about +5 months): works best when sessions are regular, sustained over a planned period, and linked to what the student is learning. A planned number of sessions and a book-until date make the run regular and sustained.
- **Feedback** (EEF, about +6 months) and **metacognition and self-regulation** (EEF, about +7 months): students gain most when they know where they are going, how they are going, and what to do next. The study plan sets the goals; the term review (included at no charge) checks progress against them each term.
- **Parental engagement** (EEF, about +4 months): personalised updates about a child's progress work better than general ones. The term review is written by the student's own tutor and checked by CLG. Asking the family to opt in (rather than CLG adding the child) also makes the family an active partner from the start.
- **Tutor consistency and dosage** (Evidence for Learning and AERO guidance on high-impact tutoring, drawing on the Stanford National Student Support Accelerator): a stable relationship with one tutor, enough sessions, and quick matching reduce lost learning time. Program students go first in Matching. Limiting places protects that promise: priority means little if every student has it.

## How the design follows it

1. **The family asks.** Under each child on the family dashboard, **Student Success Program** explains the program and has a tick box ("Yes, I would like to ask about a place") with an optional message. An adult learner who manages their own account asks from their own dashboard. The family can cancel the request until CLG answers.
2. **An admin decides.** Owner and Operations admins see a **Student Success Program** card in Families: places used and left, requests waiting, places waiting for the deposit (amber once overdue) and students in the program. Approving a place (in Change a student's details) records the sessions planned, book-until date and a note, and holds one place. Declining sends the family an optional reason. The database checks the number of places inside a lock, so two admins can never give away the last place twice.
3. **The deposit is sent.** Approving asks billing to make a $500 deposit invoice, already approved, which the family pays with **Pay now** in Billing. It goes to Xero as an approved invoice on the next billing run. The family gets an app notice and an email. Only the person who pays sees the due date and the Billing link (billing information is for payers only). The deposit is never charged automatically to a saved card or bank account, family credit is not used on it, and an unpaid deposit never puts the family's sessions on hold. It only means the place is not confirmed.
4. **Paid means in.** When billing marks the deposit paid (Stripe, or a payment entered in Xero), the student is in the program straight away: the study plan add-on is given, term reviews are included, the violet label shows in Matching and they go first in the queue. The family is told.
5. **Changes.** Admins can change a place's details, withdraw a place before the deposit is paid (the invoice is cancelled and the place freed), or remove a student from the program (the program study plan ends; any refund follows CLG's terms and is done in Billing). If a deposit invoice is cancelled in Xero, the place is freed and the request goes back to the waiting list.
6. **Places and payment time** are set on the card (10 places and 7 days to start). The deposit amount is the "Student Success Program deposit" price in Billing, Prices and settings.

## How we will know it works

- requests per term, and how many become paid places
- days from request to decision, and from approval to deposit paid
- days from deposit to first session for program students, against everyone else
- share of program students with a term review sent each term
- share of program students who finish their planned sessions, and who re-enrol

## Privacy, child safety and legal notes

- **Privacy Act 1988 (APPs 3, 6 and 11) and the Children's Online Privacy Code**: the program record holds only what CLG needs (status, dates, sessions planned, an optional family message and an admin note). Families read their own child's status through a function that leaves out CLG's own note; only front desk admins read the whole list, and only owner and Operations admins change it. Tutors do not see requests. The note boxes are not for health or diagnosis details. Every change is in the audit log, and the record is deleted with the student. Deposit invoices are kept for 7 years like all invoices.
- **Australian Consumer Law**: CLG's family terms must say what the deposit is for, whether it comes off later invoices or is a separate program fee, and when it is refunded. A deposit that is not refundable in any situation, or is much larger than CLG's real costs of holding a place, risks being an unfair contract term (ACL sections 23 to 25, with penalties since November 2023). The consumer guarantees still apply. The app records and collects the deposit but does not refund it; refunds follow the terms and are done in Billing.
- **Consent to charges**: ticking the box is a request for information, not an agreement to pay. The family pays the deposit themselves, so no money is taken without a clear action by the person paying.
- **GST**: Carla treats curriculum tutoring as GST-free, and the deposit is a payment towards that program, so the price item is GST-free. The setting can be changed on the price item. Detailed GST questions belong in Carla's finance work with her accountant.
- **UK and EU (GDPR)**: the same data minimisation, access and retention rules apply if CLG expands. A deposit would also need to meet UK consumer contract rules on cancellation.

## Technical

- Migration `20261124710900_student_success_program.sql` (run after `20261124710800_policy_versions_read_again.sql`). Safe to run more than once, and safe to run after the first, admin-only version of this file.
- Billing (module: billing): `billing_invoices.kind` ('sessions' or 'deposit'), price item `ssp_deposit`, `private.billing_charge_deposit`; `billing_should_pause`, `billing_has_invoice` and `billing_family_invoiced` ignore deposits. `src/lib/billing/run.ts` never auto-charges a deposit and sends deposits to Xero as approved invoices.
- Progress (module: progress): tables `public.ssp_settings` and `public.ssp_enrolments`; functions `ssp_request`, `ssp_cancel_request`, `ssp_family_status`, `ssp_places`, `ssp_set_places`, `ssp_approve`, `ssp_save_details`, `ssp_decline`, `ssp_withdraw`, `ssp_leave`, `private.ssp_member`; trigger `ssp_deposit_changed` on `billing_invoices` (writes only the program list and the shared add-ons list); progress notice kind `ssp_update` (emailed by the usual progress notice emails).
- Changes `private.queue_term_reviews`, `public.matching_queue` and `public.matching_tutor_fill` in place.
- Screens: `src/app/admin/ssp-section.tsx`, `src/app/admin/ssp-form.tsx`, `src/app/admin/student-details-section.tsx`, `src/app/dashboard/ssp-family.tsx`, `src/app/dashboard/ssp-family-forms.tsx`.
- Tests: `supabase/tests/student_success_program.test.sql`.
