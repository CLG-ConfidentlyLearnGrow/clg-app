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
