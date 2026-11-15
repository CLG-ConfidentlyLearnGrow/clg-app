# Staff names (first and last name)

Asked for by Carla, 15 Nov 2026. Staff were showing as the start of their
email address (for example "amy.swann2000") on the confidential worker flag
form and elsewhere, because the app filled in the name from the email when
none was given, and there was no screen to change a name.

## What it does

- **Joining as staff** (`/join`) now asks for a first name and a last name,
  both required.
- **Existing tutors and admins** with no first and last name are sent to the
  new **Your name** page (`/my-name`) when they next open their dashboard.
  It brings them straight back once saved. If their current name looks real
  (it has a space and isn't their email), the boxes are pre-filled to save
  typing; otherwise they start empty.
- **Anyone can change their own name** at any time by tapping their name at
  the top right ("Signed in as"). This includes parents and students.
- **The owner and operations admins can change a tutor's or admin's name** in
  the staff directory (Manage > Name). Staff with no first and last name show
  a "Name not given yet" label there.
- Everywhere the app shows a name (staff directory, child safety and
  feedback forms, sessions, matching, pay, invoices) uses the account's full
  name, which the database now builds as "First Last" whenever both are
  given. No page needed its own change.

## Access rules (in the database)

- New columns `accounts.first_name` and `accounts.last_name` (1 to 100
  characters each).
- `public.set_my_name(first, last)`: changes only the caller's own name.
- `public.set_staff_name(account, first, last)`: owner or operations admin
  with two-step sign-in, and only for someone with a tutor or admin role.
- Nobody can write first or last name directly; only through these two
  functions, which tidy spacing, refuse blanks, over-long names and email
  addresses, and note old and new name in the activity log.
- Once first and last name are set, writing the full name directly can't
  change what is shown.
- Tests: `supabase/tests/staff_names.test.sql`.

## Research and law

- Using a person's preferred, correctly spelled name supports trust and
  belonging, which AERO and Evidence for Learning link to engagement; for
  families, seeing a real tutor name (not an email handle) supports the
  clear, accountable relationships that child safe standards expect.
- Child safe practice (SA child safety rules, National Principles for Child
  Safe Organisations): families and children should know exactly who the
  adults working with them are. A real name, controlled by CLG admin, is part
  of that.
- Privacy Act (APP 10, quality of personal information): people can correct
  their own details, and the organisation keeps them accurate. Names are the
  only thing other people see from the `accounts` table, so no contact details
  are exposed by this change. Same position under UK and EU GDPR (right to
  rectification).
