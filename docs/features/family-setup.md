# Setting up a family's account for them

Requested by Carla, 2026-10-28.

## What it does

- **Admin sets up the account.** In Admin, under "Families and matching", the "Set up a family" form lets an admin fill in a family's details. This might be during a phone call, or for families already with CLG.
  - **Parents and children:** the admin enters the parent's name and email, then one child. That child's details are the name, date of birth, state, school year level, school, subjects (with the level they work at in each), end goal and other information.
  - **More children:** the admin uses the same parent email again, and each child is added to the same account.
  - **Students 16 or over, or adult learners:** they can get their own account the same way.
- **Only the basics are needed (added 2026-10-28).** For a parent's child, the admin needs only the parent's name and email and the child's name. Anything left blank (date of birth, state, year level, school, subjects, goal) the family is asked to finish on their dashboard: a "Please finish ... details" card appears until it's done.
  - Families can fill in a missing date of birth or state once. After that, only CLG can change them.
  - No tutor can be assigned and nothing can be booked until date of birth, state, year level and school are in. This is enforced in the database.
  - Students 16 or over with their own login still need date of birth, state, year level and school up front, because their age must be checked before they get a login.
- **Why we ask for date of birth.** Every date of birth field says: "We ask for date of birth so we can apply the privacy and child safety protections that suit each age group." Date of birth decides parent consent, whether a student may have their own login (16+), and child safety checks.
- **The family gets a link.** The app emails the link to choose a password.
  - Until CLG's own email sender (Resend) is set up, Supabase can't email families. Instead, the admin sees the link and sends it themselves, for example by text.
  - The link works once, for a short time, in any browser.
- **First sign-in.** After choosing a password, the family agrees to the privacy policy and terms (the `/agree` page) before seeing their dashboard. They can check and change the details CLG entered. The `/agree` page also covers anyone whose parent or student account has no agreement on record.
- **Already checked.** A parent link made by an admin is already confirmed, so a tutor can be assigned straight away. Links that parents make themselves still wait for an admin.
- **Existing parent accounts.** If the email already belongs to a parent, the child is added to that account. No second account or email is made.

## Sending a new link (added 2026-10-28)

- **When:** a family's or student's link ran out before they used it.
- **Where:** Admin, "Families and matching", "Send a new login link". The admin enters the email and the app emails a new link, or shows it for the admin to send while CLG's email sender isn't set up. The old link stops working.
- **Limits, for safety:**
  - Only for family and student accounts that have never signed in. Anyone who has signed in uses "Forgot password" themselves, so an admin can never take over an account that's in use.
  - Not for staff accounts; staff are invited again under Staff.
  - For a student's own login, the admin uses "Give a student their own login" again with the same email. The database now allows this when the account made the first time was never used (`20261029100400_send_new_login_link.sql`, tests in `supabase/tests/student_own_login.test.sql`).

## Why (research)

- **Removing barriers to engagement.** The EEF guidance report *Working with Parents to Support Children's Learning* (2021) recommends:
  - making it easy for parents to take part, using personal and direct contact;
  - focusing effort on families who are harder to reach.

  Setting the account up during a call removes a sign-up step that busy or less confident families may put off. It also fits Carla's rule that parent support stays light.
- **Starting tuition well.** One-to-one tuition (EEF Toolkit, about +5 months) works best when it is linked to what the learner needs. Capturing subjects, levels and the end goal during the first conversation gives the tutor this before the first session, rather than waiting for the family to fill in a form.
- **Fewer drop-offs.** Asking people to create accounts themselves loses some of them before they start. Doing it with the family, then and there, avoids that.

## Legal notes

- **Privacy Act, APP 3 and APP 5:**
  - The admin collects only what the sign-up form asks for, directly from the family, during contact the family started.
  - The family sees the privacy policy and must agree before using the app.
  - The "other information" box still asks for no medical details.
- **Consent:**
  - Agreement to the privacy policy and terms is recorded only when the family ticks it themselves (`consent_records`), never by the admin on their behalf.
  - When CLG changes the policy version, parents and students are asked to agree again.
- **Children:**
  - Under-16s are added only to a parent's account. A student's own login still needs them to be 16 or over, enforced in the database.
  - Date of birth and state stay admin-only to change.
- **Access rules (database):**
  - `admin_add_child` and `admin_find_account` need an admin with two-step login.
  - Tutors, parents and the public can't use them.
  - Tests are in `supabase/tests/family_setup.test.sql`.
- **Audit:** everything the admin creates is recorded in the activity log by the existing audit triggers.

## Not built yet

- Bulk import of current families from a spreadsheet.
