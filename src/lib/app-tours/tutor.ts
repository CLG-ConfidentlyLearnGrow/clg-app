// Summary: the first-time tour for tutors. It opens the first time a tutor
// uses their dashboard and takes them through the main parts of the app,
// saying what each part is, why it matters, and where to find it. The text
// below is the tour itself, in the simple layout read by parseTour in
// ./index.ts ("##" a step, "Why:" why it matters, "Where:" where to find
// it; **stars** mark the exact names of buttons and menu items). Update
// this text whenever a tutor screen or button changes, as with the tutor
// App guide.
//
import type { TourSource } from "./index"; // The shape of a tour's words (for type checking only).

// The tutor tour's words. (Text inside the backticks is the tour itself,
// not code, so its lines don't carry code comments.)
export const TUTOR_TOUR: TourSource = { // The tour:
  title: "Welcome to CLG", // its title,
  text: `
## Welcome to your tutor dashboard

This tour shows you the main parts of the app, what you need to do in each, and why it matters. It takes about 4 minutes.

You can skip it now and take it again any time from **App guide** in the side menu.

## Getting around

Everything you need is in the side menu (on a phone, the **Tutor menu** button above the page). A number next to an item means something is waiting for you there.

**Home**, **Feedback**, **Your privacy** and **Report app issue** are at the top of every page on a computer, and under **Menu** at the top right on a phone.

**App guide** has step-by-step help for each task. The **Handbook** has CLG's policies and what to do when something happens.

Why: The numbers are how the app tells you about booking requests, notes due and checks running out. Checking them each day keeps families and CLG in the loop.

## Your child safety checks

Add your Working with Children Check, RRHAN-EC training and first aid, with a copy of each card or certificate. CLG checks them and confirms them.

Why: The law requires a current check for the state each student lives in. CLG can only match you with students, and only shows you their sessions, while your checks are confirmed and in date. You will get reminders before one runs out.

Where: **Child safety checks** in the side menu.

## What you teach, and when

Add each subject with the year levels you teach it at. Then set the most hours you can work each week, the times you are available, and where you teach (online, libraries, or both).

Why: The app only suggests you for students whose subject, level, times and place fit what you have entered, and never more hours than your weekly limit. Keeping it right means you get students that suit you.

Where: **What you teach** and **Hours and availability**. Then **Sessions**, **Where you teach**.

## Accepting sessions

CLG offers you a booking request. Check the student, subject, day, time and place, then accept or decline with a note.

Why: Requests run out after 48 hr and the time is freed. A quick answer keeps the student learning without a gap.

Where: **Sessions**, then **Overview**.

## On the day

From 30 minutes before, choose **Sign on**. For online sessions, choose **Join** to open Teams. Afterwards, mark each session **Done** or **No-show**.

If a student has not arrived, wait 15 minutes after the start before choosing **No-show**.

Why: Signing on and marking sessions is what records that the session happened, which drives your pay and the family's invoice.

Where: **Sessions**, then **Overview**, and your **Weekly calendar**.

## Session notes

Write a short note within 6 hr of each session: what went well, a specific next step, any practice, and one small thing to try at home. It takes about three minutes.

Why: Specific feedback on the next step is one of the most effective things a tutor can give. Families are promised notes within 48 hr, so CLG follows up anything later than 6 hr.

Where: **Your students**, then **Session notes to write**.

## Goals, progress and materials

Set goals for each student and link the curriculum skills they cover, then move skill levels up as they improve. Look at work families upload, and write term reviews when booked.

**CLG materials** shows resources matched to your students' goals.

Why: Clear goals, and tracking progress against them, help students see how far they have come and help you plan what comes next.

Where: **Your students**, then **Progress and notes**. Then **CLG materials**.

## Cancelling and changes

Cancel in the app, never by text: choose **Cancel**, pick a reason, and offer two other times that week for a make-up. Add away dates as early as you can.

If CLG needs to change a student's tutor or time, everyone confirms before anything moves.

Why: Cancelling in the app tells the family straight away and keeps credit and pay fair. Early away dates give families time to plan.

Where: **Sessions**: **Overview** and **Away dates**.

## Training and pay

**Training** lists your compulsory modules. Safety modules must be done before new students are matched with you.

**My pay** shows your rates and sessions. Log any work outside sessions by the day after each pay week ends.

Why: Training keeps students safe and you up to date. Logging hours on time means you are paid correctly and on time.

Where: **Training**, **Handbook** and **My pay** in the side menu.

## Child safety and privacy

**Child safety** (in red, at the top of every page) is where to report any worry about a child. If a child is in danger right now, call 000. Concerns are confidential.

You only see students you are matched with, and only what you need to teach them. Keep their details in the app: do not copy them into texts, emails or personal notes.

Why: Every adult at CLG shares the job of keeping children safe and their information private.

## You are all set

That is the tour. Whenever you need the steps for something, open **App guide** in the side menu and search, for example "no-show" or "note".

After an app update, a **What's new** box shows what has changed for tutors.
`, // End of the tour's text.
}; // End of the tutor tour.
