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
