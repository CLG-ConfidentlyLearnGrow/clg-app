// Summary: the app guide for students who have their own login (16 and
// over, including adult learners who pay for themselves). The text below is
// the guide itself, in the simple layout read by parseGuide in ./index.ts
// ("##" a part, "###" a task, "1." a step, "-" a bullet point, "Tip:" a
// tip; **stars** mark the exact names of buttons and menu items). Update
// this text whenever a feature for students changes.
//
import type { GuideSource } from "./index"; // The shape of a guide's words (for type checking only).

// The student guide's words. (Text inside the backticks is the guide itself,
// not code, so its lines don't carry code comments.)
export const STUDENT_GUIDE: GuideSource = { // The guide:
  title: "App guide for students", // its title,
  who: "For students aged 16 and over with their own CLG login.", // who it's for,
  text: `
## Getting around

- **Home** (top of every page) takes you to your **Overview**: a quick look at your next session, your steps this week and anything waiting for you.
- Your progress page has a **Back to home** button at the top.
- The side menu has **Overview**, **Your learning**, **Sessions**, **Weekly calendar** and **App guide**. If you pay for your own sessions, you also see **Billing**. A number next to a menu item means something is waiting for you. A menu item with smaller items under it (for example **Sessions**) has an arrow at the end of its row. Click the arrow to open or close those smaller items from any page, without leaving the page you are on. When they are folded away, the number beside the menu item adds up all of theirs.
- **Child safety** (in red, top of every page) is there if you ever feel unsafe or are worried about someone.
- **Help chat**, **Feedback**, **Your privacy** and **Report app issue** are at the top of every page too. On a phone, tap **Menu** (top right) to see them, your name and **Sign out**.

### See what needs you on the Overview
Your dashboard opens on **Overview** (also first in the side menu). It shows:
- **Next session**, **Next 7 days**, **Steps this week** and **New from tutors**. Tap a box to open that page.
- **Needs your attention**: one line for each thing waiting for you, such as an overdue step or a session time to answer. When nothing is waiting, it says **All caught up**.
- **Your steps this week**: tick each one off when it is done.
- **Coming up** (your next sessions) and **Your tutors**, with a link to your progress page.
- **Billing**, only if you pay for your own sessions.

Only your own sessions, steps and tutors are shown.

### Sign in for the first time
1. Your parent or CLG sends you a login link by email.
2. Open the link and choose a password (at least 12 characters, with upper and lowercase letters and a number).
3. Next time, go to app.clgtutoring.com and choose **Sign in**. Forgot your password? Choose **Forgot your password?**

### Sign up yourself (16 and over)
1. On the sign-in page, choose **Create an account**.
2. Under **I am signing up as**, choose the learner option.
3. Enter your name, email, password, date of birth, state, year level or stage of study, and your school, university or TAFE (or "Not studying").
4. Agree to the privacy policy and terms, then choose **Create account**, and open the link CLG emails you.

Tip: Students under 16 join through their family's account.

### Put CLG on your phone's home screen
Choose **Add CLG to your home screen** at the bottom of any page and follow the steps for your phone.

### Change your name
Tap your name under **Signed in as** (top right) to change it. On a phone, tap **Menu** at the top right first.

### Get a refresher on the page you are on
Every page has a **Show me how** button next to its heading. Choose it to see the App guide steps for that page, without leaving it. From there you can also choose **Open the whole App guide**, or **Take the app tour again**.

### Take the app tour again
The first time you open your dashboard, a short **app tour** shows the main parts of the app and why each one matters. To take it again, choose **Show me how** next to any page heading, then **Take the app tour again**. You can also open **App guide** in the side menu and choose **Take the tour again** at the top. If you stopped part-way, the button says **Carry on the tour** and starts where you left off.

## Your learning

### See what to do this week
1. In the side menu, choose **Your learning**.
2. **Your steps this week** lists the small steps to tick off before your next session.
3. **Your tutors** shows who you work with.
4. Choose **Open your progress page** for everything else.

### Use your progress page
- **Next step** is what your tutor suggests next, with practice or something to try.
- **Roadmap** shows this week's steps and what is coming up, like tests and assignments.
- **Goals and skills** shows what you are working on and how far you have come.
- **Recent sessions** has the notes from each session, and any files your tutor added (for example a photo of the whiteboard or a worked example). Choose a file's name to open it.

Tip: Your parent or carer and your tutor can also see your progress page and roadmap.

### Reflect after a session
1. On your progress page, find **How did it go?**
2. Say how confident you feel about the work, what was hard, and what you will try before next time.
3. Choose **Send to my tutor**. Your tutor uses it to plan the next session.

### Add a test or assignment to your roadmap
1. On your progress page, find **Roadmap**.
2. Add a school assessment or goal, with its date, then choose **Add to roadmap**. When you add an assessment (a test, exam or assignment due date), CLG is told straight away, so your tutor can plan for it.
3. Use **Add a step** to break it into smaller steps, or choose **Plan study steps for me** if you have study plans with CLG.
4. Tick steps off as you do them.

### Share marked work or reports
1. On your progress page, find **Work and reports**.
2. Choose a file or photo, say what it is, and add a grade or comment if you like.
3. Choose **Upload**. Your tutor can see where to focus.

## Sessions

Open **Sessions** in the side menu. Its sections are **Overview**, **Bookings**, **Preferred times**, **How long to book**, **Away dates**, **Requests**, **Blocks**, **Notices** and **Book again**. Times are Adelaide time.

### See upcoming sessions and join online
1. In **Sessions**, choose **Overview**.
2. **Upcoming sessions** lists each session with your tutor, the subject and the place.
3. For an online session, choose **Join** a few minutes before it starts. It opens Microsoft Teams. You do not need a Microsoft account.

### See your week, and add sessions to your own calendar
1. In the side menu, choose **Weekly calendar**.
2. Under **Add to your own calendar**, choose **Make my calendar link** and follow the steps for Google, Outlook or Apple calendar.
3. If you share the link by mistake, choose **Make a new link**.

### Approve a session time
When CLG offers a time, you see a notice and a number on **Sessions**.
1. In **Sessions**, choose **Bookings**.
2. Check the day, time, tutor and place, then choose **Approve**, or **This time does not suit** and say why.

Tip: You or your parent can answer. The first answer counts.

### Cancel a session
1. In **Sessions**, choose **Overview**, find the session and choose **Cancel**.
2. Choose a reason, and offer two other times that week for a make-up. Your tutor picks one. If no time works, tick that box and CLG will help.
3. Choose **Cancel this session**.

Credit: more than 24 hr before gets full credit, 24 to 2 hr before gets half, under 2 hr gets none. A cancel saved in quiet hours (9pm to 5am Adelaide time) counts from 5am.

### Pick or confirm a make-up time, or a change
If your tutor or CLG cancels a session, or CLG needs to change your tutor or time, a card shows at the top of the **Overview** (**Pick a make-up time**, **Confirm a make-up time** or **Please confirm a change**). Choose an answer, or say why it does not work. While a change is waiting, a session that does not go ahead is not counted as a missed session for you. CLG follows up and rebooks it, with no charge.

### Tell CLG which times suit, and for how long
1. In **Sessions**, choose **Preferred times**. Tick the days and parts of the day that suit, then **Save preferences**.
2. Under **How far you will travel**, enter the address you travel from and the most km you will travel to a library (in a straight line), then **Save travel distance**. Tutors cannot see the address.
3. Set your study period: SA school terms, or your own dates for university or TAFE (add each semester or term with its first and last day).
4. In **How long to book**, choose the last date for sessions and whether you want them in the holidays.

### Add away dates
1. In **Sessions**, choose **Away dates**.
2. Enter the first and last day away and a reason if you like.
3. Choose **Save away dates**. Sessions on those days are cancelled.

### Ask for an extra session
1. In **Sessions**, choose **Requests**, then **Ask for a session**.
2. Choose the subject and what you would like (for example an extra session before a significant date, such as a test, exam or assignment due date), the **Significant date**, and times that suit.
3. Choose **Send request**.

### Answer a check-in about your tutor
When you start with a new tutor, a card on your dashboard asks how it is going 1 week, 2 weeks and 6 weeks after your first session. Choose how it is going (1 to 5), whether you would like to keep working with them, and add a comment if you like. Tick **Please contact me about this** if you would like CLG to get in touch, then choose **Send** (or **Skip this check-in**). Only CLG's office team sees your answers, not your tutor. When you finish with a tutor, a card also asks how the sessions went and how well the ending was handled.

### Book again before your book-till date
About 3 weeks before your book-till date, you get a notice called **Book again?**. Go to **Sessions**, then **Book again**. Say whether you want the same day, time and tutor, choose a new book-till date, say again whether you want sessions during school holidays and on public holidays, then choose **Send answer**.

Tip: Most libraries are closed on public holidays, so a library session that falls on one does not go ahead. **Requests** shows **library closed** for those weeks, and you can ask for a one-off at another time that week.

### Notices and reminders
In **Sessions**, choose **Notices** to read reminders and news. Under a notice, choose **Mark as seen** once you have read it, or **Mark as done** once you have dealt with it (it moves to the **Done** list at the bottom). You get a reminder 24 hr before each session and another 1 hr before. Nothing is sent between 9pm and 5am your time.

### Get pop-up notifications on your phone or computer
Pop-ups tell you straight away about reminders, booking news and help chat replies, even when the app is closed or you have been signed out. They never show names or details.
1. On your phone or computer, choose **Turn on pop-ups** on the note at the top of your dashboard, or go to **Sessions**, choose **Notices**, and choose **Turn on pop-ups on this device** on the **Pop-up notifications** card.
2. When your browser asks, choose **Allow**.
3. Choose **Send me a test** to check it works.

Tip: On an iPhone or iPad, add CLG to your home screen first, open it from there, then turn on pop-ups. To stop them on a device, choose **Turn off on this device**.

### Ask about the Student Success Program (if you manage your own account)
The Student Success Program is a planned run of sessions with a study plan, each term review included, and priority when CLG finds a tutor. Places are limited.
1. On your dashboard, open **Student Success Program**.
2. Tick **Yes, I would like to ask about a place**, add anything CLG should know, and choose **Send my request**.
3. If CLG offers a place, pay the $500 deposit in **Billing** by the date shown. You are in the program once it is paid.

If a parent manages your account, they ask for you, and you can see where it is up to on your dashboard.

## Billing (if you pay for yourself)

### Set up your payments
1. In the side menu, choose **Billing**.
2. Choose how often you would like to pay (you need to do this before booking), and agree to the payment terms. To change it later, open **Change how often you pay**: once you have an invoice, the change is booked and starts from your next invoice, and you can choose **Cancel this change** before then.
3. Choose **Set up automatic payment** and enter your card or bank details on Stripe's secure page. CLG never sees them.
4. Pay any invoice with **Pay (amount) now**.

Tip: You do not need a Family profile to pay. An adult learner who pays for themselves does it all here, on the Student dashboard.

Tip: Only the person or people paying see Billing. If your parent or someone else pays, you will not see it, unless CLG has made you the bill payer or an extra payer. If your sessions are on hold, your dashboard says so: check with whoever pays.

## Help, privacy and safety

### If you do not feel safe
1. If you are in danger now, call 000.
2. You can talk to someone any time, for free: Kids Helpline 1800 55 1800 (ages 5 to 25) or Lifeline 13 11 14.
3. You can also tell an adult you trust, or choose **Child safety** at the top of any page and use the form to tell CLG. It is kept confidential.

### Ask CLG a question (Help chat)
1. Choose **Help chat** at the top of any page (on a phone, tap **Menu** first), then **Ask CLG a question**.
2. Choose what it is about, give it a short title, write your message and choose **Send to CLG**.
3. CLG replies in the chat and you get an email saying there is a reply. When you are done, choose **Close this chat**.

Tip: Only you and CLG's admins can read your chats. Your brothers and sisters cannot see them.

### Give feedback or report an app issue
- **Feedback** (top of the page): tell CLG what is going well, an idea, or a worry.
- **Report app issue**: tell CLG if something in the app is not working, with a screenshot if you can.

### Your privacy
Choose **Your privacy** to download your information, ask CLG to fix or delete something, or choose whether you get CLG news by email. If you are 18 or over, you can also choose whether CLG may quote what you write in its advertising without your name (off unless you turn it on).

Tip: Your profile is private. If your brothers or sisters have their own login, they cannot see your sessions, progress or anything else on your profile, and you cannot see theirs. Your parent can see all their children.
`, // End of the guide's text.
}; // End of the student guide.
