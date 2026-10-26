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

## Change, 26 Oct 2026: police check optional, first aid added
- Carla decided a national police check (Nationally Coordinated Criminal History Check) is no longer required. The law requires a working with children check for child-related work. That check already includes ongoing criminal history screening, and in SA it is the required screening (Child Safety (Prohibited Persons) Act 2016). A police check is not required on top of it.
- Tutors can still record a police check. It still counts for 5 years from the date it was issued, but it no longer affects who can be matched.
- First aid certificates can now be recorded, with their renewal date. They are optional. HLTAID011 Provide First Aid is commonly renewed every 3 years, and the CPR part every year.
- Policy documents that mention a required police check (child safe policy, tutor contract) need the same change.

## Change, 26 Oct 2026: tutors attach a copy of each certificate
- Carla decided tutors must attach a copy (PDF or photo) with every check they add. This makes checking quicker for admins and gives a record of what was shown. It replaces the earlier "no copies stored" approach.
- Copies are kept in a private file store. Each tutor has their own folder. Only that tutor and CLG admins can open a copy, and only after two-step login. Each "open" makes a link that works for one minute. Database rules enforce this, with tests.
- The database refuses a tutor's check without an uploaded copy in their own folder. A tutor can't attach someone else's file, and can't delete a copy once it's attached.
- The app checks the file type from the file itself, not its name (PDF, JPG, PNG or WebP), and limits files to 3.5 MB. Large phone photos are shrunk before upload.
- Admins should still confirm a working with children check against the state's online check (for SA, the DHS screening portal). A copy of a card doesn't show whether the clearance is still valid today.
- Privacy: a police check copy is sensitive information (criminal record) under the Privacy Act (APP 3.3 needs consent and that it is reasonably necessary). The upload form tells tutors who can see it. The privacy policy and tutor contract should say CLG stores copies of screening documents, and for how long.
- Retention: copies follow the check record (screening records are kept 7 years after the tutor leaves). Still to build: the nightly deletion must also remove the stored file through the storage service, not only the record. This isn't due before 2033 at the earliest.
