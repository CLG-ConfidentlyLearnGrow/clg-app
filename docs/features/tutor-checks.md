# Tutors add their own child safety checks

## What it does
Tutors enter each check themselves: the number, the date done and the date it is due again. Every entry is logged with who sent it and when. An admin confirms it against the official record (or sends it back with a reason the tutor sees). Only confirmed checks count towards matching.

## Why (research and practice)
- Self-entry with employer verification is the model used by the state screening units: the worker applies and holds the check, and the organisation verifies it online and records the result (SA DHS Screening Unit; NSW Office of the Children's Guardian; Service Victoria WWC).
- Keeping an up-to-date register of each worker's check, with expiry dates and prompts before expiry, is part of National Principles for Child Safe Organisations, Principle 5 (people working with children are suitable and supported).
- Moving routine data entry to the person who holds the information cuts admin time and errors; the admin confirmation step keeps the safety control with CLG.

## Legal rules it touches
- Working with Children checks in each state (SA: Child Safety (Prohibited Persons) Act 2016; VIC: Worker Screening Act 2020; NSW: Child Protection (Working with Children) Act 2012). The employer must verify, not just accept a number.
- National police check within 5 years (CLG policy).
- RRHAN-EC training (SA Department for Education requirement for people working with children in education settings).
- Privacy Act 1988, APP 3 and APP 11: collect only what is needed and keep it secure. The app stores the check details, not copies of certificates.
- Records are deleted with the tutor's other records under the retention rules (7 years after a tutor leaves).

## Rules in the database
- A tutor can only add checks for themselves, with two-step login, and cannot confirm, edit or delete them.
- Admin entries and admin confirmations are stamped with who and when.
- Tests: `supabase/tests/tutor_checks.test.sql`.
