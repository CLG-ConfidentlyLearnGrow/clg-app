// Summary: the first-time tours for CLG's admin staff, one for each admin
// level: Owner (everything), Operations (day-to-day running), Support
// (families and bookings) and Finance (invoices and pay). Each tour only
// covers what that level can see and do. Shared steps (such as Sessions or
// child safety) are written once below and put into each tour that needs
// them, the same way as the admin App guides.
//
// The text is the tour itself, in the simple layout read by parseTour in
// ./index.ts ("##" a step, "Why:" why it matters, "Where:" where to find
// it; **stars** mark the exact names of buttons and menu items). Update
// this text whenever an admin screen or button changes.
//
import type { AdminLevel } from "@/lib/auth"; // The admin level type (for type checking only).
import type { TourSource } from "./index"; // The shape of a tour's words (for type checking only).

// (Text inside the backticks below is tour text, not code, so its lines
// don't carry code comments.)

// The welcome step, for every admin level.
const WELCOME = `
## Welcome to the admin dashboard

This tour shows you the parts of the app your admin level uses, what each is for, and why it matters. It takes a few minutes.

You can skip it now and take it again any time from **App guide** in the side menu.

## Getting around

The side menu (on a phone, the **Admin menu** button above the page) shows only what your admin level can use. A number next to an item means something is waiting there. If you also tutor or are a parent, tabs at the top switch between your dashboards.

**Home**, **Feedback**, **Your privacy** and **Report app issue** are at the top of every page on a computer, and under **Menu** at the top right on a phone.

You sign in with two-step login each time.

Why: The app holds children's information, so each admin level sees only what its job needs, and two-step login keeps accounts safe even if a password leaks.
`;

// Families (front-desk levels: Owner, Operations, Support).
const FAMILIES = `
## Families

Set up a family during a phone call, link a second parent or guardian, sort out possible double-ups, give a student 16 or over their own login, and send a new login link when one has run out.

Why: Getting each child's record right once, with the right parents linked, is what keeps matching, billing and privacy correct everywhere else in the app.

Where: **Families** in the side menu.
`;

// Matching and sessions (front-desk levels).
const MATCHING_SESSIONS = `
## Matching

**Matching** lists students by stage, from **Needs a tutor** to **Active**. Choosing a student shows **Tutors who suit**, best fit first, and you offer a tutor and time.

Why: The app only suggests tutors with checks in date for the student's state, who teach the subject at the right level and have spare hours. It never offers a tutor for their own child or family. That keeps every match safe and suitable.

Where: **Matching** in the side menu. **Gaps** shows who to recruit next.

## Sessions and bookings

Book sessions for families, cancel or stop bookings for someone, change the tutor on booked sessions, and help with requests, blocks, away dates, the waitlist and book again answers.

Why: Every offer and change needs the tutor and family to confirm, and offers close after 3 days. Following up quickly keeps students learning without gaps.

Where: **Sessions** in the side menu.
`;

// Running CLG day to day (Owner and Operations).
const RUNNING = `
## Tutors, checks and applications

Confirm each tutor's child safety checks against the official record. Review tutor applications, record interviews and referee checks, then approve or decline.

Why: A tutor is only matched with students, and only sees sessions, while their checks are confirmed and in date. Careful screening is a core part of being a child safe organisation.

Where: **Tutors and checks** and **Tutor applications** in the side menu.

## Progress and curriculum

Check term reviews before families see them, follow up overdue session notes, and spot-check that next steps are specific. Load and confirm curricula so tutors can link goals to skills.

Why: Session notes and reviews are how families see the value of tutoring. Checking quality keeps the promise CLG makes to every family.

Where: **Progress** and **Curriculum** in the side menu.

## Staff, leaving and records

Add staff, unlock accounts, record people leaving, reply to privacy requests within 28 days, and record any suspected data breach straight away.

Why: Australian privacy law sets deadlines for privacy requests and breaches, and records must be kept or deleted on time. These screens keep CLG on track.

Where: **Staff and accounts**, **Leaving** and **Privacy and records** in the side menu.

## Other admin tools

**What is new** writes the pop-ups people see after an update. **Teams links**, **Travel map**, **Materials library**, **Training setup** and **Feedback** are here too.

Why: These keep families and tutors informed, resourced and trained, and show what people are saying about CLG.
`;

