# Loading many curricula at once

## What it does
- In Admin, under Curriculum, an admin chooses ACARA's "Download entire curriculum" Excel file (Australian Curriculum v9, Foundation to Year 10).
- The file is read in the admin's browser. The app lists every subject, grouped by learning area. Each language pathway and sequence is listed separately.
- The admin ticks the subjects CLG needs and presses Load. Each subject becomes its own curriculum, and each content description becomes one skill, with its ACARA code and year level. Elaborations (teaching examples) are not loaded.
- Every loaded subject is a draft until an admin opens its summary (skills per year) and confirms it. There is also "Confirm all". A draft can be thrown away. Draft skills can't be used in goals or set for a student (database rule, tested).
- A subject that is already loaded is shown and skipped, so loading the same file twice is safe.

## Research basis
- Aligning tutoring to what the student is learning in class is one of the features of effective tutoring. See EEF, "Making a Difference with Effective Tutoring" (2021), and AERO's tutoring guidance (2023). Using the official content descriptions keeps goals tied to the curriculum the school is teaching.
- An admin checks each subject before use, because a wrong or partial load would put wrong goals in front of families.

## Legal rules touched
- ACARA content is licensed under CC BY 4.0. Each loaded curriculum stores ACARA's required credit, including the date it was downloaded and a note that it was not modified. The credit is shown with the draft in Admin.
- No personal information is involved.

## Any other curriculum (added 2026-10-26)

The admin section is now "Upload a curriculum". Besides the ACARA file, an admin can upload any curriculum as an Excel or CSV file in CLG's own simple layout: one row per skill, with these columns:

- Code (optional)
- Subject
- Year or level
- Skill
- Plain wording (optional)

The template is `public/templates/curriculum-template.csv`. The file is read in the browser and arrives as one draft, which an admin checks and confirms, as with ACARA. The "Where it comes from" field is required and is stored as the framework's `source`.

This is how CLG loads SACE (Years 11 and 12, Stage 1 and Stage 2). SACE does not publish a downloadable dataset; each subject has a PDF subject outline. Use "Year 11 (Stage 1)" and "Year 12 (Stage 2)" as the levels.

**Legal (copyright):** SACE Board material is not openly licensed. The SACE copyright page (sace.sa.edu.au/copyright, read 2026-10-26) says:

- Written permission is needed to reproduce it, except as the Copyright Act 1968 allows.
- Fees may apply.
- Applications go to askSACE@sa.gov.au and take 3 to 5 weeks.

Until permission is given, CLG should not load SACE wording word for word. Short topic names written in CLG's own words are lower risk, but are not legal advice. Record the permission and its date in "Where it comes from". The same applies to other states' and countries' curricula unless they use an open licence, as ACARA's CC BY 4.0 does.

Admins can now reach any student's progress page from Curriculum > "Link skills to a student". There they use Add a goal to link skills.
