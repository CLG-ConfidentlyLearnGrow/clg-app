# Students who don't pay get no billing

Carla, 16 Nov 2026: "Students who are not the payee of the lessons do not get a billing tab." Found while writing the pilot test guide (test ST2): a student aged 18 or over with their own login counted as a payer even when a parent pays, so they saw a Billing tab with the family's plan and invoices.

## Why this matters for learning

- **A student's dashboard is for learning.** Students do better when their tools keep attention on goals, next steps and practice, without extra load (AERO, "Cognitive load theory" and explicit teaching guidance; EEF, "Metacognition and self-regulation"). Invoices and payment set-up for someone else's account add noise.
- **Students still know when sessions are paused.** If a family's sessions go on hold, the student's dashboard says so and asks them to check with their parent or carer, so they aren't left wondering why a session is missing.

## The rules it touches

- **Privacy Act 1988 (Cth), APP 6 and APP 11:** use and disclose personal information only for the purpose it was collected, and limit access. A family's payment details and invoices belong to the payer.
- **Children's Online Privacy Code (OAIC, due Dec 2026):** data minimisation and privacy by default for young people.
- **UK GDPR and EU GDPR Article 5(1)(c)** (data minimisation), for when CLG goes international.

## Who pays now

A person counts as paying for a family when they are:
1. a linked parent or guardian of one of its students (unchanged),
2. the family's chosen bill payer (unchanged), or
3. an adult learner (18+) with their own login who is the family's only learner (from sibling privacy, PR #146) and has no parent or guardian linked, so they signed up for themselves (narrowed: an only learner whose parent pays no longer counts).

Split share payers keep their own rules. Someone who is a parent and also learns with CLG pays from their Parent tab, so their Student tab never shows Billing.

## How it works

- Migration `20261118900200_billing_students_who_pay.sql` (run after `20261118900100_sibling_privacy.sql`, which it builds on) narrows `private.is_family_payer` (so a non-paying student can't read the family's plan or invoices or change how it pays) and adds `public.billing_i_pay()`.
- `src/lib/dashboard-menu.ts` shows the student Billing tab only when `billing_i_pay()` says yes.

## Tests

`supabase/tests/billing_students_who_pay.test.sql`: the paying parent and a self-paying adult learner get billing; a 19-year-old whose parent pays gets no tab, no plan choice, no invoices and can't change the plan; making that student the bill payer gives them billing.
