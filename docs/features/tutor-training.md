# Tutor training, handbook and CLG certification

Requested by Carla, 12 Nov 2026. Decisions from Carla's answers on 16 Nov 2026.

## 1. What it's for

Tutors (and CLG admin staff) need to learn how CLG works before they tutor, and keep learning after that. Carla wants:

- a **starting course** every new tutor finishes: child safety and reporting, the code of conduct, privacy and student information, how the CLG app works and where to go, running a session and writing the summary, and effective tutoring practice;
- **short ongoing modules** after that, and **short refreshers** rather than repeating the whole course;
- an easy, go-to **tutor handbook** for when something happens, and proof that tutors know where it is and how to use it;
- training done in **paid time**, mainly in part-time staff's guaranteed-hours top-up time;
- **certificates**, and later a paid **"CLG certified"** service that outside, independent tutors can join. Certification is kept current by completing **3 hours of training every 3 months** (the safety modules don't count towards the 3 hours).

## 2. What the evidence says

- **Training and ongoing support make tutoring work.** The EEF's guidance report *Making a Difference with Effective Tutoring* (2021) and its Teaching and Learning Toolkit entries on one-to-one and small group tuition find that tutoring gets the strongest results when tutors are trained and supported, and when sessions link to what the student is learning. The NTP evaluations found that the tutor's training and quality affected results more than the programme brand.
- **Trained tutors do better than untrained ones.** Nickow, Oreopoulos and Quan's meta-analysis (2020, 96 randomised trials) found effects were biggest for teacher and paraprofessional tutors with structured training, and smaller for untrained volunteers and parents.
- **One-off training fades. Short, spaced, practical modules last.** The EEF's *Effective Professional Development* guidance report (2021) lists the mechanisms that change practice: building knowledge, motivating staff, developing techniques (modelling and practice) and embedding practice (prompts, reminders, revisiting). One-off events without follow-up have little effect. AERO's work on effective teaching practices (explicit instruction, checking for understanding, spaced retrieval) points the same way, and the same practices apply to adult learners.
- **Retrieval practice.** Short quizzes help people remember (the EEF Toolkit and *Cognitive Science Approaches in the Classroom* review, 2021). Requiring 100% with unlimited retries turns the quiz into practice, not a gate.
- **Child safety training must keep going.** The National Principles for Child Safe Organisations, **Principle 7**: "staff and volunteers are equipped with the knowledge, skills and awareness to keep children and young people safe through ongoing education and training". The Royal Commission (2017) recommended regular training on recognising and reporting abuse.
- **Refresh by finding it, not repeating it.** People rarely remember procedures they seldom use, so the safe pattern is a known, quick place to look it up (a handbook) plus practice finding it. That is the refresher Carla chose: a short module and a "find it in the handbook" quiz.

## 3. How the design follows the evidence

- **Modules** are made of short lessons (text, video, PDF, links) and a short quiz. Admins (owner and operations) write them. Each module says who it's for (tutors, admins or everyone), how long it takes (a set time, which is what's paid), whether it's **compulsory**, whether it **holds new matches** until it's done (the safety modules), whether it counts towards the **3 hours a quarter**, and whether it needs **redoing** every so many months (yearly for child safety and privacy).
- **Quizzes** need 100%. People can retry as often as they like. After each try the app says which questions to look at again, without giving the answers away. The answers are hidden from tutors in the database.
- **Big changes.** When an admin makes a big change to a module, they choose "Ask everyone to redo this". Everyone gets the usual time to finish it again.
- **Matching hold.** Tutors get **4 weeks** (an admin setting) to finish the compulsory safety modules, counted from when they joined or when the module was added. After that, the database refuses a **new** match. Students they already tutor stay with them. The Matching page shows the reason.
- **Pay.** Each completed compulsory module adds a "Training" hours entry for the module's set time, which waits for approval like other logged hours. It counts towards agreed weekly hours, so in a short week it fills the guaranteed-hours top-up first. It's paid at the rate of the job the training is for: tutor training at the tutor rate, admin training at the admin rate, and training for everyone at the tutor rate for someone who tutors. Optional modules aren't paid automatically. Tutors can log that time themselves if CLG agreed to it.
- **Handbook.** The handbook is searchable pages, with "Something's happened, what do I do?" pinned at the top. It's linked from every training page and the tutor menu.
- **Certificates.** Each module gives a downloadable certificate with a certificate number. A "CLG certified" certificate is available while the person is certified.
- **CLG certified.** A person is certified once all their compulsory modules are done. To stay certified, they finish 3 hours of training that counts in each calendar quarter after that. If a full quarter ends short, their status shows "lapsed" until they catch up. CLG can put sessions on hold if needed. The app never does this by itself.
- **Reminders.** Reminders go out 6 weeks and 2 weeks before a module needs redoing, 1 week before a safety module's 4 weeks run out, and 2 weeks before a quarter ends if they're short of 3 hours. Admins hear about holds and expiries. The usual quiet hours apply.
- **Built for outside tutors later.** Training is its own module, with its own tables. Certification rules don't depend on sessions or pay. That way, outside tutors can be added later as a new kind of learner without a rebuild.

