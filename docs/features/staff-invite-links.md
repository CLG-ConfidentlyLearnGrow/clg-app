# Staff invite links (no approval step)

Requested by Carla, 2026-10-29: "If people are sent a link, that email is
auto yes for requesting access as a tutor or admin, depending on the link
sent to them. Parents and students can create profiles without asking for
permission."

## What it's for

- **Tutors and admins join in one step.** An admin adds the person's email
  and picks Tutor or Admin. The person gets a CLG link. When they use it,
  they choose their name and password and are a tutor (or admin) straight
  away. Nobody has to approve them afterwards.
- **Links that keep working long enough.** Supabase's own invite links
  work for about an hour and email virus scanners (common with Microsoft
  365, which CLG uses) can use them up by opening them. The CLG link works
  for 7 days, and opening it only shows a form.
- **Parents and students sign up freely.** This already worked: anyone can
  create a parent account, and students aged 16 or over can create their
  own. The sign-up page now says so plainly.

## What it does

- Admin > Staff > **Add staff**: email and role.
  - Email already has a CLG account (for example a parent who tutors): the
    role is added straight away (unchanged).
  - Otherwise: CLG makes an invite link and emails it through Resend. If
    email isn't set up, or sending fails, the admin sees the link to send
    themselves.
- The link is tied to **one email and one role**, works **once**, for
  **7 days**. Adding the same person again sends a new link and the old
  one stops working.
- **Admin links:** only the owner can make them (same rule as before). Any
  admin can make tutor links.
- `/join?t=...` shows who the invitation is for and the role, then asks
  for name and password. After joining, staff set up two-step login.
- Admin > Staff > **Invitations not used yet**: who hasn't joined, when
  each link runs out, and a Cancel button.

## What the evidence says

- **Tutor quality and support matter more than paperwork.** The EEF's
  guidance on tutoring (*Making a difference with effective tutoring*,
  2021,
  https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/tutoring)
  stresses that tutoring works when tutors are well prepared, trained and
  supported, and linked with what the learner is doing elsewhere. Getting
  new tutors into the app quickly, without an extra approval queue, means
  CLG's time goes on induction and checks rather than admin.
- **One-to-one tuition has high impact when sessions happen.** Evidence for
  Learning's Toolkit rates one-to-one tuition at about +5 months
  (https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/one-to-one-tuition).
  A smooth start for new tutors helps CLG match waiting students sooner.
- **Safe people around children.** The National Principles for Child Safe
  Organisations, Principle 5, asks that people working with children are
  suitable and supported, including screening before they start
  (https://childsafe.humanrights.gov.au/national-principles). The
  invitation is the "suitable to be invited" step; the checks below are the
  screening step, and they stay in place.

## How the design follows the evidence

- No approval step for invited staff: the admin's decision to invite is
  the approval.
- **Checks still come first.** A new tutor has the tutor role but can't be
  matched with, or assigned to, any student until CLG has confirmed their
  Working with Children Check, RRHAN-EC (SA) and first aid, in date, for
  the student's state. This is enforced in the database (unchanged).
- The welcome text tells new tutors exactly what to do next: set up
  two-step login, then add their checks.

## How we'll know it works

- Invitations not used yet stays short; few links expire unused.
- Time from invite to first confirmed check, for new tutors.
- No "my link didn't work" messages from new staff.

## Privacy, security and child safety

- **Who can invite:** only admins with two-step login; only the owner can
  invite admins. Checked in the database (`create_staff_invite_link`), not
  only in the app.
- **The link proves the inbox.** It is only emailed to the invited address
  (or sent by an admin who chose to pass it on). Using it creates the
  account with that email confirmed, like Supabase's own invite link.
- **Only a scrambled copy (SHA-256 hash) of the link is stored.** The link
  has 64 random characters, so it can't be guessed. The join page tells
  people not to use a link sent to someone else, and asks browsers not to
  pass the link on to other websites.
- **Two-step login** is still required for all staff before any staff
  tools work (Australian Cyber Security Centre Essential Eight: multi-factor
  authentication; APP 11, keeping personal information secure).
- **Audit:** invitations are recorded in the activity log (who invited
  whom, as what, and when it was used).
- **Data:** the invited email and role, kept with the invitation record.
- **Parents and students:** self sign-up is unchanged. Under-16s still
  can't have their own login (checked in the database). An admin still
  confirms each parent and child link before a tutor can be assigned to a
  child. That is a child safety check, not permission to sign up, so it
  stays.
- **UK and EU:** the same design fits UK GDPR and EU GDPR (data
  minimisation, security of processing); nothing country-specific.
- Tests: `supabase/tests/staff_invite_links.test.sql`.

## Not built yet

- A "request to join as a tutor" form for people CLG hasn't invited
  (all staff still start with an invitation).
- Resending a link with one click from the "not used yet" list (for now,
  add the person again).