// Billing (Owner, Operations, Finance).
const BILLING = `
## Billing

Set each family's plan and bill payer, add credit, look after paused families, and run billing and check invoices before they go to Xero.

Why: Only the people who pay see billing, and an overdue invoice pauses the whole family's sessions. Getting plans and payers right avoids awkward pauses and keeps cash flowing.

Where: **Billing** in the side menu.
`;

// Staff pay (Owner and Finance).
const PAY = `
## Staff pay

Approve logged hours, send each pay period to Xero Payroll, keep pay rates up to date, and work through the Xero to-do list.

Why: Staff must be paid correctly under the awards and on time. The app works out pay from sessions and approved hours, and Xero must match it.

Where: **Billing**, then **Staff pay**.
`;

// Child safety, own training and pay, and the finish (every admin level).
const FINISH = `
## Child safety

**Child safety** (in red, at the top of every page) is where anyone raises a concern. If a child is in danger right now, call 000. The Child Safety Officer and deputy see a number there when something is waiting.

Why: Every adult at CLG shares the job of keeping children safe. Concerns stay confidential and are never copied into emails or Teams.

## Your own training and pay

**Training** lists your compulsory modules, **Handbooks** has CLG's policies, and **My pay** is where you log your office hours by the day after each pay week ends.

Why: Training keeps you up to date on child safety and privacy, and logging hours on time means you are paid correctly.

## You are all set

That is the tour. Whenever you need the steps for something, open **App guide** in the side menu and search. Admins who help families and tutors can open their guides there too, to talk them through the app.
`;

// The tour for each admin level, built from the parts above.
export const ADMIN_TOURS: Record<AdminLevel, TourSource> = { // level -> tour:
  owner: { // The owner's tour:
    title: "Welcome, Owner", // its title,
    text: WELCOME + FAMILIES + MATCHING_SESSIONS + RUNNING + BILLING + PAY + `
## Owner only

You can change admin levels and invite admins, change prices and billing settings, see **Reports**, delete records on request, check **App issues**, set who receives child safety concerns and the flagged words, and approve or cancel emergency owner access.

Why: These settings affect everyone's access, money and children's records, so only the owner can change them.

Where: **Staff and accounts**, **Billing**, **Reports**, **Privacy and records** and **App issues**.
` + FINISH, // its steps,
  }, // End of the owner's tour.
  operations: { // The operations tour:
    title: "Welcome, Operations", // its title,
    text: WELCOME + FAMILIES + MATCHING_SESSIONS + RUNNING + BILLING + `
## Emergency owner access

If the owner cannot be reached and something only the owner can do is urgent, ask for emergency owner access with your reason. It starts 24 hr later unless the owner approves or cancels it, and ends after 7 days.

Why: CLG can keep running if the owner is unavailable, while the owner stays told and in control.

Where: **Staff and accounts**, then **Emergency owner access**.
` + FINISH, // its steps,
  }, // End of the operations tour.
  support: { // The support tour:
    title: "Welcome, Support", // its title,
    text: WELCOME + `
## What Support covers

As a Support admin you see **Families**, **Matching** and **Sessions**. Progress notes, tutor checks and money details are kept to other levels. If a family asks about those, pass it to an Operations admin.

Why: Each admin sees only what their job needs, which keeps children's and families' information private.
` + FAMILIES + MATCHING_SESSIONS + FINISH, // its steps,
  }, // End of the support tour.
  finance: { // The finance tour:
    title: "Welcome, Finance", // its title,
    text: WELCOME + `
## What Finance covers

As a Finance admin you work in **Billing**. You see names on invoices, but not student records, sessions, notes or tutor checks.

Why: Each admin sees only what their job needs, which keeps children's information private.
` + BILLING + PAY + FINISH, // its steps,
  }, // End of the finance tour.
}; // End of the admin tours.
