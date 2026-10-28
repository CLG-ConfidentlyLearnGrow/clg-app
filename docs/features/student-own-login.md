# Giving a student their own login

Requested by Carla, 2026-10-28.

## What it does

- **Own login is optional.** Students 16 or over can stay on a parent's account. When a student is ready for their own login, an admin gives them one.
- **Where:** Admin, "Families and matching", "Give a student their own login". The admin picks the student and enters the student's own email.
  - Only students aged 16 or over, on a parent's account, with a date of birth, are listed.
  - The email must not already be used for a CLG account.
- **The link.** The student gets a link to choose a password. Until CLG's own email sender is set up, the admin sees the link and sends it themselves. The link works once, for a short time. Giving the login again sends a new link and cancels the old one.
- **What the student keeps.** The same student record: details, subjects, goals, progress, bookings and tutor. Nothing is copied or lost.
- **What the parent keeps.** The parent link stays, so the parent can still see and manage the student's details, bookings and invoices.
- **First sign-in.** The student agrees to the privacy policy and terms themselves (the `/agree` page).

## Why (research)

- **Learner agency and self-regulation.** The EEF guidance report *Metacognition and Self-Regulated Learning* (2018, updated 2021) finds that teaching learners to plan, monitor and evaluate their own learning has high impact (about +7 months). Giving older students their own view of their goals, progress and sessions supports this.
- **Parents stay involved.** The EEF report *Working with Parents to Support Children's Learning* (2021) recommends keeping parents engaged as students grow. Keeping the parent link means the parent still sees what's happening without extra work.

## Legal notes

- **Age 16.** Students under 16 can't have their own login. This is checked in the database (`check_login_age` and `admin_offer_student_login`). OAIC guidance presumes under-15s can't make their own privacy decisions; 16 also meets the highest EU age of digital consent.
- **Proving the inbox.** The student record is handed to the new login only once the student uses the emailed link (the email is confirmed). Signing up with that email without confirming it gives nothing.
- **Consent.** The student agrees to the privacy policy and terms themselves at first sign-in (APP 5 notice). The admin never agrees for them.
- **Under 18.** The parent link is kept, so a parent or carer stays responsible for bookings and payment (contract and child safety rules for minors).
- **Access rules (database):** only an admin with two-step login can make an offer. Parents, tutors, students and the public can't make or see offers. Tests: `supabase/tests/student_own_login.test.sql`.
- **Audit:** offers are recorded in the activity log.

## Not built yet

- Letting a parent ask for their child's own login from the parent dashboard.
- Removing the parent link when a student turns 18, if the student asks.
