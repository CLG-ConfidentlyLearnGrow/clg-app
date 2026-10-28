# Progress tracking

Full research brief, approved by Carla on 26 October 2026: https://claude.ai/artifact/UvGuihmTC7xyH9XHrjLbLt

## What it's for

Turning each session into specific feedback and one clear next step, so students, parents and tutors can see learning move. It replaces the free-text summaries posted in Teams.

## What the evidence says

- **Feedback** (+6 months, EEF Toolkit): feedback works when it is specific, actionable and acted on. It should answer three questions: where am I going, how am I going, where to next (Hattie and Timperley).
- **Metacognition and self-regulation** (+8 months, EEF): students who set goals, rate their confidence and reflect learn faster.
- **Parental engagement** (+4 months, EEF): personalised messages about successes and next steps, with practical tips on habits, rather than asking parents to teach content.
- **Formative assessment** (AERO review of 138 studies): clear success criteria, evidence of learning, and feedback that moves learning forward. This favours a skill-by-skill view over a single mark.
- **Australian Curriculum v9** content descriptions give skills that families can match to school reports.

## How the design follows the evidence

- **Goals:** 1 to 3 active goals per subject, written so a parent understands them. Each goal is made of skills from the student's curriculum. The database refuses a fourth active goal.
- **Skill levels:** four steps (Not started, Learning, Secure with help, Secure on own), set by ability, not year level. A skill moves at most one step per session, up or down, and only through a session note. Every change therefore has a date and a reason.
- **Session note:** a three-minute structured form covering attendance, skills worked on, what went well and one next step (both written to the student), homework, and an optional note for staff only. A session that happened must have a next step.
- **Student reflection:** confidence (1 to 4), what was hard, and what they will try. Written by the student, or with a parent for a young child.
- **Next step first:** the progress page leads with the latest next step. Students and parents see their own path only, never comparisons with other students.
- **Curricula as data:** each curriculum is a versioned framework. A student can follow more than one (AC9 and SACE). Retired skills are kept and point to their replacement, so history stays true. Adding a country means loading data, not changing code.

## How we'll know it works

Measured each term:

- the share of sessions with a note, and how soon after the session it was written
- the share of notes with a reflection
- skill movement per student per term
- students whose skills haven't moved in 4 or more sessions

(Notes on time and writing time are measured from part 2. Parent open rates need email, which comes later.)

## Privacy and child safety

- All tables hang off `students`, so the shared access rules apply. Tutors see only their current, cleared students, and only with two-step login. Families see only their own children.
- Staff-only notes are in their own table. The database never returns them to families.
- Families can read notes but not change them. Tutors can correct their own note for 7 days. Every change is in the audit log.
- Session notes count as activity for automatic deletion. All progress records are deleted with the student.
- Following the Children's Online Privacy Code (exposure draft): only fields that help learning, no free-text diagnosis fields, private by default.
- Concern flags are not part of this module. They belong to the child safety module, which follows the child safe policy.

## Part 2: finishing phase 1 (October 2026)

Migration `20261029100100_progress_follow_up.sql`, tests in `supabase/tests/progress_follow_up.test.sql`.

What it adds, and the evidence behind each part:

- **Notes for booked sessions.** The note form opens on the oldest session still waiting for a note, with the date and length filled in. Fewer fields means faster notes (EEF warns that feedback's cost is staff time). Notes for sessions arranged outside the app still work.
- **One thing to try at home.** An optional line for the family: a small habit, not re-teaching. EEF Parental engagement (+4 months) finds tips on habits such as planning and practice help more than asking parents to teach content.
- **An update for the family after each note.** It shows in the app with the next step and the tip, so parents see successes and next steps without reading a Teams channel (EEF Parental engagement). Updates written between 8pm and 8am wait until 8am. Email delivery comes once CLG's email sending is set up; it will read `progress_notices.email_sent_at`.
- **Reminders.** The tutor is reminded 24 hr after a session with no note; admins are told at 48 hr (brief: "Due within 24 hours"). An hourly job (`clg-note-reminders`) checks sessions from the last 7 days.
- **Tutor caseload.** The tutor dashboard lists notes to write, and under each student the last note, missing goals, and when no skill has moved in 4 or more sessions (Stanford NSSA: monitor closely and adjust).
- **Admin oversight** (Admin > Progress): the measures above per tutor for any dates, overdue notes, students to check, and recent notes to spot-check.
- **Time to write a note.** Measured in the browser from first tap to last change, stored in `session_note_stats`, seen only by admins. It checks the pilot gate: notes under 3 minutes.

Privacy and child safety:

- Updates go only to the student's linked parents and the student's own login. Reminders name the student and go only to the tutor (24 hr) or admins (48 hr). Each person sees only their own notices, and only once they are due.
- Writing times are staff data about the form, not about the child, and only admins can read them.
- Notices are deleted with the student or the account. Progress reads scheduling's sessions but never writes them.
- Children's Online Privacy Code (exposure draft): no new data about the child beyond the optional tip, which is written to the family.

## Not built yet

Still to come: voice-to-text, and email delivery of updates. Phase 2 built: roadmaps (learning-roadmaps.md), term reviews and monthly summaries (term-reviews.md), work and reports uploads (learning-evidence.md), senior certificates by state (senior-certificates.md).
