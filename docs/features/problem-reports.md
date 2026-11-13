# Report a problem

Asked for by Carla, 12 Nov 2026: "Need to make a spot where anyone can
outline any problems with the app - is it possible for it to be auto fixed?
Or it might be better if a particular person/s are required to check this
over - this also needs a place where a screenshot or multiple screenshots can
be provided as supporting evidence."

## 1. What it's for

Families, students, tutors and staff hit problems the owner never sees: a
button that does nothing on one phone, a confusing step, a wrong time. Today
these arrive by text or email, or not at all. This gives everyone one place
to say what went wrong, with screenshots, and gives CLG one queue to check,
reply to and fix.

**Can it fix itself?** Not safely. An automatic fix means letting software
change a live app that holds children's records, based on text anyone can
type. A report could be wrong, or written to trick the fixer into weakening
access rules. So a person always checks first. The safe version of "auto
fix" is built in as an option: once a reviewer approves a report and writes
the fix in plain words, the owner can send it to GitHub as an issue. A
developer (for example Claude) then makes the change as a pull request,
the database tests run, and the owner checks it before it goes live.

## 2. What the evidence says

- **Sessions need to happen reliably.** One to one and small group tuition
  works best when sessions are regular and sustained over time (EEF Teaching
  and Learning Toolkit, [one to one tuition](https://educationendowmentfoundation.org.uk/education-evidence/teaching-learning-toolkit/one-to-one-tuition);
  Evidence for Learning, [one to one tutoring](https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/one-to-one-tutoring)).
  A booking or reminder that fails quietly costs a session. Fast reports
  shorten the time a fault goes unnoticed.
- **Feedback loops make changes stick.** The EEF's guidance report
  [*A School's Guide to Implementation*](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/implementation)
  recommends monitoring how a new approach is working in practice, using
  structured feedback from the people using it, and adjusting. The pilot
  (Nov–Dec 2026) is exactly this stage for the app.
- **Keep contact low effort for families.** The EEF's
  [*Working with Parents*](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/supporting-parents)
  guidance says communication should be simple and easy for parents. A
  one-box form with optional screenshots, reachable from every page, keeps
  reporting to a minute.

## 3. How the design follows the evidence

- **On every page.** "Report a problem" sits in the top bar for anyone
  signed in. The link remembers which page you were on.
- **One required box.** "What went wrong?" is the only required field. "What
  were you trying to do?" and screenshots are optional.
- **Screenshots from a phone or computer.** Up to 6, chosen or pasted
  (Ctrl+V). The browser shrinks each one before sending, so uploads work on
  mobile data, and redrawing removes hidden photo details such as location.
- **People check every report.** The owner always sees reports and chooses
  which other admins check them (Problem reports > Who checks reports).
  Statuses: New, Being checked, Approved to fix, Fixed, Closed (no change).
  Priority: Urgent (privacy, safety or money), Normal, Low. Urgent reports
  are listed first.
- **The reporter hears back.** Reviewers write a reply the reporter sees on
  their Report a problem page, with the status. Private notes stay with
  reviewers.
- **Optional hand-off to a developer.** The owner can turn an approved
  report into a GitHub issue. Only the reviewer's fix summary and the page
  name (with ids removed) are sent.

## 4. How we'll know it works

- Reports per week during the pilot, and how many are fixed or closed.
- Time from New to a first reply (aim: within 2 working days; urgent the
  same day).
- Fewer problems arriving by text or email instead.

## 5. Privacy, child safety and the law

- **Data held**: the reporter's name, what they wrote, the page, their
  browser, and screenshots. Screenshots may show a child's details, so:
  - they sit in a private file store, opened only through one-minute links;
  - only the owner and the admins they choose can see reports and
    screenshots, with two-step login; reporters see only their own reports
    and never reviewers' notes. This is enforced in the database (row level
    security), tested in `supabase/tests/problem_reports.test.sql`;
  - the form asks people to crop out anything not needed and not to include
    medical details (APP 3 and APP 11; Children's Online Privacy Code draft:
    collect the minimum, protect it; UK GDPR / GDPR Article 5 data
    minimisation).
- **Keeping it short** (APP 11.2; GDPR storage limitation): screenshots are
  deleted 90 days after a report is fixed or closed, and the report 2 years
  after that, by the daily job. The owner can delete a report at once if it
  holds something that shouldn't have been shared.
- **Overseas** (APP 8; GDPR Chapter V): GitHub is in the United States.
  Nothing personal goes there: no names, emails, reporter's words, notes,
  screenshots or record ids, only the reviewer's fix summary. Reviewers are
  told this next to the box.
- **Child safety** (SA Child Safe Environments; CLG child safe policy): this
  form is not a channel for safety concerns. The form says so and points to
  the Child Safety Officer. If a report reveals a concern, the reviewer
  follows the child safe policy, not this queue.
- **Data breaches** (Notifiable Data Breaches scheme): if a report shows
  someone could see data they shouldn't, mark it Urgent and follow the breach
  plan.
- **Every change is logged** in the shared change log (who changed a
  report's status, who was added to the reviewer list).
- **Spam guard**: at most 10 reports per person per day.

## 6. How it's built

- Migration `20261113700100_problem_reports.sql` (module: problem_reports):
  tables `problem_reports`, `problem_report_screenshots`, `problem_reviewers`,
  `problem_screenshot_removals`; file store `problem-screenshots`.
- Pages: `/report-problem` (everyone), `/admin/problems` (reviewers).
- Daily job: `/api/problems/cron` (tidy-up and file removal).
- GitHub hand-off (optional): set `GITHUB_ISSUES_TOKEN` (a fine-grained
  GitHub key with only "Issues: read and write" on the app's repository) and
  `GITHUB_ISSUES_REPO` (for example `CLG-ConfidentlyLearnGrow/clg-app`) in
  Vercel.
