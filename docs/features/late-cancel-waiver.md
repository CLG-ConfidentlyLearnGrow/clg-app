# Late-cancel waiver and the 15-minute no-show wait

Asked for by Carla, 16 Nov 2026, while reviewing the family terms:

- "5.3 ... This can only happen once per year, more than this and proof is
  required - further explanation to the CLG Team (NOT the tutor - at this
  stage either Lauren or myself)."
- "5.4 ... After the 15 minutes, the tutor will log off/leave location."

Billing module (waiver) and scheduling module (no-show wait). Migrations
`supabase/migrations/20261118410100_late_cancel_waiver.sql` and
`20261118410200_no_show_wait.sql`; tests in
`supabase/tests/billing_waiver.test.sql` and
`supabase/tests/scheduling_no_show_wait.test.sql`.

## What it's for

Late cancellations cost the tutor's held time, so the family terms give
little or no credit under 2 hr notice. Children do get suddenly sick, and
families have emergencies. A fixed, once-a-year waiver lets CLG be kind
without the rule becoming a negotiation every week. It also keeps the
decision with CLG, not the tutor, so the tutor-family relationship stays
about learning.

## What the evidence says

- **Attendance matters** (AERO, *Attendance matters*; EEF guidance on
  improving attendance): regular attendance is linked to learning, and
  supportive, clear responses to absence work better than punitive ones.
  A clear late-cancel rule protects the regular session; a once-a-year
  waiver is the supportive exception for genuine illness or emergencies.
- **Parental engagement** (EEF, +4 months): relationships with families work
  best when expectations are clear and contact is respectful. A rule written
  in the terms, applied the same way to every family, avoids awkward
  case-by-case talks with the tutor.
- **Tutoring dosage** (EEF one to one tuition, +5 months; Stanford National
  Student Support Accelerator): the gains come from sessions that actually
  happen. The 15-minute wait gives a late learner a fair chance to start,
  while the session still ends at its booked time so the tutor's next
  learner isn't affected.

## How it works

### Waiver

1. Owner and Operations admins (today Carla and Lauren) open **Billing >
   Family billing > Late-cancel waivers**. It lists family cancels and
   no-shows from the last 60 days and the next 14, with the notice given,
   the credit, and how many waivers the learner has had that year.
2. They write a short reason (no health details) and choose **Waive**. The
   family gets a full credit for the session.
3. Each learner gets one waiver per calendar year (by the session's date in
   Adelaide). After that, the admin must tick **Proof seen**, having had an
   explanation. The database refuses without it.
4. If the daily credit run already gave a smaller credit, the rest is added
   as a goodwill credit linked to the session. If not, the credit run gives
   the full credit.
5. Tutor pay doesn't change. A tutor paid 50% for a cancel under 2 hr notice
   keeps it.

### 15-minute no-show wait

A tutor can record a no-show only from 15 minutes after the start. Before
then the app says "Please wait 15 minutes after the start before recording a
no-show". Admins can record or correct it at any time after the start (for
example, when the family rings to say the learner won't come). Marking a
session **Done** isn't held back. Any time a tutor is paid for but not
teaching is filled with training, or set admin duties for tutors already
accepted for admin work (tutor contract 2.3A); that's handled by the
existing top-up and training features.

## Privacy, child safety and the law

- **Privacy Act 1988, APP 3 (collect only what's needed) and APP 11
  (security)**: proof of illness is often a medical certificate, which is
  health information. The app records only that proof was seen, never a
  copy. The reason box asks for no health details.
- **Need to know**: waivers and their reasons are readable only by Owner and
  Operations admins (row level security on `billing_cancel_waivers`). Tutors,
  families, Support and Finance admins can't read them. Nobody writes the
  table directly; changes go through `billing_waive_late_cancel`, and every
  change is in the audit log.
- **Australian Consumer Law (unfair contract terms)**: the waiver limit and
  the 15-minute rule are written in the family terms (5.3 and 5.4), so the
  app applies exactly what families agreed to.
- **Fair Work**: tutor pay for late cancels and no-shows is unchanged by a
  waiver.
- **UK and EU**: the same approach meets UK GDPR / GDPR data minimisation
  (no special category data stored).

## Database

- `billing_cancel_waivers`: one row per waived session (learner, family,
  year, proof seen, reason, who, when).
- `billing_waive_late_cancel(session, reason, proof_seen)`: does the checks
  and records the waiver, adding the rest of the credit if needed.
- `billing_waiver_list()`: the list for the Billing page (admins only).
- `private.billing_session_credit_percent`: a waived session gets 100%.
- `record_session_outcome` (edited in place): tutors wait 15 minutes before a
  no-show.

## How we'll know it works

- waivers per term, and how many needed proof
- no-shows recorded by tutors, and how many sessions started late but went
  ahead within the 15 minutes

## Not done (could come later)

- Families asking for a waiver in the app (for now they contact CLG).
- Showing a family how many waivers they have left.
