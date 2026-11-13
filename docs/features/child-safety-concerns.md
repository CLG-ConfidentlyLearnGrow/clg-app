# Child safety concern flag

Requested by Carla, 12 Nov 2026. Draft for the lawyer's review with the Child Safe Policy.

## 1. What it's for

Anyone using the app (tutors, admins, parents, students 16+) needs one obvious place to act when they are worried about a child. The order must be clear:

1. **Emergency: call 000 first.** A child in immediate danger gets police or ambulance before anything else.
2. **Report to the child protection line** for the child's state. In South Australia that is the Child Abuse Report Line (CARL), **13 14 78**, 24/7.
3. **Tell CLG.** The concern goes to the Child Safety Officer (Carla). The person raising it can send it to the deputy (Lauren) instead, for example when the concern is about Carla.

## 2. What the evidence and the rules say

- **Royal Commission into Institutional Responses to Child Sexual Abuse (2017)** and the **National Principles for Child Safe Organisations** (Principle 6: "processes to respond to complaints and concerns are child focused"). Organisations need a clear, known, accessible way to raise concerns, a named person to receive them, and records kept securely and for a long time (the Commission recommends at least 45 years for records about child sexual abuse).
- **SA Department for Child Protection, "Process for mandated notifiers"** (page updated 14 Jul 2026, checked 13 Nov 2026): "If it is an emergency call 000 immediately." Serious concerns must be phoned to CARL 13 14 78, not sent through e-CARL. Serious means: imminent or immediate danger of serious harm, a current injury suspected to come from abuse or neglect, chronic neglect, an unexplained injury to a baby under 12 months, a child abandoned or left unsupervised, a credible threat to kill or seriously harm a child, sexual abuse where the child will be in contact with the person within 24 hours, or a child under DCP guardianship. e-CARL (https://ecarl.sa.gov.au/) is for non-urgent reports by mandated notifiers only.
- **Children and Young People (Safety) Act 2017 (SA), s 30 and s 31.** Mandated notifiers include employees and volunteers of an organisation that provides education services wholly or partly for children, who deliver those services directly or manage them. CLG tutors fit this. They must report to DCP "as soon as is reasonably practicable" after forming a suspicion on reasonable grounds that a child is, or may be, at risk of harm, when the suspicion is formed in the course of their work. Not reporting can lead to a fine (s 31(1)).
- **Coming change:** the Children and Young People (Safety and Support) Act 2025 (SA) will repeal the 2017 Act. It has **not commenced** (legislation.sa.gov.au, checked 13 Nov 2026; commencement by proclamation). Its s 76 changes the test to "at risk of significant harm". When it commences, update the page wording and section numbers. Ask the lawyer to confirm.
- **Other states:** reporting lines from the AIFS resource sheet "Reporting child abuse and neglect" (checked 13 Nov 2026), kept in `src/lib/child-safety.ts`.
- **Education research.** The EEF and AERO have no evidence on concern reporting itself. What they do support is safe, trusting relationships as a precondition for learning (AERO, "Creating safe and supportive learning environments"; EEF behaviour guidance on knowing pupils and their circumstances). This tool is a safeguarding duty, not a learning intervention, so the design follows the child safety sources above.

## 3. How the design follows this

- **000 first, impossible to miss.** The Child safety page opens with a thick red box: "1. Is a child in immediate danger? Call 000 now", with a large Call 000 button (dials on a phone). The form also asks "Is a child in immediate danger right now?" with a red reminder and an "I have called 000" tick.
- **Step 2: the state's line.** SA's CARL number is large and highlighted, with DCP's list of when you must phone. The other states' lines sit in a fold-out list. The page explains the mandated notifier duty and CLG's rule that every worker reports, then tells CLG.
- **Step 3: tell CLG.** The form asks which child (only children the person can already see, or "Someone not listed" with a name and state), what happened, when, and whether they've reported to the line (with a reference number). It's sent to **one** person: the Child Safety Officer (default) or the deputy.
- **Always reachable.** A red "Child safety" button is in the top bar on every page for everyone signed in. For the officer and deputy, it shows the number of new concerns.
- **Documents.** The page links the Child Safe Policy, the Staff Code of Conduct, DCP's reporting pages and the Act. CLG's policies are Claude Doc drafts. People need access to open them until approved versions are published in the app.
- **Young people.** A short card points young people to 000, Kids Helpline 1800 55 1800 and Lifeline 13 11 14.
- **Follow-up.** The officer or deputy sees "Concerns sent to you". They can add notes (which can't be edited or deleted), mark where it's up to (new, being dealt with, closed), or pass it to the other contact with a reason. After passing it on, they can't open it.
- **Alert email.** The recipient gets an email straight away, even in quiet hours. It has no names or details, only "open the app". Urgent concerns say "Urgent" in the subject.

## 4. How we'll know it works

- Every concern has a recorded outcome (a note and "Closed").
- The time from a concern being raised to being opened (new to being dealt with). Target: same day; urgent ones within 1 hr.
- Tutors can find the page without help in the pilot test guide.

## 5. Privacy and child safety

- **Who can see a concern.** Only the person it was sent to, after two-step sign-in. That rule is in the database (row level security), so other admins can't read it, the owner included. The person who raised it sees what they sent and where it's up to, not the notes. The person it is about is never told. Tests are in `supabase/tests/child_safety_concerns.test.sql`.
- **No leaks elsewhere.** The activity log gets the concern's id only. The alert email has no names or details.
- **Who receives concerns.** Only the owner can change this (two-step sign-in, logged). The officer and deputy must be different staff members. Concerns already raised stay with the person they were sent to, so changing the setting never opens old concerns to someone new. If a recipient's account is deleted, their concerns move to the other contact.
- **Keeping records.** Concerns are not in the automatic deletion rules. If a student or account is deleted, the concern keeps the copied names. This follows the Child Safe Policy draft (child safety records kept 45+ years) and the Privacy Act's APP 11.2, which allows keeping information the law requires. The lawyer should confirm the period.
- **Privacy Act / APP 3 and APP 6.** Concerns can hold sensitive information. Collecting and sharing it to protect a child is allowed under the permitted general situation for serious threats to life, health or safety. Reporting to DCP is what the law requires of mandated notifiers.
- **Children's Online Privacy Code (draft).** Children can use the form. The wording is plain, and young people are pointed to help lines too.
- **UK / EU later.** UK: Working Together to Safeguard Children 2023 (Designated Safeguarding Lead, record keeping). EU: GDPR Art. 9 special category data, with the vital interests and legal obligation grounds. The design (named lead, restricted records, long retention) fits both.

## Open questions for Carla and the lawyer

1. Publish the approved Child Safe Policy and Code of Conduct inside the app, so families and tutors can open them (the Claude Doc links need access).
2. Confirm the 45-year keep period for concern records.
3. Should parents and students see the same wording about mandatory reporting, or a simpler version?
4. Anonymous concerns are not offered (the policy draft lists this as open).
