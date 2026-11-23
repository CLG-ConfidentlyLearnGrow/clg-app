# End-of-day updates from admin staff

Carla, 22 Nov 2026: "Updates should be sent every day admin work is done. What they did, what went well, what didn't go well (in dot point form...)". This comes from Emma's job proposal (Emma joins as admin staff) and the How We Do Things guide.

## What it is for

Admin staff often work alone and at different times. A short daily update keeps Carla in the picture without meetings, shows problems early, and builds a record for check-ins and probation reviews.

## What the evidence says

- **Feedback and metacognition** (EEF Teaching and Learning Toolkit, metacognition and self-regulation): reflecting on what went well and what did not, and planning from it, is one of the strongest levers for improvement. The same habit works for staff.
- **Professional development** (EEF guidance on effective professional development, AERO): regular, specific reflection with feedback from a leader builds skills more than one-off reviews.
- **Short and regular beats long and rare**: three dot point lists take a few minutes, so they get done every day.

## How the design follows it

- A new **End-of-day updates** page in the admin menu. Admin staff choose the day (today, or up to 7 days back), and write dot points (one per line) under **What I did**, **What went well** and **What did not go well**. They can correct an update for up to 7 days.
- A reminder: if they logged office admin hours on a day in the last week but sent no update, the menu shows a number and the page lists the day with a link.
- CLG's owner sees everyone's updates from the last 30 days, newest first, with new ones counted on the menu, and marks them as read. A corrected update shows as new again.

## How we will know it works

- share of office admin days with an update
- problems raised in "What did not go well" and how quickly they are sorted out

## Privacy, child safety and legal notes

- **Privacy Act 1988 (APPs 6 and 11)**: updates are employee records. Only the person who wrote them and CLG's owner can see them; access rules are in the database and every change is in the audit log. The form reminds staff to keep to work tasks; families' and students' details should be kept to first names or left out.
- **Fair Work Act (right to disconnect)**: updates are written during paid admin time, not after hours. The reminder is a number on the menu, not a message sent at night.

## Technical

- Migration `20261124711400_admin_end_of_day_updates.sql`: table `public.admin_day_updates`, functions `admin_day_update_save`, `admin_day_updates_mark_read`, `my_missing_day_updates` and `day_updates_unread_count`. Safe to run more than once.
- Tests: `supabase/tests/staff_end_of_day_updates.test.sql`.
