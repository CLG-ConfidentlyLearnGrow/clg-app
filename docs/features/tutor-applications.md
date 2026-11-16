# Tutor applications (apply to tutor through the app)

Requested by Carla, 16 Nov 2026: "Would be really great if tutors could
apply to be a tutor through the app."

## What it's for

- **One place for applications.** Today people ask to tutor by email,
  Typeform or word of mouth, so details end up in several inboxes. A
  public **Apply to tutor** page puts every application in one admin
  queue, with the same questions for everyone.
- **Safe recruitment, step by step.** Each application moves through the
  child-safe recruitment steps (interview, two referee checks, Working
  with Children Check verified) before anyone is invited to the app.
- **Approval flows straight into the invite.** Approving an application
  sends the existing staff invite link (Staff invite links), so the new
  tutor joins, sets up two-step login and adds their checks as usual.
- **Growth.** CLG plans to go from 5 to 20+ tutors within a year. A
  consistent application and screening record makes that possible
  without Carla holding it all in her head.

## What the evidence says

- **Who tutors matters.** The EEF's guidance on tutoring (*Making a
  difference with effective tutoring*, 2021,
  https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/tutoring)
  says tutoring works best when tutors have good subject knowledge, are
  well trained and supported, and keep sessions linked to what the learner
  is doing in class. So the form asks what each person can teach (subjects
  with year levels), their qualifications and teaching experience, and
  how they would help a learner who is stuck.
- **One-to-one tuition has high impact when it is well matched.**
  Evidence for Learning's Toolkit rates one-to-one tuition at about +5
  months of progress
  (https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/one-to-one-tuition),
  with the impact depending on sessions being regular and linked to the
  learner's needs. Asking for state, in-person or online, availability
  and weekly hours up front means CLG recruits for the gaps in its
  waiting list rather than at random.
