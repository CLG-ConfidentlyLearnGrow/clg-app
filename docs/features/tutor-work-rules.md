# Tutor work rules in the app

Requested by Carla, 18 Nov 2026, while reviewing the casual and part-time or
full-time tutor contracts. The contract wording itself is handled
separately; this brief covers the four parts the app enforces or records.

## 1. What it is for

1. **Availability in blocks of at least 2 hours (casual tutors).** Casual
   tutors are paid for at least 2 hours each time they work. Short
   availability windows create bookings that cost CLG a 2-hour minimum for
   less teaching. Carla: "Tutor availability must be given in minimum
   2 hour blocks ... except for part-time and full-time employees with
   approved and agreed to regular hours."
2. **Paid time outside sessions is described and checked.** Tutors are paid
   for preparation, materials, training and other set work. Carla: tutors
   "must note what they do outside of tutor sessions for that worked time to
   be logged. There needs to be some way to track they have actually
   achieved something in this work time, and a way to check what they have
   achieved."
3. **Running late.** A family waiting at a library or at home should know
   straight away when their tutor will be late, and CLG needs a fair, factual
   record if lateness becomes a pattern. Carla: "How does it work if a tutor
   is going to be late? ... especially if it is a regular occurrence."
4. **A yearly reminder to enter new award pay rates.** Award minimums change
   from the first full pay period on or after 1 July each year. Carla: "add
   a reminder in the app to myself (or finance admin) to input the new pay
   rates for each new financial year."

## 2. What the evidence says

- **Teaching time and consistency matter.** Evidence for Learning's Teaching
  and Learning Toolkit rates one-to-one tuition at about +5 months'
  progress, and notes the effect depends on sessions being regular and
  well-run
  (https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/one-to-one-tuition).
  The EEF's guidance on tutoring (National Tutoring Programme, 2021) stresses
  consistent, well-planned sessions linked to what the learner needs. Late
  starts cut into a short session and into the family's trust, so CLG
  should know about them early.
- **Preparation is where tutoring quality is built.** The EEF's guidance on
  effective tutoring and AERO's work on explicit teaching (2023) both find
  that sessions planned against a learner's next steps work better than
  improvised ones. Asking tutors to record what they finished (a lesson
  plan, a worksheet set, a resource in Materials) keeps paid preparation
  time tied to learners' needs and makes it visible.
- **Feedback and follow-up change practice.** The EEF's *Effective
  Professional Development* (2021) and *Putting Evidence to Work* (2nd ed.,
  2024) find that practice improves when there is specific, timely
  feedback and follow-up. A record of what was achieved, and a lateness
  record that is reviewed with a note, give CLG something specific to talk
  about with a tutor.
- **Tell families simply and quickly.** The EEF's *Working with Parents to
  Support Children's Learning* recommends short, timely communication. A
  one-line "running late" notice and email does this without detail the
  family does not need.

## 3. How the design follows the evidence

### Availability blocks
- When a tutor adds or changes an available time, the database refuses a
  time shorter than 2 hours for a casual tutor, with a plain message.
- Part-time or full-time staff with agreed weekly hours on their pay details
  have no minimum. Anyone without pay details counts as casual (the safer
  choice).
- Older times shorter than 2 hours are not removed; the dashboard marks them
  so the tutor can replace them.

### Work outside sessions
- Logging hours on **My pay** now needs: the kind of work (lesson
  preparation and planning, making learning materials, training CLG set,
  other work CLG set, work during a no-show or late cancel, or office admin
  for admin staff), **What you did**, and **What you finished or achieved**.
- Work during a no-show or late cancel is already paid with that session. It
  is logged against the session to record what was done, and approving it
  adds no pay. Each session can be logged once.
- The owner or a Finance admin sees the kind of work and the achievement
  before approving. **Work outside sessions (last 8 weeks)** on Staff pay
  lists every entry by person, so the work can be checked over time.

### Running late
- From 3 hours before a session until 30 minutes after the start (and
  before signing on), the tutor can choose **Running late?**, pick about how
  late they will be and give a reason.
- The parents, and the learner if they have their own login, get an app
  notice and an email straight away. The reason is not sent to the family.
  Owner and operations admins get an app notice with the reason.
- A sign-on more than 5 minutes after the start is recorded by itself, with
  or without notice. A notice followed by an on-time sign-on is cleared.
- **Tutor lateness** (owner and operations) lists late starts to review,
  each tutor's count for the last 90 days, and how many were without notice
  before the start. Each is marked reviewed with a private note.
- Tutors see their own late starts (not the notes), so the record is open.
- Pay is unchanged: session pay already runs from the later of sign-on and
  the booked start, so time not worked is not paid.

### Yearly award rates
- From 1 June, if no award rates start on or after the coming 1 July, the
  owner and Finance admins get an app notice (then every 14 days), Billing
  shows a to-do number, and Staff pay shows a reminder card.
- Rates are entered once in the app. The app already raises any staff rate
  below the new minimum on the start date and adds a **Xero to-do** line for
  each change, so Xero is updated from that list. Changing Xero pay
  templates automatically was not built: the Xero Payroll API can do it, but
  an error would change real pay without a person checking, so the to-do
  list stays the safer step for now.

## 4. How we will know it works

- Fewer short availability windows and fewer 2-hour minimum top-ups for
  under-length days.
- Every new hours entry has a kind of work and an achievement; declined
  entries (and their reasons) show whether descriptions are good enough.
- Late starts per tutor over 90 days, and the share with notice before the
  start, on the Tutor lateness page.
- New award rates uploaded before 1 July each year.

## 5. Privacy, employment law and child safety

- **Records of hours worked.** The Fair Work Act 2009 (s 535) and the Fair
  Work Regulations 2009 (Part 3-6) require time and wages records, kept for
  7 years. Hours entries, their descriptions and approvals are part of
  those records and are audited.
- **Casual minimum engagement.** The Miscellaneous Award 2020 (MA000104) and
  the Educational Services (Post-Secondary Education) Award 2020 (MA000075)
  set a minimum payment for each casual engagement. The 2-hour block rule
  supports that; how it applies to separate lessons in one day is being
  checked in the contract work.
- **Fair process before any dismissal.** The Fair Work Act unfair dismissal
  rules (s 387) and the Small Business Fair Dismissal Code look at whether
  there was a valid reason, whether the person was warned and given a chance
  to improve, and whether records were kept. The lateness record is
  factual (sign-on times and notices), visible to the tutor, and reviewed
  with notes, which supports that process. Any warning or dismissal is still
  a decision for CLG, not the app.
- **Privacy.** In Australia, employee records of current and former
  employees are largely exempt from the Privacy Act (s 7B(3)), but CLG still
  limits who sees them: the reason for lateness and review notes are seen
  only by the owner and operations admins; hours entries only by the person,
  the owner and Finance admins. The family only learns that the tutor is
  running late and about how late. Under the UK GDPR and EU GDPR, employee
  data is covered fully, so this narrow access already fits a later
  international move.
- **Child safety.** A tutor running late means a child may be waiting
  without them. The family is told straight away, and CLG is told at the
  same time, so a pattern can be acted on.
- **Pay rates.** Award minimums are set by the Fair Work Commission's Annual
  Wage Review, usually published in early June and starting from the first
  full pay period on or after 1 July. The app never lowers a rate.

## 6. Not built yet (raised but waiting for Carla)

- Penalty rates under the Miscellaneous Award for evenings, weekends and
  public holidays, and a prompt to move a tutor from Level 1 after 3 months.
  Both need checking against the award and Carla's go-ahead first.
- Pay deductions or warnings for lateness. These depend on the contract
  wording.
