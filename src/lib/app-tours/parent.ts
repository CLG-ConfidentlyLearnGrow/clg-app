// Summary: the first-time tour for parents and carers. It opens the first
// time a parent uses their dashboard and takes them through the main parts
// of the app, saying what each part is, why it matters, and where to find
// it. The text below is the tour itself, in the simple layout read by
// parseTour in ./index.ts ("##" a step, "Why:" why it matters, "Where:"
// where to find it; **stars** mark the exact names of buttons and menu
// items). Update this text whenever a parent screen or button changes, as
// with the parent App guide.
//
import type { TourSource } from "./index"; // The shape of a tour's words (for type checking only).

// The parent tour's words. (Text inside the backticks is the tour itself,
// not code, so its lines don't carry code comments.)
export const PARENT_TOUR: TourSource = { // The tour:
  title: "Welcome to CLG", // its title,
  text: `
## Welcome to your CLG dashboard

This quick tour shows you the main parts of the app and why each one matters for your child. It takes about 4 minutes.

You can skip it now and take it again any time: choose **Show me how** next to any page heading, or open **App guide** in the side menu.

## Getting around

The side menu on the left (on a phone, the **Parent menu** button above the page) has everything for your family. A number next to a menu item means something is waiting for you there.

**Home** always brings you back here. It is at the top on a computer, and under **Menu** at the top right on a phone. If you have more than one role, tabs at the top switch between your dashboards.

Why: The numbers are how the app tells you a session time needs your yes, or a detail is missing. Checking them when you sign in means nothing is missed.

## Your children

This is where you add each child and keep their details up to date: year level, school, subjects, goals, and any learning needs you choose to share.

Once your child is matched, you see their tutor here, and a **Progress** link.

Why: CLG uses these details to choose a tutor who teaches the right subject at the right level, and to plan sessions around your child's goals. The more accurate they are, the better the match.

Where: **Your children** and **Add a child** in the side menu.

## Saying yes to session times

CLG finds a time with a tutor who suits and offers it to you. A booking only goes ahead once you and the tutor have both said yes.

You have 3 days to answer, with a reminder after 2. One parent, or a child 16 or over with their own login, can answer for the family.

Why: If nobody answers in time, the offer closes and the time may go to another family. A quick yes keeps your child's place with their tutor.

Where: **Sessions**, then **Bookings**.

## Planning ahead

In **Sessions**, tell CLG which days and times suit, how long to keep booking (for example to the end of the year), and any dates you will be away.

**Weekly calendar** shows your week, and can add sessions to your own phone calendar with a private link.

Why: Regular, planned sessions with the same tutor make the biggest difference to learning. Adding away dates early also gets you full credit for those sessions.

Where: **Sessions**: **Preferred times**, **How long to book** and **Away dates**. Then **Weekly calendar**.

## Cancelling or changing a session

Always cancel in the app: choose **Cancel** on the session, pick a reason, and offer two other times that week for a make-up.

If CLG or the tutor needs to change a time or tutor, you will be asked to confirm first. Nothing changes until you say yes.

Why: Notice counts from when you save the cancel in the app, not from a text or call. Cancelling more than 24 hr ahead gets full credit, 24 to 2 hr gets half, and under 2 hr gets none. Cancelling in the app also tells your tutor straight away.

Where: **Sessions**, then **Overview**.

## Following your child's progress

After each session, your tutor writes a short note with what went well, the next step, and one small thing to try at home. The **Progress** page also shows your child's goals, skills and roadmap.

You can tell the tutor how it went, and share school reports or marked work.

Why: Research shows parents help most by talking with their child about their learning and supporting good habits at home. The tip for home and the roadmap are made for exactly that.

Where: **Your children**, then **Progress** next to your child.

## Billing

If you pay for your family's sessions, **Billing** is where you choose how often to pay, agree to the payment terms, and set up automatic payment through Stripe's secure page.

Why: Sessions are paid in advance. If an invoice becomes overdue, all your family's sessions go on hold until it is paid, so automatic payment keeps everything running.

Where: **Billing** in the side menu.

## Safety, privacy and help

**Child safety** (in red, at the top of every page) is there if you are ever worried about a child. If a child is in danger right now, call 000.

**Your privacy** lets you download or ask about the information CLG holds. **Feedback** and **Report app issue** are for ideas, worries and anything not working. All three are at the top of every page on a computer, and under **Menu** at the top right on a phone.

Why: Keeping children safe is everyone's job, and you should always know what CLG holds about your family and be able to ask about it.

## You are all set

That is the tour. Whenever you need a refresher, choose **Show me how** next to the page heading to see the steps for that page. For anything else, open **App guide** in the side menu and search, for example "cancel" or "invoice".

After an app update, a **What is new** box shows what has changed for you.
`, // End of the tour's text.
}; // End of the parent tour.
