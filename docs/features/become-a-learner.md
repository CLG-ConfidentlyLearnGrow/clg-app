# Become a learner too

Requested by Carla, 2026-10-28.

## What it does

- **Who:** anyone already signed in, such as a tutor, admin or parent, who wants to learn with CLG themselves.
- **Where:** a link at the bottom of the Tutor and Parent dashboards, "Add a student profile", opens `/dashboard/learn`.
- **What they enter:** the same details a student aged 16 or over gives at sign-up: date of birth, state, year level or stage of study, school (or university or TAFE), the subjects they want help with, and an optional goal.
- **What happens:** the account gets a student role and a Student tab next to their other dashboards. It's the same login, with no second email needed.
- **What it replaces:** before this, staff had to sign up again with a second email address (for example a plus-address).

## Why (research)

- **One person, one record.** Keeping a person's roles on one account avoids duplicate records of the same person. It is also simpler for the person and easier to keep accurate (APP 10, quality of personal information).
- **Adult learning.** The EEF Toolkit's one-to-one tuition evidence (about +5 months) is drawn from school-age learners. For adult and tertiary learners, CLG uses the same goal-setting and progress approach (EEF *Metacognition and Self-Regulated Learning*, 2021), which this profile feeds.

## Legal notes

- **Age:** only people aged 16 or over can add a student profile. This is checked in the database (`add_me_as_learner` and the existing `check_login_age` rule), the same as for sign-up.
- **Privacy:** the person enters their own details (APP 3: collected directly from them). If they haven't agreed to the privacy policy and terms yet, they are asked to on the `/agree` page.
- **Access rules (database):** a person can only add a profile to their own account. Other people can't see it unless they are CLG admins or the person's tutor. Tests: `supabase/tests/become_a_learner.test.sql`.
- **Conflicts of interest:** a tutor who is also a student is matched like any other student. Admins should not assign a tutor to themselves.

## Not built yet

- Removing a student profile from an account (an admin can delete the student record).
