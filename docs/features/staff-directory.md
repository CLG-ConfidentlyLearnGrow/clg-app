# Staff directory

Requested by Carla, 2026-10-29: "a list of all employees and their job
roles, which can be searched through and filtered". Built 2026-11-02, after
the app email setup was finished.

## What it's for

As CLG grows from 5 to 20+ tutors and adds office and finance help, admins
need one place to answer "who does what here?": who to ask about a booking,
which tutors teach Advanced Maths, who works in Victoria, who has finished.
Until now the Staff and accounts section listed names, emails and admin
levels, but had no job titles and no way to search or filter.

What it does:

- **Admin > Staff directory** (`/admin/staff`) lists every tutor and admin.
- Each person shows their **job title** (for example "Director and Child
  Safety Officer", "Operations coordinator", "Tutor"), their **role in the
  app** (Owner, Operations, Support or Finance admin; Tutor), the state they
  work in, the subjects they teach, and their email.
- **Search** by name, email, job title or subject. **Filter** by role in the
  app, job title, status (working now, finished, everyone), state and subject.
- The owner and operations admins **set job titles** (Edit on each card).
  A blank title removes it. Each change goes in the activity log.
- Job titles are separate from admin levels on purpose: a title says what
  someone's job is; the level decides what they can see. Changing a title
  never changes anyone's access.

## What the evidence says

The education research bodies (Evidence for Learning, AERO, EEF) study
teaching, not staff lists, but two of their findings apply to how a
growing tutoring service is run:

- **Clear roles make change stick.** The EEF's guide to implementation
  (*A School's Guide to Implementation*, 2nd ed., 2024) says new ways of
  working succeed when staff know who is responsible for what and who to go
  to for support
  (https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/implementation).
  Evidence for Learning publishes the Australian edition
  (https://evidenceforlearning.org.au/education-evidence/guidance-reports/putting-evidence-to-work-a-schools-guide-to-implementation).
- **Matching students to the right tutor.** The EEF's tutoring guidance and
  AERO's work on small-group tuition stress fitting the tutor to the
  student's subject and level. Filtering by subject and state helps admins
  find the right tutor quickly (the matching rules themselves stay in the
  scheduling module).

Child-safe-organisation guidance points the same way:

- **National Principles for Child Safe Organisations**, Principle 1
  (leadership and culture) and Principle 7 (staff are equipped with the
  knowledge and skills to keep children safe): staff should know who holds
  child safety duties. A job title such as "Child Safety Officer" makes that
  visible inside the app
  (https://childsafe.humanrights.gov.au/national-principles).
- South Australia's child safe environments guidance asks organisations to
  name who is responsible for child safety and make it known to staff.

## How the design follows the evidence

- One list, one place to look, with plain job titles anyone can read.
- Filters for the questions admins actually ask (subject, state, finished).
- Job titles are free text with suggestions, so CLG can describe real jobs
  (including child safety duties) without a code change.

## How we'll know it works

- Every current staff member has a job title (the "No job title yet"
  filter shows who's missing one).
- Admins stop keeping a separate staff list in Excel or Teams.

## Privacy and child safety

**Data held.** Only one new item: a job title for each staff member
(`staff_job_titles`). The directory shows names, work emails, app roles,
work state and subjects, which the app already held. It deliberately does
**not** show phone numbers, addresses, dates of birth, check details or pay.
No children's data is involved.

**Who sees it (enforced in the database).**

| Who | Sees the directory | Changes job titles |
| --- | --- | --- |
| Owner | Yes | Yes |
| Operations admin | Yes | Yes |
| Support admin | Yes | No |
| Finance admin | Yes | No |
| Tutor | No (only their own job title, through "Download my information") | No |
| Parent, student, signed-out visitor | No | No |

Admins must use two-step login, as for the rest of the admin area. The
table can't be written directly; the only way in is `set_staff_job_title`,
which checks the level and that the person is staff.

**Rules it touches.**

- **Privacy Act 1988 and the APPs.** Private-sector employee records are
  partly exempt (s 7B(3)), but the exemption doesn't cover contractors or
  job applicants, and it may narrow in the privacy reforms. The design
  meets the APPs anyway: collect only what's needed (APP 3), use it for
  running CLG (APP 6), keep access to those who need it (APP 11), and let
  people see their own record (APP 12, via Download my information).
- **UK GDPR / EU GDPR** (for later): staff data is personal data. Lawful
  basis is legitimate interests or the employment contract; the directory
  is internal only and minimal, which fits data minimisation (Art. 5(1)(c)).
- **Retention.** A job title is deleted with the person's account. Former
  tutors stay in the list (marked finished) until the retention rules
  delete their account.

**Not built (could be added later):** letting tutors see the directory
(names and job titles only), phone numbers, start dates, or a link to Xero
employee records.
