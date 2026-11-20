# Home and school sessions

Requested by Carla, 20 Nov 2026, in her comments on Emma's admin role review:
"Need to go through the process of booking school sessions. Need to make a
process of booking home sessions (require at least 2 hours booked at any one
time)."

## What it does

- **Home sessions are at least 2 hours.** Weekly bookings, "another time or
  place" offers and one-off sessions at home are refused under 2 hours, in
  the database and on screen. Home times found by **Book a session** only
  show for 2 hr or longer.
- **Matching can offer home or school.** In an offer, **Another time or
  place…** now lists **At the student's home** and **At the student's
  school**. This path checks the tutor's weekly maximum and other bookings
  (a direct home or school booking used to skip those). An amber note on the
  form gives the steps to check first.
- **Times to check** no longer lists home or school sessions for a missing
  location (there is no place to check against).
- Still CLG only: families and tutors cannot book home or school sessions.
- Admin App guide: **Book a home or school session**.

Migration: `20261123400400_home_school_sessions.sql`. Tests:
`supabase/tests/scheduling_travel_home_school.test.sql`, and
`scheduling_travel_distance.test.sql` updated for the 2 hr rule.

## Evidence

- EEF Teaching and Learning Toolkit (one to one tuition, +5 months) and
  Evidence for Learning's Australian edition: regular sessions over a set
  period work best; the place matters less than consistency. Home and school
  sessions stay exceptions for access needs.
- Longer blocks when a tutor travels keep the travel time worthwhile and
  reduce cancellations from travel (CLG's own operating rule; travel between
  home sessions is unpaid under the tutor contract 2.7).

## Legal and child safety notes

- **SA Child Safe Environments and the National Principles (Principle 8,
  physical and online environments):** home visits carry more risk, so they
  stay arranged and recorded by CLG, with a valid WWCC (checked by the
  booking functions) and the tutor's code of conduct.
- **Schools:** schools set their own visitor rules (sign-in, WWCC sighting,
  supervision); the form prompts the admin to confirm them.
- **Privacy Act APP 3 and 11:** no new data. Addresses go in the booking note
  only when needed for that session.
- **Work health and safety (WHS Act 2012 (SA)):** CLG should check a home is
  safe for the tutor; the admin check before booking covers this.
