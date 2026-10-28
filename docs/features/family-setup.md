# Setting up a family's account for them

Requested by Carla, 2026-10-28.

## What it does

- **Admin sets up the account.** In Admin, under "Families and matching", the "Set up a family" form lets an admin fill in a family's details. This might be during a phone call, or for families already with CLG.
  - **Parents and children:** the admin enters the parent's name and email, then one child. That child's details are the name, date of birth, state, school year level, school, subjects (with the level they work at in each), end goal and other information.
  - **More children:** the admin uses the same parent email again, and each child is added to the same account.
  - **Students 16 or over, or adult learners:** they can get their own account the same way.
- **The family gets a link.** The app emails the link to choose a password.
  - Until CLG's own email sender (Resend) is set up, Supabase can't email families. Instead, the admin sees the link and sends it themselves, for example by text.
  - The link works once, for a short time, in any browser.
- **First sign-in.** After choosing a password, the family agrees to the privacy policy and terms (the `/agree` page) before seeing their dashboard. They can check and change the details CLG entered. The `/agree` page also covers anyone whose parent or student account has no agreement on record.
- **Already checked.** A parent link made by an admin is already confirmed, so a tutor can be assigned straight away. Links that parents make themselves still wait for an admin.
- **Existing parent accounts.** If the email already belongs to a parent, the child is added to that account. No second account or email is made.

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
- Re-sending a link if it expires before the family uses it.
