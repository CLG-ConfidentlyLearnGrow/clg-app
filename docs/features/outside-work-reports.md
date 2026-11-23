# Work outside CLG

Carla, 22 Nov 2026, from the tutor contract (v1.2 to v1.4, clause 6.7): "While you work for CLG, you must tell CLG, through the CLG App, about any educational support or administrative role you do outside CLG, paid or unpaid. This includes tutoring privately or through another business. Tell CLG before you start the role, and again if it changes or ends."

## What it is for

CLG needs to know about outside roles to manage conflicts of interest (for example a tutor teaching a CLG family privately), to check workloads stay reasonable, and to meet child safety duties, where knowing who else a worker supports matters. The contract says this is reported through the app, so the app needs a place for it.

## What the evidence says

- **Child safe organisations** (National Principles for Child Safe Organisations, Principle 5, and the SA Child Safe Environments guidance): organisations should know about their staff's roles with children and keep clear records. Outside education roles are part of that picture.
- **Staff wellbeing and workload** (EEF and AERO guidance on tutor quality): tutors who are overloaded across several jobs prepare less. Knowing about outside work lets CLG talk about hours in check-ins.

## How the design follows it

- Every tutor and admin staff member has **My contract** in their menu (even before a contract is sent), with a **Work outside CLG** card: kind of role, the role, where (blank for private work), paid or unpaid, start date and optional end date, and optional details (with a reminder not to include students' names).
- They can change a report or say it has ended at any time.
- CLG's owner gets an app notice each time a report is added, changed or ended (the notice names the person, not the details), and sees all reports under **Contracts > Work outside CLG**, not yet seen first, with a private note and **Mark as seen**. A change puts a report back to "Not yet seen".

## How we will know it works

- share of staff with an up-to-date answer (any reports, or none)
- conflicts spotted early (owner notes)

## Privacy, child safety and legal notes

- **Privacy Act 1988 (APPs 3, 6 and 11)**: this is employee information, collected because the contract requires it. Only the staff member and CLG's owner can see it (Operations, Support and Finance admins cannot). Access rules are in the database, every change is in the audit log, and reports are deleted with the account. The employee records exemption may apply, but CLG handles this as if the APPs apply in full.
- **Fair Work and restraint of trade**: the clause only asks staff to tell CLG; it does not stop outside work. The app records, it does not approve or refuse. The proposed ban on non-compete clauses for workers on lower incomes does not affect a duty to disclose.
- **UK and EU (GDPR)**: legitimate interest and contract are the bases; the same minimal fields and owner-only access apply.

## Technical

- Migration `20261124711300_outside_work_reports.sql`. It adds the table `public.outside_work_reports`, the functions `outside_work_save`, `outside_work_end` and `outside_work_mark_seen`, and an owner-only notice helper. Safe to run more than once.
- Tests: `supabase/tests/outside_work_reports.test.sql`.
