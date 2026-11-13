# Removing staff who leave CLG

Requested by Carla, 14 Nov 2026: "Need to be able to remove employees from the staff registry, for when they're no longer part of the CLG team."

## What it does

- **Where:** Admin, Staff directory. Press **Manage** on a person, then **Remove from the team** in the "Left CLG" box. Only the owner sees it. It isn't offered on the owner's own card or on another owner's card.
- **What the owner enters:** their last day (today or earlier, within the past year), why they left (from a short list), an optional short note, and their full name typed to confirm.
- **Before it goes ahead:** the box shows how many students they're matched with (those students will need a new tutor in Matching). It refuses while a tutor still has bookings coming up, with a link to Sessions, so no student is left without a tutor.
- **What happens, all in one step** (if any part is refused, nothing changes):
  - Their tutor and admin access ends straight away. Tutors are marked as finished and their matches end. This reuses the existing "remove a role" step, so the same checks and activity log apply.
  - Their private calendar link is deleted, so it can't start working again if they rejoin.
  - They're signed out on every device.
  - Their last day, reason and note are written down. Tutors also get a line in the shared "why people leave" record used by Reports.
  - A parent role, if they have one, is left alone. They still see their own children.
- **Former staff** stay in the directory. Choose **Left CLG** under Status to see them. Their card shows when they left. The owner and operations admins also see why. Support and finance admins see only the date.
- **Bringing someone back:** press Manage on their card and add a tutor or admin role. They show as current staff again. Their old leaving record stays as history. Tutors still need confirmed checks before they're matched with students.
- **Steps outside the app:** after removing someone, the page lists what's left to do by hand: final pay and Xero payroll, Microsoft 365 and Teams, CLG materials, devices and shared passwords, their Working with Children Check link, and telling families about the new tutor.

## Why (research)

- **Continuity for learners.** EEF's evidence on one-to-one and small-group tuition, and AERO's guidance on tutoring, both point to the tutor–learner relationship and consistent, well-planned sessions as part of what makes tutoring work. The step refuses to go ahead while bookings remain and shows how many students need a new tutor. This means a learner is handed to a new tutor on purpose, rather than finding their sessions have stopped.
- **Least privilege.** The Australian Cyber Security Centre's *Essential Eight* (restrict administrative privileges) and the OAIC's guide to securing personal information both say access should end as soon as someone's role no longer needs it. Removing access, signing out every device and deleting the calendar link on the last day does that.
- **Child safety.** The National Principles for Child Safe Organisations, Principle 5 (people working with children are suitable and supported), and SA's child safe environment rules expect organisations to control who can reach children and their information. A former tutor loses access to children's details on the day they leave.

## Legal notes

- **Employee records (Fair Work Act 2009 s 535; Fair Work Regulations 2009 regs 3.31–3.44):** pay, hours and leave records must be kept for 7 years. Nothing is deleted when someone leaves. The nightly clean-up also had a gap: an account with no roles left was deleted after 12 months unused, even when it belonged to someone who left the staff less than 7 years ago. This change keeps those accounts for the full 7 years (the existing "former tutors" keeping period). After that, the usual clean-up removes them.
- **Tax records:** 5 years under tax law. The 7-year rule covers this.
- **Privacy (APP 11.2):** destroy personal information once it's no longer needed. The leaving record holds only the name, last day, reason, a short note and the roles that ended, and it goes when the account is finally deleted. The note box says to keep it factual and to put any child safety concern in Child safety instead.
- **Final pay:** most modern awards (including the Miscellaneous Award) say final pay is due within 7 days of the last day. The app shows this as a reminder only; pay runs in Xero.
- **UK and EU:** the same approach meets UK GDPR and GDPR storage limitation and security rules. Access ends at once, and records are kept only as long as employment and tax law require.
- **Access rules (database):** `public.staff_leave()` works only for the owner, signed in with two-step login, with the person's name typed. It refuses the owner's own account and any owner account. Nobody can write `staff_departures` directly, and only the owner and operations admins can read it. `public.staff_directory()` shows the reason only to them. Every use is written to the activity log.
- **Fix found while building:** ending a tutor's matches used to fail. The match checks ("is this tutor cleared?") ran even when a match was being ended. Removing a tutor switches their profile off first, so that check always failed. A tutor whose Working with Children Check had expired couldn't be removed either. Ending a match early (same tutor, student and subject, with an earlier end date) now skips those checks, because it can only reduce access. Starting or changing a match is still fully checked.
- **Tests:** `supabase/tests/staff_leaving.test.sql`.
