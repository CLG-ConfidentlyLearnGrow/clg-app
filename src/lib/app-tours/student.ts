// Summary: the first-time tour for students with their own login (16 and
// over, including adult learners). It opens the first time a student uses
// their dashboard and takes them through the main parts of the app, saying
// what each part is, why it matters, and where to find it. The text below
// is the tour itself, in the simple layout read by parseTour in ./index.ts
// ("##" a step, "Why:" why it matters, "Where:" where to find it; **stars**
// mark the exact names of buttons and menu items). Update this text
// whenever a student screen or button changes, as with the student App
// guide.
//
import type { TourSource } from "./index"; // The shape of a tour's words (for type checking only).

// The student tour's words. (Text inside the backticks is the tour itself,
// not code, so its lines don't carry code comments.)
export const STUDENT_TOUR: TourSource = { // The tour:
  title: "Welcome to CLG", // its title,
  text: `
## Welcome to your CLG dashboard

This quick tour shows you the main parts of the app and why each one helps your learning. It takes about 3 minutes.

You can skip it now and take it again any time from **App guide** in the side menu.

## Getting around

The side menu on the left (on a phone, the menu button near the top of the page) has **Your learning**, **Sessions**, **Weekly calendar** and **App guide**. If you pay for your own sessions, you also see **Billing**.

A number next to a menu item means something is waiting for you.

Why: The numbers tell you when a step is due or a session time needs your answer, so check them when you sign in.

## Your learning

**Your steps this week** lists the small things to do before your next session. Your progress page shows your next step, your goals and skills, your roadmap of tests and assignments, and the notes from each session.

Why: Small, regular steps between sessions are what turn a good session into real progress. Adding your tests and assignments to the roadmap lets your tutor plan around them.

Where: **Your learning**, then **Open your progress page**.

## Reflecting after a session

After each session, take a minute on **How did it go?** to say how confident you feel, what was hard, and what you'll try before next time.

Why: Thinking about how you learn, and planning what to do next, is one of the most powerful study habits there is. It also tells your tutor what to focus on.

Where: Your progress page, under **How did it go?**

## Your sessions

**Sessions** shows what's coming up. For an online session, choose **Join** a few minutes before it starts. When CLG offers a new time, you or your parent can approve it.

**Weekly calendar** shows your week, and can add sessions to your own phone calendar.

Why: A booking only goes ahead once it's approved, and an offer closes after 3 days. Joining on time gets you your full session.

Where: **Sessions** and **Weekly calendar** in the side menu.

## Cancelling or changing a session

If you can't make it, cancel in the app as early as you can and offer two other times that week for a make-up. If a time or tutor needs to change, you'll be asked to confirm first.

Why: Notice counts from when the cancel is saved in the app, and earlier notice means more credit. It also tells your tutor straight away.

Where: **Sessions**, then **Overview**.

## Who can see what

Your parent or carer (if they're on your account) and your tutor can see your progress page and roadmap. Brothers and sisters never see your profile.

If you pay for yourself, **Billing** is where you choose how often to pay and set up automatic payment.

Why: Being open about who sees your learning helps everyone support you, and you stay in control of your own information.

## Feeling safe, and getting help

**Child safety** (in red, at the top of every page) is there if you ever feel unsafe or are worried about someone. If you're in danger right now, call 000.

**Your privacy**, **Feedback** and **Report app issue** are at the top of every page too.

Why: You should always be able to speak up, and know someone will listen.

## You're all set

That's the tour. Whenever you need the steps for something, open **App guide** in the side menu and search, for example "cancel" or "roadmap".

After an app update, a **What's new** box shows what's changed for you.
`, // End of the tour's text.
}; // End of the student tour.
