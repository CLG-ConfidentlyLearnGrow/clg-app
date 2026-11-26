# Materials access for students and families

Status: draft brief, 24 November 2026. Waiting for Carla to confirm the choices marked "Suggested".

Builds on the materials library (`materials.md`, `materials in use` part), the add-ons switch (`add-ons.md`), the Student Success Program (`student-success-program.md`), billing (`billing.md`) and matching (waitlist).

## What Carla asked for (24 November 2026)

- An easy way to see which materials a student can open, by year level, subject and topic.
- A student can open materials only while they are in a program that includes them (the Student Success Program) or while their family pays for ongoing access as an add-on.
- Charged per student. Price idea: $250 a term. Access starts once payment is received, and opens up to two weeks before that term.
- Anyone can buy it, not only families who already have tutoring. Families on the waitlist are pointed to it.
- Only inside the app: view on screen or print, no download.
- A "how to use" guide and a tutorial.
- Students need answers and tests, so that finishing one small set unlocks the next. This keeps the amount on screen small and shows students where to start.

## Who sees what

- **Tutors**: no change. They see every published material for the subjects and years they teach, stamped with their name, logged, at most 30 different materials a day. Materials are part of tutoring, so a tutor can use them with any matched student whether or not the student pays for their own access.
- **Admins**: a "Materials access" card on each student's page (access status, how it was given, until when, the student's place in each path) and one list of every student with their status. Filters: year level, subject, topic.
- **Students with access**: a Materials page showing only their own subjects, the set they are on in each path, and the sets they have finished. Filters: subject, topic.
- **Family members**: see the student's progress through the paths (sets finished, quiz results). Only the bill payer and extra payers see the price, invoices and the Buy button (`billing-only-payers.md`).
- **Students and families without access**: a short description of what is included. A student is told to ask their family. Waitlist families see the same card on their waitlist status.

## How access is given

- A new add-on, "Materials access", in the existing add-ons table. It starts **off**. The owner switches it to paid once the price is set, or to free for a trial.
- Students in the Student Success Program get it automatically for as long as they are in the program, the same way they already get study plans.
- Owner or Operations admins can give it at no charge with a note (for example hardship), as with other add-ons.
- Paid access: one invoice line per student (and per subject, if Carla chooses per subject), paid in advance for the term through Stripe. Access starts when the payment is received and opens from two weeks before the term starts. It ends at the end of the term unless the next term is paid.
- Suggested: 20% off for each extra student in the same family; per subject pricing ($250 first subject, $150 each extra subject a term).

## Organising materials

- **Topic**: each material gets a topic, chosen from a short list for each subject that admins keep (for example Mathematics: Fractions, Algebra, Measurement). A list instead of free typing keeps names tidy so filters work.
- **Students can open this**: a tick on each material. Learning materials, worksheets, answers and quizzes in a path can be ticked; lesson plans stay tutor-only.
- Subject and year level use the existing names ("Mathematics" for Reception to Year 10; "Mathematics: Essential, General, Methods, Specialist" for Years 11 and 12).

## The step-by-step path (Carla, 26 November 2026)

- Every material is tagged to a **topic**. Carla will enter all topics for every subject currently tutored and tag each material.
- Each subject and topic has ordered materials. Each material has a learning part (with worked examples), a worksheet and its own **interactive quiz**, marked by the app (multiple choice and short number answers).
- The worksheet's **answers** open once the student says they have finished the worksheet, so they check their own work.
- A material counts as **completed only when the student scores 100%** on its quiz. Unlimited retries, with questions in a different order each time. Completing a material unlocks the next one.
- **Where to start**: suggested short placement quiz for each subject. The student's tutor or an admin can move a student to another material.
- Only the current material and completed materials open, which keeps the student focused and limits what can be shared.

## Never running out: alerts and requests

- A nightly check counts, for each student and topic, how many of the topic's published materials the student has completed.
- At **75%** Carla gets an alert; at **90%** an urgent alert. Student Success Program students are listed first. Alerts show on the Home dashboard and in the end-of-day update. The two percentages are settings the owner can change at any time.
- Families (and students with their own login) can **request more materials** for a topic. The request goes to admins with the student, subject, topic and how far through they are.
- Wording in the app and the family terms: "**Unlimited\***" with the footnote "**\*New materials provided within 2 business days of request**". The footnote sits right next to the word wherever it appears (Australian Consumer Law: a qualification must be clear and close to the claim). "Business days" means Monday to Friday, not counting SA public holidays (Carla, 26 November 2026).

## Protecting the materials (Carla, 26 November 2026)

- No download button. Pages show inside the app. A Print button prints a copy stamped on every page with the student's first name, a family code and the date (no email, because many users are children).
- Every open and every print is logged, so admins can see unusual use. No print limit.
- Answers and worked solutions are view only in the app: they cannot be printed. Quizzes are interactive in the app.
- A photo of the screen cannot be prevented by any app. The stamp, the log and the path (only the current material open) make copying unrewarding without adding admin work.
- Family terms need wording: materials are for the student's own use, not to be shared, copied or uploaded.

## What the evidence says

- **Mastery learning** (EEF Teaching and Learning Toolkit, +5 months): learning broken into units, a check of understanding, and moving on only once a high pass mark is reached. This is the step-by-step path.
- **Worked examples and practice** (AERO, *Explicit instruction* and *Worked examples* practice guides): learners new to a topic do better studying worked examples before practising on their own.
- **Practice testing and retrieval practice** (Dunlosky and others 2013; AERO *Spacing and retrieval practice*): short low-stakes quizzes are one of the most effective study methods, especially with feedback, which the app gives at once.
- **Feedback** (EEF, +6 months): answers opened after the attempt let students see and fix mistakes straight away.
- **Homework** (EEF, +5 months at secondary): works best when it is linked to classroom learning and is short and focused. Paths are short sets linked to the curriculum skills already tagged on each material.
- **Cognitive load** (AERO, *Cognitive load theory* practice guide): showing a small amount at once avoids overwhelming students. Only the current set opens.
- **Equity** (EEF, closing the disadvantage gap): admins can give access at no charge, with a note.

## How we will know it works

- Share of students with access who finish at least one set a week.
- Quiz pass rate on the first try (too high means sets are too easy; too low means they are too hard).
- Where students leave a path, so materials can be improved.
- Families who move from the waitlist into tutoring after using materials.

## Legal rules and privacy

- **Australian Consumer Law**: price, term, start date, what is included and how access ends must be clear before payment. Family terms need wording for this add-on (lawyer review).
- **Privacy Act 1988 and APPs**: new data is quiz results, path progress and opens. Seen only by the student, their family, their current tutors and admins. Kept while the account is active and deleted with the student. A privacy notice on the Materials page (APP 5).
- **Children's Online Privacy Code (draft) and UK Age Appropriate Design Code**: collect only what the path needs, no public leaderboards, no stamp with contact details, high privacy by default.
- **Copyright Act 1968**: CLG owns its materials; third-party content needs permission before students can open it.
- **Anyone can buy it**: buyers who are not yet clients need a family account and must accept the family terms. Students under 16 do not have their own login, so a parent opens materials with them.
- **GST** (Carla, 24 November 2026): GST follows the student, not the material. Two price items in the existing price list, each with its own GST setting: one GST-free for school students (Reception to Year 12), one with GST included for everyone else (for example adults, or later the Spanish modules). The invoice line uses the one that matches the student's year level.

## Choices waiting for Carla

1. Sibling discount (suggested 20% off each extra student).
2. Per subject or all subjects (suggested per subject: $250 first, $150 each extra).
3. Starting point (suggested placement quiz, tutor or admin can move).
