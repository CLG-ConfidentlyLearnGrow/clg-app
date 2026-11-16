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

- **Home** (top of every page) takes you back to your dashboard.
- The side menu has **Your learning**, **Sessions**, **Weekly calendar** and **App guide**. If you pay for your own sessions, you also see **Billing**. A number next to a menu item means something is waiting for you.
- **Child safety** (in red, top of every page) is there if you ever feel unsafe or are worried about someone.
- **Feedback**, **Your privacy** and **Report app issue** are at the top of every page too.

### Sign in for the first time
1. Your parent or CLG sends you a login link by email.
2. Open the link and choose a password (at least 12 characters, with upper and lowercase letters and a number).
3. Next time, go to app.clgtutoring.com and choose **Sign in**. Forgot your password? Choose **Forgot your password?**

### Sign up yourself (16 and over)
1. On the sign-in page, choose **Create an account**.
2. Under **I am signing up as**, choose the learner option.
3. Enter your name, email, password, date of birth, state, year level or stage of study, and your school, university or TAFE (or "Not studying").
4. Agree to the privacy policy and terms, then choose **Create account**, and open the link CLG emails you.

Tip: Students under 16 join through a parent's account.

### Put CLG on your phone's home screen
Choose **Add CLG to your home screen** at the bottom of any page and follow the steps for your phone.

### Change your name
Tap your name under **Signed in as** (top right) to change it.

## Your learning

### See what to do this week
1. In the side menu, choose **Your learning**.
2. **Your steps this week** lists the small steps to tick off before your next session.
3. **Your tutors** shows who you work with.
4. Choose **Open your progress page** for everything else.

### Use your progress page
- **Next step** is what your tutor suggests next, with practice or something to try.
- **Roadmap** shows this week's steps and what's coming up, like tests and assignments.
- **Goals and skills** shows what you are working on and how far you have come.
- **Recent sessions** has the notes from each session.

Tip: Your parent or carer and your tutor can also see your progress page and roadmap.

### Reflect after a session
1. On your progress page, find **How did it go?**
2. Say how confident you feel about the work, what was hard, and what you will try before next time.
3. Choose **Send to my tutor**. Your tutor uses it to plan the next session.

### Add a test or assignment to your roadmap
1. On your progress page, find **Roadmap**.
2. Add a school assessment or goal, with its date, then choose **Add to roadmap**.
3. Use **Add a step** to break it into smaller steps, or choose **Plan study steps for me** if you have study plans with CLG.
4. Tick steps off as you do them.

### Share marked work or reports
1. On your progress page, find **Work and reports**.
2. Choose a file or photo, say what it is, and add a grade or comment if you like.
3. Choose **Upload**. Your tutor can see where to focus.

## Sessions

Open **Sessions** in the side menu. Its sections are **Overview**, **Bookings**, **Preferred times**, **How long to book**, **Away dates**, **Requests**, **Blocks**, **Notices** and **Next term**. Times are Adelaide time.

### See upcoming sessions and join online
1. In **Sessions**, choose **Overview**.
2. **Upcoming sessions** lists each session with your tutor, the subject and the place.
3. For an online session, choose **Join** a few minutes before it starts. It opens Microsoft Teams. You don't need a Microsoft account.

### See your week, and add sessions to your own calendar
1. In the side menu, choose **Weekly calendar**.
2. Under **Add to your own calendar**, choose **Make my calendar link** and follow the steps for Google, Outlook or Apple calendar.
3. If you share the link by mistake, choose **Make a new link**.

### Approve a session time
When CLG offers a time, you see a notice and a number on **Sessions**.
1. In **Sessions**, choose **Bookings**.
2. Check the day, time, tutor and place, then choose **Approve**, or **This time doesn't suit** and say why.

Tip: You or your parent can answer. The first answer counts.

### Cancel a session
1. In **Sessions**, choose **Overview**, find the session and choose **Cancel**.
2. Choose a reason, and offer two other times that week for a make-up. Your tutor picks one. If no time works, tick that box and CLG will help.
3. Choose **Cancel this session**.

Credit: more than 24 hr before gets full credit, 24 to 2 hr before gets half, under 2 hr gets none.

### Pick or confirm a make-up time, or a change
If your tutor or CLG cancels a session, or CLG needs to change your tutor or time, a card shows at the top of the **Overview** (**Pick a make-up time**, **Confirm a make-up time** or **Please confirm a change**). Choose an answer, or say why it doesn't work.

### Tell CLG which times suit, and for how long
1. In **Sessions**, choose **Preferred times**. Tick the days and parts of the day that suit, then **Save preferences**.
2. Set your study period: SA school terms, or your own dates for university or TAFE (add each semester or term with its first and last day).
3. In **How long to book**, choose the last date for sessions and whether you want them in the holidays.

### Add away dates
1. In **Sessions**, choose **Away dates**.
2. Enter the first and last day away and a reason if you like.
3. Choose **Save away dates**. Sessions on those days are cancelled.

### Ask for an extra session
1. In **Sessions**, choose **Requests**, then **Ask for a session**.
2. Choose the subject and what you would like (for example an extra session before a test), the date, and times that suit.
3. Choose **Send request**.

### Answer the next term question
Before your study period ends, go to **Sessions**, then **Next term**. Say whether you want the same time and tutor, then choose **Send answer**.

### Notices and reminders
In **Sessions**, choose **Notices** to read reminders and news. Open **Reminder settings** to choose when your first reminder comes. Nothing is sent between 9pm and 5am your time.

## Billing (if you pay for yourself)

### Set up your payments
1. In the side menu, choose **Billing**.
2. Choose how often you would like to pay, and agree to the payment terms.
3. Choose **Set up automatic payment** and enter your card or bank details on Stripe's secure page. CLG never sees them.
4. Pay any invoice with **Pay (amount) now**.

Tip: If you are the only person in your family who has sessions with CLG, you look after billing yourself. If a brother, sister or other family member also has sessions, billing stays with your parent or carer (or the bill payer CLG has set up), and **Billing** tells you so. Contact CLG if you would like to be the bill payer. If your sessions are on hold, check with your parent or carer.

## Help, privacy and safety

### If you don't feel safe
1. If you are in danger now, call 000.
2. You can talk to someone any time, for free: Kids Helpline 1800 55 1800 (ages 5 to 25) or Lifeline 13 11 14.
3. You can also tell an adult you trust, or choose **Child safety** at the top of any page and use the form to tell CLG. It is kept confidential.

### Give feedback or report an app issue
- **Feedback** (top of the page): tell CLG what is going well, an idea, or a worry.
- **Report app issue**: tell CLG if something in the app isn't working, with a screenshot if you can.

### Your privacy
Choose **Your privacy** to download your information, ask CLG to fix or delete something, or choose whether you get CLG news by email.
`, // End of the guide's text.
}; // End of the student guide.
