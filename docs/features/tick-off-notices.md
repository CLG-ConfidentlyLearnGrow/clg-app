# Tick off notices, and the active libraries list

Asked for by Carla, 20 Nov 2026: "How [do I] tick off I have seen these
things, or that they have been done?" (about Sessions > Notices), and "Is
there a list somewhere of all active libraries?"

## 1. What it is for

Notices mix news (a session was cancelled) with jobs (confirm a library, add
its opening hours, check next term's availability). Until now the only
control was one "Mark all as read" link at the bottom of the list, so a job
looked the same before and after it was dealt with, and old notices piled up
on top of new ones. Tutors, families and admins need to see at a glance what
still needs them.

The Libraries section already listed every library, but with one long list
(especially after loading all South Australian libraries) it was hard to see
which ones are actually ready for sessions.

## 2. What the evidence says

- **Make the next action clear and reduce what people have to hold in their
  heads.** AERO's
  [*Teaching how students learn* practice guides](https://edresearch.edu.au/resource-collections/teaching-how-students-learn-practice-guides)
  (drawing on cognitive load theory) recommend cutting out what is not
  needed so attention goes to what matters. Moving done notices out of the
  main list leaves only what still needs a look.
- **Keep communication with families simple and actionable.** The EEF's
  [*Working with Parents to Support Children's Learning*](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/supporting-parents)
  recommends messages that are easy to take in and act on. A clear "Mark as
  done" next to each notice tells a parent or student whether anything is
  left for them.
- **Staff time goes further with simple routines.** The EEF's
  [*A School's Guide to Implementation*](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/implementation)
  stresses removing friction so staff can keep doing the new practice.
  Ticking off each job, and a filtered "Active (ready for sessions)" library
  list, keeps admin follow-up quick as CLG grows to 20+ tutors.
- Evidence for Learning's
  [Teaching and Learning Toolkit](https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit)
  rates parental engagement as positive for learning when it is easy for
  families to stay involved; fewer missed booking jobs supports that.

## 3. What was built

- Each notice has **Mark as seen** (only while unread) and **Mark as done**.
  Done also marks it seen. Done notices move to a folded **Done** list (the
  latest 20), each with **Not done yet: put it back**. **Mark all as read**
  still works.
- The unread number on **Notices** (and on the folded **Sessions** menu
  heading, PR #188) drops as notices are ticked off.
- **Sessions > Libraries** (Owner and Operations admins) has filter buttons
  with counts: **All**, **Active (ready for sessions)** (shown, confirmed and
  with opening hours), **To confirm or add hours**, and **Hidden**.

Database: migration `20261122560100_tick_off_notices.sql` adds
`session_notices.done_at`, `public.tick_off_notice(id, action)`, a small
index of unread notices for fast counts, and re-makes the "own delivered
notices" rule with `(select auth.uid())`. Tests:
`supabase/tests/scheduling_notices_tick_off.test.sql`.

## 4. Legal rules it touches

- **Privacy Act 1988 (APP 11, security) and the Children's Online Privacy
  Code**: a person can only see and tick off their own notices, and only
  once delivered. The check is in the database (security definer function
  that matches the signed-in person), not only in the page. Nobody can
  change a notice's words; only the read and done times change. No new
  personal information is collected.
- **APP 6 (use)**: read and done times are used only to show the person's
  own list and counts.
- **UK GDPR / EU GDPR**: nothing new is shared; the same rules apply when
  CLG goes international.
- The library list shows the same library details as before (public
  addresses of public libraries, OpenStreetMap credit kept).

## 5. Follow-ups (Carla, 20 Nov 2026)

Carla: "Can it be default that libraries close on public holidays", and
"Ability to search through libraries, and filter for current libraries -
maybe even have a star on libraries which are yet to be confirmed, but have
been asked for by a tutor, family or student".

- **Closed on public holidays by default.** `libraries.open_public_holidays`
  (false for every library). One-off times skip a library closed that day;
  a weekly booking makes no session there that day (the family can ask for a
  one-off that week); any other session there that day is refused with a
  plain message. Admins choose **Set as open on public holidays** per
  library. Existing booked sessions are not cancelled: the migration ends
  by listing any upcoming ones so CLG can sort them out with the family.
  The family's **Public holiday weeks** list says **library closed**.
  Matches the family terms (no sessions on SA public holidays unless
  agreed) and avoids sending a child to a closed building (child safety:
  a safe, supervised public venue is part of the in-person session plan).
- **Search and a star.** The Libraries list has a search box (name, suburb
  or address) and a **★ Asked for, to confirm** filter; those libraries
  show a ★. The to-do list now says "Asked for by a tutor, family or
  student" instead of "Suggested by a tutor".

Migration `20261122560200_libraries_closed_public_holidays.sql`, tests
`supabase/tests/scheduling_library_public_holidays.test.sql`. No new
personal information; the public holiday list keeps the same access rule
(admins see all, families their own).
