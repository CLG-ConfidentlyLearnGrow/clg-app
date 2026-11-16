# Only the people paying see billing

Carla, 16 Nov 2026: "the person/s paying are the only ones to see billing information." This replaces two earlier rules from the same day: sibling privacy (an adult learner sees family billing only when they're the only learner) and "students who don't pay get no Billing tab". Being a parent, or an adult learner, is no longer enough on its own.

## Who sees a family's billing

- The family's **bill payer**: named by CLG on Admin > Billing, or the first parent (or adult learner who signed up alone) to choose the plan or agree to the payment terms while the family has no bill payer.
- Any **extra payer** sharing the invoices (named by CLG with Save split).

Everyone else (another parent, a student, an adult sibling) sees no plan, invoices, invoice lines, payments or credit, can't choose the plan or accept the terms, and gets no Billing tab. They still see **Sessions on hold** on their dashboard when an invoice is overdue, so nobody is left wondering why sessions stopped.

## Why

- **Learning first.** Family and student dashboards stay focused on learning and next steps (AERO, cognitive load theory; EEF, "Metacognition and self-regulation"; EEF, "Working with Parents to Support Children's Learning", which puts parents' role on supporting learning at home). Invoices belong with the person paying.
- **Privacy Act 1988 (Cth), APP 6 and APP 11:** a family's payment details and invoices are used for billing the payer; limit access to those who need it. Separated or blended families often split who pays; another adult in the family shouldn't see someone else's payments.
- **Children's Online Privacy Code (OAIC, due Dec 2026)** and **UK/EU GDPR Article 5(1)(c)**: data minimisation and privacy by default.

## How it works (migration `20261118900300_billing_only_payers.sql`)

- `private.is_family_payer` now means bill payer or extra payer. Every billing access rule uses it (billing accounts, invoices and their lines and payments, credit, credit balance, terms, plan choice, to-do numbers).
- `private.billing_can_start` lets a parent (or a sole adult learner with no parent) set up payments only while the family has no bill payer; doing so makes them the bill payer. It never shows invoices.
- `billing_my_plan_choices`, `billing_choose_plan`, `billing_accept_terms` and `billing_i_pay` use both checks.
- Menus: Billing shows on the Parent and Student dashboards only when `billing_i_pay()` says yes. The parent dashboard now shows **Sessions on hold** (the student dashboard already did).
- Who CLG can add as an extra payer (`private.can_pay_for_family`) is unchanged from sibling privacy.

## Tests

- New `supabase/tests/billing_only_payers.test.sql`: before a payer exists a parent is offered the plan but sees no invoices; accepting the terms makes them the bill payer; a second parent then sees nothing and can't change anything but is told about a pause; naming them an extra payer gives them billing.
- `sibling_privacy.test.sql`, `billing.test.sql`, `billing_choose_plan.test.sql` and `billing_students_who_pay.test.sql` re-run this migration after the older files they re-run, and sibling privacy now also checks that a parent who stops paying loses billing.