- **Clear teaching and good relationships.** AERO's explicit instruction
  resources (https://www.edresearch.edu.au) stress clear explanations,
  modelling and checking for understanding, alongside positive
  relationships with learners.
  The short statement asks applicants to describe a time they helped a
  young person understand something difficult, which shows these
  practices better than a list of jobs.
- **Safe people around children.** The National Principles for Child Safe
  Organisations, Principle 5 (https://childsafe.humanrights.gov.au/national-principles),
  asks that people working with children are suitable and supported,
  with recruitment that includes a child safety focus, screening, and
  referee checks. South Australia's *Child Safe Environments* guidance
  (Department of Human Services, Safe recruitment) recommends: stating the
  organisation's child-safe commitment in the job advertisement and
  application; behaviour-based interview questions about working with
  children; at least two referee checks (ideally by phone, including a
  recent supervisor, asking directly about suitability to work with
  children); and verifying the Working with Children Check with the
  screening unit before the person starts.

## How the design follows the evidence

- **Public form** at `/apply` (linked from the sign-in, sign-up and home
  pages). It opens with CLG's child-safe commitment and what happens next.
- **What the form asks** (default set, Carla to review):
  - Name, email, phone, state, suburb or town.
  - In person, online or both; right to work in Australia (yes or no).
  - Subjects and year levels they can teach (free text; once they join,
    tutors add their subjects properly in the app).
  - Days and times free, and hours per week wanted.
  - Qualifications (including current study and teacher registration, if
    any) and teaching or tutoring experience.
  - Working with Children Check: held, applied for, or not yet (number,
    state and expiry if held). RRHAN-EC done or not yet. First aid current
    or not yet. (Police check is optional at CLG, so it isn't asked.)
  - Two referees: name, how they know them, email and phone. At least one
    should be a recent supervisor; ideally someone who has seen them work
    with children or young people.
  - Why they'd like to tutor with CLG, and a time they helped a young
    person understand something difficult.
  - A CV (PDF, optional).
  - Two declarations: the information is true and CLG may contact
    referees and verify checks; and they are not prohibited from working
    with children and know of no reason they would be unsuitable.
  - How they heard about CLG (optional).
- **Not asked, on purpose:** age, date of birth, gender, marital status,
  health, religion, photos or criminal history. These aren't needed to
  decide (APP 3), and asking them invites discrimination claims (SA Equal
  Opportunity Act 1984; federal Sex, Age and Disability Discrimination
  Acts). Right to work is a yes or no question only.
- **Admin queue** at **Tutor applications** (owner and Operations admins,
  with two-step login): New, Shortlisted, Approved, Declined, Withdrawn.
  Each application shows every answer, the CV, and a **screening record**:
  - interview date and notes, with a list of child-safe interview
    questions to use;
  - referee 1 and referee 2 checked (date and notes);
  - Working with Children Check verified with the screening unit (date);
  - private admin notes.
- **Approve** is only possible once the interview and both referee checks
  are recorded and the person has said they have the right to work in
  Australia. This is enforced in the database. Approving sends the usual
  tutor invite link to the applicant's email. If the email can't be sent,
  the admin sees the link and a **Send invite again** button.
- **Decline** needs a reason from a short list (for example "Subjects or
  year levels not needed right now") plus an optional note. CLG can send
  a polite "not this time" email. The reason stays private to admins.
- **Still enforced later:** a new tutor can't be matched with any student
  until their checks are confirmed in the app (unchanged).

## How we'll know it works

- Every new tutor in 2027 arrives through an application with a complete
  screening record.
- Time from application to decision (aim: under 14 days).
- Number of applications by subject and state, compared with the
  waiting list, to target advertising.

## Privacy, security and child safety

- **Data:** applicants' contact details, work history, qualifications,
  check details, referees' contact details, statements and CV. This is
  personal information under the Privacy Act 1988. The employee records
  exemption does not cover applicants who are not hired, so the APPs
  apply in full.
- **Collection notice (APP 5):** the form says who is collecting, why,
  that CLG will contact referees and the screening unit, who sees it,
  how long it's kept, and links to the privacy policy. Applicants confirm
  they have their referees' permission to share their details.
- **Who sees it:** only the owner and Operations admins with two-step
  login (access rules in the database, `private.is_admin()`). Support and
  Finance admins, tutors, parents and students see nothing. Nobody can
  read the table or the CVs without signing in.
- **How it gets in:** the public form never talks to the database
  directly. The app's server checks the form, then saves it using the
  server's own key. The save function can't be called with the public
  key, so spam checks can't be skipped.
- **Spam protection:** a hidden "leave this empty" box that people never
  see (bots fill it); a minimum time to fill the form; at most 3
  applications a day from one internet address (only a scrambled copy of
  the address is kept, and only for 30 days); at most 100 a day in total;
  one open application per email.
- **CVs:** PDF only (checked from the file's contents, not its name), up
  to 3.5MB, kept in a private file store. Admins open them through a link
  that works for one minute.
- **How long it's kept (APP 11.2):**
  - Declined or withdrawn: deleted 12 months after the decision.
  - Never decided: deleted 12 months after it was sent.
  - Approved: kept 7 years after approval, as part of CLG's child-safe
    recruitment record (matches the 7 years kept for tutor records).
  - 12 months covers the time to make a complaint under the SA Equal
    Opportunity Act 1984 (12 months). CVs are deleted with the
    application. The app's daily job does the deleting.
- **Audit:** every change to an application is recorded in the activity
  log.
- **UK and EU later:** the UK ICO's employment practices guidance
  suggests keeping unsuccessful applications for around 6 months; the
  period is set in one place in the database so it can be shortened per
  country.
- Tests: `supabase/tests/tutor_applications.test.sql`.

## Not built yet

- An email to admins when a new application arrives (for now, the side
  menu shows a number next to **Tutor applications**).
- Applicants checking their own progress or withdrawing online (they
  can email CLG).
- Copying an approved applicant's subjects and availability into their
  new tutor profile automatically.