## 4. How we'll know it works

- Each tutor's completion and when it was done (the admin progress table).
- Whether quiz retries per question go down as modules are improved. Questions many people get wrong point to a lesson to rewrite.
- No new tutor matched before finishing the safety modules.
- In the pilot test guide, tutors can find the "Something's happened" page in under a minute.
- Later, whether tutors who finish more training have better session summaries and family feedback.

## 5. Privacy, child safety and legal notes

- **Data held:** what each staff member completed, quiz scores and attempts, and certificate numbers. This is employment information. Under the Privacy Act's employee records exemption, CLG's handling of current and former employees' records is mostly outside the APPs, but CLG treats it with the same care. Only the person and full admins can see it, and that rule is in the database (row level security). Tests are in `supabase/tests/training.test.sql`.
- **Pay (Fair Work Act 2009 and the awards).** Training CLG requires is work time and must be paid at the right rate: the Miscellaneous Award (MA000104) for school tutoring, the Educational Services (Post-Secondary Education) Award (MA000075) for tertiary, and the Clerks award for admin. Payslips must show hours and rates (Fair Work Regulations 2009, reg 3.46). Training lines are labelled "Training" in the app. Showing a separate "Training" label on Xero payslips needs its own earnings rate in Xero (a follow-up). Carla should confirm the rate rule with her pay adviser.
- **Child safety (SA).** Children and Young People (Safety) Act 2017, mandated notifier duty (ss 30–31), and the National Principles (Principles 5 and 7). The safety modules teach CLG's reporting steps (000, CARL 13 14 78, then tell CLG) and point to the Child safety page. RRHAN-EC is still a separate, required external check. CLG training doesn't replace it.
- **Copyright.** Content written by employees as part of their job belongs to CLG (Copyright Act 1968 s 35(6)). Modules written by contractors need an IP clause in their contract. Videos must use content CLG has rights to.
- **Certification as a paid service later.** Selling certification to outside tutors brings in the Australian Consumer Law (clear claims about what "CLG certified" means), privacy for non-employees (the full APPs apply, because the employee exemption won't cover them) and, if it's ever offered as accredited training, ASQA rules. Get the lawyer's advice before launch. A public "check a certificate" page waits until then, because it shows a person's name.
- **UK / EU later.** UK: Keeping Children Safe in Education expects regular safeguarding training with annual updates. EU: GDPR applies to training records (legitimate interest or employment contract). The design fits both.

## 6. Storage

Videos and PDFs are kept in a private "training" file store. Admins upload them straight from the browser. Staff can only open files that belong to a published module made for them, through links that stop working after an hour. On Supabase Pro, check that the project's global upload limit (Storage settings) is at least the "largest video" setting.

## 7. Carla's review of the drafts, 16 Nov 2026

Carla answered the 8 review questions on the starter drafts. Two migrations load the result. Everything is still a **draft**: nothing reaches tutors until an admin publishes it in Training setup.

- `20261118200100_training_review_edits.sql` updates the seven draft modules and the draft handbook pages:
  - **All contact with families goes through the app**: session summaries, comments, replies to feedback notes and offering another session time. Never phone, text, personal email or social media. Teams is only for session links. (Module 2, handbook "Who to contact".)
  - **Reaching a parent urgently**: the tutor phones CLG, who calls the parent. 000 first in an emergency. (Handbook "Something's happened".)
  - **No-show**: wait 15 minutes, online or at the library. (Handbook, module 5.)
  - **Under 12s** are dropped off and collected by a parent. A tutor never leaves the library with a student. (Handbook "In-person sessions".)
  - **Lauren is tutors' first point of contact.** Carla can see those contacts and helps when time permits, and Lauren can see Carla's contacts with tutors. (Handbook "Who to contact", module 4.) The app has no tutor-to-staff messaging yet, so this is a working rule; admin notices already go to both.
  - **Honest work**: tutors never write any of the student's work, "not a sentence, a paragraph or a conclusion". New module 2 lesson and quiz question.
  - The review's other additions: tell CLG even when unsure (module 1), what to write down (module 1 quiz), no private tutoring and Block a student (module 2), no private copies and medical details in notes (module 3), Requests and Blocks (module 4), summaries within 6 hours, honest end times (only a finish more than 15 minutes early is recorded) and the first three sessions (module 5), building confidence and independence (module 6).
  - Only draft modules and pages are changed, and only exact pieces of text are swapped, so edits Carla made elsewhere are kept. A published module is left alone.
- `20261118200200_training_new_modules.sql` (merged first) added the four review modules as drafts. `20261118200600_training_wording_6_hours.sql` then updates the draft summary and early-finish wording to Carla's later rules.
- `20261118200700_training_15_minute_modules.sql` splits all the training into **25 modules of 15 minutes** (Carla, 16 Nov 2026: "numerous short modules which should only take 15 minutes"). Each has one or two lessons and a 2 or 3 question quiz.
  - **1 to 8, safety** (everyone, compulsory, hold new matches, due before any sit-in): spotting harm; the three steps; your duty and if a child tells you; professional and honest; boundaries with students and families; safe online sessions; keeping student information safe; when something goes wrong.
  - **9 to 16, the rest of the starting course** (tutors, compulsory): setting up in the app; where to go when; before and during a session; the session summary; your first three sessions; explain, show, practise; feedback and remembering; building confidence and independence.
  - **17, yearly refresher** (everyone, holds new matches, redo every 12 months).
  - **18 to 25, ongoing** (tutors, count towards the 3 hours a quarter): two on assessment drafting, two on families and communication, two on learning support, two on term reviews. They're set as compulsory, so once published each is due within the usual 4 weeks. Untick "compulsory" before publishing if that's not wanted. The app can't yet hold a tutor back from a first drafting job or term review, so Lauren checks 18 and 19 (drafting) and 24 and 25 (term reviews) are done before assigning one.
  - The starter lessons and questions are **moved** into the new modules, not rewritten, so edits made in Training setup are kept. It only runs while all eleven earlier modules are drafts.
  - Fewer sit-ins: modules 11 to 13 cover how a CLG session runs, so the sit-ins can be shorter (Carla wants as few as possible, to keep disruption to current clients low).
- Evidence for the new modules: EEF *Feedback* and *Metacognition and self-regulation* (Teaching and Learning Toolkit) for drafting comments and building independence; EEF *Special Educational Needs in Mainstream Schools* (2020) for learning support; EEF *Parental engagement* for communicating with families. Legal notes are unchanged from section 5. The integrity rule protects students under school and SACE rules on acceptable help with assessed work.
- Tests: `supabase/tests/training_review_content.test.sql`.

## 8. Admins who don't tutor, 16 Nov 2026

Carla: "Admins who are not tutors do not need to do the tutoring modules." Modules for tutors already only go to people with the tutor role. `20261118300100_training_tutoring_modules_for_tutors.sql` moves modules 4 (professional and honest), 5 (boundaries) and 6 (online sessions) from everyone to tutors only. An admin who doesn't tutor now does modules 1 to 3 (child safety), 7 and 8 (privacy) and the yearly refresher (17), which every staff member who can see children's information needs (National Principles, Principle 7; Privacy Act). An admin who also tutors does everything. Only draft modules change.

## 9. Saving part way, and paid time, 18 Nov 2026

Carla: tutors should be able to save a module part way through and come back to it, for example when a module takes 30 minutes but they have 15 minutes set aside. Tutors are paid only for the training time they are given, and may do modules in their own time if they wish.

- **Saving.** Each lesson has a **Done, save my place** button, and the quiz has **Save my answers and finish later** (answers are kept but not marked). Next time the module shows how many lessons are done and a **Carry on from lesson N** link. Saved answers are cleared once the quiz is passed. Stored in `training_progress` (one row per person per module), written only by `training_save_progress`, which checks the module is published and for that person. The person and full admins can read it. Migration: `20261120700100_training_save_progress.sql`. Tests: `supabase/tests/training_save_progress.test.sql`.
- **Evidence.** Spacing learning over shorter sessions helps people remember more than one long sitting (EEF Teaching and Learning Toolkit and AERO's guidance on spaced practice), so stopping and coming back is good for learning, not just convenient.
- **Pay.** Unchanged in the app: a compulsory module pays its set time once, when it is finished, however long it takes. The handbook's pay page, the tutor and admin guides and each compulsory module now say so, and that modules can be done in the person's own time but only the set time is paid.
- **Legal note.** Under the Fair Work Act 2009 and the awards, training CLG requires is work time. Paying only the set time is fair while the set time is a realistic estimate of how long the module takes. If a compulsory module usually takes longer, raise its set time rather than leave the extra unpaid. Carla should confirm this with her pay adviser. Optional modules done in a person's own time are their choice and are not paid unless CLG agreed first.

## 10. Goals, plans, the session routine and term reviews, 18 Nov 2026

Carla asked for a module on setting up weekly, termly and yearly student plans (done before a tutor needs to make one), measurable goals, a clear note that the session routine stays the same each week while the content and how it is presented change, a 1-hour term review that goes through every goal, and a priority list. `20261121300100_training_plans_routine.sql` adds:

- **Modules 26 to 28** (drafts, compulsory, tutors, starting course): measurable goals, the yearly and term plan, the weekly plan. They sit after module 13 in the list, so they are done before the first student.
- **Module 11** gets a first lesson, "The CLG session routine" (check in, warm-up recall, review, new learning, practice, reflect and next step), plus a quiz question. Module 23's routine bullet points to it.
- **Modules 24 and 25**: allow about 1 hour; go through each goal (reached, in progress, changed or dropped, with why); the work and the direction; what helped most, including what the family reports from home; then next term's focus and the recommendation. A new quiz question on the time.
- **Priority order** in the list: 1 to 8 (safety), 9 to 13 and 26 to 28, 14 to 16, 18 and 19 (drafting), 24 and 25 (term reviews), 20 to 23, and 17 (refresher) last. Only modules still in their first place are moved.
- **Evidence.** Measurable goals and planning backwards from them: AERO's guidance on formative assessment and EEF *Feedback*. A consistent routine with explicit instruction and guided practice: AERO's *Explicit instruction* and EEF *Special Educational Needs in Mainstream Schools* (predictable structure helps anxious students and those with learning needs). Retrieval at the start of each session: EEF *Cognitive science approaches in the classroom* (2021).
- **Legal note.** No new personal information. Term reviews keep health and diagnosis details out, as before (Privacy Act 1988, APP 3 and 6).
- Tests: `supabase/tests/training_plans_routine.test.sql`.

## 11. Assigning modules, order, and readiness for jobs, 18 Nov 2026

Carla: admins can assign modules with due dates; assigned modules are paid for their set time, and doing training outside designated training time is paid only with pre-approval. The safety modules are done in order. The app should flag when a tutor is booked for drafting or a term review without the modules. `20261121300200_training_assign_order_jobs.sql` adds:

- **Assignments** (`training_assignments`, one per person per module, with due date and reason). Only full admins assign or remove them (`training_assign`, `training_unassign`), only for published modules made for that person. The person and full admins can read them. An assigned module shows as To do (overdue after the date) until it is finished after being assigned, and its completion is paid even if the module is optional. Other training is unpaid unless approved first and logged under My pay.
- **Done in order** (`in_order`, ticked for 1 to 8). `training_finish` refuses an in-order module until every earlier in-order module (published, made for them) is done; the module page says which one to do first.
- **Needed before a job** (`needed_for`: drafting for 18 and 19, term_review for 24 and 25). When a term review is made for a tutor who has not done those modules, a trigger assigns them (due the day before the review is due) and tells the tutor and full admins. `training_job_readiness` gives admins a **Ready for** column on Training progress. The app does not book drafting jobs yet, so Lauren checks that column before giving one; when drafting bookings exist, they can call the same check.
- **Evidence.** Sequencing foundational safety content before practice, and short required learning tied to the task it prepares for, follows AITSL's guidance on induction and the EEF's *Effective Professional Development* guidance (2021): build knowledge, then rehearse it close to when it is used.
- **Legal note.** Required training is work time under the Fair Work Act 2009 and the awards, so compulsory and assigned modules are paid automatically; optional training a person chooses is unpaid unless CLG approves it first. The handbook pay page says so. Assignments hold no personal information beyond who and when (Privacy Act 1988, APP 11).
- Tests: `supabase/tests/training_assign_order_jobs.test.sql`.

## 12. Screenshot questions and practice tasks, 18 Nov 2026

Carla: for modules about the app, questions should show screenshots and ask what to press or write; tutors should also write things like mock session summaries that a CLG admin checks and approves before they pass. `20261121300300_training_screenshots_tasks.sql` adds:

- **Screenshot questions.** `training_questions.image_path` and `image_alt` (a description for screen readers). Pictures (PNG, JPEG, WebP) go in the private training store; staff can open one only while they can see its module. Admins upload them on each question in Training setup. The screenshots themselves are taken from the running app with test data (the list of questions per module is in the new-modules doc), so Carla or Lauren adds them once the app is set up with a practice student.
- **Practice tasks.** `training_modules.practice_task` holds the instructions. People write their answer on the module page (`training_submit_task`); full admins approve it or send it back with what to change (`training_review_task`, never their own) under Training setup, Practice tasks. Admins are told when one arrives; the person is told the outcome. `training_finish` waits for an approved task for the current version, and approving after the quiz is passed finishes the module (paid when compulsory or assigned, through the shared `private.training_record_completion`). Submissions (`training_task_submissions`) can be read by the person and full admins only.
- **Tasks loaded** (made-up students only): module 12 (a session summary for Mia), 19 (comments on a sample history paragraph against a rubric), 25 (a term review for Sam), 27 (a year goal, term goal and assessment targets for Lily).
- **Evidence.** Rehearsing the real task with feedback before doing it with students: EEF *Effective Professional Development* (2021) names modelling, rehearsal and feedback among the mechanisms that work. Checking against clear criteria: EEF *Feedback* (2021).
- **Legal note.** Tasks use made-up students, and the page and task wording say never to write about a real student (Privacy Act 1988, APP 6 and 11; the Children's Online Privacy Code). Submissions are training records, kept with completions.
- Tests: `supabase/tests/training_screenshots_tasks.test.sql`.
